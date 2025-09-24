// lib/ui/vehicle_select_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:van_inventory/services/cloud.dart';

class VehicleSelectScreen extends StatelessWidget {
  const VehicleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tenantId = Cloud.tenantId;
    final vehicles = FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenantId)
        .collection('vehicles')
        .orderBy('name');

    return Scaffold(
      appBar: AppBar(title: const Text('Fahrzeug wählen')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: vehicles.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('Noch keine Fahrzeuge angelegt.'));
          }
          final docs = snap.data!.docs;
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final name = (d.data()['name'] ?? d.id).toString();
              final plate = (d.data()['plate'] ?? '').toString();
              return ListTile(
                title: Text(name),
                subtitle: plate.isEmpty ? null : Text(plate),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => InventoryScreen(
                    vehicleId: d.id,
                    vehicleName: name,
                  )),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
