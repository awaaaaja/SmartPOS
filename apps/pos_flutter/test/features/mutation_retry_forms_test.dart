import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/sale_models.dart';
import 'package:pos_flutter/core/mutation_retry.dart';
import 'package:pos_flutter/features/inventory/inventory_repository.dart';
import 'package:pos_flutter/features/inventory/stock_page.dart';
import 'package:pos_flutter/features/pos/pos_repository.dart';
import 'package:pos_flutter/features/sales_history/history_page.dart';

import '../helpers/memory_preferences.dart';

class _Server {
  final preferences = MemoryPreferences();
  final refundReply = Completer<void>();
  final stockReply = Completer<void>();
  final refundCalls = <Map<String, dynamic>>[];
  final stockCalls = <Map<String, dynamic>>[];
  final receipts = <String, Receipt>{};
  final movements = <String, Ingredient>{};
  int refunded = 0;
  double balance = 100;

  Receipt receipt() => Receipt(
    saleId: 1,
    receiptNo: 'QA-REFUND',
    createdAt: DateTime.utc(2026, 10, 27),
    status: refunded == 10000 ? 'REFUNDED' : 'FINAL',
    subtotal: 10000,
    discountAmount: 0,
    taxAmount: 0,
    serviceAmount: 0,
    total: 10000,
    refundAmount: refunded,
    items: const [],
  );

  Ingredient ingredient() => Ingredient(
    id: 1,
    name: 'Tepung QA',
    baseUnit: 'g',
    balance: balance,
    reorderLevel: 0,
    unitCost: 1,
  );

  void releaseReplies() {
    if (!refundReply.isCompleted) refundReply.complete();
    if (!stockReply.isCompleted) stockReply.complete();
  }
}

class _Pos implements PosRepository {
  _Pos(this.server) : store = MutationRetryStore(server.preferences);
  final _Server server;
  final MutationRetryStore store;

  @override
  Future<PendingMutation?> pendingRefund(int saleId) =>
      store.pending('operator', 'pos_refund', saleId);

  @override
  Future<Receipt> saleReceipt(int saleId) async => server.receipt();

