import 'dart:convert';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

const patientCallChannelId = 'tamreedy_patient_calls_v3';
const patientUpdatesChannelId = 'tamreedy_patient_updates_v3';
const patientAlertSound = RawResourceAndroidNotificationSound('tamreedy_alert');

/// Patient App notification & call alert handler (Tamreedy 3.0).
///
/// Enforces:
/// - Role isolation (`PATIENT` / `PATIENT_APP` only).
/// - `eventId` deduplication and expiry checks.
/// - Clear separation between insistent call alarms (`call.incoming`)
///   and standard high-priority updates (proposals, assignment, visit progress, billing, chat).
class PatientAlarm {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static NotificationCoordinator? coordinator;
  static void Function(Map<String, dynamic> data)? onTapData;

  static final Set<String> _handledEventIds = <String>{};
  static final List<String> _handledOrder = <String>[];

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
    if (_ready || kIsWeb || !Platform.isAndroid) return;
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
        patientCallChannelId,
        'المكالمات الواردة',
        description: 'رنين وتنبيه فوري عند ورود مكالمة صوتية من الممرض',
        importance: Importance.max,
        playSound: true,
        sound: patientAlertSound,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 800, 250, 800, 250, 1000]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        patientUpdatesChannelId,
        'تحديثات الطلب والزيارة',
        description: 'عروض الممرضين وتقدم الزيارة والفواتير والمحادثات',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    _ready = true;
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
  }

  static Future<void> showCallAlert({
    required String id,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    int timeoutSeconds = 45,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    final notificationId = id.codeUnits.fold(
      13,
      (value, unit) => (31 * value + unit) & 0x7fffffff,
    );
    try {
      await _plugin.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            patientCallChannelId,
            'المكالمات الواردة',
            channelDescription: 'رنين وتنبيه فوري عند ورود مكالمة صوتية من الممرض',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            autoCancel: true,
            timeoutAfter: timeoutSeconds * 1000,
            playSound: true,
            sound: patientAlertSound,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
            visibility: NotificationVisibility.public,
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
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('patient call alarm not shown: $e');
    }
  }

  static Future<void> showStandardNotification({
    required String id,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    final notificationId = id.codeUnits.fold(
      17,
      (value, unit) => (31 * value + unit) & 0x7fffffff,
    );
    try {
      await _plugin.show(
        notificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            patientUpdatesChannelId,
            'تحديثات الطلب والزيارة',
            channelDescription: 'عروض الممرضين وتقدم الزيارة والفواتير والمحادثات',
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
            playSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('patient notification not shown: $e');
    }
  }

  static Future<void> handlePush(
    Map<String, dynamic> data, {
    String? titleOverride,
    String? bodyOverride,
  }) async {
    final role = '${data['recipientRole'] ?? ''}'.toUpperCase();
    final targetApp = '${data['targetApp'] ?? ''}'.toUpperCase();
    // BUG-028: Require explicit non-empty role & targetApp matching PATIENT / PATIENT_APP
    if (role != 'PATIENT' || targetApp != 'PATIENT_APP') return;
    final authUid = coordinator?.authenticatedUserId;
    final recipientUid = '${data['recipientUserId'] ?? ''}'.trim();
    if (authUid != null && authUid.isNotEmpty && recipientUid != authUid) return;

    final expiresAt = DateTime.tryParse('${data['expiresAt'] ?? ''}');
    if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) return;

    final eventId = '${data['eventId'] ?? data['id'] ?? ''}';
    if (coordinator != null) {
      final ev = AppNotificationEvent.fromMap(data);
      if (!coordinator!.acceptEvent(ev, dedupe: true)) return;
    } else if (!_markHandled(eventId)) {
      return;
    }

    final type = '${data['eventType'] ?? data['type'] ?? ''}';
    final isCallAlarm = type == 'call.incoming' || '${data['priority'] ?? ''}'.toUpperCase() == 'ALARM';

    final title = titleOverride ??
        data['title']?.toString() ??
        switch (type) {
          'call.incoming' => 'مكالمة صوتية واردة',
          'marketplace.proposal.created' => 'عرض جديد من ممرض',
          'request.assigned' => 'تم إسناد الطلب لممرض',
          'visit.depart' => 'الممرض في الطريق إليك',
          'visit.arrive' => 'وصل الممرض إلى موقعك',
          'visit.start' => 'بدأت الزيارة التمريضية',
          'visit.complete' => 'تم إنهاء الزيارة',
          'chat.message' => 'رسالة جديدة في المحادثة',
          _ => 'تحديث على طلبك',
        };
    final body = bodyOverride ??
        data['body']?.toString() ??
        switch (type) {
          'call.incoming' => 'اضغط للرد على المكالمة الآن',
          'marketplace.proposal.created' => 'راجع العرض المقدم وقارن وقت الوصول',
          'chat.message' => 'افتح المحادثة لقراءة الرسالة',
          _ => 'افتح تطبيق تمريضي لمتابعة التفاصيل',
        };

    final notifKey = eventId.isNotEmpty
        ? eventId
        : '${data['callId'] ?? data['proposalId'] ?? data['requestId'] ?? DateTime.now().millisecondsSinceEpoch}';

    if (isCallAlarm) {
      await showCallAlert(id: notifKey, title: title, body: body, data: data);
    } else {
      await showStandardNotification(id: notifKey, title: title, body: body, data: data);
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _plugin.cancelAll();
  }
}

@pragma('vm:entry-point')
Future<void> patientBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase options may not be configured in local/dev builds.
  }
  await PatientAlarm.handlePush(
    message.data,
    titleOverride: message.notification?.title,
    bodyOverride: message.notification?.body,
  );
}
