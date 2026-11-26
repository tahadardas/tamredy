import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'alarm.dart';
import 'app/nurse_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TamreedyApi.baseUrl;
  await Analytics.init(appRole: 'nurse');
  await FirebaseBoot.ensure();
  await OfferAlarm.init();
  FirebaseMessaging.onBackgroundMessage(offerBackgroundHandler);
  runApp(const TamreedyNurseApp());
}
