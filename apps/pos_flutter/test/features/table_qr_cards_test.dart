import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/png_share.dart';
import 'package:pos_flutter/features/tables_qr/qr_page.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/memory_preferences.dart';

DiningTableEntry _table({int id = 7, String label = 'Meja 1'}) =>
    DiningTableEntry(id: id, label: label, isEnabled: true, tokenVersion: 2);

/// Fake repository hapus meja: mencatat panggilan & hasil tanpa menyentuh
/// jaringan (migrasi 0021 diuji terpisah oleh test integrasi Python).
class _FakeTablesRepository extends TablesRepository {
  _FakeTablesRepository()
    : super(
        SupabaseClient(
          'https://tables-test.invalid',
          'sb_publishable_test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final deleteCalls = <int>[];
  ({int draftsRemoved, int salesDetached})? lastResult;

  @override
  Future<({int draftsRemoved, int salesDetached})> deleteTable(
    int tableId,
  ) async {
    deleteCalls.add(tableId);
    final result = (draftsRemoved: 2, salesDetached: 1);
    lastResult = result;
    return result;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Map<int, String> tokens,
  TablesRepository? repository,
  TableTokenStore? tokenStore,
}) async {
  tester.view.physicalSize = const Size(1024, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tablesListProvider.overrideWith((ref) async => [_table()]),
        tableTokensProvider.overrideWith((ref) async => tokens),
        qrWebBaseUrlProvider.overrideWithValue('https://menu.uji.test'),
        if (repository != null)
          tablesRepositoryProvider.overrideWithValue(repository),
        if (tokenStore != null)
          tableTokenStoreProvider.overrideWithValue(tokenStore),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const TablesQrPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('kartu meja', () {
    testWidgets('QR tampil langsung di kartu bila token tersedia', (
      tester,
    ) async {
      await _pump(tester, tokens: {7: 'token-satu'});

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('QR belum ada'), findsNothing);

      // Ketuk QR → dialog besar siap cetak, tautan bersistem token meja.
      await tester.tap(find.byKey(const ValueKey('table-qr-7')));
      await tester.pumpAndSettle();
      expect(find.text('QR Meja 1'), findsOneWidget);
      expect(find.text('Cetak / Bagikan'), findsOneWidget);
      expect(find.textContaining('token-satu'), findsWidgets);
    });

    testWidgets('meja tanpa token lokal meminta rotasi, tanpa QR palsu', (
      tester,
    ) async {
      await _pump(tester, tokens: {});

      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('QR belum ada\ndi perangkat ini'), findsOneWidget);
    });
  });

  group('tombol Cetak / Bagikan', () {
    late Future<Uint8List?> Function(GlobalKey key) originalCapture;
    late Future<bool> Function(String, List<int>) originalPng;
    late (String, List<int>)? seenPng;

    setUp(() {
      originalCapture = qrPngCapture;
      originalPng = sharePngHandler;
      // Capture & share sheet asli butuh device; di test cukup dummy instan.
      qrPngCapture = (_) async => Uint8List.fromList(const [137, 80, 78, 71]);
      sharePngHandler = (filename, bytes) async {
        seenPng = (filename, bytes);
        return true;
      };
    });
    tearDown(() {
      qrPngCapture = originalCapture;
      sharePngHandler = originalPng;
    });

    testWidgets('menangkap QR menjadi PNG lalu membuka lembar berbagi', (
      tester,
    ) async {
      await _pump(tester, tokens: {7: 'token-satu'});
      await tester.tap(find.byKey(const ValueKey('table-qr-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cetak / Bagikan'));
      await tester.pumpAndSettle();

      expect(seenPng, isNotNull);
      expect(seenPng!.$1, 'qr-Meja-1.png');
      expect(seenPng!.$2, isNotEmpty); // header PNG
      expect(seenPng!.$2.first, 0x89);
    });
  });

  group('hapus meja', () {
    testWidgets('tombol tempat sampah tampil di kartu meja', (tester) async {
      await _pump(tester, tokens: {7: 'token-satu'});
      expect(find.byKey(const ValueKey('table-delete-7')), findsOneWidget);
    });

    testWidgets('Batal menutup dialog tanpa menghapus apa pun', (tester) async {
      final repo = _FakeTablesRepository();
      await _pump(tester, tokens: {7: 'token-satu'}, repository: repo);

      await tester.tap(find.byKey(const ValueKey('table-delete-7')));
      await tester.pumpAndSettle();
      expect(find.text('Hapus Meja 1?'), findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus Meja 1?'), findsNothing);
      expect(repo.deleteCalls, isEmpty);
    });

    testWidgets('konfirmasi menghapus meja, membuang token lokal, '
        'lalu menampilkan hasil server', (tester) async {
      final repo = _FakeTablesRepository();
      final prefs = MemoryPreferences()
        ..values['table-qr-tokens'] = '{"7":"token-satu"}';
      final store = TableTokenStore(prefs);
      await _pump(
        tester,
        tokens: {7: 'token-satu'},
        repository: repo,
        tokenStore: store,
      );

      await tester.tap(find.byKey(const ValueKey('table-delete-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus meja'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, [7]);
      // Token lokal ikut dibuang — QR lama tidak meninggalkan sisa.
      expect(await store.readAll(), isEmpty);
      // Hasil server jujur: draft ikut terhapus, penjualan tetap tersimpan.
      expect(
        find.textContaining('2 draft ikut terhapus'),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 penjualan tetap tersimpan'),
        findsOneWidget,
      );
    });
  });

  group('TableTokenStore', () {
    test('simpan, tampilkan ulang, dan timpa saat rotasi', () async {
      final store = TableTokenStore(MemoryPreferences());

      await store.save(7, 'abc');
      await store.save(8, 'xyz');
      expect(await store.readAll(), {7: 'abc', 8: 'xyz'});

      // Rotasi token versi lama menimpa penyimpanan lokal.
      await store.save(7, 'baru');
      expect((await store.readAll())[7], 'baru');
      expect((await store.readAll())[8], 'xyz');
    });

    test('data rusak dibuang, bukan melempar error', () async {
      final prefs = MemoryPreferences();
      prefs.values['table-qr-tokens'] = 'bukan-json';
      expect(await TableTokenStore(prefs).readAll(), {});
    });
  });
}
