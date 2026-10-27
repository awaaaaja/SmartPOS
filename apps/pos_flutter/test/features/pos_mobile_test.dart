import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/sale_models.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';
import 'package:pos_flutter/features/pos/pos_page.dart';
import 'package:pos_flutter/features/pos/pos_repository.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';

class _QuoteRepository implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  int quotedQty = 0;

  @override
  Future<Quote> quote(List<CartLine> lines, double discountPct) async {
    quotedQty = lines.fold(0, (sum, line) => sum + line.qty);
    return Quote(
      subtotal: quotedQty * 10000,
      discountAmount: 0,
      taxAmount: 0,
      serviceAmount: 0,
      total: quotedQty * 10000,
    );
  }
}

void main() {
  testWidgets('tablet 1024: katalog dan keranjang tampil bersama sidebar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsProvider.overrideWith((ref) async => []),
          categoriesProvider.overrideWith((ref) async => []),
          qrDraftsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            appBar: AppBar(toolbarHeight: 64),
            body: const Row(
              children: [
                SizedBox(width: 249),
                Expanded(child: PosPage()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keranjang Kasir'), findsOneWidget);
    expect(find.text('Bayar →'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'HP: perubahan jumlah masuk quote dan pembayaran aman saat keyboard terbuka',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _QuoteRepository();
      final container = ProviderContainer(
        overrides: [
          productsProvider.overrideWith((ref) async => []),
          categoriesProvider.overrideWith((ref) async => []),
          qrDraftsProvider.overrideWith((ref) async => []),
          posRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(cartControllerProvider.notifier)
          .add(
            const CartLine(
              productId: 1,
              productName: 'Teh manis',
              basePrice: 10000,
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildAppTheme(), home: const PosPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bayar →'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Tambah'));
      await tester.pumpAndSettle();
      expect(find.text('2 item'), findsOneWidget);
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      expect(repo.quotedQty, 2);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Konfirmasi & Simpan Penjualan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Konfirmasi & Simpan Penjualan').hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
