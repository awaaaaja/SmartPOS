import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/features/settings/settings_page.dart';
import 'package:pos_flutter/features/settings/settings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Test halaman Pengaturan (K06-08) tanpa jaringan:
/// - form edit membuka nilai saat ini dan mengirim fraksi ke RPC settings_save
/// - validasi klien menolak nama kosong dan persen di luar 0-100
/// - kegagalan server (42501 non-operator) dipetakan ke pesan operator

class _FakeSettings implements SettingsRepository {
  int fetchCount = 0;
  final List<Map<String, dynamic>> saves = [];
  Object? saveError;

  Map<String, dynamic> _data = {
    'name': 'Waroeng MeJeng Kampoeng',
    'address': 'Padang',
    'timezone': 'Asia/Jakarta',
    'tax_rate': 0.075,
    'service_rate': 0.025,
  };

  @override
  Future<Map<String, dynamic>> fetch() async {
    fetchCount++;
    return Map.of(_data);
  }

  @override
  Future<void> save({
    required String name,
    String? address,
    required String timezone,
    required double taxRate,
    required double serviceRate,
  }) async {
    final error = saveError;
    if (error != null) throw error;
    saves.add({
      'name': name,
      'address': address,
      'timezone': timezone,
      'tax_rate': taxRate,
      'service_rate': serviceRate,
    });
    _data = {
      'name': name,
      'address': address,
      'timezone': timezone,
      'tax_rate': taxRate,
      'service_rate': serviceRate,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_FakeSettings> _openPage(WidgetTester tester) async {
  final fake = _FakeSettings();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SettingsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(fake.fetchCount, 1);
  return fake;
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Edit pengaturan'));
  await tester.pumpAndSettle();
}

void main() {
  // Urutan field: 0 nama, 1 alamat, 2 zona waktu, 3 pajak, 4 biaya layanan.
  Finder field(int index) => find.byType(TextFormField).at(index);

  testWidgets('simpan: nilai diformat persen lalu dikirim sebagai fraksi',
      (tester) async {
    final fake = await _openPage(tester);
    await _openDialog(tester);

    expect(find.text('Waroeng MeJeng Kampoeng'),
        findsAtLeastNWidgets(1));
    expect(find.widgetWithText(TextFormField, '7.5'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '2.5'), findsOneWidget);

    await tester.enterText(field(0), 'Waroeng MeJeng Baru');
    await tester.enterText(field(3), '10,5');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(fake.saves, hasLength(1));
    expect(fake.saves.single['name'], 'Waroeng MeJeng Baru');
    expect(fake.saves.single['address'], 'Padang');
    expect(fake.saves.single['timezone'], 'Asia/Jakarta');
    expect(fake.saves.single['tax_rate'], closeTo(0.105, 1e-9));
    expect(fake.saves.single['service_rate'], closeTo(0.025, 1e-9));

    // Provider di-invalidate sehingga data terbaru dibaca ulang.
    expect(fake.fetchCount, 2);
    expect(find.text('Pengaturan usaha tersimpan.'), findsOneWidget);
    expect(find.text('Waroeng MeJeng Baru'), findsOneWidget);
  });

  testWidgets('validasi klien: nama kosong dan persen di luar 0-100 ditolak',
      (tester) async {
    final fake = await _openPage(tester);
    await _openDialog(tester);

    await tester.enterText(field(0), '');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Nama wajib diisi (min. 2 huruf)'), findsOneWidget);
    expect(fake.saves, isEmpty);

    await tester.enterText(field(0), 'Waroeng MeJeng');
    await tester.enterText(field(4), '150');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Persen antara 0 sampai 100'), findsOneWidget);
    expect(fake.saves, isEmpty);

    // Dialog masih terbuka setelah validasi gagal.
    expect(find.text('Edit pengaturan usaha'), findsOneWidget);
  });

  testWidgets('server menolak non-operator (42501) -> pesan operator',
      (tester) async {
    final fake = await _openPage(tester);
    fake.saveError = const PostgrestException(
      message: 'operator_required',
      code: '42501',
    );
    await _openDialog(tester);
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(
      find.text('Hanya akun operator yang boleh mengubah data ini. '
          'Masuk ulang dengan akun operator.'),
      findsOneWidget,
    );
    expect(find.text('Edit pengaturan usaha'), findsOneWidget);
    expect(fake.fetchCount, 1);
  });
}
