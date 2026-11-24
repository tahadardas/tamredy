import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef GuardianSosState = ({
  Map<String, dynamic>? pending,
  Map<String, dynamic>? receipt,
});

abstract interface class GuardianSosStore {
  Future<GuardianSosState> read(String owner);
  Future<void> write(String owner, GuardianSosState state);
}

class SecureGuardianSosStore implements GuardianSosStore {
  final _storage = const FlutterSecureStorage();

  String _key(String owner) => 'guardian.sos.v1.$owner';

  @override
  Future<GuardianSosState> read(String owner) async {
    final raw = await _storage.read(key: _key(owner));
    if (raw == null) return (pending: null, receipt: null);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (
      pending: decoded['pending'] as Map<String, dynamic>?,
      receipt: decoded['receipt'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<void> write(String owner, GuardianSosState state) => _storage.write(
    key: _key(owner),
    value: jsonEncode({'pending': state.pending, 'receipt': state.receipt}),
  );
}
