import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// =========================
///   GLOBAL / PERSISTENZ
/// =========================

late Box<String> skuBox; // Artikelnummern (SKU): key=itemName, value=sku

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Storage.open(); // Haupt-Boxen öffnen / laden
  skuBox = await Hive.openBox<String>('skus'); // SKU-Box
  runApp(const VanInventoryApp());
}

/// Eine einzige Hive-Box 'van_box' hält Items/Kunden/Entnahmen/Log als Listen von Maps.
/// Zusätzlich gibt es die Box 'skus' (global oben) für Artikelnummern.
class Storage {
  static late Box _box;

  static Future<void> open() async {
    _box = await Hive.openBox('van_box');

    if (!_box.containsKey('items')) {
      items = [
        Item(name: 'Kabelbinder', qty: 20, min: 10, target: 30),
        Item(name: 'Sicherungen 16A', qty: 8, min: 12, target: 20),
        Item(name: 'Schrauben 4x40', qty: 12, min: 8, target: 20),
        Item(name: 'Wago-Klemmen', qty: 6, min: 3, target: 10),
      ];
      customers = [];
      depletions = [];
      changelog = [];
      await saveAll();
    } else {
      final itemList = (_box.get('items') as List).cast<Map>();
      final custList = (_box.get('customers') as List).cast<Map>();
      final deplList = (_box.get('depletions') as List).cast<Map>();
      final logList  = (_box.get('changelog') as List? ?? []).cast<Map>();

      items = itemList.map(Item.fromMap).toList();
      customers = custList.map(Customer.fromMap).toList();

      // Depletions brauchen Customer-Objekt
      depletions = deplList.map((m) {
        final name = m['customerName'] as String;
        final dateMs = m['customerDateMs'] as int;
        final found = customers.firstWhere(
          (c) => c.name == name && c.date.millisecondsSinceEpoch == dateMs,
          orElse: () => Customer(name: name, date: DateTime.fromMillisecondsSinceEpoch(dateMs)),
        );
        return Depletion.fromMap(m, found);
      }).toList();

      changelog = logList.map(ChangeLogEntry.fromMap).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
  }

  static Future<void> saveAll() async {
    await _box.put('items', items.map((e) => e.toMap()).toList());
    await _box.put('customers', customers.map((e) => e.toMap()).toList());
    await _box.put('depletions', depletions.map((e) => e.toMap()).toList());
    await _box.put('changelog', changelog.map((e) => e.toMap()).toList());
  }
}

/// =========================
///        MODELLE
/// =========================

class Item {
  Item({required this.name, required this.qty, required this.min, required this.target});

  String name;
  int qty;
  int min;
  int target;

  int get warnThreshold {
    final mid = ((target + min) / 2).floor();
    return (min + 1 > mid) ? (min + 1) : mid;
  }

  bool get isLow  => qty < min;
  bool get isWarn => !isLow && qty <= warnThreshold;

  Map<String, dynamic> toMap() => {
    'name': name, 'qty': qty, 'min': min, 'target': target,
  };

  static Item fromMap(Map m) => Item(
    name: m['name'] as String,
    qty: m['qty'] as int,
    min: m['min'] as int,
    target: m['target'] as int,
  );
}

class Customer {
  Customer({required this.name, required this.date, this.note});
  String name;
  DateTime date;
  String? note;

  Map<String, dynamic> toMap() => {
    'name': name,
    'dateMs': date.millisecondsSinceEpoch,
    'note': note,
  };

  static Customer fromMap(Map m) => Customer(
    name: m['name'] as String,
    date: DateTime.fromMillisecondsSinceEpoch(m['dateMs'] as int),
    note: m['note'] as String?,
  );

  // Für Map-Key benutzt Flutter standardmäßig ==/hashCode auf Objektidentität.
  // Hier lassen wir es so; im UI gruppieren wir über die Depletions (siehe unten).
}

class Depletion {
  Depletion({required this.itemName, required this.qty, required this.customer, required this.timestamp});
  String itemName;
  int qty;
  Customer customer; // NICHT NULLABLE – wir setzen ihn auch nicht mehr auf null
  DateTime timestamp;

  Map<String, dynamic> toMap() => {
    'itemName': itemName,
    'qty': qty,
    'customerName': customer.name,
    'customerDateMs': customer.date.millisecondsSinceEpoch,
    'timestampMs': timestamp.millisecondsSinceEpoch,
  };

