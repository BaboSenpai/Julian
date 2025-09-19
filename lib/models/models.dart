// lib/models.dart
import 'package:flutter/material.dart';

/// ===== Grund-Modelle =====

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
}

class Depletion {
  Depletion({required this.itemName, required this.qty, required this.customer, required this.timestamp});
  String itemName;
  int qty;
  Customer customer;
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

/// ===== Globale Daten (In-Memory) =====
List<Item> items = [];
List<Customer> customers = [];
List<Depletion> depletions = [];
List<ChangeLogEntry> changelog = [];

/// Aktiver Kunde (für Schnell-Entnahme)
Customer? activeCustomer;
String customerKey(Customer c) => '${c.name}|${c.date.millisecondsSinceEpoch}';

/// Helper
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}';
