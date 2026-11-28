import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

typedef SafetyFix = ({
  double latitude,
  double longitude,
  double accuracy,
  DateTime capturedAt,
});

abstract interface class SafetyPointStore {
  Future<String?> read(String account);
  Future<void> write(String account, String value);
}

class SecureSafetyPointStore implements SafetyPointStore {
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String account) =>
      _storage.read(key: 'guardian.points.v1.$account');

  @override
  Future<void> write(String account, String value) =>
      _storage.write(key: 'guardian.points.v1.$account', value: value);
}

class GuardianLocation extends ChangeNotifier with WidgetsBindingObserver {
  final TamreedyApi _api;
  final Future<String?> Function() _accountId;
  final SafetyPointStore _store;
  final Future<Stream<SafetyFix>> Function() _positions;

  GuardianLocation(
    this._api,
    this._accountId, {
    SafetyPointStore? store,
    Future<Stream<SafetyFix>> Function()? positions,
  }) : _store = store ?? SecureSafetyPointStore(),
       _positions = positions ?? _platformPositions {
    WidgetsBinding.instance.addObserver(this);
  }

  static const _limit = 1500;
  static const _interval = Duration(seconds: 30);
  Future<void> _operations = Future.value();
  StreamSubscription<SafetyFix>? _stream;
  Timer? _retry;
  Timer? _stopAtExpiry;
  String? _owner;
  String? _session;
  DateTime? _lastFix;
  bool _starting = false;
  bool _sending = false;
  bool _syncRequested = false;
  bool _disposed = false;
  bool _foreground = true;
  int _generation = 0;
  int _accountGeneration = 0;
  int queued = 0;
  String? error;

  bool get capturing => _stream != null;
  bool get starting => _starting;

