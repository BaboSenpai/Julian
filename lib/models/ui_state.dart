// lib/models/ui_state.dart
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:van_inventory/models/models.dart';
import 'package:van_inventory/models/state.dart';

/// --- Formatierungen ---
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// --- Aktiver Kunde (für Quick-Flow Entnahme) ---
Customer? activeCustomer;
String customerKey(Customer c) => '${c.name}|${c.date.millisecondsSinceEpoch}';

/// --- ChangeLog für die UI ---
class ChangeLogEntry {
  ChangeLogEntry({
    required this.timestamp,
    required this.category, // 'material' | 'customer'
    required this.action,
    required this.details,
    this.user,
  });

  DateTime timestamp;
  String category;
  String action;
  String details;
  String? user;
}

final List<ChangeLogEntry> changelog = <ChangeLogEntry>[];

/// --- SKU-Speicher in eigener Hive-Box ---
late Box<String> skuBox;

Future<void> initSkuBox() async {
  if (!Hive.isBoxOpen('skus')) {
    await Hive.initFlutter();
    skuBox = await Hive.openBox<String>('skus');
  } else {
    skuBox = Hive.box<String>('skus');
  }
}

String? getSkuForItem(String itemName) {
  if (!Hive.isBoxOpen('skus')) return null;
  final v = skuBox.get(itemName);
  if (v == null || v.trim().isEmpty) return null;
  return v.trim();
}

Future<void> setSkuForItem(String itemName, String? sku) async {
  if (!Hive.isBoxOpen('skus')) {
    await initSkuBox();
  }
  if (sku == null || sku.trim().isEmpty) {
    await skuBox.delete(itemName);
  } else {
    await skuBox.put(itemName, sku.trim());
  }
}
