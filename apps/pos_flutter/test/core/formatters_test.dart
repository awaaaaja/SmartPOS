import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/formatters.dart';

void main() {
  group('formatRupiah', () {
    test('memformat rupiah pola id-ID', () {
      expect(formatRupiah(0), 'Rp 0');
      expect(formatRupiah(18000), 'Rp 18.000');
      expect(formatRupiah(1234567), 'Rp 1.234.567');
    });

    test('nilai negatif ditandai jelas', () {
      expect(formatRupiah(-5000), '-Rp 5.000');
    });

    test('pembulatan ke rupiah terdekat', () {
      expect(formatRupiah(18000.4), 'Rp 18.000');
      expect(formatRupiah(18000.6), 'Rp 18.001');
    });
  });

  group('WIB', () {
    test('toWib menambah 7 jam dari UTC', () {
      final utc = DateTime.utc(2026, 10, 26, 9, 30);
      expect(toWib(utc), DateTime.utc(2026, 10, 26, 16, 30));
    });

    test('lewat tengah malam berganti tanggal', () {
      final utc = DateTime.utc(2026, 10, 26, 18, 0);
      final wib = toWib(utc);
      expect(wib.day, 27);
      expect(wib.hour, 1);
    });

    test('formatWib deterministik dengan zona WIB', () {
      final utc = DateTime.utc(2026, 10, 26, 9, 30);
      expect(formatWib(utc), '26 Okt 2026, 16:30 WIB');
    });
  });
}
