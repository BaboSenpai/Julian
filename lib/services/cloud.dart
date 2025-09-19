// lib/services/cloud.dart
//
// Firebase Cloud-Sync für van_inventory
// - Live-Bindings für items/customers/depletions
// - Teamverwaltung (watchMembers / Rollen ändern / entfernen / hinzufügen)
// - Utilitys, die in main.dart aufgerufen werden:
//     • ensureMembershipForCurrentUser()
//     • bindLiveListeners()
//     • upsertItem(Item it)
//
// Voraussetzungen:
//   - Firebase.initializeApp() wurde aufgerufen
//   - Firestore-Struktur:
//       tenants/{tenantId}/items
//       tenants/{tenantId}/customers
//       tenants/{tenantId}/depletions
//       tenants/{tenantId}/members
//
// Hinweis zu globalen Listen (state.dart):
//   Die Listen sind final -> niemals neu zuweisen, sondern ..clear() ..addAll(...)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'package:van_inventory/models/models.dart';
import 'package:van_inventory/models/state.dart';

class Cloud {
  Cloud._();

  static late final fs.FirebaseFirestore _db;
  static String _tenantId = 'default';

  // aktive Streams, damit wir sie trennen können
  static StreamSubscription? _itemsBind;
  static StreamSubscription? _customersBind;
  static StreamSubscription? _depletionsBind;

  /// Einmalig aufrufen (z. B. in main.dart nach Firebase.init)
  static Future<void> init({required String tenantId}) async {
    _tenantId = tenantId;
    _db = fs.FirebaseFirestore.instance;

    // Standard: direkt binden
    bindLiveListeners();
  }

  /// Wird von deiner main.dart aufgerufen (existiert dort bereits).
  /// Stellt sicher, dass der eingeloggte User in /members steht.
  static Future<void> ensureMembershipForCurrentUser() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final email = user.email?.toLowerCase().trim();
    if (email == null || email.isEmpty) return;

    final membersCol = _db.collection('tenants').doc(_tenantId).collection('members');
    final q = await membersCol.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isEmpty) {
      await membersCol.add({
        'email': email,
        'role': 'member',
        'createdAt': fs.FieldValue.serverTimestamp(),
      });
    }
  }

  /// Wird von deiner main.dart aufgerufen (existiert dort bereits).
  /// Startet/erneuert alle Live-Listener.
  static void bindLiveListeners() {
    _bindItems();
    _bindCustomers();
    _bindDepletions();
  }

  // ---------------- Team / Members ----------------

  /// Stream für TeamTab
  static Stream<List<UserMember>> watchMembers() {
    final col = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .orderBy('email');

    return col.snapshots().map((snap) {
      return snap.docs.map<UserMember>((d) {
        final m = _ensureMap(d.data());
        return UserMember(
          id: d.id,
          email: (m['email'] ?? '').toString(),
          role: (m['role'] ?? 'member').toString(),
          // falls euer UserMember kein displayName Feld hat -> weglassen
        );
      }).toList();
    });
  }

  static Future<void> updateMemberRole(String memberId, String role) async {
    final ref = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(memberId);
    await ref.update({'role': role});
  }

  static Future<void> removeMember(String memberId) async {
    final ref = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('members')
        .doc(memberId);
    await ref.delete();
  }

  static Future<void> addMemberByEmail(String email, {String role = 'member'}) async {
    final col = _db.collection('tenants').doc(_tenantId).collection('members');
    final q = await col.where('email', isEqualTo: email).limit(1).get();
    if (q.docs.isNotEmpty) {
      await q.docs.first.reference.update({'role': role});
      return;
    }
    await col.add({
      'email': email,
      'role': role,
      'createdAt': fs.FieldValue.serverTimestamp(),
      'invitedBy': fb_auth.FirebaseAuth.instance.currentUser?.email ?? '',
    });
  }

  // ---------------- Items / Customers / Depletions ----------------

  static void _bindItems() {
    _itemsBind?.cancel();
    final col = _db.collection('tenants').doc(_tenantId).collection('items');

    _itemsBind = col.snapshots().listen((snap) {
      final list = snap.docs.map<Item>((d) {
        final m = _ensureMap(d.data());
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
      final list = snap.docs.map<Customer>((d) {
        final m = _ensureMap(d.data());
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
        final m = _ensureMap(d.data());

        // Customer via Name zuordnen (euer Customer hat kein id-Feld)
        final Customer cust = _mapCustomerFromName(m['customerName']);

        try {
          temp.add(Depletion.fromMap(m, cust));
        } catch (_) {
          // ungültiger Eintrag -> überspringen
        }
      }

      depletions
        ..clear()
        ..addAll(temp);
    });
  }

  /// Upsert für ein Item (wird von main.dart aufgerufen)
  static Future<void> upsertItem(Item it) async {
    final col = _db.collection('tenants').doc(_tenantId).collection('items');

    final data = {
      'id': it.id,
      'name': it.name,
      'qty': it.qty,
      'min': it.min,
      'target': it.target,
      'note': it.note,
      'createdAt': fs.FieldValue.serverTimestamp(),
    };

    if (it.id.isNotEmpty) {
      // existierendes Dokument per ID überschreiben
      await col.doc(it.id).set(data, fs.SetOptions(merge: true));
    } else {
      // neues Dokument anlegen, id zurück in das Item schreiben
      final ref = await col.add(data);
      it.id = ref.id;
    }
  }

  // ---------------- Mapper & Helpers ----------------

  static Item _mapItem(String docId, Map<String, dynamic> m) {
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
      final idx = customers.indexWhere((c) => c.name == n);
      if (idx >= 0) return customers[idx];
    }
    return customers.isNotEmpty
        ? customers.first
        : Customer(name: n.isEmpty ? 'Unbekannt' : n, date: DateTime.now(), note: null);
  }

  static DateTime _toDateTime(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is fs.Timestamp) return v.toDate();
    final i = int.tryParse(v.toString());
    if (i != null) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(i);
      } catch (_) {}
    }
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

  // optional: Listener aufräumen
  static Future<void> dispose() async {
    await _itemsBind?.cancel();
    await _customersBind?.cancel();
    await _depletionsBind?.cancel();
    _itemsBind = null;
    _customersBind = null;
    _depletionsBind = null;
  }
}
