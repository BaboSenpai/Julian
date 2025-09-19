// lib/models/storage.dart
//
// Lokale Persistenz mit Hive + CSV-Export-Helfer.
// - Speichert/Lädt items, customers, depletions aus einer Hive-Box
// - "changelog" wird aktuell ignoriert (kein Model vorhanden)
// - CSV-Export erzeugt Datei, kopiert sie in /exports und teilt sie via Share

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Hive.initFlutter()
import 'dart:convert' show utf8;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import 'package:van_inventory/models/models.dart';
import 'package:van_inventory/models/state.dart';

class Storage {
  static Box<dynamic>? _box;

  /// Öffnet die lokale Box und lädt die Daten in die globalen Listen.
  static Future<void> open() async {
    // Hive initialisieren (nur einmal nötig)
    await Hive.initFlutter();

    // Box öffnen (oder erstellen, wenn sie noch nicht existiert)
    _box ??= await Hive.openBox<dynamic>('van_inventory');

    // Daten aus Box lesen
    await _loadAll();
  }

  /// Speichert alle globalen Listen in die Box.
  static Future<void> saveAll() async {
    final box = _box ?? await Hive.openBox<dynamic>('van_inventory');

    await box.put(
      'items',
      items.map((e) => e.toMap()).toList(),
    );

    await box.put(
      'customers',
      customers.map((e) => e.toMap()).toList(),
    );

    await box.put(
      'depletions',
      depletions.map((e) => e.toMap()).toList(),
    );

    // Changelog aktuell stumm „ignorieren“ (kein Model vorhanden)
    await box.put('changelog', <Map<String, dynamic>>[]);
  }

  /// Interne Ladefunktion: zieht alles aus der Box in die globalen Listen.
  static Future<void> _loadAll() async {
    final box = _box ?? await Hive.openBox<dynamic>('van_inventory');

    // ---- Items ----
    final itemList = (box.get('items') as List?) ?? const <dynamic>[];
    final loadedItems = itemList
        .whereType<dynamic>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .map<Item>(Item.fromMap)
        .toList();

    items
      ..clear()
      ..addAll(loadedItems);

    // ---- Customers ----
    final custList = (box.get('customers') as List?) ?? const <dynamic>[];
    final loadedCustomers = custList
        .whereType<dynamic>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .map<Customer>(Customer.fromMap)
        .toList();

    customers
      ..clear()
      ..addAll(loadedCustomers);

    // ---- Depletions ----
    // Je nach altem Datenformat kann Depletion einen Customer benötigen.
    // Wir versuchen, über eine customerId aufzulösen; falls nicht vorhanden,
    // fällt es auf einen Dummy-Fallback zurück.
    final deplList = (box.get('depletions') as List?) ?? const <dynamic>[];
    final List<Depletion> loadedDepletions = <Depletion>[];

    for (final raw in deplList.whereType<dynamic>()) {
      final map = Map<String, dynamic>.from(raw as Map);

      // Versuch: Customer per ID auflösen
      Customer? cust;
      final custId = map['customerId']?.toString();
      if (custId != null) {
        cust = customers.where((c) => c.id == custId).cast<Customer?>().firstOrNull;
      }

      // Fallback, falls keine ID oder kein Treffer
      cust ??= customers.isNotEmpty
          ? customers.first
          : Customer(
              id: map['customerId']?.toString() ?? 'unknown',
              name: map['customerName']?.toString() ?? 'Unbekannt',
              date: DateTime.now(),
              note: null,
            );

      try {
        loadedDepletions.add(Depletion.fromMap(map, cust));
      } catch (_) {
        // Falls Schema nicht passt, überspringen wir den Eintrag
      }
    }

    depletions
      ..clear()
      ..addAll(loadedDepletions);

    // ---- Changelog: ignorieren (kein Model vorhanden) ----
    // final logList = (box.get('changelog') as List?) ?? const <dynamic>[];
  }
}

/// Exportiert eine CSV-Datei, speichert sie in /exports und bietet Share an.
/// [filename] sollte auf ".csv" enden.
Future<void> exportCsvFile(
  BuildContext context, {
  required String filename,
  required String content,
}) async {
  try {
    // UTF8-BOM für Excel-Kompatibilität
    final normalized = content.replaceAll('\r\n', '\n');
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(normalized)];

    // Temporäre Datei schreiben
    final cacheDir = await getTemporaryDirectory();
    final cacheFile = File('${cacheDir.path}/$filename');
    await cacheFile.writeAsBytes(bytes, flush: true);

    // Dauerhafte Kopie in /exports
    final appDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${appDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final copyFile = File('${exportsDir.path}/$filename');
    await cacheFile.copy(copyFile.path);

    // Teilen anbieten (optional)
    await Share.shareXFiles(
      [XFile(cacheFile.path, mimeType: 'text/csv', name: filename)],
      subject: filename,
      text: 'Export aus van_inventory: $filename',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV erzeugt: $filename')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    }
  }
}

// --- kleine Helfer-Erweiterung ---
extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
