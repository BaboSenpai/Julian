import 'package:flutter/material.dart';
import 'package:van_inventory/services/cloud.dart';

class InventoryScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleName;
  const InventoryScreen({super.key, required this.vehicleId, required this.vehicleName});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final StockService _svc;

  @override
  void initState() {
    super.initState();
    _svc = StockService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Inventar – ${widget.vehicleName}')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _svc.listenVehicleInventory(widget.vehicleId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snap.data!;
          if (rows.isEmpty) return const Center(child: Text('Keine Artikel im Fahrzeug.'));
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              final warn = (r['qty'] as int) <= (r['minQty'] as int);
              return ListTile(
                title: Text(r['productName'] ?? r['productId']),
                subtitle: Text('${r['sku'] ?? ''} • Min: ${r['minQty']} • Einheit: ${r['unit'] ?? 'Stk'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (warn) const Icon(Icons.warning_amber, size: 20),
                    Text('${r['qty']}'),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () => _svc.bookMovement(
                        vehicleId: widget.vehicleId,
                        productId: r['productId'],
                        delta: -1,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _svc.bookMovement(
                        vehicleId: widget.vehicleId,
                        productId: r['productId'],
                        delta: 1, // ✅ hier korrigiert
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

