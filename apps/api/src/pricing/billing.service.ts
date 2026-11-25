import { createHash } from 'node:crypto';
import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { LedgerService, type LedgerLegInput } from '../wallet/ledger.service.js';
import { DuesService } from './fees.service.js';
import { ReferralService } from './referral.service.js';

export interface FinalBill {
  timeGross: number;
  gross: number;
  discount: number;
  surcharge: number;
  distanceFee: number;
  tax: number;
  due: number;
  commission: number;
  nurseEarning: number;
  minutes: number;
}

const positiveLeg = (accountId: string, debit: number, credit: number): LedgerLegInput | null =>
  debit > 0 || credit > 0 ? { accountId, debitAmount: debit, creditAmount: credit } : null;

@Injectable()
export class BillingService {
  constructor(
    private readonly ledger: LedgerService,
    private readonly dues: DuesService,
    private readonly referrals: ReferralService,
  ) {}

  async issueInvoice(
    client: PoolClient,
    requestId: string,
    visitId: string,
    nurseId: string,
    currencyCode: string,
    bill: FinalBill,
    pricingSnapshot: Record<string, unknown>,
  ) {
    const items = await client.query(`SELECT cri.id,cri.quantity,cri.performed_quantity,cri.unit_price,
      cri.item_status,cri.status_reason,s.title_ar
      FROM care_request_items cri JOIN services s ON s.id=cri.service_id
      WHERE cri.request_id=$1 ORDER BY cri.created_at,cri.id FOR UPDATE OF cri`, [requestId]);
    if (!items.rowCount || items.rows.some(item => item.item_status === 'PENDING')) {
      throw new ConflictException({ code: 'REQUEST_ITEMS_REQUIRE_OUTCOME' });
    }
    if (!items.rows.some(item => item.item_status === 'COMPLETED')) {
      throw new ConflictException({ code: 'NO_SERVICE_ITEM_COMPLETED' });
    }

    const existing = await client.query('SELECT * FROM invoices WHERE request_id=$1', [requestId]);
    if (existing.rowCount) return { invoice: existing.rows[0], replayed: true };

    const invoice = (await client.query(`INSERT INTO invoices(
      request_id,visit_id,status,currency_code,subtotal,discount_amount,surcharge_amount,
      distance_fee,tax_amount,total_amount,pricing_snapshot
    ) VALUES($1,$2,CASE WHEN $9::numeric=0 THEN 'PAID' ELSE 'ISSUED' END,$3,$4,$5,$6,$7,$8,$9,$10::jsonb) RETURNING *`,
    [requestId,visitId,currencyCode,bill.gross,bill.discount,bill.surcharge,bill.distanceFee,
      bill.tax,bill.due,JSON.stringify(pricingSnapshot)])).rows[0];

    let itemBaseTotal = 0;
    for (const item of items.rows.filter(row => row.item_status === 'COMPLETED')) {
      const lineAmount = Number(item.unit_price) * Number(item.performed_quantity);
      itemBaseTotal += lineAmount;
      await client.query(`INSERT INTO invoice_lines(
        invoice_id,request_item_id,line_type,description_ar,quantity,unit_amount,line_amount
      ) VALUES($1,$2,'SERVICE',$3,$4,$5,$6)`,
      [invoice.id,item.id,item.title_ar,item.performed_quantity,item.unit_price,lineAmount]);
    }
    if (bill.timeGross !== itemBaseTotal) {
      await client.query(`INSERT INTO invoice_lines(invoice_id,line_type,description_ar,unit_amount,line_amount)
        VALUES($1,'ADJUSTMENT','تسوية مدة الخدمة',$2,$2)`, [invoice.id,bill.timeGross-itemBaseTotal]);
    }
    const extraLines: Array<[string,string,number]> = [
      ['SURCHARGE','رسوم إضافية',bill.surcharge], ['DISTANCE','بدل المسافة',bill.distanceFee],
      ['DISCOUNT','الخصم',-bill.discount], ['TAX','الضريبة',bill.tax],
    ];
    for (const [type,description,amount] of extraLines) {
      if (amount === 0) continue;
      await client.query(`INSERT INTO invoice_lines(invoice_id,line_type,description_ar,unit_amount,line_amount)
        VALUES($1,$2,$3,$4,$4)`, [invoice.id,type,description,amount]);
    }

    const legs: LedgerLegInput[] = [];
    const add = (leg: LedgerLegInput | null) => { if (leg) legs.push(leg); };
    add(positiveLeg('PATIENT_RECEIVABLE',bill.due,0));
    add(positiveLeg('DISCOUNTS_EXPENSE',bill.discount,0));
    add(positiveLeg('COMMISSION_REVENUE',0,bill.commission));
    add(positiveLeg('TAX_PAYABLE',0,bill.tax));
    add(positiveLeg(`NURSE_PAYABLE:${nurseId}`,0,bill.nurseEarning));
    const debit = bill.due + bill.discount;
    const credit = bill.commission + bill.tax + bill.nurseEarning;
    add(positiveLeg('ROUNDING_ADJUSTMENTS',Math.max(0,credit-debit),Math.max(0,debit-credit)));
    if (legs.length) await this.ledger.postTransaction(client, {
      transactionType: 'INVOICE_ISSUED',referenceType: 'INVOICE',referenceId: invoice.id,
      idempotencyKey: `invoice:${requestId}`,currencyCode,legs,
    });

    const reservations = await client.query(`SELECT id,nurse_id,amount,prepaid_amount,credit_amount
      FROM financial_reservations
      WHERE reference_id=$1 AND status='HELD' FOR UPDATE`, [requestId]);
    for (const reservation of reservations.rows) {
      await this.ledger.resolveReservation(client,reservation.id,'COMMITTED');
      if (reservation.nurse_id) {
        await client.query(`UPDATE nurse_financial_accounts SET
          reserved_balance=greatest(0,reserved_balance-$2),
          prepaid_balance=greatest(0,prepaid_balance-$3),updated_at=statement_timestamp()
          WHERE nurse_id=$1`, [reservation.nurse_id,reservation.amount,reservation.prepaid_amount]);
      }
    }
    return { invoice, replayed: false };
  }

