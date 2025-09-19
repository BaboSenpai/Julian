// lib/models/storage.dart
//
// Lokale Persistenz mit Hive + CSV-Export-Helfer.
// - Speichert/LÃƒÆ’Ã‚Â¤dt items, customers, depletions aus einer Hive-Box
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

  /// ÃƒÆ’Ã¢â‚¬â€œffnet die lokale Box und lÃƒÆ’Ã‚Â¤dt die Daten in die globalen Listen.
  static Future<void> open() async {
    // Hive initialisieren (nur einmal nÃƒÆ’Ã‚Â¶tig)
    await Hive.initFlutter();

    // Box ÃƒÆ’Ã‚Â¶ffnen (oder erstellen, wenn sie noch nicht existiert)
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

    // Changelog aktuell stumm ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾ignorierenÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ (kein Model vorhanden)
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
    // Wir versuchen, den Customer ÃƒÆ’Ã‚Â¼ber Namen zu matchen (bei dir gibt es kein Customer.id).
    final deplList = (box.get('depletions') as List?) ?? const <dynamic>[];
    final List<Depletion> loadedDepletions = <Depletion>[];

    for (final raw in deplList.whereType<dynamic>()) {
      final map = Map<String, dynamic>.from(raw as Map);

      // Versuch: Customer per Name auflÃƒÆ’Ã‚Â¶sen
      Customer? cust;
      final custName = map['customerName']?.toString();
      if (custName != null) {
        cust = customers.firstWhere(
          (c) => c.name == custName,
          orElse: () => customers.isNotEmpty
              ? customers.first
              : Customer(
                  name: custName,
                  date: DateTime.now(),
                  note: null,
                ),
        );
      } else {
        cust = customers.isNotEmpty
            ? customers.first
            : Customer(
                name: 'Unbekannt',
                date: DateTime.now(),
                note: null,
              );
      }

      try {
        loadedDepletions.add(Depletion.fromMap(map, cust));
      } catch (_) {
        // Falls Schema nicht passt, Eintrag ÃƒÆ’Ã‚Â¼berspringen
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
/// Aufruf wie in main.dart:
///   await exportCsvFile(context, filename: 'inventar.csv', csv: csv);
Future<void> exportCsvFile(
  BuildContext context, {
  required String filename,
  required String csv, // <- heiÃƒÆ’Ã…Â¸t absichtlich 'csv', damit main.dart passt
}) async {
  try {
    // UTF8-BOM fÃƒÆ’Ã‚Â¼r Excel-KompatibilitÃƒÆ’Ã‚Â¤t
    final normalized = csv.replaceAll('\r\n', '\n');
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(normalized)];

    // TemporÃƒÆ’Ã‚Â¤re Datei schreiben
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
