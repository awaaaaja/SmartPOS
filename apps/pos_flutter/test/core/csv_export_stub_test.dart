import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/csv_export_stub.dart';
import 'package:pos_flutter/core/error_mapper.dart';
import 'package:share_plus/share_plus.dart';

/// Test berbagi CSV (tanpa device): berkas ditulis lengkap dan status share
/// tidak tersedia dipetakan ke pesan operator, bukan error mentah.
void main() {
  late Future<ShareResult> Function(ShareParams params) original;

  setUp(() => original = shareSheetHandler);
  tearDown(() => shareSheetHandler = original);

  test('CSV ditulis ke temp dan dilemparkan ke lembar berbagi', () async {
    ShareParams? seen;
    shareSheetHandler = (params) async {
      seen = params;
      return ShareResult('', ShareResultStatus.dismissed);
    };

    await saveCsvFile('laporan-uji.csv', 'item,total\nKopi,10000');

    final path = seen!.files!.single.path;
    expect(path, endsWith('laporan-uji.csv'));
    expect(File(path).readAsStringSync(), 'item,total\nKopi,10000');
  });

  test('share sheet tak tersedia -> StateError yang dipetakan ke pesan Indonesia',
      () async {
    shareSheetHandler = (params) async =>
        ShareResult('', ShareResultStatus.unavailable);

    Object? error;
    try {
      await saveCsvFile('laporan-uji-2.csv', 'a,b');
    } catch (e) {
      error = e;
    }
    expect(error, isA<StateError>());
    expect((error! as StateError).message, 'csv_share_unavailable');
    expect(
      mapErrorToMessage(error),
      contains('lembar berbagi tidak tersedia'),
    );
  });
}
