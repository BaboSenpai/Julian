import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

/// Globale Cloud-Funktionen für Firestore
class Cloud {
  static String _tenantId = "van1"; // Standard (kann per init überschrieben werden)

  /// Initialisiert den Tenant (wird in main.dart aufgerufen)
  static Future<void> init({required String tenantId}) async {
    _tenantId = tenantId;
  }

  /// Getter, damit wir Cloud.tenantId überall nutzen können
  static String get tenantId => _tenantId;

  static final _db = fs.FirebaseFirestore.instance;

  // --- Dein restlicher vorhandener Cloud-Code würde hier weitergehen ---

  static Map<String, dynamic> _ensureMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    return {};
  }
}

/// ===== Inventory per Vehicle (Stocks & Movements) =====
class StockService {
  final _db = fs.FirebaseFirestore.instance;
  String get _tenantId => Cloud.tenantId; // reuse tenant from Cloud

  /// Inventar pro Fahrzeug mit einfachen Join auf items
  Stream<List<Map<String, dynamic>>> listenVehicleInventory(String vehicleId) async* {
    final stocksCol = _db
        .collection('tenants')
        .doc(_tenantId)
        .collection('stocks')
        .where('vehicleId', isEqualTo: vehicleId);

    await for (final snap in stocksCol.snapshots()) {
      final rows = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final m = _ensureMap(d.data());
        final productId = (m['productId'] ?? '').toString();
        // join mit items (Produkt-Stammdaten)
        final prodDoc = await _db
            .collection('tenants')
            .doc(_tenantId)
            .collection('items')
            .doc(productId)
            .get();
        final prod = _ensureMap(prodDoc.data());
        rows.add({
          'id': d.id,
          'productId': productId,
          'productName': (prod['name'] ?? productId).toString(),
          'sku': (prod['sku'] ?? '').toString(),
          'unit': (prod['unit'] ?? 'Stk').toString(),
          'qty': (m['qty'] ?? 0) is int ? m['qty'] as int : int.tryParse(m['qty'].toString()) ?? 0,
          'minQty': (m['minQty'] ?? 0) is int ? m['minQty'] as int : int.tryParse(m['minQty'].toString()) ?? 0,
        });
      }
      yield rows;
    }
  }

  /// Buchung (+/-) mit deterministischer Stock-ID (vehicleId__productId)
  Future<void> bookMovement({
    required String vehicleId,
    required String productId,
    required int delta,
    String source = 'van',
    String? jobId,
  }) async {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid ?? 'system';
    final tenantRef = _db.collection('tenants').doc(_tenantId);
    final movesCol = tenantRef.collection('stock_movements');
    final stocksCol = tenantRef.collection('stocks');

    final stockDocId = '${vehicleId}__${productId}';
    final stockRef = stocksCol.doc(stockDocId);

    await _db.runTransaction((tx) async {
      // 1) Bewegung protokollieren
      final mvRef = movesCol.doc();
      tx.set(mvRef, {
        'vehicleId': vehicleId,
        'productId': productId,
        'delta': delta,
        'source': source,
        'jobId': jobId,
        'userId': uid,
        'ts': fs.FieldValue.serverTimestamp(),
      });

      // 2) Bestand aktualisieren (deterministisches Doc → tx.get erlaubt)
      final snap = await tx.get(stockRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['qty'] ?? 0) is int ? data['qty'] as int : int.tryParse('${data['qty']}') ?? 0;
      final minQty = (data['minQty'] ?? 0) is int ? data['minQty'] as int : int.tryParse('${data['minQty']}') ?? 0;

      tx.set(stockRef, {
        'vehicleId': vehicleId,
        'productId': productId,
        'qty': current + delta,
        'minQty': minQty,
      }, fs.SetOptions(merge: true));
    });
  }

  static Map<String, dynamic> _ensureMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    return {};
  }
}
