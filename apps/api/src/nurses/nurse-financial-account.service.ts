import { createHash } from 'node:crypto';
import { BadRequestException, Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { conflict, missing } from '../common/errors.js';
import type { Q } from '../pricing/fees.service.js';
import { fromMinor, toMinor } from '../wallet/ledger.service.js';

export const financialModels = ['RECEIVABLES', 'PREPAID', 'HYBRID'] as const;
export type FinancialModel = typeof financialModels[number];
export const financialCurrency = /^[A-Z][A-Z0-9_]{2,15}$/;
interface Policy {
  currencyCode: string;
  financialModel: FinancialModel;
  creditLimit: string;
}
interface PolicyUpdate extends Omit<Policy,'currencyCode'> {
  expectedVersion: number;
  administrativelyRestricted: boolean;
  restrictionReason?: string;
}
interface LegacyProof {
  currencyCode: string;
  expectedVersion: number;
  evidenceReference: string;
  proofTransactionId?: string;
}

export function readFinancialPolicy(value: unknown): Policy | null {
  if (!value || typeof value !== 'object') return null;
  const input = value as Partial<Policy>;
  if (typeof input.currencyCode !== 'string' || !financialCurrency.test(input.currencyCode)
      || !input.financialModel || !financialModels.includes(input.financialModel)
      || typeof input.creditLimit !== 'string' || !/^\d{1,16}(?:\.\d{1,2})?$/.test(input.creditLimit)) return null;
  return {...input, creditLimit: fromMinor(toMinor(input.creditLimit))} as Policy;
}

@Injectable()
export class NurseFinancialAccountService {
  async initializeAccount(q: Q, nurseId: string, actor: string, explicit?: Policy) {
    const configured = explicit ?? readFinancialPolicy((await q.query(
      "SELECT value FROM app_settings WHERE key='nurse_financial_default_policy'",
    )).rows[0]?.value);
    if (!configured) return {status:'FINANCIAL_SETUP_REQUIRED' as const};
    const policy = readFinancialPolicy(configured);
    if (!policy) throw new BadRequestException({code:'INVALID_FINANCIAL_ACCOUNT_POLICY'});
    const inserted = await q.query(`INSERT INTO nurse_financial_currency_accounts(
      nurse_id,currency_code,financial_model,prepaid_balance,reserved_balance,credit_limit,
      settlement_required,created_by,updated_by)
      VALUES($1,$2,$3,0,0,$4,false,$5,$5)
      ON CONFLICT(nurse_id,currency_code) DO NOTHING RETURNING id`,
    [nurseId,policy.currencyCode,policy.financialModel,policy.creditLimit,actor]);
    if (inserted.rowCount) {
      await this.audit(q,actor,nurseId,'financial.currency_account_initialized',policy);
      await this.recomputeEligibility(q,nurseId,policy.currencyCode);
    }
    return {status:'FINANCIAL_CONFIGURED' as const,account:await this.getAccount(q,nurseId,policy.currencyCode)};
  }

  async getAccount(q: Q, nurseId: string, currencyCode: string, lock=false) {
    return (await q.query(`SELECT * FROM nurse_financial_currency_accounts
      WHERE nurse_id=$1 AND currency_code=$2 ${lock?'FOR UPDATE':''}`,[nurseId,currencyCode])).rows[0] ?? null;
  }

  async listAccounts(q: Q,nurseId:string) {
    if (!(await q.query('SELECT id FROM nurses WHERE id=$1',[nurseId])).rowCount) missing();
    const [accounts,legacy] = await Promise.all([
      q.query(`SELECT a.*,coalesce((SELECT sum(e.debit_amount-e.credit_amount)
        FROM financial_ledger_entries e WHERE e.currency=a.currency_code AND e.account_id IN
        ('CASH_HELD_BY_NURSE:'||a.nurse_id::text,'NURSE_PAYABLE:'||a.nurse_id::text)),0)::text AS balance
        FROM nurse_financial_currency_accounts a WHERE a.nurse_id=$1 ORDER BY a.currency_code`,[nurseId]),
      q.query(`SELECT l.reconciliation_required,l.prepaid_balance,l.reserved_balance,
        rc.currency_code,rc.evidence_reference,rc.reconciled_at FROM nurse_financial_accounts l
        LEFT JOIN nurse_legacy_financial_reconciliations rc ON rc.nurse_id=l.nurse_id WHERE l.nurse_id=$1`,[nurseId]),
    ]);
    return {
      items:accounts.rows,
      legacy:legacy.rows[0] ?? null,
      status:accounts.rowCount?'FINANCIAL_CONFIGURED':'FINANCIAL_SETUP_REQUIRED',
      legacyStatus:legacy.rows[0]?.reconciliation_required?'LEGACY_RECONCILIATION_REQUIRED':null,
    };
  }

  async updatePolicy(q: Q,nurseId:string,currencyCode:string,actor:string,input:PolicyUpdate) {
    const policy=readFinancialPolicy({...input,currencyCode});
    if (!policy || (input.administrativelyRestricted && !input.restrictionReason?.trim()))
      throw new BadRequestException({code:'INVALID_FINANCIAL_ACCOUNT_POLICY'});
    const present=await this.getAccount(q,nurseId,currencyCode,true);
    if (!present) missing();
    const changed=await q.query(`UPDATE nurse_financial_currency_accounts SET
      financial_model=$4,credit_limit=$5,administratively_restricted=$6,restriction_reason=$7,
      version=version+1,updated_by=$8,updated_at=statement_timestamp()
      WHERE nurse_id=$1 AND currency_code=$2 AND version=$3 RETURNING id`,
    [nurseId,currencyCode,input.expectedVersion,policy.financialModel,policy.creditLimit,
      input.administrativelyRestricted,input.restrictionReason?.trim() || null,actor]);
    if (!changed.rowCount) conflict('FINANCIAL_ACCOUNT_VERSION_CONFLICT');
    await this.recomputeEligibility(q,nurseId,currencyCode);
    await this.audit(q,actor,nurseId,'financial.currency_account_policy_updated',{...policy,
      previousVersion:input.expectedVersion,administrativelyRestricted:input.administrativelyRestricted,
      restrictionReason:input.restrictionReason?.trim() || null});
    return this.getAccount(q,nurseId,currencyCode);
  }

  async reconcileLegacyAccount(q: Q,nurseId:string,actor:string,input:LegacyProof) {
    const account=await this.getAccount(q,nurseId,input.currencyCode,true);
    if (!account) conflict('FINANCIAL_SETUP_REQUIRED');
    if (account.version!==input.expectedVersion) conflict('FINANCIAL_ACCOUNT_VERSION_CONFLICT');
    const legacy=(await q.query(`SELECT * FROM nurse_financial_accounts
      WHERE nurse_id=$1 AND reconciliation_required FOR UPDATE`,[nurseId])).rows[0];
    if (!legacy) conflict('LEGACY_RECONCILIATION_NOT_PENDING');
    const open=(await q.query(`SELECT 1 FROM financial_reservations WHERE nurse_id=$1
      AND status='HELD' AND currency_account_id IS NULL LIMIT 1`,[nurseId])).rowCount;
    if (open || toMinor(legacy.reserved_balance)>0n) conflict('LEGACY_RESERVATIONS_UNRESOLVED');
    const prepaid=toMinor(legacy.prepaid_balance);
    // A nonzero balance requires an existing, non-reversed ledger obligation
    // for this nurse and currency. Reconciling projects it once, without minting money.
    if (prepaid>0n || input.proofTransactionId) {
      if (!input.proofTransactionId || toMinor(account.prepaid_balance)>0n) conflict('LEGACY_CURRENCY_PROOF_REQUIRED');
      const proved=await q.query(`SELECT 1 FROM financial_transactions t
        JOIN financial_ledger_entries e ON e.transaction_id=t.id
        WHERE t.id=$1 AND t.currency_code=$2 AND e.currency=$2 AND e.account_id=$3
          AND NOT EXISTS (SELECT 1 FROM financial_transactions x WHERE x.reversal_of_transaction_id=t.id)
        GROUP BY t.id HAVING sum(e.credit_amount-e.debit_amount)=$4::numeric
          AND (SELECT coalesce(sum(all_e.credit_amount-all_e.debit_amount),0)
            FROM financial_ledger_entries all_e WHERE all_e.account_id=$3 AND all_e.currency=$2)=$4::numeric`,
      [input.proofTransactionId,input.currencyCode,`PREPAID_LIABILITY:${nurseId}`,fromMinor(prepaid)]);
      if (!proved.rowCount) conflict('LEGACY_CURRENCY_PROOF_REQUIRED');
    }
    await q.query(`INSERT INTO nurse_legacy_financial_reconciliations(nurse_id,currency_account_id,currency_code,
      legacy_prepaid_balance,proof_transaction_id,evidence_reference,reconciled_by)
      VALUES($1,$2,$3,$4,$5,$6,$7)`,[nurseId,account.id,input.currencyCode,fromMinor(prepaid),
      input.proofTransactionId ?? null,input.evidenceReference.trim(),actor]);
    await q.query(`UPDATE nurse_financial_accounts SET reconciliation_required=false,updated_at=statement_timestamp()
      WHERE nurse_id=$1`,[nurseId]);
    await q.query(`UPDATE nurse_financial_currency_accounts SET prepaid_balance=prepaid_balance+$2::numeric,
      version=version+1,updated_by=$3,updated_at=statement_timestamp() WHERE id=$1`,
    [account.id,fromMinor(prepaid),actor]);
    await this.recomputeEligibility(q,nurseId,input.currencyCode);
    await this.audit(q,actor,nurseId,'financial.legacy_account_reconciled',input);
    return this.listAccounts(q,nurseId);
  }

  async recomputeEligibility(q: Q,nurseId:string,currencyCode:string): Promise<string[]> {
    const result=await q.query('SELECT recompute_nurse_financial_eligibility($1,$2) AS reasons',[nurseId,currencyCode]);
    return result.rows[0]?.reasons ?? ['FINANCIAL_SETUP_REQUIRED'];
  }

  async accountStatus(q: Q,nurseId:string) {
    const states=(await q.query(`SELECT settlement_required
      FROM nurse_financial_currency_accounts WHERE nurse_id=$1`,[nurseId])).rows;
    return {configured:states.length>0,blocked:states.length>0 && states.every(row=>row.settlement_required===true)};
  }

  async allocateCommissionSettlement(q: Q,accountId:string,transactionId:string,payment:bigint) {
    const rows=(await q.query('SELECT * FROM nurse_uncovered_commission($1) WHERE outstanding>0',[accountId])).rows;
    let available=payment;
    for (const row of rows) {
      if (available<=0n) break;
      const outstanding=toMinor(row.outstanding);
      const amount=available<outstanding?available:outstanding;
      await q.query(`INSERT INTO nurse_commission_settlement_allocations(reconciliation_id,transaction_id,amount)
        VALUES($1,$2,$3)`,[row.reconciliation_id,transactionId,fromMinor(amount)]);
      available-=amount;
    }
  }

  async runAdminMutation<T>(client:PoolClient,actor:string,nurseId:string,key:string,input:unknown,
    execute:()=>Promise<T>):Promise<T> {
    if (!key?.trim() || key.length>128) throw new BadRequestException({code:'IDEMPOTENCY_KEY_REQUIRED'});
    const digest=createHash('sha256').update(JSON.stringify({nurseId,input})).digest('hex');
    // Keep the nurse row ahead of financial account locks for every admin mutation.
    if (!(await client.query('SELECT id FROM nurses WHERE id=$1 FOR UPDATE',[nurseId])).rowCount) missing();
    const claimed=await client.query(`INSERT INTO nurse_financial_admin_operations(actor_user_id,idempotency_key,payload_digest)
      VALUES($1,$2,$3) ON CONFLICT(actor_user_id,idempotency_key) DO NOTHING RETURNING payload_digest`,
    [actor,key,digest]);
    if (!claimed.rowCount) {
      const existing=(await client.query(`SELECT payload_digest,result FROM nurse_financial_admin_operations
        WHERE actor_user_id=$1 AND idempotency_key=$2 FOR UPDATE`,[actor,key])).rows[0];
      if (!existing || existing.payload_digest!==digest || existing.result==null) conflict('FINANCIAL_IDEMPOTENCY_KEY_REUSED');
      return existing.result as T;
    }
    const result=await execute();
    await client.query(`UPDATE nurse_financial_admin_operations SET result=$3::jsonb
      WHERE actor_user_id=$1 AND idempotency_key=$2`,[actor,key,JSON.stringify(result)]);
    return result;
  }

  private async audit(q:Q,actor:string,nurseId:string,action:string,detail:unknown) {
    await q.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail)
      VALUES($1,$2,'nurse',$3,$4::jsonb)`,[actor,action,nurseId,JSON.stringify(detail)]);
  }
}
