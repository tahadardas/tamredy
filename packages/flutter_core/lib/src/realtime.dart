import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';
import 'core/notification_coordinator.dart';
import 'core/realtime_bus.dart';
import 'firebase_boot.dart';

/// FCM is enabled by default when google-services.json / GoogleService-Info.plist is present.
const bool kFcmEnabled = bool.fromEnvironment(
  'FCM_ENABLED',
  defaultValue: true,
);

/// Complete set of events emitted by `/live` Gateway.
const liveEvents = [
  'catalog.changed',
  'offer.created',
  'offer.expired',
  'offer.closed',
  'request.created',
  'request.clinical_review_changed',
  'request.assigned',
  'request.cancelled',
  'visit.interrupted',
  'request.unfulfilled',
  'request.schedule_released',
  'marketplace.request.published',
  'marketplace.request.updated',
  'marketplace.proposal.created',
  'marketplace.proposal.accepted',
  'marketplace.proposal.withdrawn',
  'marketplace.recovery.alert',
  'safety.event_changed',
  'safety.checkin_due',
  'safety.checkin_reminder',
  'visit.depart',
  'visit.arrive',
  'visit.start',
  'visit.complete',
  'visit.departure_delayed',
  'payment.updated',
  'payment.partially_paid',
  'payment.partial',
  'payment.paid',
  'payment.tip',
  'tracking.updated',
  'chat.message',
  'chat.read',
  'call.incoming',
  'call.ringing',
  'call.accepted',
  'call.rejected',
  'call.cancel',
  'call.signal',
  'call.connected',
  'call.reconnecting',
  'call.ended',
  'call.missed',
  'call.failed',
  'NOTIFICATION_RECEIVED',
];

/// One ingestion path for both transports; presentation has independent dedupe
/// in NotificationCoordinator.acceptEvent (used by the alarm presenters).
bool ingestPrivateEvent({
  required Map<String, dynamic> payload,
  required NotificationCoordinator? coordinator,
  required RealtimeEventBus? eventBus,
  String? fallbackType,
  void Function(String, Map<String, dynamic>)? onDomainData,
  void Function(String)? onDomainEvent,
  void Function(Map<String, dynamic>)? present,
}) {
  if (coordinator == null) return false;
  final event = AppNotificationEvent.fromMap(payload, fallbackType: fallbackType);
  if (!coordinator.isAuthorizedForThisApp(event) || event.isExpired) return false;
  final processed = coordinator.acceptDomainEvent(event);
  if (processed) {
    eventBus?.emit(eventId:event.eventId, type:event.eventType, payload:payload);
    onDomainData?.call(event.eventType,payload);
    onDomainEvent?.call(event.eventType);
  }
  // A previous delivery may only have consumed the domain event (for example
  // a cold-start tap). Presentation independently decides if it already ran.
  if (event.eventType != 'tracking.updated' && event.eventType != 'call.signal') present?.call(payload);
  return processed;
}

/// Primary WebSocket channel for Tamreedy 3.0.
/// Routes deduplicated events to [RealtimeEventBus] and [NotificationCoordinator]
/// WITHOUT triggering blanket REST resyncs on every event or GPS tick.
class LiveChannel {
  final TamreedyApi api;
  final RealtimeEventBus? eventBus;
  final NotificationCoordinator? coordinator;
  final VoidCallback onResync;
  final void Function(Map<String, dynamic>)? presentNotification;
  final void Function(String type)? onEvent;
  final void Function(String type, Map<String, dynamic> payload)? onEventData;

  io.Socket? _socket;
  bool _refreshing = false;
  bool _disposed = false;
  bool connected = false;
  final Set<String> _seenEvents = {};

  LiveChannel({
    required this.api,
    required this.onResync,
    required this.onEvent,
    this.onEventData,
    this.presentNotification,
    this.eventBus,
    this.coordinator,
  });

  io.Socket? get rawSocket => _socket;