  @override
  Future<Receipt> refund(int saleId, int amount, String reason) => store.run(
    owner: 'operator',
    operation: 'pos_refund',
    target: saleId,
    params: {'p_sale_id': saleId, 'p_amount': amount, 'p_reason': reason},
    send: (wire) async {
      server.refundCalls.add(wire);
      final key = wire['p_idempotency_key'] as String;
      final receipt = server.receipts.putIfAbsent(key, () {
        server.refunded += amount;
        return server.receipt();
      });
      if (server.refundCalls.length == 1) {
        await server.refundReply.future;
        throw TimeoutException('committed but response lost');
      }
      return receipt;
    },
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Inventory implements InventoryRepository {
  _Inventory(this.server) : store = MutationRetryStore(server.preferences);
  final _Server server;
  final MutationRetryStore store;

  @override
  Future<PendingMutation?> pendingAdjustment(int ingredientId) =>
      store.pending('operator', 'inv_adjust_stock', ingredientId);

  @override
  Future<Ingredient> adjustStock({
    required int ingredientId,
    required double qty,
    String? unit,
    required String reason,
    required String source,
  }) => store.run(
    owner: 'operator',
    operation: 'inv_adjust_stock',
    target: ingredientId,
    params: {
      'p_ingredient_id': ingredientId,
      'p_qty': qty,
      'p_unit': unit,
      'p_reason': reason,
      'p_source': source,
    },
    send: (wire) async {
      server.stockCalls.add(wire);
      final key = wire['p_idempotency_key'] as String;
      final ingredient = server.movements.putIfAbsent(key, () {
        server.balance += source == 'WASTE' ? -qty.abs() : qty;
        return server.ingredient();
      });
      if (server.stockCalls.length == 1) {
        await server.stockReply.future;
        throw TimeoutException('committed but response lost');
      }
      return ingredient;
    },
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _app(_Server server, {bool stock = false}) => ProviderScope(
  overrides: [
    posRepositoryProvider.overrideWithValue(_Pos(server)),
    inventoryRepositoryProvider.overrideWithValue(_Inventory(server)),
    ingredientsProvider.overrideWith((ref) async => [server.ingredient()]),
    salesListProvider.overrideWith(
      (ref, search) async => [
        SaleSummary(
          id: 1,
          receiptNo: 'QA-REFUND',
          status: 'FINAL',
          total: 10000,
          refundAmount: server.refunded,
          createdAt: DateTime.utc(2026, 10, 27),
        ),
      ],
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: stock ? const InventoryPage() : const SalesHistoryPage(),
  ),
);

Finder get _fields => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

Future<void> _surface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1024, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _openStock(WidgetTester tester) async {
  await tester.tap(find.text('Tepung QA'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Koreksi / Waste'));
  await tester.pumpAndSettle();
}

void main() {
  for (final amount in [100, 10000]) {
    testWidgets(
      'refund $amount: timeout, reopen, dan retry tidak memotong dua kali',
      (tester) async {
        await _surface(tester);
        final server = _Server();
        addTearDown(server.releaseReplies);
        await tester.pumpWidget(_app(server));
        await tester.pumpAndSettle();
        await tester.tap(find.text('QA-REFUND'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Proses Refund'));
        await tester.pumpAndSettle();
        await tester.enterText(_fields.first, '$amount');
        await tester.enterText(_fields.last, 'retry QA');
        await tester.tap(find.text('Simpan Refund'));
        await tester.pumpAndSettle();
        expect(server.refundCalls, hasLength(1));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Simpan Refund'),
              )
              .onPressed,
          isNull,
        );
        server.refundReply.complete();
        await tester.pumpAndSettle();
        expect(find.text('Ulangi refund yang sama'), findsOneWidget);
        expect(tester.widget<TextField>(_fields.first).enabled, isFalse);
        await tester.tap(find.text('Tutup'));
        await tester.pumpAndSettle();
        // Tutup detail lalu buka kembali: struk kini sudah mencerminkan commit.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        await tester.tap(find.text('QA-REFUND'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            amount == 10000 ? 'Periksa refund tertunda' : 'Proses Refund',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_fields.first).controller!.text,
          '$amount',
        );
        await tester.tap(find.text('Ulangi refund yang sama'));
        await tester.pumpAndSettle();
        expect(server.refunded, amount);
        expect(server.receipts, hasLength(1));
        expect(server.refundCalls, hasLength(2));
        expect(
          server.refundCalls[0]['p_idempotency_key'],
          server.refundCalls[1]['p_idempotency_key'],
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final source in ['ADJUSTMENT', 'WASTE']) {
    testWidgets(
      '$source: modal bertahan saat timeout dan reopen memakai key lama',
      (tester) async {
        await _surface(tester);
        final server = _Server();
        addTearDown(server.releaseReplies);
        await tester.pumpWidget(_app(server, stock: true));
        await tester.pumpAndSettle();
        await _openStock(tester);
        if (source == 'WASTE') {
          await tester.tap(find.text('Waste'));
          await tester.pumpAndSettle();
        }
        final qty = source == 'WASTE' ? 2.0 : -3.0;
        await tester.enterText(_fields.first, '$qty');
        await tester.enterText(_fields.last, 'retry QA');
        await tester.tap(find.text('Catat mutasi'));
        await tester.pumpAndSettle();
        expect(server.stockCalls, hasLength(1));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Catat mutasi'),
              )
              .onPressed,
          isNull,
        );
        server.stockReply.complete();
        await tester.pumpAndSettle();
        expect(find.text('Ulangi mutasi yang sama'), findsOneWidget);
        expect(tester.widget<TextField>(_fields.first).enabled, isFalse);
        await tester.tap(find.text('Tutup'));
        await tester.pumpAndSettle();
        await _openStock(tester);
        expect(
          tester.widget<TextField>(_fields.first).controller!.text,
          '$qty',
        );
        expect(
          tester
              .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>),
              )
              .onSelectionChanged,
          isNull,
        );
        await tester.tap(find.text('Ulangi mutasi yang sama'));
        await tester.pumpAndSettle();
        expect(server.balance, source == 'WASTE' ? 98 : 97);
        expect(server.movements, hasLength(1));
        expect(server.stockCalls, hasLength(2));
        expect(
          server.stockCalls[0]['p_idempotency_key'],
          server.stockCalls[1]['p_idempotency_key'],
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
