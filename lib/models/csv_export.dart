// lib/csv_export.dart
import 'package:intl/intl.dart';
import 'models.dart';
import 'storage.dart';

// Fallback-Mapping: aktuell keine SKUs -> immer null zurückgeben.
// (Später könnt ihr hier eine echte Zuordnung pflegen.)
String? getSkuForItem(String name) => null;


class CsvBuilders {
  static final _date = DateFormat('dd.MM.yyyy');

  static String _esc(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  static String _toCsv(List<List<String>> rows) {
    final sb = StringBuffer();
    for (final r in rows) {
      if (r.isEmpty) {
        sb.write('\r\n');
        continue;
      }
      sb.writeln(r.map(_esc).join(';'));
    }
    return sb.toString().replaceAll('\n', '\r\n');
  }

  /// Inventar inkl. Artikelnummern â€” Semikolon + CRLF
  static String buildItemsCsv(List<Item> list) {
    final rows = <List<String>>[];
    rows.add(['Name','Bestand','Minimum','Ziel','Status','Artikelnummer']);
    for (final it in list) {
      final status = it.isLow ? 'ROT' : it.isWarn ? 'GELB' : 'OK';
      final sku = getSkuForItem(it.name) ?? '';
      rows.add([it.name, it.qty.toString(), it.min.toString(), it.target.toString(), status, sku]);
    }
    return _toCsv(rows);
  }

  /// Kunden/Aufmaß (zusammengeführt)
  static String buildCustomerMergedCsv({
    required List<Customer> customers,
    required List<Depletion> depletions,
  }) {
    final rows = <List<String>>[];
    for (final c in customers) {
      rows.add(['Kunde/Auftrag', c.name, 'Datum', _date.format(c.date), 'Notiz', c.note ?? '']);
      rows.add([]);
      rows.add(['Material/Aufmaß', 'Artikel', 'Stückzahl / Meter', 'Artikelnummer']);

      final taken = depletions.where((d) =>
        d.customer.name == c.name &&
        d.customer.date.millisecondsSinceEpoch == c.date.millisecondsSinceEpoch
      ).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final d in taken) {
        final sku = getSkuForItem(d.itemName) ?? '';
        rows.add(['', d.itemName, d.qty.toString(), sku]);
      }
      rows.add([]);
    }
    return _toCsv(rows);
  }

  /// Einzelner Kunde/Auftrag
  static String buildSingleCustomerCsv({
    required String customer,
    required String date,
    String note = '',
    required List<Map<String, String>> items,
  }) {
    final rows = <List<String>>[];
    rows.add(['Kunde/Auftrag:', customer]);
    rows.add(['Datum:', date]);
    rows.add(['Notiz:', note]);
    rows.add([]);
    rows.add(['Material/Aufmaß','Artikel','Stückzahl / Meter','Artikelnummer']);
    for (var item in items) {
      rows.add(['', item['name'] ?? '', item['quantity'] ?? '', item['sku'] ?? '']);
    }
    return _toCsv(rows);
  }
}