  static Depletion fromMap(Map m, Customer customer) => Depletion(
    itemName: m['itemName'] as String,
    qty: m['qty'] as int,
    customer: customer,
    timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestampMs'] as int),
  );
}

class ChangeLogEntry {
  ChangeLogEntry({required this.timestamp, required this.category, required this.action, required this.details, this.user});
  DateTime timestamp;
  String category; // 'material' | 'customer'
  String action;
  String details;
  String? user;

  Map<String, dynamic> toMap() => {
    'timestampMs': timestamp.millisecondsSinceEpoch,
    'category': category,
    'action': action,
    'details': details,
    'user': user,
  };

  static ChangeLogEntry fromMap(Map m) => ChangeLogEntry(
    timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestampMs'] as int),
    category: m['category'] as String,
    action: m['action'] as String,
    details: m['details'] as String,
    user: m['user'] as String?,
  );
}

// Globale (im Speicher gehaltene) Listen
List<Item> items = [];
List<Customer> customers = [];
List<Depletion> depletions = [];
List<ChangeLogEntry> changelog = [];

String fmtDate(DateTime d) => '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}';

// === SKU-Helpers ===
String? getSkuForItem(String itemName) {
  if (!Hive.isBoxOpen('skus')) return null;
  final v = skuBox.get(itemName);
  if (v == null || v.trim().isEmpty) return null;
  return v.trim();
}

Future<void> setSkuForItem(String itemName, String? sku) async {
  if (!Hive.isBoxOpen('skus')) {
    skuBox = await Hive.openBox<String>('skus');
  }
  if (sku == null || sku.trim().isEmpty) {
    await skuBox.delete(itemName);
  } else {
    await skuBox.put(itemName, sku.trim());
  }
}

/// =========================
///          APP
/// =========================

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
      home: const HomeScreen(),
    );
  }
}