  Future<void> start() async {
    if (_socket != null || _disposed) return;
    final epoch = api.sessionScopeEpoch.value;
    final token = await api.accessToken();
    if (token == null || epoch != api.sessionScopeEpoch.value || api.sessionChanging || _disposed) return;
    final s = io.io(
      TamreedyApi.socketNamespaceUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token, 'appType': api.appType})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .setRandomizationFactor(0.25)
          .disableAutoConnect()
          .build(),
    );
    _socket = s;
    eventBus?.signalSender = sendCallSignal;
    s.onConnect((_) {
      if (_disposed || epoch != api.sessionScopeEpoch.value) return;
      connected = true;
      eventBus?.setConnected(true);
      api.markOnline();
    });
    // Reconcile over REST only on socket (re)connection handshake.
    s.on('connected', (_) { if (!_disposed && epoch == api.sessionScopeEpoch.value) onResync(); });

    for (final e in liveEvents) {
      s.on(e, (data) {
        if (epoch != api.sessionScopeEpoch.value || api.sessionChanging) return;
        final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        if (e == 'catalog.changed') {
          eventBus?.emit(eventId:'catalog:${DateTime.now().microsecondsSinceEpoch}',type:e,payload:payload);
          onEventData?.call(e,payload);
          onEvent?.call(e);
          return;
        }
        ingestPrivateEvent(payload:payload,coordinator:coordinator,eventBus:eventBus,
          fallbackType:e,onDomainData:onEventData,onDomainEvent:onEvent,present:presentNotification);
      });
    }

    s.onDisconnect((reason) async {
      if (_disposed || epoch != api.sessionScopeEpoch.value) return;
      connected = false;
      eventBus?.setConnected(false);
      api.markReconnecting();
      if (reason == 'io server disconnect') await _reauth();
    });
    s.onConnectError((_) {
      if (_disposed || epoch != api.sessionScopeEpoch.value) return;
      connected = false;
      eventBus?.setConnected(false);
      api.markReconnecting();
      _reauth();
    });
    s.connect();
  }

  Future<Map<String, dynamic>?> sendCallSignal(String callId, Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null || !socket.connected) return null;
    final completer = Completer<Map<String, dynamic>?>();
    socket.emitWithAck('call.signal', {'callId':callId,...payload}, ack:(response) {
      if (completer.isCompleted) return;
      if (response is Map && response['relayed'] == true &&
          response['eventId'] == payload['eventId'] && response['sequenceNumber'] == payload['sequenceNumber']) {
        completer.complete(Map<String,dynamic>.from(response));
      } else {
        completer.complete(null);
      }
    });
    return completer.future.timeout(const Duration(seconds:2), onTimeout:()=>null);
  }

  Future<bool> sendLocation(Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    final completer = Completer<bool>();
    socket.emitWithAck('location.update', payload, ack: (response) {
      if (!completer.isCompleted) {
        completer.complete(response is Map && response['sequenceNumber'] == payload['sequenceNumber']);
      }
    });
    return completer.future.timeout(const Duration(seconds: 2), onTimeout: () => false);
  }

  Future<void> _reauth() async {
    if (_refreshing || _disposed || api.sessionChanging) return;
    final epoch = api.sessionScopeEpoch.value;
    _refreshing = true;
    try {
      if (await api.refreshNow()) {
        final t = await api.accessToken();
        if (t != null && _socket != null && !_disposed && epoch == api.sessionScopeEpoch.value) {
          _socket!.auth = {'token': t, 'appType': api.appType};
          _socket!.connect();
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  void dispose() {
    _disposed = true;
    eventBus?.signalSender = null;
    _socket?.dispose();
    _socket = null;
    _seenEvents.clear();
  }
}

/// Dedicated authenticated location transport (uses [LiveChannel] when shared,
/// or falls back to its own socket when instantiated standalone).
class LiveLocationChannel {
  final TamreedyApi api;
  final LiveChannel? sharedChannel;
  io.Socket? _socket;
  bool get connected => sharedChannel?.connected ?? (_socket?.connected == true);

  LiveLocationChannel(this.api, {this.sharedChannel});

  Future<void> start() async {
    if (sharedChannel != null) {
      await sharedChannel!.start();
      return;
    }
    if (_socket != null) return;
    final epoch = api.sessionScopeEpoch.value;
    final token = await api.accessToken();
    if (token == null || epoch != api.sessionScopeEpoch.value || api.sessionChanging) return;
    final socket = io.io(
      TamreedyApi.socketNamespaceUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token, 'appType': api.appType})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;
    socket.connect();
  }

  Future<bool> send(Map<String, dynamic> payload) async {
    if (sharedChannel != null) {
      return sharedChannel!.sendLocation(payload);
    }
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    final completer = Completer<bool>();
    socket.emitWithAck('location.update', payload, ack: (response) {
      if (!completer.isCompleted) {
        completer.complete(response is Map && response['sequenceNumber'] == payload['sequenceNumber']);
      }
    });
    return completer.future.timeout(const Duration(seconds: 2), onTimeout: () => false);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}

/// Registers this device for FCM with role/app isolation and routes foreground/tap/cold-start pushes.
class PushRegistrar {
  final TamreedyApi api;
  final VoidCallback onPush;
  final RealtimeEventBus? eventBus;
  final void Function(String, Map<String, dynamic>)? onDomainData;
  final void Function(String)? onDomainEvent;
  int? _sessionEpoch;
  bool _disposed = false;
  bool get _currentSession => !_disposed && _sessionEpoch == api.sessionScopeEpoch.value;
  final NotificationCoordinator? coordinator;
  final void Function(Map<String, dynamic> data)? onForegroundData;

  StreamSubscription<RemoteMessage>? _fg, _opened;
  StreamSubscription<String>? _refresh;
  String? _lastRegisteredToken;

  PushRegistrar({
    required this.api,
    required this.onPush,
    this.eventBus,
    this.onDomainData,
    this.onDomainEvent,
    this.coordinator,
    this.onForegroundData,
  });

  Future<void> start() async {
    _sessionEpoch = api.sessionScopeEpoch.value;
    _disposed = false;
    if (!kFcmEnabled || kIsWeb) return;
    try {
      if (!await FirebaseBoot.ensure() || !_currentSession) return;
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (!_currentSession || perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await m.getToken();
      if (!_currentSession) return;
      if (token != null) await _register(token);
      if (!_currentSession) return;
      _refresh = m.onTokenRefresh.listen(_register);

      // Cold-start launch from notification tap
      final initial = await m.getInitialMessage();
      if (initial != null && _currentSession) {
        ingestPrivateEvent(payload:initial.data,coordinator:coordinator,eventBus:eventBus,
          onDomainData:onDomainData,onDomainEvent:onDomainEvent);
        coordinator?.routeFromTap(initial.data, coldStart: true);
      }

      if (!_currentSession) return;
      _fg = FirebaseMessaging.onMessage.listen((msg) {
        if (!_currentSession) return;
        ingestPrivateEvent(payload:msg.data,coordinator:coordinator,eventBus:eventBus,
          onDomainData:onDomainData,onDomainEvent:onDomainEvent,present:onForegroundData);
      });

      _opened = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (!_currentSession) return;
        ingestPrivateEvent(payload:msg.data,coordinator:coordinator,eventBus:eventBus,
          onDomainData:onDomainData,onDomainEvent:onDomainEvent);
        if (coordinator != null) {
          coordinator!.routeFromTap(msg.data);
        }
        onPush();
      });
    } catch (e) {
      debugPrint('push disabled: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      if (!_currentSession) return;
      final devId = await api.getDeviceId();
      if (!_currentSession) return;
      await api.post('/v1/devices', {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'deviceId': devId,
        'appType': api.appType,
      });
      _lastRegisteredToken = token;
    } catch (_) {
      /* retried on next launch / token refresh */
    }
  }

  Future<void> unregister() async {
    try {
      final devId = await api.getDeviceId();
      await api.delete('/v1/devices', {
        if (_lastRegisteredToken != null) 'token': _lastRegisteredToken,
        'deviceId': devId,
        'appType': api.appType,
      });
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _fg?.cancel();
    _opened?.cancel();
    _refresh?.cancel();
  }
}

/// Signed-in Realtime & Push host.
/// In Tamreedy 3.0, events flow directly to [RealtimeEventBus] and [NotificationCoordinator]
/// without triggering redundant global `onResync` calls on every single event!
class RealtimeHost extends StatefulWidget {
  final TamreedyApi api;
  final VoidCallback onResync;
  final void Function(String type)? onEvent;
  final void Function(String type, Map<String, dynamic> payload)? onEventData;
  final RealtimeEventBus? eventBus;
  final NotificationCoordinator? coordinator;
  final void Function(Map<String, dynamic> data)? onForegroundPush;
  final Widget child;

  const RealtimeHost({
    super.key,
    required this.api,
    required this.onResync,
    this.onEvent,
    this.onEventData,
    this.eventBus,
    this.coordinator,
    this.onForegroundPush,
    required this.child,
  });

  @override
  State<RealtimeHost> createState() => _RealtimeHostState();
}

class _RealtimeHostState extends State<RealtimeHost> with WidgetsBindingObserver {
  LiveChannel? _live;
  PushRegistrar? _push;
  DateTime _lastResyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _debouncedResync() {
    final now = DateTime.now();
    if (now.difference(_lastResyncAt) < const Duration(seconds: 3)) return;
    _lastResyncAt = now;
    widget.onResync();
  }

  @override
  void initState() {
    super.initState();
    if (kDemoMode) return;
    WidgetsBinding.instance.addObserver(this);
    widget.api.sessionScopeEpoch.addListener(_onSessionEpochChanged);
    _startChannels();
  }

  void _startChannels() {
    _live?.dispose();
    _push?.dispose();
    _live = LiveChannel(
      api: widget.api,
      eventBus: widget.eventBus,
      coordinator: widget.coordinator,
      onResync: _debouncedResync,
      onEventData: widget.onEventData,
      presentNotification: widget.onForegroundPush,
      onEvent: widget.onEvent,
    )..start();
    _push = PushRegistrar(
      api: widget.api,
      coordinator: widget.coordinator,
      onForegroundData: widget.onForegroundPush,
      eventBus: widget.eventBus,
      onDomainData: widget.onEventData,
      onDomainEvent: widget.onEvent,
      onPush: _debouncedResync,
    )..start();
  }

  void _onSessionEpochChanged() {
    if (!mounted || kDemoMode) return;
    if (widget.api.sessionChanging || widget.api.authSessionSignal.value != null) {
      _live?.dispose();
      _live = null;
      _push?.dispose();
      _push = null;
    } else {
      _startChannels();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _debouncedResync();
    }
  }

  @override
  void dispose() {
    widget.api.sessionScopeEpoch.removeListener(_onSessionEpochChanged);
    WidgetsBinding.instance.removeObserver(this);
    _live?.dispose();
    _push?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
