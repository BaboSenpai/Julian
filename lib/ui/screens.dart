// lib/ui/screens.dart
import 'package:flutter/material.dart';
import 'package:van_inventory/ui/vehicle_select_screen.dart';

import 'package:van_inventory/models/models.dart';
import 'package:van_inventory/models/state.dart';
import 'package:van_inventory/models/storage.dart';
import 'package:van_inventory/models/csv_export.dart' hide getSkuForItem; // Konflikt vermeiden
import 'package:van_inventory/services/cloud.dart';

import 'package:van_inventory/models/ui_state.dart'
    show fmtDate, activeCustomer, customerKey, ChangeLogEntry, changelog, getSkuForItem, setSkuForItem;

/// ===================================================
///                    HOME / DASH
/// ===================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    setState(() {}); // z. B. nach Kundenanlage refresh
  }

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final warn  = items.where((e) => e.isWarn).length;
    final low   = items.where((e) => e.isLow).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Van Inventory'),
        actions: [
          IconButton(
            tooltip: 'Fahrzeuginventar',
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const VehicleSelectScreen(),
              ));
            },
          ),
        
          if (customers.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: activeCustomer == null ? null : customerKey(activeCustomer!),
                hint: const Text('Kunde wählen'),
                alignment: Alignment.centerRight,
                borderRadius: BorderRadius.circular(12),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Kein Kunde (Standard)')),
                  ...customers
                      .map((c) => DropdownMenuItem<String?>(
                            value: customerKey(c),
                            child: Text('${c.name} â€“ ${fmtDate(c.date)}'),
                          ))
                      .toList()
                    ..sort((a, b) => ((a.child as Text).data!).compareTo((b.child as Text).data!)),
                ],
                onChanged: (v) {
                  setState(() {
                    activeCustomer = v == null
                        ? null
                        : customers.firstWhere((c) => customerKey(c) == v);
                  });
                  if (activeCustomer != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Aktiver Kunde: ${activeCustomer!.name}')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kein aktiver Kunde')),
                    );
                  }
                },
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
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
          if (activeCustomer != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person, size: 18),
                const SizedBox(width: 6),
                Text('Aktiver Kunde: ${activeCustomer!.name} â€“ ${fmtDate(activeCustomer!.date)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
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

/// ===================================================
///                    INVENTAR
/// ===================================================
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
    if (activeCustomer != null) {
      final qtyCtrl = TextEditingController(text: '1');
      final form = GlobalKey<FormState>();

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Entnahme: ${item.name}'),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Kunde: ${activeCustomer!.name} â€“ ${fmtDate(activeCustomer!.date)}'),
              const SizedBox(height: 8),
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
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Buchen'),
            ),
          ],
        ),
      );

      if (ok == true) {
        final req = int.parse(qtyCtrl.text);
        final taken = req.clamp(0, item.qty);
        final before = item.qty;

        setState(() {
          item.qty -= taken;
          if (taken > 0) {
            depletions.add(Depletion(
              itemName: item.name,
              qty: taken,
              customer: activeCustomer!,
              timestamp: DateTime.now(),
            ));
            changelog.insert(0, ChangeLogEntry(
              timestamp: DateTime.now(),
              category: 'material',
              action: 'Entnahme gebucht',
              details: '${item.name}: $before  →  ${item.qty} (−$taken) für ${activeCustomer!.name}',
            ));
          }
        });
        await Storage.saveAll();

        if (taken < req) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nur $taken Stück entnommen (Bestand war zu niedrig).')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entnahme gebucht.')),
          );
        }
      }
      return;
    }

    // --- Standard-Flow ---
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
                  items: customers.map((c) => DropdownMenuItem(value: c, child: Text('${c.name} â€“ ${fmtDate(c.date)}'))).toList(),
                  onChanged: (v) => setSB(() => chosenCustomer = v),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextFormField(
                  controller: newNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Neuer Kunde/Auftrag (optional)',
                    hintText: 'z. B. Müller GmbH â€“ Bad',
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
      Customer cust;
      if (newNameCtrl.text.trim().isNotEmpty) {
        cust = Customer(

          name: newNameCtrl.text.trim(),
          date: newDate,
          note: null,
        );
        customers.add(cust);
        changelog.insert(0, ChangeLogEntry(
          timestamp: DateTime.now(), category: 'customer', action: 'Kunde angelegt',
          details: '${cust.name} â€“ ${fmtDate(cust.date)}',
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
            details: '${item.name}: $before  →  ${item.qty} (−$taken) für ${cust.name}',
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
        id: '',
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
    final before = Item(id: item.id, name: item.name, qty: item.qty, min: item.min, target: item.target);

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
      if (before.name   != item.name)   changes.add('Name: ${before.name}  →  ${item.name}');
      if (before.qty    != item.qty)    changes.add('qty: ${before.qty}  →  ${item.qty}');
      if (before.min    != item.min)    changes.add('min: ${before.min}  →  ${item.min}');
      if (before.target != item.target) changes.add('target: ${before.target}  →  ${item.target}');
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
                    '${item.isLow ? '  •  Nachfüllen!' : item.isWarn ? "  •  Achtung" : ''}'
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
                          details: '${item.name}: $before  →  ${item.qty} (+1)',
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

/// ===================================================
///                HEUTIGE ENTNAHMEN
/// ===================================================
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

/// ===================================================
///               EINSTELLUNGEN / EXPORT
/// ===================================================
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
            Tab(text: 'Änderungen â€“ Material'),
            Tab(text: 'Änderungen â€“ Kunden'),
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
    await exportCsvFile(context, filename: filename, csv: csv);
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
          'Für Google Sheets wird die Datei geteilt â€“ wähle dort „Sheets“ bzw. „Drive/Speichern in Drive“.',
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

/// ===================================================
///               AUFMASS / KUNDEN
/// ===================================================
class AufmassScreen extends StatefulWidget {
  const AufmassScreen({super.key});
  @override
  State<AufmassScreen> createState() => _AufmassScreenState();
}

class _AufmassScreenState extends State<AufmassScreen> {
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
          final newCust = Customer(

            name: nameCtrl.text.trim(),
            date: date,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
          customers.add(newCust);
        } else {
          final idx = customers.indexOf(existing);
          if (idx >= 0) {
            customers[idx] = Customer(

              name: nameCtrl.text.trim(),
              date: date,
              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            );
          }
        }
      });
      await Storage.saveAll();
    }
  }

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
                          final sku = getSkuForItem(e.itemName);
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
                                      'sku': getSkuForItem(d.itemName) ?? '',
                                    })
                                .toList();

                            // CSV für EINEN Kunden bauen (Semikolon + CRLF)
                            String _buildSingleCustomerCsv({
                              required String customer,
                              required DateTime date,
                              String note = '',
                              required List<Map<String, String>> items,
                            }) {
                              String esc(String v) => '"${v.replaceAll('"', '""')}"';
                              final buf = StringBuffer();
                              buf.writeln('${esc('Kunde/Auftrag:')};${esc(customer)}');
                              buf.writeln('${esc('Datum:')};${esc(fmtDate(date))}');
                              buf.writeln('${esc('Notiz:')};${esc(note)}');
                              buf.writeln('');
                              buf.writeln('${esc('Material/Aufmaß')};${esc('Artikel')};${esc('Stückzahl / Meter')};${esc('Artikelnummer')}');
                              for (final it in items) {
                                buf.writeln('${esc('')};${esc(it['name'] ?? '')};${esc(it['quantity'] ?? '')};${esc(it['sku'] ?? '')}');
                              }
                              return buf.toString().replaceAll('\n', '\r\n');
                            }

                            final csv = _buildSingleCustomerCsv(
                              customer: cust.name,
                              date: cust.date,
                              note: cust.note ?? '',
                              items: itemsList,
                            );

                            await exportCsvFile(
                              context,
                              filename: '${cust.name}_${cust.date.toIso8601String()}.csv',
                              csv: csv,
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