/// ---------- Start ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final warn  = items.where((e) => e.isWarn).length;
    final low   = items.where((e) => e.isLow).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Van Inventory')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: _StatCard(title: 'Artikel gesamt', value: '$total')),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(title: 'Warnung (gelb)', value: '$warn', color: Colors.amber)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(title: 'Minimum (rot)', value: '$low', color: Colors.red)),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Schnellzugriff', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12, runSpacing: 12,
            children: [
              _ActionCard(icon: Icons.inventory_2, label: 'Inventar', onTap: () => _open(const InventoryScreen())),
              _ActionCard(icon: Icons.list_alt, label: 'Heutige Entnahmen', onTap: () => _open(const TodayDepletionsScreen())),
              _ActionCard(icon: Icons.receipt_long, label: 'Aufmaß', onTap: () => _open(const AufmassScreen())),
              _ActionCard(icon: Icons.settings, label: 'Einstellungen', onTap: () => _open(const SettingsScreen())),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Kritisch (unter Minimum)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (low == 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.teal.withOpacity(.05), borderRadius: BorderRadius.circular(12)),
              child: const Text('Alles gut 👍 Keine Artikel unter Minimum.'),
            )
          else
            Column(
              children: items.where((e) => e.isLow).map((it) {
                return Card(
                  elevation: 0,
                  color: Colors.red.withOpacity(.06),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.red.withOpacity(.15),
                      child: const Icon(Icons.error_outline, color: Colors.red),
                    ),
                    title: Text(it.name),
                    subtitle: Text(
                      'Bestand: ${it.qty} • Min: ${it.min} • Ziel: ${it.target}',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                    trailing: IconButton(
                      tooltip: 'Zur Inventarseite',
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _open(const InventoryScreen()),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.inventory),
        label: const Text('Inventar öffnen'),
        onPressed: () => _open(const InventoryScreen()),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, this.color});
  final String title; final String value; final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withOpacity(.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 170, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.withOpacity(.07), borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// ---------- Inventar ----------
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _search = '';

  Future<DateTime?> _pickDate(BuildContext ctx, DateTime initial) async {
    return await showDatePicker(context: ctx, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
  }

  Future<void> _logDepletionDialog(Item item) async {
    final qtyCtrl = TextEditingController(text: '1');
    Customer? chosenCustomer = customers.isNotEmpty ? customers.first : null;
    final newNameCtrl = TextEditingController();
    DateTime newDate = DateTime.now();
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: Text('Entnahme: ${item.name}'),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'Menge (Stk)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Zahl > 0 eingeben';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (customers.isNotEmpty)
                DropdownButtonFormField<Customer>(
                  value: chosenCustomer,
                  decoration: const InputDecoration(labelText: 'Kunde/Auftrag (vorhanden)'),
                  items: customers.map((c) => DropdownMenuItem(
                    value: c, child: Text('${c.name} – ${fmtDate(c.date)}'))).toList(),
                  onChanged: (v) => setSB(() => chosenCustomer = v),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextFormField(
                  controller: newNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Neuer Kunde/Auftrag (optional)',
                    hintText: 'z. B. Müller GmbH – Bad',
                  ),
                )),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Datum wählen',
                  onPressed: () async {
                    final d = await _pickDate(context, newDate);
                    if (d != null) setSB(() => newDate = d);
                  },
                  icon: const Icon(Icons.event),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Datum: ${fmtDate(newDate)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 6),
              const Text('Entweder vorhandenen Kunden wählen ODER neuen Namen + Datum eintragen.',
                style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                if (chosenCustomer == null && newNameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bitte Kunde wählen oder neu anlegen')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Eintragen'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      final req = int.parse(qtyCtrl.text);
      // Kunde bestimmen / ggf. neu anlegen
      Customer cust;
      if (newNameCtrl.text.trim().isNotEmpty) {
        cust = Customer(name: newNameCtrl.text.trim(), date: newDate);
        customers.add(cust);
        changelog.insert(0, ChangeLogEntry(
          timestamp: DateTime.now(), category: 'customer', action: 'Kunde angelegt',
          details: '${cust.name} – ${fmtDate(cust.date)}',
        ));
      } else {
        cust = chosenCustomer!;
      }

      final taken = req.clamp(0, item.qty);
      final before = item.qty;
      setState(() {
        item.qty -= taken;
        if (taken > 0) {
          depletions.add(Depletion(itemName: item.name, qty: taken, customer: cust, timestamp: DateTime.now()));
          changelog.insert(0, ChangeLogEntry(
            timestamp: DateTime.now(), category: 'material', action: 'Entnahme gebucht',
            details: '${item.name}: $before → ${item.qty} (−$taken) für ${cust.name}',
          ));
        }
      });
      await Storage.saveAll();

      if (taken < req) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nur $taken Stück entnommen (Bestand war zu niedrig).')),
        );
      }
    }
  }

  Future<void> _addItemDialog() async {
    final name = TextEditingController();
    final qty  = TextEditingController(text: '0');
    final min  = TextEditingController(text: '0');
    final tgt  = TextEditingController(text: '0');
    final sku  = TextEditingController();
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuen Artikel hinzufügen'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null),
            const SizedBox(height: 8),
            TextFormField(controller: qty, decoration: const InputDecoration(labelText: 'Bestand (qty)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl eingeben' : null),
            const SizedBox(height: 8),
            TextFormField(controller: min, decoration: const InputDecoration(labelText: 'Mindestbestand (min)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl eingeben' : null),
            const SizedBox(height: 8),
            TextFormField(controller: tgt, decoration: const InputDecoration(labelText: 'Sollbestand (target)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl eingeben' : null),
            const SizedBox(height: 8),
            TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'Artikelnummer (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final minVal = int.parse(min.text), tgtVal = int.parse(tgt.text);
              if (tgtVal < minVal) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Target muss ≥ Minimum sein')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final it = Item(
        name: name.text.trim(),
        qty: int.parse(qty.text),
        min: int.parse(min.text),
        target: int.parse(tgt.text),
      );
      setState(() => items.add(it));
      if (sku.text.trim().isNotEmpty) {
        await setSkuForItem(it.name, sku.text.trim());
      }
      changelog.insert(0, ChangeLogEntry(
        timestamp: DateTime.now(), category: 'material', action: 'Artikel angelegt',
        details: '${it.name} (qty=${it.qty}, min=${it.min}, target=${it.target})',
      ));
      await Storage.saveAll();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('„${it.name}“ hinzugefügt')));
    }
  }

  Future<void> _editItemDialog(Item item) async {
    final name = TextEditingController(text: item.name);
    final qty  = TextEditingController(text: item.qty.toString());
    final min  = TextEditingController(text: item.min.toString());
    final tgt  = TextEditingController(text: item.target.toString());
    final sku  = TextEditingController(text: getSkuForItem(item.name) ?? '');
    final form = GlobalKey<FormState>();
    final before = Item(name: item.name, qty: item.qty, min: item.min, target: item.target);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Artikel bearbeiten: ${item.name}'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null),
            const SizedBox(height: 8),
            TextFormField(controller: qty, decoration: const InputDecoration(labelText: 'Bestand (qty)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl eingeben' : null),
            const SizedBox(height: 8),
            TextFormField(controller: min, decoration: const InputDecoration(labelText: 'Mindestbestand (min)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl eingeben' : null),
            const SizedBox(height: 8),
            TextFormField(controller: tgt, decoration: const InputDecoration(labelText: 'Sollbestand (target)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Zahl eingeben' : null),
            const SizedBox(height: 8),
            TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'Artikelnummer (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              final minVal = int.parse(min.text), tgtVal = int.parse(tgt.text);
              if (tgtVal < minVal) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Target muss ≥ Minimum sein')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final oldName = item.name;
      setState(() {
        item
          ..name = name.text.trim()
          ..qty = int.parse(qty.text)
          ..min = int.parse(min.text)
          ..target = int.parse(tgt.text);
      });
      // SKU speichern/umziehen (falls Name geändert)
      final newName = item.name;
      final newSku = sku.text.trim();
      if (oldName != newName) {
        final oldSku = getSkuForItem(oldName);
        if (oldSku != null && newSku.isEmpty) {
          await setSkuForItem(newName, oldSku);
          await setSkuForItem(oldName, null);
        }
      }
      await setSkuForItem(newName, newSku.isEmpty ? null : newSku);

      final changes = <String>[];
      if (before.name   != item.name)   changes.add('Name: ${before.name} → ${item.name}');
      if (before.qty    != item.qty)    changes.add('qty: ${before.qty} → ${item.qty}');
      if (before.min    != item.min)    changes.add('min: ${before.min} → ${item.min}');
      if (before.target != item.target) changes.add('target: ${before.target} → ${item.target}');
      changelog.insert(0, ChangeLogEntry(
        timestamp: DateTime.now(), category: 'material', action: 'Artikel bearbeitet',
        details: '${before.name}: ${changes.join(', ')}',
      ));
      await Storage.saveAll();
    }
  }

  Future<void> _deleteItem(Item item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artikel löschen?'),
        content: Text('„${item.name}“ wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => items.remove(item));
      await setSkuForItem(item.name, null);
      changelog.insert(0, ChangeLogEntry(
        timestamp: DateTime.now(), category: 'material', action: 'Artikel gelöscht', details: item.name,
      ));
      await Storage.saveAll();
    }
  }

  List<Item> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventar'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Suche Artikel…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
      ),
      body: _filtered.isEmpty
          ? const Center(child: Text('Keine Artikel gefunden'))
          : ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = _filtered[index];
                Color badgeColor; IconData badgeIcon; TextStyle? subStyle;
                if (item.isLow) {
                  badgeColor = Colors.red;   badgeIcon = Icons.error_outline;
                  subStyle   = const TextStyle(color: Colors.red, fontWeight: FontWeight.w600);
                } else if (item.isWarn) {
                  badgeColor = Colors.amber; badgeIcon = Icons.warning_amber_rounded;
                  subStyle   = const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600);
                } else {
                  badgeColor = Colors.teal;  badgeIcon = Icons.inventory_2;
                }

                final sku = getSkuForItem(item.name);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: badgeColor.withOpacity(.15),
                    child: Icon(badgeIcon, color: badgeColor),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.qty} Stk • Min: ${item.min} • Ziel: ${item.target}'
                    '${item.isLow ? '  •  Nachfüllen!' : item.isWarn ? '  •  Achtung' : ''}'
                    '${sku == null ? '' : '  •  SKU: $sku'}',
                    style: subStyle,
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Entnehmen (−)',
                      onPressed: item.qty == 0 ? null : () => _logDepletionDialog(item),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Auffüllen (+1)',
                      onPressed: () async {
                        final before = item.qty;
                        setState(() => item.qty++);
                        changelog.insert(0, ChangeLogEntry(
                          timestamp: DateTime.now(), category: 'material', action: 'Bestand geändert',
                          details: '${item.name}: $before → ${item.qty} (+1)',
                        ));
                        await Storage.saveAll();
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _editItemDialog(item);
                        if (v == 'delete') _deleteItem(item);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                        PopupMenuItem(value: 'delete', child: Text('Löschen')),
                      ],
                    ),
                  ]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItemDialog, icon: const Icon(Icons.add), label: const Text('Artikel')),
    );
  }
}

