// lib/services/cloud.dart
//
// Firebase Cloud-Sync für van_inventory
// - Lädt Items, Customers, Depletions aus Firestore und spiegelt sie in die
//   globalen Listen (items, customers, depletions) aus state.dart.
// - Bietet Team-/Benutzerverwaltung (watchMembers, add/update/remove).
//
// Voraussetzungen:
//   - Firebase ist in main.dart initialisiert (Firebase.initializeApp)
//   - Es gibt Collections unter:
//       tenants/{tenantId}/items
//       tenants/{tenantId}/customers
//       tenants/{tenantId}/depletions
//       tenants/{tenantId}/members
//
// WICHTIG: Die globalen Listen sind "final" -> niemals neu zuweisen,
//          sondern immer mit ..clear() ..addAll(...) befüllen.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'package:van_inventory/models/models.dart';
import 'package:van_inventory/models/state.dart';

class Cloud {
  Cloud._();

  static late final fs.FirebaseFirestore _db;
  static String _tenantId = 'default';

  // optionale aktive Bindings (damit man sie bei Bedarf wieder kündigen kann)
  static StreamSubscription? _itemsBind;
  static StreamSubscription? _customersBind;
  static StreamSubscription? _depletionsBind;

  /// Einmalig aufrufen (nach Firebase.initializeApp), z. B. in main():
  ///   await Cloud.init(tenantId: 'van1');
  static Future<void> init({required String tenantId}) async {
    _tenantId = tenantId;
    _db = fs.FirebaseFirestore.instance;

    // Live-Bindings starten (optional – wenn du das nicht willst, auskommentieren)
    _bindItems();
    _bindCustomers();
    _bindDepletions();
  }

  // ---------- Public Streams / Team ----------

  /// Stream der Team-Mitglieder (für TeamTab)
  static Stream<List<UserMember>> watchMembers() {
    final col = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .orderBy('email');

    return col.snapshots().map((snap) {
      return snap.docs.map((d) {
        final m = d.data();
        return UserMember(
          id: d.id,
          email: (m['email'] ?? '').toString(),
          role: (m['role'] ?? 'member').toString(),
          displayName: (m['displayName'] ?? '').toString(),
        );
      }).toList();
    });
  }

  /// Rolle eines Mitglieds ändern (z. B. 'member' <-> 'admin')
  static Future<void> updateMemberRole(String memberId, String role) async {
    final ref = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(memberId);
    await ref.update({'role': role});
  }

  /// Mitglied entfernen
  static Future<void> removeMember(String memberId) async {
    final ref = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(memberId);
    await ref.delete();
  }

  /// Mitglied per E-Mail hinzufügen (falls bereits vorhanden -> upsert)
  static Future<void> addMemberByEmail(String email, {String role = 'member'}) async {
    final col = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members');

    // nach existierendem Member mit gleicher E-Mail suchen
    final q = await col.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isNotEmpty) {
      // update Rolle
      await q.docs.first.reference.update({'role': role});
      return;
    }

    // neu anlegen
    await col.add({
      'email': email,
      'role': role,
      'displayName': '',
      'createdAt': fs.FieldValue.serverTimestamp(),
      'invitedBy': fb_auth.FirebaseAuth.instance.currentUser?.email ?? '',
    });
  }

  // ---------- Live-Bindings für Items / Customers / Depletions ----------

  static void _bindItems() {
    _itemsBind?.cancel();
    final col = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('items');

    _itemsBind = col.snapshots().listen((snap) {
      final list = snap.docs.map((d) {
        final m = d.data();
        return _mapItem(d.id, m);
      }).toList();

      items
        ..clear()
        ..addAll(list);
    });
  }

  static void _bindCustomers() {
    _customersBind?.cancel();
    final col = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('customers')
        .orderBy('date', descending: true);

    _customersBind = col.snapshots().listen((snap) {
      final list = snap.docs.map((d) {
        final m = d.data();
        return _mapCustomer(m);
      }).toList();

      customers
        ..clear()
        ..addAll(list);
    });
  }

  static void _bindDepletions() {
    _depletionsBind?.cancel();
    final col = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('depletions')
        .orderBy('date', descending: true);

    _depletionsBind = col.snapshots().listen((snap) {
      final temp = <Depletion>[];
      for (final d in snap.docs) {
        final m = d.data();

        // Customer via Name zuordnen (da euer Customer kein id-Feld hat)
        Customer cust = _mapCustomerFromName(m['customerName']);

        try {
          temp.add(Depletion.fromMap(_ensureMap(m), cust));
        } catch (_) {
          // falls Format nicht passt -> Eintrag überspringen
        }
      }

      depletions
        ..clear()
        ..addAll(temp);
    });
  }

  // ---------- Mapper ----------

  static Item _mapItem(String docId, Map<String, dynamic> m) {
    // Robust gegen Strings/Zahlen
    int _asInt(dynamic v) =>
        (v is int) ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

    return Item(
      id: (m['id']?.toString().isNotEmpty ?? false) ? m['id'].toString() : docId,
      name: (m['name'] ?? '').toString(),
      qty: _asInt(m['qty']),
      min: _asInt(m['min']),
      target: _asInt(m['target']),
      note: (m['note']?.toString().isNotEmpty ?? false) ? m['note'].toString() : null,
      createdAt: _toDateTime(m['createdAt']),
    );
  }

  static Customer _mapCustomer(Map<String, dynamic> m) {
    return Customer(
      name: (m['name'] ?? m['customerName'] ?? '').toString(),
      date: _toDateTime(m['date']),
      note: (m['note']?.toString().isNotEmpty ?? false) ? m['note'].toString() : null,
    );
  }

  static Customer _mapCustomerFromName(dynamic name) {
    final n = (name ?? '').toString();
    if (n.isNotEmpty) {
      // Versuch: exakten Treffer in bereits geladenen Kunden finden
      final idx = customers.indexWhere((c) => c.name == n);
      if (idx >= 0) return customers[idx];
    }
    // Fallback: vorhandener erster Kunde – oder Dummy
    return customers.isNotEmpty
        ? customers.first
        : Customer(name: n.isEmpty ? 'Unbekannt' : n, date: DateTime.now(), note: null);
  }

  static DateTime _toDateTime(dynamic v) {
    if (v == null) return DateTime.now();
    // Firestore Timestamp?
    if (v is fs.Timestamp) return v.toDate();
    // Milliseconds?
    final i = int.tryParse(v.toString());
    if (i != null) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(i);
      } catch (_) {}
    }
    // ISO-String?
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  static Map<String, dynamic> _ensureMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  // ---------- Optional: Manuelles Entbinden ----------

  static Future<void> dispose() async {
    await _itemsBind?.cancel();
    await _customersBind?.cancel();
    await _depletionsBind?.cancel();
    _itemsBind = null;
    _customersBind = null;
    _depletionsBind = null;
  }
}
