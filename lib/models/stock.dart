// lib/models/stock.dart
class Stock {
  final String id;
  final String vehicleId;
  final String productId; // maps to Item.id
  final int qty;
  final int minQty;

  Stock({
    required this.id,
    required this.vehicleId,
    required this.productId,
    required this.qty,
    required this.minQty,
  });

  factory Stock.fromDoc(String id, Map<String, dynamic> m) => Stock(
        id: id,
        vehicleId: (m['vehicleId'] ?? '').toString(),
        productId: (m['productId'] ?? '').toString(),
        qty: (m['qty'] ?? 0) is int ? m['qty'] as int : int.tryParse(m['qty']?.toString() ?? '0') ?? 0,
        minQty: (m['minQty'] ?? 0) is int ? m['minQty'] as int : int.tryParse(m['minQty']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'vehicleId': vehicleId,
        'productId': productId,
        'qty': qty,
        'minQty': minQty,
      };
}
