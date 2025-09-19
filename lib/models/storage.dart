// lib/storage.dart
import 'dart:io';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

import 'models.dart';

late Box<String> skuBox; // Artikelnummern (SKU): key=itemName, value=sku

class Storage {
  static late Box _box;

  static Future<void> open() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('van_box');
    skuBox = await Hive.openBox<String>('skus');

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

/// === SKU-Helpers (liegen bei Storage, da Hive) ===
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

/// ===== CSV/Sharing Helpers die vom UI gebraucht werden =====

Future<void> exportCsvFile(
  BuildContext context, {
  required String filename,
  required String csv,
  bool preferSheets = false,
}) async {
  try {
    // Normalize to CRLF + add UTF-8 BOM
    final normalized = csv.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(normalized)];

    final cacheDir = await getTemporaryDirectory();
    final cacheFile = File('${cacheDir.path}/$filename');
    await cacheFile.writeAsBytes(bytes, flush: true);

    final appDir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${appDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final copyFile = File('${exportsDir.path}/$filename');
    await copyFile.writeAsBytes(bytes, flush: true);

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
