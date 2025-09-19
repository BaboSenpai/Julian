//lib/models/storage.dart
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart'; // fÃƒÆ’Ã‚Â¼r Hive.initFlutter()
import 'dart:convert' show utf8;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

// alle Models (Item, Customer, Depletion, UserMember)
import 'package:van_inventory/models/models.dart';

// globale Listen/State
import 'package:van_inventory/models/state.dart';


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