/// ========= Aufmaß (Kunden) – VERSION ohne IDs (nutzt d.customer) =========

class AufmassScreen extends StatefulWidget {
  const AufmassScreen({super.key});

  @override
  State<AufmassScreen> createState() => _AufmassScreenState();
}

class _AufmassScreenState extends State<AufmassScreen> {
  /// Gruppiert alle Entnahmen nach Kunde/Auftrag
  Map<Customer, List<Depletion>> _groupByCustomer() {
    final map = <Customer, List<Depletion>>{};
    for (final d in depletions) {
      final c = d.customer;
      map.putIfAbsent(c, () => <Depletion>[]).add(d);
    }
    for (final list in map.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    return map;
  }

  /// Kunde/Auftrag anlegen oder bearbeiten
  Future<void> _createOrEditCustomer({Customer? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    DateTime date = existing?.date ?? DateTime.now();
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: Text(existing == null ? 'Kunde/Auftrag anlegen' : 'Kunde bearbeiten'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name des Kunden/Auftrags'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Datum: ${fmtDate(date)}')),
                  IconButton(
                    icon: const Icon(Icons.event),
                    tooltip: 'Datum wählen',
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setSB(() => date = d);
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        if (existing == null) {
          customers.add(Customer(
            name: nameCtrl.text.trim(),
            date: date,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          ));
        } else {
          existing
            ..name = nameCtrl.text.trim()
            ..date = date
            ..note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();
        }
      });
      await Storage.saveAll();
    }
  }

  /// Kunde löschen (Entnahmen bleiben bestehen – Referenzen NICHT anfassen)
  Future<void> _deleteCustomer(Customer cust) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Löschen'),
        content: Text(
          'Kunde/Auftrag „${cust.name}“ wirklich löschen?\n'
          'Die Entnahmen bleiben bestehen (als verwaiste Einträge).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        customers.remove(cust);
      });
      await Storage.saveAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByCustomer();

    // Kunden sortieren: zuerst Datum neu->alt, dann Name
    final keys = [...grouped.keys]..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Aufmaß = Kunden/Aufträge')),
      body: grouped.isEmpty
          ? const Center(child: Text('Noch keine Kunden/Aufträge angelegt'))
          : ListView.builder(
              itemCount: keys.length,
              itemBuilder: (c, i) {
                final cust = keys[i];
                final list = grouped[cust] ?? <Depletion>[];
                final total = list.fold<int>(0, (p, e) => p + e.qty);

                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: ExpansionTile(
                    leading: const Icon(Icons.person),
                    title: Text(cust.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${fmtDate(cust.date)}\n${cust.note ?? ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _createOrEditCustomer(existing: cust);
                        if (v == 'delete') _deleteCustomer(cust);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                        PopupMenuItem(value: 'delete', child: Text('Löschen')),
                      ],
                    ),
                    children: [
                      if (list.isEmpty)
                        const ListTile(title: Text('Noch keine Entnahmen für diesen Kunden.'))
                      else
                        ...list.map((e) {
                          final t = TimeOfDay.fromDateTime(e.timestamp);
                          final hh = t.hour.toString().padLeft(2, '0');
                          final mm = t.minute.toString().padLeft(2, '0');
                          final sku = skuBox.get(e.itemName);
                          return ListTile(
                            leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            title: Text(e.itemName),
                            subtitle: Text(
                              '${e.qty} Stk · $hh:$mm Uhr, ${fmtDate(e.timestamp)}'
                              '${sku == null ? '' : ' · SKU: $sku'}',
                            ),
                          );
                        }).toList(),

                      // Export-Button NUR für diesen Kunden/Auftrag
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Aufmaß exportieren'),
                          onPressed: () async {
                            final itemsList = list
                                .map((d) => {
                                      'name': d.itemName,
                                      'quantity': d.qty.toString(),
                                      'sku': skuBox.get(d.itemName) ?? '',
                                    })
                                .toList();

                            await exportCustomerCsv(
                              context,
                              customer: cust.name,
                              date: cust.date.toIso8601String(),
                              note: cust.note ?? '',
                              items: itemsList,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Kunde/Auftrag anlegen'),
        onPressed: () => _createOrEditCustomer(),
      ),
    );
  }
}

/// ---------- Heutige Entnahmen ----------
class TodayDepletionsScreen extends StatelessWidget {
  const TodayDepletionsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    bool sameDay(DateTime a, DateTime b) => a.year==b.year && a.month==b.month && a.day==b.day;

    final todays = depletions.where((d) => sameDay(d.timestamp, today)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(title: const Text('Heutige Entnahmen')),
      body: todays.isEmpty
          ? const Center(child: Text('Heute noch keine Entnahmen'))
          : ListView.builder(
              itemCount: todays.length,
              itemBuilder: (_, i) {
                final e = todays[i];
                final t = TimeOfDay.fromDateTime(e.timestamp);
                final hh = t.hour.toString().padLeft(2, '0');
                final mm = t.minute.toString().padLeft(2, '0');
                return ListTile(
                  leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  title: Text(e.itemName),
                  subtitle: Text('−${e.qty} • $hh:$mm Uhr • ${e.customer.name} (${fmtDate(e.customer.date)})'),
                );
              },
            ),
    );
  }
}

/// ---------- Einstellungen (Änderungen + Export) ----------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Einstellungen'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Änderungen – Material'),
            Tab(text: 'Änderungen – Kunden'),
            Tab(text: 'Export'),
          ]),
        ),
        body: const TabBarView(
          children: [
            _ChangeLogList(category: 'material'),
            _ChangeLogList(category: 'customer'),
            _ExportTab(),
          ],
        ),
      ),
    );
  }
}

