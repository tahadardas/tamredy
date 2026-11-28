import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

/// One unresolved creation per owner. A changed draft cannot replace a request
/// whose outcome is unknown, and a confirmed response survives process death.
class PendingRequestOperationStore {
  final TamreedyApi api;
  PendingRequestOperationStore(this.api);
  Future<void> _mutations = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _mutations;
    final completion = Completer<void>();
    _mutations = completion.future;
    await previous;
    try {
      return await action();
    } finally {
      completion.complete();
    }
  }

  String _key(String owner) => 'pending_create_op_$owner';

  Future<Map<String, dynamic>?> read(String owner) async {
    if (owner.isEmpty) throw StateError('Authenticated owner required');
    final raw = await api.readLocal(_key(owner));
    if (raw == null) return null;
    final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (value['ownerUserId'] != owner) {
      throw StateError('Request operation owner mismatch');
    }
    return value;
  }

  Future<Map<String, dynamic>> begin(
    String owner,
    Map<String, dynamic> payload, {
    bool expectsClinicalUpload = false,
  }) => _serial(() async {
    final canonical = jsonEncode(canonicalize(payload));
    final hash = base64Encode(
      (await Sha256().hash(utf8.encode(canonical))).bytes,
    );
    final previous = await read(owner);
    if (previous != null && previous['status'] != 'RECONCILED') {
      // Compare the canonical payload as well for records from the previous
      // release, whose payloadHash used FNV rather than SHA-256.
      if (previous['canonicalPayload'] != canonical) {
        throw StateError(
          'يوجد طلب سابق غير محسوم. استعد نتيجته قبل إرسال طلب مختلف.',
        );
      }
      return previous;
    }
    final value = <String, dynamic>{
      'operationId': api.newIdempotencyKey(),
      'idempotencyKey': api.newIdempotencyKey(),
      'payloadHash': hash,
      'canonicalPayload': canonical,
      'ownerUserId': owner,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'PENDING',
      'expectsClinicalUpload': expectsClinicalUpload,
    };
    await api.writeLocal(_key(owner), jsonEncode(value));
    return value;
  });

  Future<void> confirm(
    String owner,
    Map<String, dynamic> operation,
    Map<String, dynamic> response,
  ) => _serial(() async {
    final current = await read(owner);
    if (current == null || current['operationId'] != operation['operationId']) {
      throw StateError('Superseded request operation');
    }
    if (current['status'] == 'RECONCILED') return;
    if (operation['ownerUserId'] != owner ||
        '${response['id'] ?? ''}'.isEmpty) {
      throw StateError('Invalid confirmed request operation');
    }
    await api.writeLocal(
      _key(owner),
      jsonEncode({
        ...operation,
        'status': 'CONFIRMED',
        'requestId': response['id'],
        'confirmedResponse': response,
        'confirmedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  });

  Future<void> reconcile(String owner, String requestId) => _serial(() async {
    final operation = await read(owner);
    if (operation == null ||
        operation['status'] != 'CONFIRMED' ||
        operation['requestId'] != requestId) {
      throw StateError('Request operation has not been durably confirmed');
    }
    await api.writeLocal(
      _key(owner),
      jsonEncode({
        'operationId': operation['operationId'],
        'ownerUserId': owner,
        'requestId': requestId,
        'status': 'RECONCILED',
        'reconciledAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  });

  static Object? canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: canonicalize(value[key])};
    }
    if (value is List) return value.map(canonicalize).toList();
    return value;
  }
}
