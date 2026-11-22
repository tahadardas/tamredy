import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase is optional: without google-services.json / GoogleService-Info.plist
/// the apps still run (demo, tests, web). Initialised at most once.
class FirebaseBoot {
  static Future<bool>? _once;
  static bool ready = false;

  static Future<bool> ensure() => _once ??= _init();

  static Future<bool> _init() async {
    if (kIsWeb) return false;
    try {
      await Firebase.initializeApp();
      ready = true;
    } catch (e) {
      debugPrint('Firebase unavailable: $e');
    }
    return ready;
  }
}
