import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

const alarmChannelId = 'tamreedy_offers_v3';
const nurseUpdatesChannelId = 'tamreedy_nurse_updates_v3';
const alarmSound = RawResourceAndroidNotificationSound('tamreedy_alert');

class AlarmData {
  final String offerId;
  final String title;
  final String body;
  final int ttlSeconds;
  final Map<String, dynamic> data;

  const AlarmData(
    this.offerId,
    this.title,
    this.body,
    this.ttlSeconds, {
    this.data = const {},
  });

  static AlarmData? from(Map<String, dynamic> d, {DateTime? now}) {
    final type = '${d['eventType'] ?? d['type'] ?? ''}';
    final isOfferAlarm = type == 'offer.created' ||
        type == 'visit.departure_delayed' ||
        type == 'call.incoming' ||
        '${d['alarm']}' == '1' ||
        '${d['priority'] ?? ''}'.toUpperCase() == 'ALARM';
    if (!isOfferAlarm) return null;

    var ttl = int.tryParse('${d['ttl']}') ?? 30;
    final exp = DateTime.tryParse('${d['expiresAt'] ?? ''}');
    if (exp != null) {
      ttl = exp.difference(now ?? DateTime.now().toUtc()).inSeconds;
      if (ttl <= 1) return null;
    }
    final id = '${d['offerId'] ?? d['callId'] ?? d['proposalId'] ?? d['requestId'] ?? DateTime.now().millisecondsSinceEpoch}';
    return AlarmData(
      id,
      '${d['title'] ?? (type == 'call.incoming' ? 'مكالمة واردة من المريض' : 'طلب زيارة جديد قريب منك')}',
      '${d['body'] ?? 'افتح التطبيق للرد الآن'}',
      ttl.clamp(2, 60),
      data: d,
    );
  }

  int get notificationId => notificationIdFor(offerId);

  static int notificationIdFor(String offerId) {
    return offerId.codeUnits.fold(7, (value, unit) => (31 * value + unit) & 0x7fffffff);
  }
}

/// Nurse App alarm & push handler (Tamreedy 3.0).
class OfferAlarm {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static final _closedUntil = <String, DateTime>{};
  static final Set<String> _handledEventIds = <String>{};
  static final List<String> _handledOrder = <String>[];
  static bool disabledForTesting = false;
  static NotificationCoordinator? coordinator;
  static void Function(Map<String, dynamic> data)? onTapData;

  static bool _markHandled(String eventId) {
    if (eventId.isEmpty) return true;
    if (_handledEventIds.contains(eventId)) return false;
    _handledEventIds.add(eventId);
    _handledOrder.add(eventId);
    if (_handledOrder.length > 256) {
      _handledEventIds.remove(_handledOrder.removeAt(0));
    }
    return true;
  }

