import 'dart:async';
import 'firebase_boot.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';

/// FCM is enabled by default when google-services.json / GoogleService-Info.plist is present.
const bool kFcmEnabled = bool.fromEnvironment(
  'FCM_ENABLED',
  defaultValue: true,
);

/// Events the server emits on `/live` (payloads only carry ids; details come from REST).
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
  'safety.event_changed',
  'safety.checkin_due',
  'safety.checkin_reminder',
  'visit.depart',
  'visit.arrive',
  'visit.start',
  'visit.complete',
  'payment.updated',
  'payment.partially_paid',
  'payment.paid',
  'payment.tip',
  'tracking.updated',
];

/// Best-effort realtime channel. REST is the source of truth: every (re)connect,
/// app resume and push triggers [onResync], so missed events never leave stale UI.
class LiveChannel {
  final TamreedyApi api;
  final VoidCallback onResync;
  final void Function(String type) onEvent;
  final void Function(String type, Map<String, dynamic> payload)? onEventData;
  io.Socket? _socket;
  bool _refreshing = false;
  bool connected = false;
  final Set<String> _seenEvents = {};

  LiveChannel({
    required this.api,
    required this.onResync,
    required this.onEvent,
    this.onEventData,
  });

  Future<void> start() async {
    if (_socket != null) return;
    final token = await api.accessToken();
    if (token == null) return;
    final s = io.io(
      '${TamreedyApi.baseUrl}/live',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );
    _socket = s;
    s.onConnect((_) => connected = true);
    // Server accepts the socket, then tells us to reconcile over REST.
    s.on('connected', (_) => onResync());
    for (final e in liveEvents) {
      s.on(e, (data) {
        if (data is Map) {
          final eventId = data['eventId'];
          if (eventId is String) {
            if (!_seenEvents.add(eventId)) return;
            if (_seenEvents.length > 512) _seenEvents.remove(_seenEvents.first);
          }
          onEventData?.call(e, Map<String, dynamic>.from(data));
        }
        onEvent(e);
      });
    }
    s.onDisconnect((reason) async {
      connected = false;
      // The server drops sockets whose access token expired: refresh and reconnect with the new one.
      if (reason == 'io server disconnect') await _reauth();
    });
    s.onConnectError((_) => _reauth());
    s.connect();
  }

  Future<void> _reauth() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (await api.refreshNow()) {
        final t = await api.accessToken();
        if (t != null && _socket != null) {
          _socket!.auth = {'token': t};
          _socket!.connect();
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _seenEvents.clear();
  }
}

/// Registers this device for FCM and forwards taps/foreground pushes as a resync.
class PushRegistrar {
  final TamreedyApi api;
  final VoidCallback onPush;
  StreamSubscription<RemoteMessage>? _fg, _opened;
  StreamSubscription<String>? _refresh;
  PushRegistrar({required this.api, required this.onPush});

  /// Never throws: the app must run without Firebase configured.
  Future<void> start() async {
    if (!kFcmEnabled || kIsWeb) return;
    try {
      if (!await FirebaseBoot.ensure()) return;
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await m.getToken();
      if (token != null) await _register(token);
      _refresh = m.onTokenRefresh.listen(_register);
      _fg = FirebaseMessaging.onMessage.listen((_) => onPush());
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((_) => onPush());
    } catch (e) {
      debugPrint('push disabled: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await api.post('/v1/devices', {
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      });
    } catch (_) {
      /* retried on next launch / token refresh */
    }
  }

  void dispose() {
    _fg?.cancel();
    _opened?.cancel();
    _refresh?.cancel();
  }
}

/// Wrap the signed-in shell: runs the socket + push, resyncs on app resume.
/// Does nothing in demo mode.
class RealtimeHost extends StatefulWidget {
  final TamreedyApi api;
  final VoidCallback onResync;
  final void Function(String type)? onEvent;
  final void Function(String type, Map<String, dynamic> payload)? onEventData;
  final Widget child;
  const RealtimeHost({
    super.key,
    required this.api,
    required this.onResync,
    this.onEvent,
    this.onEventData,
    required this.child,
  });
  @override
  State<RealtimeHost> createState() => _RealtimeHostState();
}

class _RealtimeHostState extends State<RealtimeHost>
    with WidgetsBindingObserver {
  LiveChannel? _live;
  PushRegistrar? _push;

  @override
  void initState() {
    super.initState();
    if (kDemoMode) return;
    WidgetsBinding.instance.addObserver(this);
    _live = LiveChannel(
      api: widget.api,
      onResync: widget.onResync,
      onEventData: widget.onEventData,
      onEvent: (t) {
        widget.onEvent?.call(t);
        widget.onResync();
      },
    )..start();
    _push = PushRegistrar(api: widget.api, onPush: widget.onResync)..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.onResync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live?.dispose();
    _push?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
