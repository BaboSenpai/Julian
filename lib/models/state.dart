// lib/models/state.dart
import 'package:van_inventory/models/models.dart';

final List<Item> items = <Item>[];
final List<Customer> customers = <Customer>[];
final List<Depletion> depletions = <Depletion>[];
final List<UserMember> teamMembers = <UserMember>[];

void resetState() {
  items.clear();
  customers.clear();
  depletions.clear();
  teamMembers.clear();
}
