class Customer {
  Customer({
    required this.name,
    required this.date,
    this.note,
  });

  final String name;
  final DateTime date;
  final String? note;

  Map<String, dynamic> toMap() => {
        'name': name,
        'dateMs': date.millisecondsSinceEpoch,
        'note': note,
      };

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      name: map['name'] ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(map['dateMs'] ?? 0),
      note: map['note'],
    );
  }
}
