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
    final work = _restoreFromStorage();
    _restore = work;
    return work.whenComplete(() => _restore = null);
  }

  Future<void> _restoreFromStorage() async {
    final owner = await _accountId();
    if (_disposed || owner == _owner) return;
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
        _pendingSos = saved.pending;
        event = saved.receipt;
        sosUnconfirmed = _pendingSos != null;
      } catch (_) {
        sosStorageUnavailable = true;
      }
    }
    _changed();
  }

  Future<void> _persistSos(String owner) async {
    try {
      await _store.write(owner, (pending: _pendingSos, receipt: event));
      sosStorageUnavailable = false;
    } catch (_) {
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

  String? get sessionId => session?['id'] as String?;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> sendSos() async {
    if (sendingSos) return;
    sendingSos = true;
    final tappedAt = DateTime.now().toUtc().toIso8601String();
    _changed();
    try {
      await restoreSos();
      final owner = _owner;
      if (_disposed) return;
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
      if (_disposed || await _accountId() != owner) return;
      final response = await api.post('/v1/safety/sos', _pendingSos!);
      if (response['id'] is! String || response['state'] is! String) {
        throw StateError('Missing server receipt');
      }
      if (_disposed || await _accountId() != owner) return;
      _statusRead++;
      statusUnavailable = false;
      event = response;
      _pendingSos = null;
      await _persistSos(owner);
    } catch (_) {
      sosUnconfirmed = true;
    } finally {
      sendingSos = false;
      _changed();
    }
  }

  bool get eventClosed =>
      ['RESOLVED', 'FALSE_ALARM', 'CLOSED'].contains(event?['state']);

  Future<void> refreshSos() async {
    await restoreSos();
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
    busy = true;
    error = null;
    _changed();
    try {
      await action();
    } catch (_) {
      error = 'تعذر تحديث جلسة السلامة. حاول مجددًا.';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _loadCheckin() async {
    final id = sessionId;
    if (id == null) {
      checkin = null;
      return;
    }
    final data = await api.getMap('/v1/nurse/safety/sessions/$id/checkin');
    checkin = data['checkin'] as Map<String, dynamic>?;
    if (_pendingCheckin?['checkinId'] != checkin?['id']) _pendingCheckin = null;
  }

  Future<void> refreshSession() => _run(() async {
    final previous = sessionId;
    final data = await api.getMap('/v1/safety/me/status');
    session = data['session'] as Map<String, dynamic>?;
    if (sessionId != previous) location.stop();
    await _loadCheckin();
  });

  Future<void> start(String assignment) => _run(() async {
    session = await api.post('/v1/nurse/safety/sessions/start', {
      'assignmentId': assignment,
    });
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
      await restoreSos();
      final response = await api.post('/v1/nurse/safety/assignments/$assignment/abort', {});
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
        if (receipt['id'] == id && receipt['state'] is String) {
          _statusRead++;
          event = receipt;
          if (_owner case final String owner) await _persistSos(owner);
        }
      } catch (_) {
        statusUnavailable = true;
      }
    });
    return finished;
  }

  Future<void> checkout() => _run(() async {
    final id = sessionId;
    if (id == null) return;
    location.stop();
    await api.post('/v1/nurse/safety/sessions/$id/checkout');
    location.sync();
    session = null;
    checkin = null;
    _pendingCheckin = null;
  });

  Future<void> respond(String response) => _run(() async {
    final id = sessionId;
    final checkinId = checkin?['id'];
    if (id == null || checkinId == null) return;
    _pendingCheckin ??= {
      'checkinId': checkinId,
      'clientResponseId': const Uuid().v4(),
      'response': response,
    };
    await api.post('/v1/nurse/safety/sessions/$id/checkin', _pendingCheckin!);
    _pendingCheckin = null;
    await _loadCheckin();
  });

  String? get pendingResponse => _pendingCheckin?['response'] as String?;

  @override
  void dispose() {
    _disposed = true;
    _location?.dispose();
    super.dispose();
  }
}
