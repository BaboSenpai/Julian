// lib/models/item.dart
class Item {
  String id;
  String name;
  int qty;
  int min;
  int target;
  String? note;
  DateTime createdAt;

  Item({
    required this.id,
    required this.name,
    required this.qty,
    required this.min,
    required this.target,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Status-Helper fÃƒÆ’Ã‚Â¼r UI/CSV
  bool get isLow => qty <= min;
  bool get isWarn => qty > min && qty < target;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'qty': qty,
        'min': min,
        'target': target,
        'note': note,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Item.fromMap(Map<String, dynamic> map) => Item(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        qty: (map['qty'] is int)
            ? map['qty'] as int
            : int.tryParse(map['qty']?.toString() ?? '0') ?? 0,
        min: (map['min'] is int)
            ? map['min'] as int
            : int.tryParse(map['min']?.toString() ?? '0') ?? 0,
        target: (map['target'] is int)
            ? map['target'] as int
            : int.tryParse(map['target']?.toString() ?? '0') ?? 0,
        note: map['note']?.toString(),
        createdAt: (map['createdAt'] != null)
            ? DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(map['createdAt'].toString()) ??
                    (map['createdAt'] as int))
            : DateTime.now(),
      );
}
