// lib/models/vehicle.dart
class Vehicle {
  final String id;
  final String name;
  final String? plate;

  Vehicle({required this.id, required this.name, this.plate});

  factory Vehicle.fromDoc(String id, Map<String, dynamic> m) => Vehicle(
        id: id,
        name: (m['name'] ?? '').toString(),
        plate: m['plate']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        if (plate != null) 'plate': plate,
      };
}
