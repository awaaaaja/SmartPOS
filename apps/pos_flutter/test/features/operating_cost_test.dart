import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/features/cash_shift/cash_page.dart';
import 'package:pos_flutter/features/energy/energy_page.dart';
import 'package:pos_flutter/features/expenses/expenses_page.dart';
import 'package:pos_flutter/features/operating_cost/operating_repository.dart';
import 'package:pos_flutter/features/reports/reports_page.dart';

/// Test Sprint 05 (S05-09 / UAT-09–11) tanpa jaringan:
/// - rumus kalkulator listrik & LPG (UAT-09)
/// - biaya/porsi valid
/// - halaman menampilkan penanda ESTIMASI/AKTUAL terpisah (UAT-09)
/// - kas: non-tunai tidak menambah kas fisik, selisih benar (UAT-11)
/// - laporan: refund mengurangi net sales, alokasi ≠ biaya (UAT-10)

Widget _app(Widget child) => ProviderScope(
      child: MaterialApp(
          theme: buildAppTheme(), home: Scaffold(body: child)),
    );

void main() {
  group('EnergyCalculator (UAT-09)', () {
    test('listrik 800W x 3j x 80% x Rp1.500 = 1.92 kWh / Rp2.880', () {
      expect(EnergyCalculator.kwh(watt: 800, hours: 3, loadFactor: 80),
          closeTo(1.92, 1e-9));
      expect(
          EnergyCalculator.electricityCost(
              watt: 800, hours: 3, loadFactor: 80, tariff: 1500),
          2880);
    });

    test('LPG (Rp22.000 / 20 jam) x batch 2,5 jam = Rp2.750', () {
      expect(
          EnergyCalculator.lpgCost(
              refillPrice: 22000, effectiveHours: 20, batchHours: 2.5),
          2750);
    });

    test('biaya per porsi membagi dengan porsi valid', () {
      expect(EnergyCalculator.costPerPortion(2880, 10), 288);
      expect(EnergyCalculator.costPerPortion(2880, 0), 0);
    });

    test('faktor beban 100% memaksimalkan konsumsi', () {
      final maxKwh = EnergyCalculator.kwh(watt: 1000, hours: 2, loadFactor: 100);
      expect(maxKwh, closeTo(2.0, 1e-9));
    });
  });

  testWidgets('kalkulator energi: pratinjau live listrik dan pilihan LPG',
      (tester) async {
    await tester.pumpWidget(_app(const EnergyPage()));
    await tester.pumpAndSettle();

    // Default 800 W, 3 jam, 80%, Rp1.500 -> 1,92 kWh / Rp2.880 / 288 per porsi.
    expect(find.textContaining('1.920 kWh'), findsOneWidget);
    expect(find.text('Rp 2.880'), findsWidgets);
    expect(find.text('Rp 288'), findsOneWidget);

    // Ubah watt -> pratinjau ikut berubah (kalkulator interaktif).
    await tester.enterText(
        find.widgetWithText(TextField, 'Daya (W)'), '1000');
    await tester.pump();
    // 1000 x 3 x 80% / 1000 = 2,4 kWh x 1500 = Rp3.600.
    expect(find.textContaining('2.400 kWh'), findsOneWidget);
    expect(find.text('Rp 3.600'), findsWidgets);

    // Tab LPG tersedia dan menampilkan rumus isi ulang.
    await tester.tap(find.text('LPG'));
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau estimasi LPG'), findsOneWidget);
    expect(find.text('Rp 2.750'), findsWidgets);
  });

  testWidgets('biaya operasional: daftar memisahkan ESTIMASI dan AKTUAL',
      (tester) async {
    final expenses = [
      Expense(
          id: 1,
          type: 'SEWA',
          description: 'Sewa ruko Oktober',
          amount: 1500000,
          kind: 'ACTUAL',
          expenseDate: DateTime(2026, 10, 1)),
      Expense(
          id: 2,
          type: 'LISTRIK',
          description: 'Estimasi listrik 1,92 kWh',
          amount: 2880,
          kind: 'ESTIMATED',
          expenseDate: DateTime(2026, 10, 2),
          sourceRef: 'energy_estimate:9'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expensesProvider.overrideWith((ref) async => expenses),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: ExpensesPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sewa ruko Oktober'), findsOneWidget);
    expect(find.textContaining('ESTIMASI'), findsOneWidget);
    expect(find.textContaining('AKTUAL'), findsOneWidget);
    expect(find.text('Rp 1.500.000'), findsOneWidget);
    expect(find.text('Rp 2.880'), findsOneWidget);
    // Sumber estimasi energi ditandai jujur.
    expect(find.textContaining('dari kalkulator'), findsOneWidget);
  });

  testWidgets('kas shift: status tertutup menawarkan buka shift',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashStatusProvider
              .overrideWith((ref) async => const CashShiftStatus(isOpen: false)),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: CashShiftPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada shift'), findsOneWidget);
    expect(find.text('Buka Shift Baru'), findsOneWidget);
  });

  testWidgets('kas shift aktif: menampilkan rekonsiliasi tunai',
      (tester) async {
    const status = CashShiftStatus(
        isOpen: true,
        shiftId: 7,
        openingCash: 100000,
        cashSales: 24000,
        expectedCash: 124000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashStatusProvider.overrideWith((ref) async => status),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: CashShiftPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kas diharapkan'), findsOneWidget);
    expect(find.text('Rp 124.000'), findsWidgets);
    expect(find.text('Rp 24.000'), findsOneWidget); // tunai net saja
    expect(find.text('Hitung dan Tutup Kas'), findsOneWidget);
    expect(
        find.textContaining('Transfer/QRIS tidak menambah uang tunai fisik'),
        findsOneWidget);
  });

  testWidgets('laporan: statistik, biaya terpisah, dan tombol CSV',
      (tester) async {
    final report = ReportSummary(
      from: DateTime(2026, 10, 20),
      to: DateTime(2026, 10, 26),
      netSales: 500000,
      refunds: 20000,
      transactions: 40,
      trend: const [
        ReportTrendPoint(day: '2026-10-25', revenue: 200000, tx: 15),
        ReportTrendPoint(day: '2026-10-26', revenue: 300000, tx: 25),
      ],
      topProducts: const [
        TopProduct(name: 'Tahu Goreng', qty: 30, revenue: 150000),
      ],
      hppIngredientCost: 120000,
      expensesActual: 1500000,
      expensesEstimated: 202880,
      expensesActualPeriod: 50000,
      expensesEstimatedPeriod: 2880,
      expensesByType: const [
        ExpenseByType(
            type: 'LISTRIK', actualAmount: 0, estimatedAmount: 2880),
      ],
      allocatedTotal: 500000,
    );
    // Perbesar viewport agar seluruh isi laporan terbangun sekaligus.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportProvider.overrideWith((ref) async => report),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: ReportsPage())),
      ),
    );
    await tester.pumpAndSettle();

    // Net sales sudah bersih refund (500.000 = total − 20.000 refund).
    expect(find.text('Rp 500.000'), findsWidgets);
    expect(find.text('Rp 20.000'), findsWidgets);
    // Biaya aktual dan estimasi tampil terpisah.
    expect(find.text('Rp 50.000'), findsWidgets); // aktual periode
    expect(find.text('Rp 2.880'), findsWidgets); // estimasi periode
    // Menu terlaris dan kategori biaya.
    expect(find.text('Tahu Goreng'), findsOneWidget);
    expect(find.text('LISTRIK'), findsOneWidget);
    expect(find.textContaining('bukan proyeksi laba bersih'), findsOneWidget);
    expect(find.text('Ekspor CSV'), findsOneWidget);
  });

  test('buildReportCsv menghasilkan baris nilai integer tanpa format ribuan',
      () {
    final report = ReportSummary(
      from: _day0,
      to: _day1,
      netSales: 500000,
      refunds: 20000,
      transactions: 40,
      trend: [],
      topProducts: [],
      hppIngredientCost: 120000,
      expensesActual: 1500000,
      expensesEstimated: 202880,
      expensesActualPeriod: 50000,
      expensesEstimatedPeriod: 2880,
      expensesByType: [],
      allocatedTotal: 500000,
    );
    final csv = buildReportCsv(report);
    expect(csv, contains('Penjualan,Net sales,500000'));
    expect(csv, contains('Penjualan,Refund,20000'));
    expect(csv, contains('Biaya,Aktual periode,50000'));
    expect(csv, contains('Biaya,Estimasi periode,2880'));
    // Tidak ada pemisah ribuan yang bisa mengubah makna angka.
    expect(csv.contains('500.000'), isFalse);
  });

  test('ReportSummary: margin estimasi = net − HPP − biaya aktual periode',
      () {
    final report = ReportSummary(
      from: _day0,
      to: _day1,
      netSales: 500000,
      refunds: 0,
      transactions: 10,
      trend: [],
      topProducts: [],
      hppIngredientCost: 120000,
      expensesActual: 1500000,
      expensesEstimated: 202880,
      expensesActualPeriod: 50000,
      expensesEstimatedPeriod: 2880,
      expensesByType: [],
      allocatedTotal: 0,
    );
    expect(report.operatingMarginEstimate, 500000 - 120000 - 50000);
  });
}

final _day0 = DateTime(2026, 10, 20);
final _day1 = DateTime(2026, 10, 26);
