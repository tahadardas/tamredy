import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const patientAlertChannelId = 'tamreedy_patient_alerts_v1';
const patientUpdatesChannelId = 'tamreedy_patient_updates_v1';
const patientAlertSound = RawResourceAndroidNotificationSound('tamreedy_alert');

/// Loud, insistent alert with full-screen wake-up intent for the Patient App
/// when a nurse submits a proposal or accepts/updates an active visit.
class PatientAlarm {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function()? onTap;

  static Future<void> init() async {
    if (_ready || kIsWeb || !Platform.isAndroid) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        cancelAll();
        if (r.actionId != 'mute_alarm') {
          onTap?.call();
        }
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        patientAlertChannelId,
        'تنبيهات عروض الممرضين',
        description: 'رنين وتنبيه فوري عند وصول عرض جديد أو قبول الطلب',
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
        'تحديثات حالة الزيارة',
        description: 'إشعارات اعتيادية لمسار الزيارة والمدفوعات بدون رنين متكرر',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    _ready = true;
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
  }

  static Future<void> showAlert({
    required String id,
    required String title,
    required String body,
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
            patientAlertChannelId,
            'تنبيهات عروض الممرضين',
            channelDescription: 'رنين وتنبيه فوري عند وصول عرض جديد أو قبول الطلب',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
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
                'إيقاف الرنين',
                cancelNotification: true,
                showsUserInterface: false,
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('patient alarm not shown: $e');
    }
  }

  static Future<void> showStandardNotification({
    required String id,
    required String title,
    required String body,
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
            'تحديثات حالة الزيارة',
            channelDescription: 'إشعارات اعتيادية لمسار الزيارة والمدفوعات بدون رنين متكرر',
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
            playSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('patient notification not shown: $e');
    }
  }

  static Future<void> handlePush(Map<String, dynamic> data) async {
    final type = '${data['type'] ?? ''}';
    final isAlarm =
        '${data['alarm']}' == '1' ||
        type == 'marketplace.proposal.created' ||
        type == 'request.assigned' ||
        type == 'call.incoming';
    final title = '${data['title'] ?? (type == 'call.incoming' ? 'مكالمة صوتية واردة' : isAlarm ? 'وصلك عرض تمريض جديد!' : 'تحديث على طلبك')}';
    final body = '${data['body'] ?? (type == 'call.incoming' ? 'افتح التطبيق للرد على المكالمة' : isAlarm ? 'افتح التطبيق لاستعراض العرض وقبول الممرض' : 'افتح التطبيق لمتابعة التفاصيل')}';
    final id = '${data['callId'] ?? data['proposalId'] ?? data['messageId'] ?? data['requestId'] ?? DateTime.now().millisecondsSinceEpoch}';
    if (isAlarm) {
      await showAlert(id: id, title: title, body: body);
    } else {
      await showStandardNotification(id: id, title: title, body: body);
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
    // Firebase options may not be configured in dev builds.
  }
  await PatientAlarm.handlePush(message.data);
}