  async collectCash(
    client: PoolClient,
    nurseUserId: string,
    requestId: string,
    amount: number,
    idempotencyKey: string,
  ) {
    if (!idempotencyKey || idempotencyKey.length > 128) {
      throw new BadRequestException({ code: 'IDEMPOTENCY_KEY_REQUIRED' });
    }
    const digest = createHash('sha256').update(JSON.stringify({ requestId, amount })).digest('hex');
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',
      [`payment.collection:${nurseUserId}:${idempotencyKey}`]);
    const existing = await client.query(`SELECT cc.*,i.status AS invoice_status,
      i.total_amount+i.tip_amount-i.paid_amount AS remaining
      FROM cash_collections cc JOIN invoices i ON i.visit_id=cc.visit_id
      JOIN nurses n ON n.id=cc.collector_nurse_id
      WHERE n.user_id=$1 AND cc.idempotency_key=$2`, [nurseUserId,idempotencyKey]);
    if (existing.rowCount) {
      if (existing.rows[0].payload_digest !== digest) throw new ConflictException({ code: 'FINANCIAL_IDEMPOTENCY_KEY_REUSED' });
      const previous=existing.rows[0];
      return { ...previous,status:previous.invoice_status,remaining:Number(previous.remaining),
        change:Number(previous.change_amount),replayed:true };
    }

    const row = (await client.query(`SELECT i.*,cr.requester_user_id,n.id AS nurse_id,v.id AS visit_id
      FROM invoices i JOIN care_requests cr ON cr.id=i.request_id
      JOIN visits v ON v.id=i.visit_id JOIN request_assignments a ON a.id=v.assignment_id
      JOIN nurses n ON n.id=a.nurse_id
      WHERE i.request_id=$1 AND n.user_id=$2 FOR UPDATE OF i,cr`, [requestId,nurseUserId])).rows[0];
    if (!row) throw new ConflictException({ code: 'INVOICE_NOT_COLLECTIBLE' });
    if (row.status === 'PAID') throw new ConflictException({ code: 'ALREADY_PAID' });

    const payable = Number(row.total_amount)+Number(row.tip_amount);
    const remainingBefore = payable-Number(row.paid_amount);
    const applied = Math.min(amount,remainingBefore);
    const change = amount-applied;
    const paidAmount = Number(row.paid_amount)+applied;
    const status = paidAmount === payable ? 'PAID' : 'PARTIALLY_PAID';

