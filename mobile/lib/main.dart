import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Run `flutterfire configure` from mobile/ to generate firebase_options.dart
  // and wire up native platform config (google-services.json, GoogleService-Info.plist).
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: DeliveryApp()));
}