class _ChangeLogList extends StatelessWidget {
  const _ChangeLogList({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final entries = changelog.where((e) => e.category == category).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (entries.isEmpty) {
      return const Center(child: Text('Noch keine Änderungen protokolliert'));
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = entries[i];
        final t = TimeOfDay.fromDateTime(e.timestamp);
        final hh = t.hour.toString().padLeft(2, '0');
        final mm = t.minute.toString().padLeft(2, '0');
        return ListTile(
          leading: Icon(category == 'material' ? Icons.inventory_2 : Icons.person),
          title: Text(e.action),
          subtitle: Text('${e.details}\n${fmtDate(e.timestamp)} • $hh:$mm'),
          isThreeLine: true,
        );
      },
    );
  }
}

class _ExportTab extends StatelessWidget {
  const _ExportTab();

  Future<void> _confirmAndExport(
    BuildContext context, {
    required String title,
    required Future<String> Function() buildCsv,
    required String filename,
  }) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export: $title'),
        content: const Text(
          'Wohin möchtest du exportieren?\n'
          '• Excel: Öffnet/teilt die CSV mit Excel\n'
          '• Google Sheets: Teilt die CSV zur Sheets-App/Drive'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'sheets'), child: const Text('Google Sheets')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'excel'), child: const Text('Excel')),
        ],
      ),
    );
    if (mode == null) return;

    final csv = await buildCsv();
    await exportCsvFile(context, filename: filename, csv: csv, preferSheets: mode == 'sheets');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text('Datenexport', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),

        _ExportTile(
          icon: Icons.inventory_2,
          title: 'Inventar (komplett)',
          subtitle: 'Alle Artikel mit Bestand, Minimum, Ziel, SKU',
          onTap: () => _confirmAndExport(
            context,
            title: 'Inventar',
            filename: 'inventar.csv',
            buildCsv: () async => CsvBuilders.buildItemsCsv(items),
          ),
        ),

        _ExportTile(
          icon: Icons.receipt_long,
          title: 'Kunden/Aufmaß (zusammengeführt)',
          subtitle: 'Kopf: Kunde/Datum/Notiz • Liste: Artikel, Menge, SKU',
          onTap: () => _confirmAndExport(
            context,
            title: 'Kunden/Aufmaß',
            filename: 'kunden_aufmass.csv',
            buildCsv: () async => CsvBuilders.buildCustomerMergedCsv(
              customers: customers,
              depletions: depletions,
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Text(
          'Hinweis: CSV lässt sich in Excel und Google Sheets direkt öffnen. '
          'Für Google Sheets wird die Datei geteilt – wähle dort „Sheets“ bzw. „Drive/Speichern in Drive“.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.file_download),
        onTap: onTap,
      ),
    );
  }
}

