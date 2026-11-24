import test from 'node:test';
import assert from 'node:assert/strict';
import { LedgerService } from '../dist/wallet/ledger.service.js';

test('Double-entry ledger rejects unbalanced transactions', async () => {
  const service = new LedgerService(null);
  const unbalancedLegs = [
    { accountId: 'NURSE_RECEIVABLE:123', debitAmount: 5000, creditAmount: 0 },
    { accountId: 'COMPANY_COMMISSIONS', debitAmount: 0, creditAmount: 4000 }, // off by 1000
  ];

  await assert.rejects(
    async () => service.postTransaction(null, unbalancedLegs, 'PLATFORM_COMMISSION'),
    err => {
      assert.equal(err.getResponse().code, 'LEDGER_TRANSACTION_UNBALANCED');
      assert.equal(err.getResponse().difference, 1000);
      return true;
    }
  );
});

test('Double-entry ledger rejects negative amounts and dual debit/credit on single leg', async () => {
  const service = new LedgerService(null);

  // Negative amount
  await assert.rejects(
    async () => service.postTransaction(null, [
      { accountId: 'ACC_1', debitAmount: -500, creditAmount: 0 },
      { accountId: 'ACC_2', debitAmount: 0, creditAmount: -500 },
    ], 'TEST'),
    err => err.getResponse().code === 'NEGATIVE_AMOUNTS_PROHIBITED'
  );

  // Both debit and credit on single leg
  await assert.rejects(
    async () => service.postTransaction(null, [
      { accountId: 'ACC_1', debitAmount: 500, creditAmount: 500 },
      { accountId: 'ACC_2', debitAmount: 500, creditAmount: 500 },
    ], 'TEST'),
    err => err.getResponse().code === 'LEG_MUST_BE_EXCLUSIVELY_DEBIT_OR_CREDIT'
  );
});

test('Double-entry ledger accepts balanced transaction and generates entries', async () => {
  const inserted = [];
  const mockClient = {
    query: async (sql, params) => {
      if (sql.includes('SELECT transaction_id')) return { rowCount: 0, rows: [] };
      if (sql.includes('INSERT INTO financial_ledger_entries')) {
        inserted.push(params);
        return { rowCount: 1 };
      }
      return { rowCount: 0, rows: [] };
    },
  };

  const service = new LedgerService(null);
  const balancedLegs = [
    { accountId: 'NURSE_RECEIVABLE:nurse-1', debitAmount: 7000, creditAmount: 0 },
    { accountId: 'COMPANY_COMMISSIONS', debitAmount: 0, creditAmount: 7000 },
  ];

  const result = await service.postTransaction(mockClient, balancedLegs, 'PLATFORM_COMMISSION', 'req-999');
  assert.equal(result.entriesCount, 2);
  assert.equal(inserted.length, 2);
  // Both legs share the exact same transaction ID
  assert.equal(inserted[0][0], inserted[1][0]);
});
