import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/shell.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/features/auth/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('tablet landscape: sidebar tampil, tanpa Pesanan/Dapur/Pegawai',
      (tester) async {
    await _setSurface(tester, const Size(1024, 768));
    await tester.pumpWidget(_wrap(const AppShell()));
    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets); // sidebar + judul halaman
    expect(find.text('Kasir POS'), findsOneWidget);
    expect(find.text('Meja & QR'), findsOneWidget);
    expect(find.text('Stok Bahan'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);

    // Larangan scope: tidak ada halaman Dapur/Pesanan/Pegawai.
    expect(find.text('Pesanan'), findsNothing);
    expect(find.text('Dapur'), findsNothing);
    expect(find.text('Pegawai'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('tablet: pindah modul Meja & QR menampilkan halaman nyata',
      (tester) async {
    await _setSurface(tester, const Size(1024, 768));
    await tester.pumpWidget(_wrap(const AppShell()));
    await tester.tap(find.text('Meja & QR'));
    await tester.pumpAndSettle();

    // Halaman nyata (bukan placeholder): judul + tombol tambah meja.
    expect(find.text('Meja & QR'), findsWidgets);
    expect(find.text('Meja baru'), findsOneWidget);
  });

  testWidgets('HP portrait: bottom nav 5 item, Lainnya membuka daftar',
      (tester) async {
    await _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(_wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Kasir'), findsOneWidget);
    expect(find.text('Stok'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);

    await tester.tap(find.text('Lainnya'));
    await tester.pumpAndSettle();

    expect(find.text('Biaya Operasional'), findsOneWidget);
    await tester.tap(find.text('Biaya Operasional'));
    await tester.pumpAndSettle();
    expect(find.text('Menyusul: Sprint 05 (biaya operasional)'), findsOneWidget);
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
}