/// =========================
///       CSV / EXPORT
/// =========================

class CsvBuilders {
  static final _date = DateFormat('dd.MM.yyyy');

  static String _esc(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  /// Inventar inkl. Artikelnummern
  static String buildItemsCsv(List<Item> list) {
    final rows = <String>[];
    rows.add(['Name','Bestand','Minimum','Ziel','Status','Artikelnummer'].join(','));
    for (final it in list) {
      final status = it.isLow ? 'ROT' : it.isWarn ? 'GELB' : 'OK';
      final sku = getSkuForItem(it.name) ?? '';
      rows.add([_esc(it.name), it.qty, it.min, it.target, status, _esc(sku)].join(','));
    }
    return rows.join('\n');
  }

  /// Kunden/Aufmaß (zusammengeführt): Kopf + Materialliste inkl. SKU
  static String buildCustomerMergedCsv({
    required List<Customer> customers,
    required List<Depletion> depletions,
  }) {
    final rows = <String>[];
    for (final c in customers) {
      // Kopfzeile
      rows.add([
        _esc('Kunde/Auftrag'), _esc(c.name),
        _esc('Datum'), _esc(_date.format(c.date)),
        _esc('Notiz'), _esc(c.note ?? ''),
      ].join(','));
      rows.add(''); // Leerzeile

      // Tabellenkopf
      rows.add([
        _esc('Material/Aufmaß'),
        _esc('Artikel'),
        _esc('Stückzahl / Meter'),
        _esc('Artikelnummer'),
      ].join(','));

      // Zuordnen über Name + Datum (wie in der App)
      final taken = depletions.where((d) =>
        d.customer.name == c.name &&
        d.customer.date.millisecondsSinceEpoch == c.date.millisecondsSinceEpoch
      ).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final d in taken) {
        final sku = getSkuForItem(d.itemName) ?? '';
        rows.add([
          '', // leer lassen, wie gewünscht
          _esc(d.itemName),
          _esc('${d.qty}'),
          _esc(sku),
        ].join(','));
      }
      rows.add(''); // Leerzeile zwischen Kundenblöcken
    }
    return rows.join('\n');
  }
}

