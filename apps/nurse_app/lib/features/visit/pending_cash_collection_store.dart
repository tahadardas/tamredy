import 'dart:convert';

import 'package:tamreedy_core/tamreedy_core.dart';

enum CashCollectionStatus { pending, confirmed, reconciled, failedRequiresAction }
enum CashCollectionOutcome { partialConfirmed, fullyConfirmed, pendingReconciliation, failed }

class PendingCashCollection {
  const PendingCashCollection(this.data);
  final Map<String, dynamic> data;
  String get operationId => data['operationId'] as String;
  int get amount => data['amount'] as int;
  String get key => data['idempotencyKey'] as String;
  int? get invoiceVersion => data['invoiceVersion'] as int?;
  String? get legacyKey => data['legacyKey'] as String?;
  CashCollectionStatus get status => CashCollectionStatus.values.byName(data['status'] as String);

  bool matches(BillInfo bill, String owner) => data['ownerUserId'] == owner
      && data['requestId'] == bill.requestId && data['invoiceId'] == bill.invoiceId
      && data['currencyCode'] == bill.currencyCode;

  PendingCashCollection confirm(Map<String, dynamic> receipt) {
    final version = int.tryParse('${receipt['invoiceVersion']}');
    if (receipt['invoiceId'] != data['invoiceId'] || receipt['currencyCode'] != data['currencyCode'] ||
        receipt['paymentId'] is! String || version == null || version < 1) {
      throw const FormatException('إيصال التحصيل لا يطابق الفاتورة');
    }
    return PendingCashCollection({...data, 'paymentId':receipt['paymentId'], 'invoiceVersion':version,
      'status':CashCollectionStatus.confirmed.name, 'confirmedAt':DateTime.now().toUtc().toIso8601String()});
  }
}

/// One unresolved collection per invoice and owner. The visit store serializes writes.
class PendingCashCollectionStore {
  PendingCashCollectionStore(this.api);
  final TamreedyApi api;

  String _key(String owner, BillInfo bill) => 'cash_collection_rc3_${owner}_${bill.invoiceId}';

  Future<PendingCashCollection?> read(String owner, BillInfo bill) async {
    final raw = await api.readLocal(_key(owner,bill));
    if (raw == null) return null;
    final operation = PendingCashCollection(Map<String,dynamic>.from(jsonDecode(raw) as Map));
    if (!operation.matches(bill,owner)) throw const FormatException('عملية التحصيل لا تطابق الفاتورة');
    return operation;
  }

  Future<void> save(String owner, BillInfo bill, PendingCashCollection operation) async {
    if (!operation.matches(bill,owner)) throw const FormatException('عملية التحصيل لا تطابق الفاتورة');
    await api.writeLocal(_key(owner,bill),jsonEncode(operation.data));
  }

  PendingCashCollection create(String owner, BillInfo bill, int amount, {String? key, String? legacyKey}) {
    final operationId = api.newIdempotencyKey();
    return PendingCashCollection({'operationId':operationId, 'ownerUserId':owner,
      'requestId':bill.requestId,'invoiceId':bill.invoiceId,'amount':amount,'currencyCode':bill.currencyCode,
      'idempotencyKey':key ?? operationId,'paymentId':null,'status':CashCollectionStatus.pending.name,
      'createdAt':DateTime.now().toUtc().toIso8601String(),'confirmedAt':null,'legacyKey':?legacyKey});
  }

  Future<PendingCashCollection?> recoverLegacy(String owner, BillInfo bill) async {
    final v3 = 'cash_collect_v3_${bill.requestId}_';
    final v4 = 'cash_collect_v4_${owner}_${bill.requestId}_';
    final entries = {...await api.readLocalByPrefix(v3),...await api.readLocalByPrefix(v4)};
    if (entries.isEmpty) return null;
    final keys = entries.values.toSet();
    final amounts = entries.keys.map((key) => int.tryParse(key.split('_').last)).toSet();
    if (keys.length != 1 || amounts.length != 1 || amounts.single == null || amounts.single! <= 0) {
      throw const FormatException('توجد عمليات تحصيل قديمة متعددة، راجع الإدارة لتسويتها');
    }
    final operation = create(owner,bill,amounts.single!,key:keys.single,legacyKey:entries.keys.first);
    final status = await api.readCashCollection(bill.requestId!,operation.key);
    if (status['invoiceId'] != bill.invoiceId || status['currencyCode'] != bill.currencyCode ||
        (status['found'] == true && MoneyAmount.parse(status['receivedAmount'] as Object,bill.currencyCode).amountMinor !=
            MoneyAmount.parse(operation.amount,bill.currencyCode,decimalPlaces:2).amountMinor)) {
      throw const FormatException('بيانات التحصيل القديمة لا تطابق الفاتورة');
    }
    final recovered = status['found'] == true ? operation.confirm(status) : operation;
    await save(owner,bill,recovered);
    return recovered;
  }

  Future<void> reconcile(String owner, BillInfo bill, PendingCashCollection operation) async {
    await save(owner,bill,PendingCashCollection({...operation.data,'status':CashCollectionStatus.reconciled.name}));
    if (operation.legacyKey != null) {
      for (final key in ['cash_collect_v3_${bill.requestId}_${operation.amount}',
          'cash_collect_v4_${owner}_${bill.requestId}_${operation.amount}']) {
        if (await api.readLocal(key) == operation.key) await api.writeLocal(key,null);
      }
    }
  }
}
