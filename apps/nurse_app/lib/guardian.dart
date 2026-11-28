import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:uuid/uuid.dart';
import 'guardian_sos_store.dart';
import 'guardian_location.dart';

const guardianEnabled =
    bool.fromEnvironment('GUARDIAN_MOBILE_ENABLED') && !kDemoMode;

class GuardianController extends ChangeNotifier {
  final TamreedyApi api;
  final GuardianSosStore _store;
  final Future<String?> Function() _accountId;
  GuardianController(
    this.api, {
    GuardianSosStore? store,
    Future<String?> Function()? accountId,
  }) : _store = store ?? SecureGuardianSosStore(),
       _accountId = accountId ?? (() => _readLocalAccountId(api));

  // Used only to namespace device storage. The API independently authenticates
  // the access token and verifies the expected reporter on every submission.
  static Future<String?> _readLocalAccountId(TamreedyApi api) async {
    try {
      final token = await api.accessToken();
      final payload = token?.split('.');
      if (payload == null || payload.length != 3) return null;
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload[1]))),
      );
      final id = json is Map ? json['sub'] : null;
      return id is String &&
              RegExp(
                r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
                caseSensitive: false,
              ).hasMatch(id)
          ? id
          : null;
    } catch (_) {
      return null;
    }
  }

  GuardianLocation? _location;
  GuardianLocation get location =>
      _location ??= GuardianLocation(api, _accountId);
  String? _owner;
  Future<void>? _restore;
  bool sosStorageUnavailable = false;

  DateTime? get sosTriggeredAt => DateTime.tryParse(
    '${_pendingSos?['triggeredAt'] ?? event?['triggered_at'] ?? ''}',
  )?.toLocal();

  DateTime? get sosReceivedAt => sosUnconfirmed
      ? null
      : DateTime.tryParse('${event?['received_at'] ?? ''}')?.toLocal();

  Future<void> restoreSos() {
    if (_restore case final Future<void> pending) return pending;
    late final Future<void> tracked;
    tracked = _restoreFromStorage().whenComplete(() {
      if (identical(_restore, tracked)) _restore = null;
    });
    _restore = tracked;
    return tracked;
  }

  Future<void> _restoreFromStorage() async {
    final generation = _sessionGeneration;
    final owner = await _accountId();
    if (!_current(generation) || owner == _owner) return;
    _owner = owner;
    _statusRead++;
    event = null;
    _pendingSos = null;
    sosUnconfirmed = false;
    statusUnavailable = false;
    sosStorageUnavailable = false;
    if (owner != null) {
      try {
        final saved = await _store.read(owner);
        if (!_current(generation) || _owner != owner) return;
        _pendingSos = saved.pending;
        event = saved.receipt;
        sosUnconfirmed = _pendingSos != null;
      } catch (_) {
        if (!_current(generation)) return;
        sosStorageUnavailable = true;
      }
    }
    _changed();
  }

  Future<void> _persistSos(String owner) async {
    final generation = _sessionGeneration;
    try {
      await _store.write(owner, (pending: _pendingSos, receipt: event));
      if (!_current(generation)) return;
      sosStorageUnavailable = false;
    } catch (_) {
      if (!_current(generation)) return;
      sosStorageUnavailable = true;
    }
  }

  Map<String, dynamic>? session;
  Map<String, dynamic>? checkin;
  Map<String, dynamic>? event;
  Map<String, dynamic>? _pendingSos;
  Map<String, dynamic>? _pendingCheckin;
  bool sendingSos = false;
  bool sosUnconfirmed = false;
  bool busy = false;
  bool statusUnavailable = false;
  String? error;
  bool _disposed = false;
  int _statusRead = 0;
  int _sessionGeneration = 0;

  bool _current(int generation) =>
      !_disposed && generation == _sessionGeneration;

  String? get sessionId => session?['id'] as String?;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> sendSos() async {
    if (sendingSos) return;
    final generation = _sessionGeneration;
    sendingSos = true;
    final tappedAt = DateTime.now().toUtc().toIso8601String();
    _changed();
    try {
      await restoreSos();
      final owner = _owner;
      if (!_current(generation)) return;
      if (owner == null) {
        sosUnconfirmed = true;
        return;
      }
      if (event != null && !eventClosed) return;
      _pendingSos ??= {
        'clientEventId': const Uuid().v4(),
        'expectedReporterId': owner,
        'triggeredAt': tappedAt,
        'silent': true,
        if (sessionId != null) 'sessionId': sessionId,
      };
      sosUnconfirmed = false;
      await _persistSos(owner);
      if (!_current(generation) ||
          await _accountId() != owner ||
          !_current(generation)) {
        return;
      }
      final response = await api.post('/v1/safety/sos', _pendingSos!);
      if (response['id'] is! String || response['state'] is! String) {
        throw StateError('Missing server receipt');
      }
      if (!_current(generation) ||
          await _accountId() != owner ||
          !_current(generation)) {
        return;
      }
      _statusRead++;
      statusUnavailable = false;
      event = response;
      _pendingSos = null;
      await _persistSos(owner);
    } catch (_) {
      if (!_current(generation)) return;
      sosUnconfirmed = true;
    } finally {
      if (_current(generation)) {
        sendingSos = false;
        _changed();
      }
    }
  }

  bool get eventClosed =>
      ['RESOLVED', 'FALSE_ALARM', 'CLOSED'].contains(event?['state']);

  Future<void> refreshSos() async {
    final generation = _sessionGeneration;
    await restoreSos();
    if (!_current(generation)) return;
    final owner = _owner;
    final id = event?['id'];
    if (owner == null || id is! String) return;
    final read = ++_statusRead;
    try {
      final response = await api.getMap('/v1/safety/events/$id');
      if (read != _statusRead || event?['id'] != id || response['id'] != id) {
        return;
      }
      event = response;
      statusUnavailable = false;
      await _persistSos(owner);
    } catch (_) {
      if (read != _statusRead) return;
      statusUnavailable = true;
    }
    _changed();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    final generation = _sessionGeneration;
    busy = true;
    error = null;
    _changed();
    try {
      await action();
    } catch (_) {
      if (_current(generation)) error = 'تعذر تحديث جلسة السلامة. حاول مجددًا.';
    } finally {
      if (_current(generation)) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> _loadCheckin() async {
    final generation = _sessionGeneration;
    final id = sessionId;
    if (id == null) {
      checkin = null;
      return;
    }
    final data = await api.getMap('/v1/nurse/safety/sessions/$id/checkin');
    if (!_current(generation) || sessionId != id) return;
    checkin = data['checkin'] as Map<String, dynamic>?;
    if (_pendingCheckin?['checkinId'] != checkin?['id']) _pendingCheckin = null;
  }

  Future<void> refreshSession() => _run(() async {
    final generation = _sessionGeneration;
    final previous = sessionId;
    final data = await api.getMap('/v1/safety/me/status');
    if (!_current(generation)) return;
    session = data['session'] as Map<String, dynamic>?;
    if (sessionId != previous) location.stop();
    await _loadCheckin();
  });

  Future<void> start(String assignment) => _run(() async {
    final generation = _sessionGeneration;
    final response = await api.post('/v1/nurse/safety/sessions/start', {
      'assignmentId': assignment,
    });
    if (!_current(generation)) return;
    session = response;
    await _loadCheckin();
  });

  Future<void> startLocation() async {
    final id = sessionId;
    final since = DateTime.tryParse('${session?['started_at']}');
    if (id == null || since == null) return;
    await location.start(
      id,
      since,
      int.tryParse('${session?['next_sequence']}') ?? 0,
    );
  }

  Future<bool> abortAssignment(String assignment) async {
    var finished = false;
    await _run(() async {
      final generation = _sessionGeneration;
      await restoreSos();
      if (!_current(generation)) return;
      final response = await api.post(
        '/v1/nurse/safety/assignments/$assignment/abort',
        {},
      );
      if (!_current(generation)) return;
      final id = response['eventId'];
      if (response['status'] != 'ESCALATED' || id is! String) {
        throw StateError('Invalid safe exit response');
      }
      finished = true;
      if (event?['id'] != id) {
        _statusRead++;
        event = {'id': id, 'state': 'UNKNOWN'};
        if (_owner case final String owner) await _persistSos(owner);
      }
      try {
        final receipt = await api.getMap('/v1/safety/events/$id');
        if (!_current(generation)) return;
        if (receipt['id'] == id && receipt['state'] is String) {
          _statusRead++;
          event = receipt;
          if (_owner case final String owner) await _persistSos(owner);
        }
      } catch (_) {
        if (!_current(generation)) return;
        statusUnavailable = true;
      }
    });
    return finished;
  }

  Future<void> checkout() => _run(() async {
    final generation = _sessionGeneration;
    final id = sessionId;
    if (id == null) return;
    location.stop();
    await api.post('/v1/nurse/safety/sessions/$id/checkout');
    if (!_current(generation)) return;
    location.sync();
    session = null;
    checkin = null;
    _pendingCheckin = null;
  });

  Future<void> respond(String response) => _run(() async {
    final generation = _sessionGeneration;
    final id = sessionId;
    final checkinId = checkin?['id'];
    if (id == null || checkinId == null) return;
    _pendingCheckin ??= {
      'checkinId': checkinId,
      'clientResponseId': const Uuid().v4(),
      'response': response,
    };
    await api.post('/v1/nurse/safety/sessions/$id/checkin', _pendingCheckin!);
    if (!_current(generation)) return;
    _pendingCheckin = null;
    await _loadCheckin();
  });

  String? get pendingResponse => _pendingCheckin?['response'] as String?;

  /// Drop account data in memory; durable SOS receipts remain namespaced to their owner.
  void resetForSessionChange() {
    _sessionGeneration++;
    _statusRead++;
    _location?.resetForSessionChange();
    _owner = null;
    _restore = null;
    session = null;
    checkin = null;
    event = null;
    _pendingSos = null;
    _pendingCheckin = null;
    sosUnconfirmed = false;
    sosStorageUnavailable = false;
    statusUnavailable = false;
    sendingSos = false;
    busy = false;
    error = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _location?.dispose();
    super.dispose();
  }
}
