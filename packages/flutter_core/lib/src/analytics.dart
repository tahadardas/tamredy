import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import 'firebase_boot.dart';

/// Turn on with `--dart-define=ANALYTICS_ENABLED=true`. Collection is also gated
/// by [Analytics.setConsent] so the app can show a consent prompt first.
const bool kAnalyticsEnabled = bool.fromEnvironment(
  'ANALYTICS_ENABLED',
  defaultValue: false,
);

/// Product analytics (Google Analytics 4 via Firebase). Safe no-op when
/// Firebase is not configured. PRIVACY RULE: never send names, phone numbers,
/// addresses, coordinates or medical notes — only ids, counts, amounts and enums.
class Analytics {
  static FirebaseAnalytics? _fa;
  static bool _consent = true;

  static Future<void> init({required String appRole}) async {
    if (!kAnalyticsEnabled || !await FirebaseBoot.ensure()) return;
    _fa = FirebaseAnalytics.instance;
    await _fa!.setAnalyticsCollectionEnabled(_consent);
    await _fa!.setUserProperty(name: 'app_role', value: appRole);
  }

  /// Call with the user's choice (e.g. from a consent dialog or settings).
  static Future<void> setConsent(bool granted) async {
    _consent = granted;
    await _fa?.setAnalyticsCollectionEnabled(granted);
  }

  /// Pseudonymous account id (uuid) lets GA4 count returning users across devices.
  static Future<void> identify(String userId) async =>
      _fa?.setUserId(id: userId);
  static Future<void> reset() async => _fa?.setUserId(id: null);

  static void screen(String name) {
    final fa = _fa;
    if (fa == null) return;
    fa.logScreenView(screenName: name).catchError((_) {});
  }

  static void log(String name, [Map<String, Object>? params]) {
    final fa = _fa;
    if (fa == null) return;
    fa.logEvent(name: name, parameters: params).catchError((_) {});
  }

  /// GA4 standard `purchase` event: gives revenue reports and marketing attribution.
  static void purchase({
    required String id,
    required num value,
    required String method,
    String? serviceId,
  }) {
    final fa = _fa;
    if (fa == null) return;
    fa
        .logPurchase(
          transactionId: id,
          value: value.toDouble(),
          currency: 'SYP',
          items: [
            AnalyticsEventItem(
              itemId: serviceId ?? 'visit',
              itemName: serviceId ?? 'visit',
            ),
          ],
          parameters: {'payment_method': method},
        )
        .catchError((_) {});
  }
}

/// Logs a `screen_view` once when the wrapped screen is first built.
class ScreenLogger extends StatefulWidget {
  final String name;
  final Widget child;
  const ScreenLogger({super.key, required this.name, required this.child});
  @override
  State<ScreenLogger> createState() => _ScreenLoggerState();
}

class _ScreenLoggerState extends State<ScreenLogger> {
  @override
  void initState() {
    super.initState();
    Analytics.screen(widget.name);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
