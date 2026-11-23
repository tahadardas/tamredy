import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android channel for new-request alarms. The id carries a version: Android freezes a channel's sound/importance
/// once created, so changing the tone later means shipping a new id.
const alarmChannelId = 'tamreedy_offers_v1';
const alarmSound = RawResourceAndroidNotificationSound(
  'tamreedy_alert',
); // android/app/src/main/res/raw/tamreedy_alert.wav

/// Data of a new-request push (see apps/worker/src/push.ts `alarmMessage`).
class AlarmData {
  final String offerId, title, body;
  final int ttlSeconds;
  const AlarmData(this.offerId, this.title, this.body, this.ttlSeconds);

  /// null when the message is not an alarm, or the offer already expired.
  static AlarmData? from(Map<String, dynamic> d, {DateTime? now}) {
    if ('${d['alarm']}' != '1') return null;
    var ttl = int.tryParse('${d['ttl']}') ?? 20;
    final exp = DateTime.tryParse('${d['expiresAt']}');
    if (exp != null) {
      // Remaining life of the offer: the alarm must stop exactly when the offer does.
      ttl = exp.difference(now ?? DateTime.now()).inSeconds;
    }
    if (ttl <= 1) return null;
    return AlarmData(
      '${d['offerId'] ?? ''}',
      '${d['title'] ?? 'طلب جديد قريب منك'}',
      '${d['body'] ?? 'افتح التطبيق للقبول'}',
      ttl.clamp(1, 60),
    );
  }

  int get notificationId =>
      (offerId.isEmpty ? 7 : offerId.hashCode & 0x7fffffff);
}

/// Long, loud, insistent alarm with the signature Tamreedy tone for every nearby nurse when a request arrives:
/// max-importance alarm channel, FLAG_INSISTENT (the sound repeats until the offer expires or is dismissed),
/// full-screen intent over the lock screen, strong vibration, and a timeout equal to the offer's remaining life.
class OfferAlarm {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool disabledForTesting = false;
  static void Function()? onTap;

  static Future<void> init() async {
    if (disabledForTesting || _ready || kIsWeb || !Platform.isAndroid) {
      return;
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        cancelAll(); // tapping silences the alarm and opens the app on the offer
        onTap?.call();
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        alarmChannelId,
        'طلبات جديدة قريبة منك',
        description: 'إنذار صوتي طويل عند وصول طلب جديد',
        importance: Importance.max,
        playSound: true,
        sound: alarmSound,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([
          0,
          900,
          300,
          900,
          300,
          900,
          300,
          1200,
        ]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        showBadge: true,
      ),
    );
    _ready = true;
  }

  /// Ask once (when the nurse goes available): notifications + full-screen alerts over the lock screen (Android 14+).
  static Future<void> requestPermissions() async {
    if (disabledForTesting || kIsWeb || !Platform.isAndroid) return;
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
  }

  static Future<void> show(AlarmData a) async {
    if (disabledForTesting || kIsWeb || !Platform.isAndroid) return;
    try {
      await init();
      if (!_ready) return;
      await _plugin.show(
        a.notificationId,
        a.title,
        a.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            alarmChannelId,
            'طلبات جديدة قريبة منك',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: true,
            playSound: true,
            sound: alarmSound,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([
              0,
              900,
              300,
              900,
              300,
              900,
              300,
              1200,
            ]),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            additionalFlags: Int32List.fromList([
              4,
            ]), // FLAG_INSISTENT: keep repeating the sound
            timeoutAfter:
                a.ttlSeconds * 1000, // stops by itself when the offer expires
            visibility: NotificationVisibility.public,
            ticker: a.title,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'alarm not shown: $e',
      ); // never break the app because of the alarm
    }
  }

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

/// Runs in a background isolate when a push arrives while the app is closed or in the background.
@pragma('vm:entry-point')
Future<void> offerBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final a = AlarmData.from(message.data);
  if (a != null) await OfferAlarm.show(a);
}
