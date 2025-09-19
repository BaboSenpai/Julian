import 'customer.dart';

class Depletion {
  Depletion({
    required this.itemName,
    required this.qty,
    required this.customer,
    required this.timestamp,
  });

  final String itemName;
  final int qty;
  final Customer customer;
  final DateTime timestamp;

  Map<String, dynamic> toMap() => {
        'itemName': itemName,
        'qty': qty,
        'customerName': customer.name,
        'customerDateMs': customer.date.millisecondsSinceEpoch,
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };

  factory Depletion.fromMap(Map<String, dynamic> map, Customer customer) {
    return Depletion(
      itemName: map['itemName'] ?? '',
      qty: map['qty'] ?? 0,
      customer: customer,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestampMs'] ?? 0),
    );
  }
}
