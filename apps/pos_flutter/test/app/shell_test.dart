import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/shell.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/catalog_models.dart';
import 'package:pos_flutter/features/auth/auth_repository.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

QrDraft _draft({int id = 42, String status = 'PENDING'}) => QrDraft(
  draftId: id,
  refCode: 'Q000$id',
  tableId: 3,
  tableLabel: 'Meja 3',
  status: status,
  subtotal: 25000,
  itemCount: 1,
  createdAt: DateTime(2026, 11, 1, 10),
  items: const [],
);

/// Kumpulan draft yang bisa dimutasi dari test (untuk polling 10 detik).
class _DraftBox {
  List<QrDraft> rows = const [];
}

class _FakeAuthRepository implements AuthRepository {
  bool signedOut = false;

  @override
  Future<void> signIn({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  User? get currentUser => null;
}

Widget _wrap(Widget child) => ProviderScope(
  overrides: [authRepositoryProvider.overrideWithValue(_FakeAuthRepository())],
  child: MaterialApp(theme: buildAppTheme(), home: child),
);

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('tablet landscape: sidebar tampil, tanpa Dapur/Pegawai', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1024, 768));
    await tester.pumpWidget(_wrap(const AppShell()));
    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets); // sidebar + judul halaman
    expect(find.text('Kasir POS'), findsOneWidget);
    // Tab Pesanan = evolusi panel QR Masuk (plan §C3/C5) — kini ada.
    expect(find.text('Pesanan'), findsOneWidget);
    expect(find.text('Meja & QR'), findsOneWidget);
    expect(find.text('Stok Bahan'), findsOneWidget);
    // Tile baru (Pesanan) membuat 'Laporan' jatuh di bawah lipatan
    // ListView sidebar yang lazy — gulir dulu.
    await tester.drag(find.text('Stok Bahan'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('Laporan'), findsOneWidget);

    // Larangan scope: tidak ada halaman Dapur/Pegawai.
    expect(find.text('Dapur'), findsNothing);
    expect(find.text('Pegawai'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('tablet: pindah modul Meja & QR menampilkan halaman nyata', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1024, 768));
    await tester.pumpWidget(_wrap(const AppShell()));
    await tester.tap(find.text('Meja & QR'));
    await tester.pumpAndSettle();

    // Halaman nyata (bukan placeholder): judul + tombol tambah meja.
    expect(find.text('Meja & QR'), findsWidgets);
    expect(find.text('Meja baru'), findsOneWidget);
  });

  testWidgets('HP portrait: bottom nav 6 item, Lainnya membuka daftar', (
    tester,
  ) async {
    await _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Kasir'), findsOneWidget);
    expect(find.text('Pesanan'), findsOneWidget);
    expect(find.text('Stok'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);

    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();

    expect(find.text('Biaya Operasional'), findsOneWidget);
    await tester.tap(find.text('Biaya Operasional'));
    await tester.pumpAndSettle();
    // Halaman nyata (bukan placeholder): judul + tombol tambah biaya.
    expect(find.text('Biaya Baru'), findsOneWidget);
    expect(find.textContaining('Menyusul'), findsNothing);
  });

  testWidgets('tombol keluar memanggil signOut operator', (tester) async {
    final repo = _FakeAuthRepository();
    await _setSurface(tester, const Size(1024, 768));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Keluar'));
    await tester.pump();
    expect(repo.signedOut, isTrue);
  });

  // --- Fase C: badge PENDING + banner [Lihat] + polling (§B1/§C3) ---

  /// Shell dengan draft QR palsu (bisa berubah lewat [box]) + tanpa audio.
  Future<void> pumpShell(
    WidgetTester tester,
    _DraftBox box, {
    Size surface = const Size(1024, 768),
  }) async {
    await _setSurface(tester, surface);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'notif-sound-enabled': false});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          qrDraftsProvider.overrideWith((ref) async => box.rows),
          // POS butuh katalog termuat agar field pencarian tampil
          // (tanpa jaringan di test).
          productsProvider.overrideWith((ref) async => const <Product>[]),
          categoriesProvider.overrideWith(
            (ref) async => const <ProductCategory>[],
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('badge tab Pesanan menghitung hanya draft PENDING', (
    tester,
  ) async {
    final box = _DraftBox()
      ..rows = [
        _draft(id: 42),
        _draft(id: 43, status: 'CLAIMED'),
        _draft(id: 44, status: 'PREPARING'),
      ];
    await pumpShell(tester, box);

    // Sidebar tablet: lencana '1' pada tile Pesanan (CLAIMED/PREPARING
    // bukan "pesanan baru").
    expect(find.widgetWithText(Badge, '1'), findsOneWidget);
  });

  testWidgets('banner pesanan baru: aksi [Lihat] membuka tab Pesanan', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final box = _DraftBox();
    await pumpShell(tester, box);
    // Muat pertama = baseline sunyi; draft PENDING baru pada tick berikutnya.
    box.rows = [_draft()];
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    expect(find.text('Pesanan baru dari Meja 3 · Q00042'), findsOneWidget);
    await tester.tap(find.text('Lihat'));
    await tester.pumpAndSettle();

    // Tab Pesanan tampil (papan aktif memuat draft yang sama).
    expect(find.text('Baru masuk'), findsOneWidget);
    expect(find.text('Meja 3 · Q00042'), findsOneWidget);
  });

  testWidgets('polling 10 detik tidak me-reset pencarian POS', (tester) async {
    final box = _DraftBox();
    await pumpShell(tester, box, surface: const Size(1024, 768));

    await tester.tap(find.text('Kasir POS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'nasi goreng');
    await tester.pump(const Duration(milliseconds: 300)); // debounce 250 ms

    // Tick polling dua kali (refresh qrDraftsProvider dari watcher).
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.controller.text, 'nasi goreng');
  });
}
