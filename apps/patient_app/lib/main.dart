import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'app/patient_app.dart';
import 'patient_alarm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Validate API_BASE_URL & HTTPS requirement at startup.
  TamreedyApi.baseUrl;
  await Analytics.init(appRole: 'patient');
  await FirebaseBoot.ensure();
  await PatientAlarm.init();
  FirebaseMessaging.onBackgroundMessage(patientBackgroundHandler);
  runApp(const TamreedyPatientApp());
}
