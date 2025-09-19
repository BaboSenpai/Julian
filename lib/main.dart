// lib/main.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert'; // CSV/BOM
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'firebase_options.dart' as fb_opts;

// ---- neue, korrekte Pfade (aus deinem Projektbaum)
import 'models/models.dart';
import 'models/storage.dart';
import 'models/csv_export.dart';
import 'services/cloud.dart';
import 'ui/team_tab.dart';
import 'features/auth/auth_gate.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kUseFirebase) {
    await fb_core.Firebase.initializeApp(
      options: fb_opts.DefaultFirebaseOptions.currentPlatform,
    );
    await Cloud.init(tenantId: 'van1'); // Tenant-ID nach Bedarf anpassen
  }

  await Storage.open(); // Hive öffnen & lokale Daten laden

  runApp(const VanInventoryApp());
}

class VanInventoryApp extends StatelessWidget {
  const VanInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Van Inventory',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: kUseFirebase ? const AuthGate() : const HomeScreen(),
    );
  }
}

/// ===================================
///   Auth / Start
/// ===================================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SignInScreen();
        }
        return const HomeScreen();
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool isRegister = false;
  String? error;

  Future<void> submit() async {
    try {
      if (isRegister) {
        await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailCtrl.text.trim(),
          password: passCtrl.text.trim(),
        );
      } else {
        await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailCtrl.text.trim(),
          password: passCtrl.text.trim(),
        );
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login / Registrierung")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "E-Mail")),
          TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Passwort"), obscureText: true),
          const SizedBox(height: 12),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: submit,
            child: Text(isRegister ? "Registrieren" : "Einloggen"),
          ),
          TextButton(
            onPressed: () => setState(() => isRegister = !isRegister),
            child: Text(isRegister ? "Schon ein Konto? Einloggen" : "Noch kein Konto? Registrieren"),
          )
        ]),
      ),
    );
  }
}

/// ===================================
///   Hauptbildschirm
/// ===================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (kUseFirebase) {
      Cloud.ensureMembershipForCurrentUser();
      Cloud.bindLiveListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const InventoryTab(),
      const CustomersTab(),
      const ExportTab(),
      if (kUseFirebase) const TeamTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Van Inventory'),
        actions: [
          if (kUseFirebase)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => fb_auth.FirebaseAuth.instance.signOut(),
            ),
        ],
      ),
      body: tabs[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.inventory), label: 'Inventar'),
          const NavigationDestination(icon: Icon(Icons.people), label: 'Kunden'),
          const NavigationDestination(icon: Icon(Icons.file_download), label: 'Export'),
          if (kUseFirebase) const NavigationDestination(icon: Icon(Icons.group), label: 'Team'),
        ],
      ),
    );
  }
}

/// ===================================
///   Inventar-Tab
/// ===================================
class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final it = items[i];
        return ListTile(
          title: Text(it.name),
          subtitle: Text("Bestand: ${it.qty}  (min: ${it.min}, Ziel: ${it.target})"),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () {
                  setState(() => it.qty--);
                  if (kUseFirebase) {
                    Cloud.upsertItem(it);
                  }
                  Storage.saveAll();
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  setState(() => it.qty++);
                  if (kUseFirebase) {
                    Cloud.upsertItem(it);
                  }
                  Storage.saveAll();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ===================================
///   Kunden-Tab
/// ===================================
class CustomersTab extends StatefulWidget {
  const CustomersTab({super.key});

  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: customers.length,
      itemBuilder: (ctx, i) {
        final c = customers[i];
        return ListTile(
          title: Text(c.name),
          subtitle: Text(fmtDate(c.date)),
          onTap: () {},
        );
      },
    );
  }
}

/// ===================================
///   Export-Tab
/// ===================================
class ExportTab extends StatelessWidget {
  const ExportTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: const Text("Inventar exportieren"),
          onTap: () async {
            final csv = CsvBuilders.buildItemsCsv(items);
            await exportCsvFile(context, filename: "inventar.csv", csv: csv);
          },
        ),
        ListTile(
          title: const Text("Kunden exportieren"),
          onTap: () async {
            final csv = CsvBuilders.buildCustomerMergedCsv(
              customers: customers,
              depletions: depletions,
            );
            await exportCsvFile(context, filename: "kunden.csv", csv: csv);
          },
        ),
      ],
    );
  }
}

/// ===================================
///   Team-Tab (aus cloud.dart)
/// ===================================
class TeamTab extends StatelessWidget {
  const TeamTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserMember>>(
      stream: Cloud.watchMembers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final members = snap.data!;
        return ListView.builder(
          itemCount: members.length,
          itemBuilder: (ctx, i) {
            final m = members[i];
            return ListTile(
              title: Text(m.email),
              subtitle: Text(m.role),
            );
          },
        );
      },
    );
  }
}