  static Future<Stream<SafetyFix>> _platformPositions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('GPS disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw StateError('Location permission required');
    }
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).map(
      (p) => (
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        capturedAt: p.timestamp,
      ),
    );
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _operations.then((_) => action());
    _operations = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace stackTrace) {},
    );
    return next;
  }

  Map<String, dynamic> get _empty => {
    'pending': <String, dynamic>{},
    'sequence': <String, dynamic>{},
  };

  Future<Map<String, dynamic>> _load(String owner) async {
    final raw = await _store.read(owner);
    return raw == null ? _empty : jsonDecode(raw) as Map<String, dynamic>;
  }

  int _count(Map<String, dynamic> data) => (data['pending'] as Map).values.fold(
    0,
    (int count, batch) => count + (batch as List).length,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start(
    String session,
    DateTime startedAt,
    int nextSequence,
  ) async {
    if (_starting || capturing || !_foreground || _disposed) return;
    final expiry = startedAt.add(const Duration(hours: 12));
    if (!DateTime.now().isBefore(expiry)) {
      error = 'انتهت مدة تسجيل الموقع لهذه الجلسة.';
      _notify();
      return;
    }
    _starting = true;
    error = null;
    final generation = ++_generation;
    _notify();
    try {
      final owner = await _accountId();
      if (_disposed || generation != _generation) return;
      if (owner == null) throw StateError('Account required');
      final positions = await _positions();
      if (_disposed || generation != _generation || !_foreground) return;
      _session = session;
      _owner = owner;
      _lastFix = null;
      _stream = positions.listen(
        (fix) =>
            _capture(owner, session, nextSequence, generation, startedAt, fix),
        onError: (Object _) {
          stop();
          error = 'انقطع التقاط الموقع. تحقق من خدمة الموقع وأعد تشغيله.';
          _notify();
        },
        onDone: stop,
      );
      _stopAtExpiry = Timer(expiry.difference(DateTime.now()), stop);
      unawaited(sync());
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error = 'تعذر تشغيل سجل الموقع. تحقق من GPS وأذونات الموقع.';
    } finally {
      if (!_disposed && generation == _generation) {
        _starting = false;
        _notify();
      }
    }
  }

  Future<void> _capture(
    String owner,
    String session,
    int minimum,
    int generation,
    DateTime startedAt,
    SafetyFix fix,
  ) async {
    if (_generation != generation || _session != session || _owner != owner) {
      return;
    }
    final now = DateTime.now();
    if (fix.capturedAt.isBefore(
          startedAt.subtract(const Duration(minutes: 1)),
        ) ||
        fix.capturedAt.isAfter(now.add(const Duration(minutes: 1)))) {
      return;
    }
    if (_lastFix != null && now.difference(_lastFix!) < _interval) return;
    if (!fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        !fix.accuracy.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180 ||
        fix.accuracy < 0 ||
        fix.accuracy > 10000) {
      return;
    }
    _lastFix = now;
    try {
      await _serial(() async {
        if (_generation != generation || await _accountId() != owner) return;
        final data = await _load(owner);
        if (_count(data) >= _limit) throw StateError('Location storage full');
        final pending = data['pending'] as Map<String, dynamic>;
        final batches = data['sequence'] as Map<String, dynamic>;
        final saved = batches[session] as int? ?? 0;
        final sequence = saved > minimum ? saved : minimum;
        final points = pending.putIfAbsent(session, () => <dynamic>[]) as List;
        points.add({
          'sequence': sequence,
          'latitude': fix.latitude,
          'longitude': fix.longitude,
          'accuracy': fix.accuracy,
          'capturedAt': fix.capturedAt.toUtc().toIso8601String(),
        });
        batches[session] = sequence + 1;
        await _store.write(owner, jsonEncode(data));
        if (generation == _generation) queued = _count(data);
      });
      if (_disposed || generation != _generation) return;
      _notify();
      unawaited(sync());
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error =
          'تعذر حفظ نقطة الموقع على الجهاز. تحقّق من التخزين أو زامن النقاط المعلّقة.';
      _notify();
    }
  }

  Future<void> sync() async {
    if (_disposed || !_foreground) return;
    if (_sending) {
      _syncRequested = true;
      return;
    }
    final accountGeneration = _accountGeneration;
    bool current() => !_disposed && accountGeneration == _accountGeneration;
    _sending = true;
    _retry?.cancel();
    var failed = false;
    try {
      final owner = await _accountId();
      if (!current() || owner == null) return;
      while (current() && _foreground && await _accountId() == owner) {
        if (!current()) return;
        final snapshot = await _serial(() => _load(owner));
        if (!current()) return;
        queued = _count(snapshot);
        final pending = snapshot['pending'] as Map<String, dynamic>;
        if (pending.isEmpty) break;
        final session = pending.keys.first;
        final batch = (pending[session] as List).take(50).toList();
        final result = await _api.post(
          '/v1/nurse/safety/sessions/$session/locations/batch',
          {'points': batch},
        );
        if (!current()) return;
        final accepted = (result['acceptedSequences'] as List).toSet();
        if (!batch.every((point) => accepted.contains(point['sequence']))) {
          throw StateError('Incomplete acknowledgement');
        }
        await _serial(() async {
          final data = await _load(owner);
          final pending = data['pending'] as Map<String, dynamic>;
          (pending[session] as List?)?.removeWhere(
            (p) => accepted.contains(p['sequence']),
          );
          if ((pending[session] as List?)?.isEmpty ?? false) {
            pending.remove(session);
          }
          await _store.write(owner, jsonEncode(data));
          if (current()) queued = _count(data);
        });
      }
      if (!current()) return;
      error = null;
    } catch (_) {
      if (!current()) return;
      failed = true;
      error =
          'تعذرت مزامنة نقاط الموقع. تبقى النقاط المحفوظة بانتظار إعادة المحاولة.';
      if (_foreground && !_disposed) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 30), () => unawaited(sync()));
      }
    } finally {
      if (current()) {
        _sending = false;
        final repeat = _syncRequested && !failed;
        _syncRequested = false;
        if (repeat) unawaited(sync());
        _notify();
      }
    }
  }

  void resetForSessionChange() {
    _accountGeneration++;
    _retry?.cancel();
    _retry = null;
    _syncRequested = false;
    _sending = false;
    _starting = false;
    queued = 0;
    error = null;
    stop();
  }

  void stop() {
    _generation++;
    _starting = false;
    _stopAtExpiry?.cancel();
    unawaited(_stream?.cancel());
    _stream = null;
    _session = null;
    _owner = null;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(sync());
    } else {
      _retry?.cancel();
      stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    stop();
    super.dispose();
  }
}
