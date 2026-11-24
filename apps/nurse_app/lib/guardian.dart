import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:uuid/uuid.dart';

const guardianEnabled =
    bool.fromEnvironment('GUARDIAN_MOBILE_ENABLED') && !kDemoMode;

class GuardianController extends ChangeNotifier {
  final TamreedyApi api;
  GuardianController(this.api);

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
    if (sendingSos || (event != null && !eventClosed)) return;
    _pendingSos ??= {
      'clientEventId': const Uuid().v4(),
      'silent': true,
      if (sessionId != null) 'sessionId': sessionId,
    };
    sendingSos = true;
    sosUnconfirmed = false;
    _changed();
    try {
      final response = await api.post('/v1/safety/sos', _pendingSos!);
      if (response['id'] is! String || response['state'] is! String) {
        throw StateError('Missing server receipt');
      }
      _statusRead++;
      statusUnavailable = false;
      event = response;
      _pendingSos = null;
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
    final id = event?['id'];
    if (id is! String) return;
    final read = ++_statusRead;
    try {
      final response = await api.getMap('/v1/safety/events/$id');
      if (read != _statusRead || event?['id'] != id || response['id'] != id) return;
      event = response;
      statusUnavailable = false;
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
    final data = await api.getMap('/v1/safety/me/status');
    session = data['session'] as Map<String, dynamic>?;
    await _loadCheckin();
  });

  Future<void> start(String assignment) => _run(() async {
    session = await api.post('/v1/nurse/safety/sessions/start', {
      'assignmentId': assignment,
    });
    await _loadCheckin();
  });

  Future<void> checkout() => _run(() async {
    final id = sessionId;
    if (id == null) return;
    await api.post('/v1/nurse/safety/sessions/$id/checkout');
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
    super.dispose();
  }
}