  static Future<void> init() async {
    if (disabledForTesting || _ready || kIsWeb || !Platform.isAndroid) {
      return;
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        cancelAll();
        if (r.actionId == 'mute_alarm') return;
        Map<String, dynamic> data = const {};
        final payload = r.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) {
              data = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }
        if (data.isNotEmpty && coordinator != null) {
          coordinator!.routeFromTap(data);
        }
        onTapData?.call(data);
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        alarmChannelId,
        'تنبيهات العروض الفورية والمكالمات',
        description: 'إنذار صوتي فوري عند وصول عرض زيارة أو مكالمة واردة',
        importance: Importance.max,
        playSound: true,
        sound: alarmSound,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 900, 300, 900, 300, 900]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        showBadge: true,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        nurseUpdatesChannelId,
        'تحديثات الزيارات والمستحقات',
        description: 'إشعارات اعتيادية لحالة الزيارات والرسائل والتسويات',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    _ready = true;
  }

  static Future<void> requestPermissions() async {
    if (disabledForTesting || kIsWeb || !Platform.isAndroid) return;
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
  }

  static Future<void> show(AlarmData a) async {
    if (disabledForTesting || kIsWeb || !Platform.isAndroid) return;
    try {
      await init();
      final now = DateTime.now();
      _closedUntil.removeWhere((_, expires) => !expires.isAfter(now));
      if (!_ready || _closedUntil.containsKey(a.offerId)) return;
      await _plugin.show(
        a.notificationId,
        a.title,
        a.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            alarmChannelId,
            'تنبيهات العروض الفورية والمكالمات',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: true,
            playSound: true,
            sound: alarmSound,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 900, 300, 900, 300, 900]),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            additionalFlags: Int32List.fromList([4]),
            timeoutAfter: a.ttlSeconds * 1000,
            visibility: NotificationVisibility.public,
            ticker: a.title,
            actions: const [
              AndroidNotificationAction(
                'mute_alarm',
                'كتم الرنين',
                cancelNotification: true,
                showsUserInterface: false,
              ),
            ],
          ),
        ),
        payload: jsonEncode(a.data),
      );
    } catch (e) {
      debugPrint('nurse alarm not shown: $e');
    }
  }

  static Future<void> showStandardNotification({
    required String id,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    if (disabledForTesting || kIsWeb || !Platform.isAndroid) return;
    try {
      await init();
      if (!_ready) return;
      await _plugin.show(
        AlarmData.notificationIdFor(id),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            nurseUpdatesChannelId,
            'تحديثات الزيارات والمستحقات',
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
            playSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('nurse notification not shown: $e');
    }
  }

  static Future<void> handle(
    Map<String, dynamic> data, {
    String? titleOverride,
    String? bodyOverride,
  }) async {
    final role = '${data['recipientRole'] ?? ''}'.toUpperCase();
    final targetApp = '${data['targetApp'] ?? ''}'.toUpperCase();
    // BUG-028: Require explicit non-empty role & targetApp matching NURSE / NURSE_APP
    if (role != 'NURSE' || targetApp != 'NURSE_APP') return;
    final authUid = coordinator?.authenticatedUserId;
    final recipientUid = '${data['recipientUserId'] ?? ''}'.trim();
    if (authUid != null && authUid.isNotEmpty && recipientUid != authUid) return;

    final type = '${data['eventType'] ?? data['type'] ?? ''}';
    if (type == 'offer.closed' || type == 'offer.expired') {
      final id = data['offerId']?.toString();
      if (id != null && id.isNotEmpty) await cancelOffer(id);
      return;
    }

    final eventId = '${data['eventId'] ?? data['id'] ?? ''}';
    if (coordinator != null) {
      final ev = AppNotificationEvent.fromMap(data);
      if (!coordinator!.acceptEvent(ev, dedupe: true)) return;
    } else if (!_markHandled(eventId)) {
      return;
    }

    final merged = {
      ...data,
      'title': ?titleOverride,
      'body': ?bodyOverride,
    };

    final alarm = AlarmData.from(merged);
    if (alarm != null) {
      await show(alarm);
      return;
    }

    final title = titleOverride ?? data['title']?.toString() ?? 'تحديث في حساب الممرض';
    final body = bodyOverride ?? data['body']?.toString() ?? 'افتح تطبيق الممرض لعرض التفاصيل';
    final id = eventId.isNotEmpty
        ? eventId
        : '${data['requestId'] ?? data['proposalId'] ?? DateTime.now().millisecondsSinceEpoch}';
    await showStandardNotification(id: id, title: title, body: body, data: merged);
  }

  static Future<void> cancelOffer(String offerId) async {
    _closedUntil[offerId] = DateTime.now().add(const Duration(minutes: 5));
    try {
      await init();
      if (_ready) await _plugin.cancel(AlarmData.notificationIdFor(offerId));
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> offerBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await OfferAlarm.handle(
    message.data,
    titleOverride: message.notification?.title,
    bodyOverride: message.notification?.body,
  );
}
