class Item {
  Item({
    required this.name,
    required this.qty,
    required this.min,
    required this.target,
  });

  final String name;
  final int qty;
  final int min;
  final int target;

  Map<String, dynamic> toMap() => {
        'name': name,
        'qty': qty,
        'min': min,
        'target': target,
      };

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      name: map['name'] ?? '',
      qty: map['qty'] ?? 0,
      min: map['min'] ?? 0,
      target: map['target'] ?? 0,
    );
  }
}