/// schreibt CSV in den Cache und öffnet den Teilen-Dialog
Future<void> exportCsvFile(
  BuildContext context, {
  required String filename,
  required String csv,
  bool preferSheets = false,
}) async {
  try {
    final cacheDir = await getTemporaryDirectory();
    final cacheFile = File('${cacheDir.path}/$filename');
    await cacheFile.writeAsString(csv, flush: true);

    // optional zusätzlich ablegen (leichter mit adb zu ziehen):
    final appDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${appDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final copyFile = File('${exportsDir.path}/$filename');
    await copyFile.writeAsString(csv, flush: true);

    await Share.shareXFiles(
      [XFile(cacheFile.path, mimeType: 'text/csv', name: filename)],
      text: preferSheets ? 'CSV für Google Sheets' : 'CSV für Excel',
      subject: filename,
    );

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV erzeugt: $filename')));
  } catch (e) {
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
  }
}

/// Baut das CSV für GENAU EINEN Kunden/Auftrag
String buildCustomerCsv({
  required String customer,
  required String date,
  String note = '',
  required List<Map<String, String>> items,
}) {
  final buffer = StringBuffer();

  buffer.writeln('Kunde/Auftrag:,$customer');
  buffer.writeln('Datum:,$date');
  buffer.writeln('Notiz:,$note');
  buffer.writeln('');
  buffer.writeln('Material/Aufmaß,Artikel,Stückzahl / Meter,Artikelnummer');

  for (var item in items) {
    buffer.writeln(
      ',${item['name']},${item['quantity']},${item['sku'] ?? ''}',
    );
  }

  return buffer.toString();
}

/// Exportiert EINEN Auftrag/Kunden als CSV.
Future<void> exportCustomerCsv(
  BuildContext context, {
  required String customer,
  required String date,
  String note = '',
  required List<Map<String, String>> items,
  bool preferSheets = false,
}) async {
  final csv = buildCustomerCsv(
    customer: customer,
    date: date,
    note: note,
    items: items,
  );

  await exportCsvFile(
    context,
    filename: '${customer}_$date.csv',
    csv: csv,
    preferSheets: preferSheets,
  );
}
