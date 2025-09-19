// lib/models/state.dart
import 'package:van_inventory/models/models.dart';

// Globale, typisierte Listen (nur falls ihr sie irgendwo nutzt).
// Wenn ihr keine Globals braucht, könnt ihr diese Datei zwar lassen,
// aber die Listen bleiben dann einfach leer/ungenutzt.

final List<Item> items = <Item>[];
final List<Customer> customers = <Customer>[];
final List<Depletion> depletions = <Depletion>[];
final List<UserMember> teamMembers = <UserMember>[];

// Optional: kleine Helper
void resetState() {
  items.clear();
  customers.clear();
  depletions.clear();
  teamMembers.clear();
}
