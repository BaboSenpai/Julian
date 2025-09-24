import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'firebase_options.dart' as fb_opts;

import 'package:van_inventory/services/cloud.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await fb_core.Firebase.initializeApp(
    options: fb_opts.DefaultFirebaseOptions.currentPlatform,
  );

  await Cloud.init(tenantId: 'van1');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Van Inventory',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const AuthGate(), // Login -> HomeScreen (dein altes UI)
    );
  }
}
