// lib/services/cloud.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../models/item.dart';
import '../models/customer.dart';
import '../models/depletion.dart';
import '../models/user_member.dart';

/// Hilfsfunktion für Customer-Dokument-ID (wie zuvor in main.dart)
String _customerDocId(Customer c) =>
    '${c.name}|${c.date.millisecondsSinceEpoch}';

class Cloud {
  Cloud._();

  static late String tenantId;

  static fs.FirebaseFirestore get _db => fs.FirebaseFirestore.instance;
  static fs.CollectionReference<Map<String, dynamic>> get _tenRoot =>
      _db.collection('tenants');

  static fs.CollectionReference<Map<String, dynamic>> get _itemsCol =>
      _tenRoot.doc(tenantId).collection('items');

  static fs.CollectionReference<Map<String, dynamic>> get _custCol =>
      _tenRoot.doc(tenantId).collection('customers');

  static fs.CollectionReference<Map<String, dynamic>> get _depCol =>
      _tenRoot.doc(tenantId).collection('depletions');

  static fs.CollectionReference<Map<String, dynamic>> get _usersCol =>
      _tenRoot.doc(tenantId).collection('users');

  /// Beim App-Start im Firebase-Modus aufrufen
  static Future<void> init({required String tenantId}) async {
    Cloud.tenantId = tenantId;
  }

  /// Prüft/erzwingt Team-Mitgliedschaft für den eingeloggten User.
  /// Falls eine Einladung per E-Mail existiert, wird sie mit der UID verknüpft.
  static Future<bool> ensureMembershipForCurrentUser() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // 1) Direkter Treffer per UID?
    final uidDoc = await _usersCol.doc(user.uid).get();
    if (uidDoc.exists) return true;

    // 2) Einladung per E-Mail?
    final email = user.email?.toLowerCase();
    if (email != null && email.isNotEmpty) {
      final byMail =
          await _usersCol.where('email', isEqualTo: email).limit(1).get();
      if (byMail.docs.isNotEmpty) {
        final invited = byMail.docs.first;
        final data = invited.data();
        final role = (data['role'] as String?) ?? 'member';

        await _usersCol.doc(user.uid).set({
          'email': email,
          'role': role,
          'uid': user.uid,
          'createdAt': fs.FieldValue.serverTimestamp(),
        }, fs.SetOptions(merge: true));

        await _usersCol.doc(invited.id).delete();
        return true;
      }
    }
    return false;
  }

  // ---- Live Sync -> Callbacks in main.dart liefern (keine Globals hier) ----
  static StreamSubscription? _itemsSub;
  static StreamSubscription? _custSub;
  static StreamSubscription? _depSub;

  static Future<void> bindLiveListeners({
    required void Function(List<Item>) onItems,
    required void Function(List<Customer>) onCustomers,
    required void Function(List<Depletion>) onDepletions,
    required Future<void> Function() onSaveAll,
  }) async {
    _itemsSub?.cancel();
    _itemsSub = _itemsCol.snapshots().listen((qs) async {
      final list = qs.docs.map((d) {
        final m = d.data();
        return Item(
          name: m['name'] ?? d.id,
          qty: (m['qty'] ?? 0) as int,
          min: (m['min'] ?? 0) as int,
          target: (m['target'] ?? 0) as int,
        );
      }).toList();
      onItems(list);
      await onSaveAll();
    });

    _custSub?.cancel();
    _custSub = _custCol.snapshots().listen((qs) async {
      final list = qs.docs.map((d) {
        final m = d.data();
        return Customer(
          name: m['name'] as String,
          date: DateTime.fromMillisecondsSinceEpoch((m['dateMs'] ?? 0) as int),
          note: m['note'] as String?,
        );
      }).toList();
      onCustomers(list);
      await onSaveAll();
    });

    _depSub?.cancel();
    _depSub =
        _depCol.orderBy('timestampMs', descending: false).snapshots().listen(
      (qs) async {
        final temp = <Depletion>[];
        for (final d in qs.docs) {
          final m = d.data();
          final name = m['customerName'] as String;
          final dateMs = (m['customerDateMs'] ?? 0) as int;

          final cust = Customer(
            name: name,
            date: DateTime.fromMillisecondsSinceEpoch(dateMs),
          );

          temp.add(Depletion(
            itemName: m['itemName'] as String,
            qty: (m['qty'] ?? 0) as int,
            customer: cust,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                (m['timestampMs'] ?? 0) as int),
          ));
        }
        onDepletions(temp);
        await onSaveAll();
      },
    );
  }

  // ================= TEAM =================
  static Stream<List<UserMember>> watchMembers() {
    return _usersCol.orderBy('email').snapshots().map((qs) {
      return qs.docs.map((d) {
        final m = d.data();
        return UserMember(
          id: d.id,
          email: (m['email'] as String?) ?? '',
          role: (m['role'] as String?) ?? 'member',
          uid: m['uid'] as String?,
        );
      }).toList();
    });
  }

  /// Admin trägt Mail + Rolle ein; Verknüpfung mit UID passiert beim ersten Login.
  static Future<void> addMemberByEmail(String email, {String role = 'member'}) async {
    final norm = email.toLowerCase();

    final exist =
        await _usersCol.where('email', isEqualTo: norm).limit(1).get();
    if (exist.docs.isNotEmpty) {
      await _usersCol.doc(exist.docs.first.id).set({
        'email': norm,
        'role': role,
        'updatedAt': fs.FieldValue.serverTimestamp(),
      }, fs.SetOptions(merge: true));
      return;
    }

    await _usersCol.add({
      'email': norm,
      'role': role,
      'uid': null,
      'createdAt': fs.FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateMemberRole(String docId, String role) async {
    await _usersCol.doc(docId).set({
      'role': role,
      'updatedAt': fs.FieldValue.serverTimestamp(),
    }, fs.SetOptions(merge: true));
  }

  static Future<void> removeMember(String docId) async {
    await _usersCol.doc(docId).delete();
  }

  // ================= ITEMS =================
  static Future<void> upsertItem(Item it) async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    await _itemsCol.doc(it.name).set({
      'name': it.name,
      'qty': it.qty,
      'min': it.min,
      'target': it.target,
      'updatedAt': fs.FieldValue.serverTimestamp(),
      'updatedBy': uid,
    }, fs.SetOptions(merge: true));
  }

  static Future<void> deleteItem(String name) async {
    await _itemsCol.doc(name).delete();
  }

  // ================= CUSTOMERS =================
  static Future<void> upsertCustomer(Customer c) async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    await _custCol.doc(_customerDocId(c)).set({
      'name': c.name,
      'dateMs': c.date.millisecondsSinceEpoch,
      'note': c.note,
      'updatedAt': fs.FieldValue.serverTimestamp(),
      'updatedBy': uid,
    }, fs.SetOptions(merge: true));
  }

  static Future<void> deleteCustomer(Customer c) async {
    await _custCol.doc(_customerDocId(c)).delete();
  }

  // ================= DEPLETIONS =================
  static Future<void> addDepletion(Depletion d) async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    await _depCol.add({
      'itemName': d.itemName,
      'qty': d.qty,
      'customerName': d.customer.name,
      'customerDateMs': d.customer.date.millisecondsSinceEpoch,
      'timestampMs': d.timestamp.millisecondsSinceEpoch,
      'updatedAt': fs.FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }
}
