import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/widgets/module_placeholder.dart';

/// Regresi ditemukan di perangkat OPPO landscape: kartu placeholder
/// "BOTTOM OVERFLOWED BY 112 PIXELS" pada viewport pendek tanpa scroll.
void main() {
  testWidgets('placeholder tidak overflow di viewport landscape pendek',
      (tester) async {
    tester.view.physicalSize = const Size(640, 240);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ModulePlaceholder(
          title: 'Dashboard',
          icon: Icons.dashboard_rounded,
          description:
              'Omzet dari transaksi final, jumlah lunas, QR masuk, dan stok kritis akan tampil di sini langsung dari basis data. Belum ada data yang diambil.',
          targetSprint: 'Sprint 02 (omzet transaksi) dan Sprint 03 (badge QR)',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Dashboard'), findsOneWidget);

    // Konten tetap bisa dijangkau dengan scroll sampai chip terlihat.
    await tester.drag(find.byType(Card), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.textContaining('Menyusul:'), findsOneWidget);
  });
}
