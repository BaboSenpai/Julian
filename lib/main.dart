// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'firebase_options.dart' as fb_opts;

import 'package:van_inventory/models/models.dart';
import 'package:van_inventory/models/state.dart';
import 'package:van_inventory/models/storage.dart';
import 'package:van_inventory/services/cloud.dart';
import 'package:van_inventory/features/auth/auth_gate.dart';

import 'package:van_inventory/models/ui_state.dart' show initSkuBox;
import 'package:van_inventory/ui/screens.dart';

// Backend Switch
const String _backend = String.fromEnvironment('BACKEND', defaultValue: 'local');
const bool kUseFirebase = _backend == 'firebase';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kUseFirebase) {
    await fb_core.Firebase.initializeApp(
      options: fb_opts.DefaultFirebaseOptions.currentPlatform,
    );
    await Cloud.init(tenantId: 'van1');
  }

  await Storage.open();
  await initSkuBox();

  runApp(const VanInventoryApp());
}

class VanInventoryApp extends StatelessWidget {
  const VanInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Van Inventory',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: kUseFirebase
          ? StreamBuilder<fb_auth.User?>(
              stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
              builder: (context, snap) {
                if (snap.data == null) return const AuthGate(signedIn: false);
                return const HomeScreen();
              },
            )
          : const HomeScreen(),
    );
  }
}