    const transaction = await this.ledger.postTransaction(client, {
      transactionType: 'CASH_COLLECTION',referenceType: 'INVOICE',referenceId: row.id,
      idempotencyKey: `collection:${row.nurse_id}:${idempotencyKey}`,currencyCode: row.currency_code,
      actorUserId: nurseUserId,
      legs: [
        { accountId: `CASH_HELD_BY_NURSE:${row.nurse_id}`,debitAmount: applied,creditAmount: 0 },
        { accountId: 'PATIENT_RECEIVABLE',debitAmount: 0,creditAmount: applied },
      ],
    });
    const collection = (await client.query(`INSERT INTO cash_collections(
      visit_id,collector_nurse_id,amount,idempotency_key,payload_digest,
      received_amount,applied_amount,change_amount,transaction_id,status
    ) VALUES($1,$2,$3,$4,$5,$6,$3,$7,$8,'CONFIRMED') RETURNING *`,
    [row.visit_id,row.nurse_id,applied,idempotencyKey,digest,amount,change,transaction.transactionId])).rows[0];
    await client.query(`UPDATE invoices SET status=$2,paid_amount=$3,
      paid_at=CASE WHEN $2='PAID' THEN statement_timestamp() ELSE NULL END,version=version+1
      WHERE id=$1`, [row.id,status,paidAmount]);
    await client.query(`UPDATE care_requests SET payment_status=$2,
      paid_at=CASE WHEN $2='PAID' THEN statement_timestamp() ELSE NULL END,version=version+1,updated_at=statement_timestamp()
      WHERE id=$1`, [requestId,status === 'PAID' ? 'PAID' : 'PARTIAL']);
    if (status === 'PAID') {
      await this.dues.enforce(client,row.nurse_id);
      await this.referrals.rewardIfFirstPaid(client,row.requester_user_id);
    }
    await client.query(`INSERT INTO request_events(request_id,actor_user_id,event_type,payload)
      VALUES($1,$2,$3,$4::jsonb)`, [requestId,nurseUserId,`payment.${status.toLowerCase()}`,
      JSON.stringify({received:amount,applied,change,remaining:payable-paidAmount,collectionId:collection.id})]);
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES($1,$2,$3::jsonb)`, [`payment.${status.toLowerCase()}`,requestId,
      JSON.stringify({requestId,recipientUserId:row.requester_user_id})]);
    return { ...collection,status,remaining:payable-paidAmount,change,replayed:false };
  }

  async setTip(
    client: PoolClient,
    patientUserId: string,
    requestId: string,
    amount: number,
    idempotencyKey: string,
  ) {
    if (!idempotencyKey || idempotencyKey.length > 128) {
      throw new BadRequestException({ code: 'IDEMPOTENCY_KEY_REQUIRED' });
    }
    const row = (await client.query(`SELECT i.*,cr.requester_user_id,a.nurse_id,n.user_id AS nurse_user_id
      FROM invoices i JOIN care_requests cr ON cr.id=i.request_id
      JOIN visits v ON v.id=i.visit_id JOIN request_assignments a ON a.id=v.assignment_id
      JOIN nurses n ON n.id=a.nurse_id
      WHERE i.request_id=$1 AND cr.requester_user_id=$2 FOR UPDATE OF i,cr`, [requestId,patientUserId])).rows[0];
    if (!row) throw new ConflictException({ code: 'INVOICE_NOT_FOUND' });
    if (row.status === 'PAID') throw new ConflictException({ code: 'ALREADY_PAID' });
    if (Number(row.tip_amount) > 0) {
      if (Number(row.tip_amount) === amount) return {tip:amount,replayed:true};
      throw new ConflictException({ code: 'TIP_ALREADY_SET' });
    }
    if (amount > 0) {
      await this.ledger.postTransaction(client, {
        transactionType:'TIP_ADDED',referenceType:'INVOICE',referenceId:row.id,
        idempotencyKey:`tip:${patientUserId}:${idempotencyKey}`,currencyCode:row.currency_code,
        actorUserId:patientUserId,
        legs:[
          {accountId:'PATIENT_RECEIVABLE',debitAmount:amount,creditAmount:0},
          {accountId:`NURSE_PAYABLE:${row.nurse_id}`,debitAmount:0,creditAmount:amount},
        ],
      });
      await client.query(`INSERT INTO invoice_lines(invoice_id,line_type,description_ar,unit_amount,line_amount)
        VALUES($1,'TIP','إكرامية للممرض',$2,$2)`, [row.id,amount]);
    }
    await client.query('UPDATE invoices SET tip_amount=$2,version=version+1 WHERE id=$1', [row.id,amount]);
    await client.query('UPDATE care_requests SET tip_amount=$2,updated_at=statement_timestamp() WHERE id=$1', [requestId,amount]);
    await client.query(`INSERT INTO outbox_events(event_type,aggregate_id,payload)
      VALUES('payment.tip',$1,$2::jsonb)`, [requestId,JSON.stringify({requestId,recipientUserId:row.nurse_user_id})]);
    return {tip:amount,replayed:false};
  }
}
