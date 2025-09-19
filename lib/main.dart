// lib/main.dart
import 'package:flutter/material.dart';


// Firebase
import 'package:firebase_core/firebase_core.dart' as fb_core;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'firebase_options.dart' as fb_opts;

// Eigene Module (immer über package:-Pfade!)
import 'package:van_inventory/models/models.dart';      // Item, Customer, Depletion, UserMember
import 'package:van_inventory/models/state.dart';       // items, customers, depletions, teamMembers
import 'package:van_inventory/models/storage.dart';     // Storage.open(), Storage.saveAll()
import 'package:van_inventory/models/csv_export.dart';  // CsvBuilders + exportCsvFile()
import 'package:van_inventory/services/cloud.dart';     // Cloud.*
import 'package:van_inventory/ui/team_tab.dart';        // TeamTab
import 'package:van_inventory/features/auth/auth_gate.dart'; // AuthGate

import 'dart:async';


// ===== Backend-Auswahl (local | firebase) =====
const String _backend = String.fromEnvironment('BACKEND', defaultValue: 'local');
const bool kUseFirebase = _backend == 'firebase';

// Kleiner Datums-Helper, der in main.dart verwendet wird (z. B. fmtDate(c.date))
String fmtDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
         '${d.month.toString().padLeft(2, '0')}-'
         '${d.day.toString().padLeft(2, '0')}';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialisieren (nur wenn gewünscht)
  if (kUseFirebase) {
    await fb_core.Firebase.initializeApp(
      options: fb_opts.DefaultFirebaseOptions.currentPlatform,
    );
    await Cloud.init(tenantId: 'van1'); // ggf. anpassen
  }

  // Lokale Persistenz laden
  await Storage.open();

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
                // Noch nicht eingeloggt → Login/Registrierung anzeigen
                if (snap.data == null) {
                  return const AuthGate(signedIn: false);
                }
                // Eingeloggt → direkt deine App anzeigen
                return const HomeScreen();
              },
            )
          : const HomeScreen(),
    );
  }
}



/// =======================
///       HOME / TABS
/// =======================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription? _syncBind;

  @override
  void initState() {
    super.initState();
    if (kUseFirebase) {
      // Leichte Sicherung: Live-Listener an Cloud binden
      // (AuthGate hat bereits angemeldet)
      Cloud.ensureMembershipForCurrentUser();
      // einmalig starten (kein echtes cancel nötig, nur Future)
      Cloud.bindLiveListeners();
    }
  }

  @override
  void dispose() {
    _syncBind?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
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
              tooltip: 'Abmelden',
              icon: const Icon(Icons.logout),
              onPressed: () => fb_auth.FirebaseAuth.instance.signOut(),
            ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Inventar'),
          const NavigationDestination(icon: Icon(Icons.person), label: 'Kunden'),
          const NavigationDestination(icon: Icon(Icons.download), label: 'Export'),
          if (kUseFirebase) const NavigationDestination(icon: Icon(Icons.group), label: 'Team'),
        ],
      ),
    );
  }
}

/// =======================
///       INVENTAR
/// =======================
class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});
  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Noch keine Artikel'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final it = items[i];
        return ListTile(
          leading: const Icon(Icons.inventory_2),
          title: Text(it.name),
          subtitle: Text('Bestand: ${it.qty}  •  Min: ${it.min}  •  Ziel: ${it.target}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '−1',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: it.qty <= 0
                    ? null
                    : () async {
                        setState(() => it.qty -= 1);
                        await Storage.saveAll();
                        if (kUseFirebase) await Cloud.upsertItem(it);
                      },
              ),
              IconButton(
                tooltip: '+1',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () async {
                  setState(() => it.qty += 1);
                  await Storage.saveAll();
                  if (kUseFirebase) await Cloud.upsertItem(it);
                },
              ),
            ],
          ),
          onTap: () => _editItem(context, it),
        );
      },
    );
  }

  Future<void> _editItem(BuildContext ctx, Item item) async {
    final name = TextEditingController(text: item.name);
    final qty  = TextEditingController(text: item.qty.toString());
    final min  = TextEditingController(text: item.min.toString());
    final tgt  = TextEditingController(text: item.target.toString());
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Artikel bearbeiten'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v==null || v.trim().isEmpty) ? 'Pflichtfeld' : null),
              const SizedBox(height: 8),
              TextFormField(controller: qty, decoration: const InputDecoration(labelText: 'Bestand'),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl' : null),
              const SizedBox(height: 8),
              TextFormField(controller: min, decoration: const InputDecoration(labelText: 'Minimum'),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl' : null),
              const SizedBox(height: 8),
              TextFormField(controller: tgt, decoration: const InputDecoration(labelText: 'Ziel'),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl' : null),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final minVal = int.parse(min.text), tgtVal = int.parse(tgt.text);
              if (tgtVal < minVal) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Ziel muss ≥ Minimum sein')));
                return;
              }
              Navigator.pop(c, true);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        item
          ..name = name.text.trim()
          ..qty  = int.parse(qty.text)
          ..min  = int.parse(min.text)
          ..target = int.parse(tgt.text);
      });
      await Storage.saveAll();
      if (kUseFirebase) await Cloud.upsertItem(item);
    }
  }
}

/// =======================
///       KUNDEN
/// =======================
class CustomersTab extends StatelessWidget {
  const CustomersTab({super.key});
  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return const Center(child: Text('Noch keine Kunden/Aufträge'));
    }
    final list = [...customers]..sort((a,b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = list[i];
        return ListTile(
          leading: const Icon(Icons.person),
          title: Text(c.name),
          subtitle: Text(fmtDate(c.date) + (c.note == null ? '' : '\n${c.note}')),
          isThreeLine: c.note != null && c.note!.isNotEmpty,
        );
      },
    );
  }
}

/// =======================
///        EXPORT
/// =======================
class ExportTab extends StatelessWidget {
  const ExportTab({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text('Export', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),

        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Inventar (CSV)'),
            subtitle: const Text('Alle Artikel mit Bestand, Minimum, Ziel, optional SKU'),
            trailing: const Icon(Icons.download),
            onTap: () async {
              final csv = CsvBuilders.buildItemsCsv(items);
              await exportCsvFile(context, filename: 'inventar.csv', csv: csv);
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Kunden/Aufmaß (CSV)'),
            subtitle: const Text('Zusammenführung aller Aufträge & Entnahmen'),
            trailing: const Icon(Icons.download),
            onTap: () async {
              final csv = CsvBuilders.buildCustomerMergedCsv(
                customers: customers,
                depletions: depletions,
              );
              await exportCsvFile(context, filename: 'kunden_aufmass.csv', csv: csv);
            },
          ),
        ),
      ],
    );
  }
}
