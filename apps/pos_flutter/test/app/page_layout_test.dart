import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/sale_models.dart';
import 'package:pos_flutter/core/mutation_retry.dart';
import 'package:pos_flutter/features/cash_shift/cash_page.dart';
import 'package:pos_flutter/features/catalog/catalog_page.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';
import 'package:pos_flutter/features/dashboard/dashboard_page.dart';
import 'package:pos_flutter/features/energy/energy_page.dart';
import 'package:pos_flutter/features/expenses/expenses_page.dart';
import 'package:pos_flutter/features/inventory/inventory_repository.dart';
import 'package:pos_flutter/features/inventory/stock_page.dart';
import 'package:pos_flutter/features/operating_cost/operating_repository.dart';
import 'package:pos_flutter/features/orders/orders_inbox_page.dart';
import 'package:pos_flutter/features/pos/pos_page.dart';
import 'package:pos_flutter/features/pos/pos_repository.dart';
import 'package:pos_flutter/features/purchases/purchases_page.dart';
import 'package:pos_flutter/features/recipes_hpp/recipes_page.dart';
import 'package:pos_flutter/features/reports/reports_page.dart';
import 'package:pos_flutter/features/sales_history/history_page.dart';
import 'package:pos_flutter/features/settings/settings_page.dart';
import 'package:pos_flutter/features/tables_qr/qr_page.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';

Future<T> _response<T>(String state, T value) => switch (state) {
  'loading' => Completer<T>().future,
  'error' => Future<T>.error(Exception('network unavailable')),
  _ => Future<T>.value(value),
};

class _Operating implements OperatingRepository {
  _Operating(this.state);
  final String state;

  @override
  Future<PendingMutation?> pendingEnergyEstimate() => _response(state, null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  const pages = <String, Widget>{
    'dashboard': DashboardPage(),
    'pos': PosPage(),
    'orders': OrdersPage(),
    'tables': TablesQrPage(),
    'catalog': CatalogPage(),
    'inventory': InventoryPage(),
    'recipes': RecipesHppPage(),
    'purchases': PurchasesPage(),
    'expenses': ExpensesPage(),
    'energy': EnergyPage(),
    'cash': CashShiftPage(),
    'history': SalesHistoryPage(),
    'reports': ReportsPage(),
    'settings': SettingsPage(),
  };
  final report = ReportSummary(
    from: DateTime(2026, 10, 27),
    to: DateTime(2026, 10, 27),
    netSales: 0,
    refunds: 0,
    transactions: 0,
    trend: const [],
    topProducts: const [],
    hppIngredientCost: 0,
    expensesActual: 0,
    expensesEstimated: 0,
    expensesActualPeriod: 0,
    expensesEstimatedPeriod: 0,
    expensesByType: const [],
    allocatedTotal: 0,
  );
  for (final size in [const Size(1024, 768), const Size(390, 844)]) {
    for (final state in ['empty', 'loading', 'error']) {
      for (final page in pages.entries) {
        testWidgets('${page.key}: $state pada $size', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                operatingRepositoryProvider.overrideWithValue(
                  _Operating(state),
                ),
                businessSettingsProvider.overrideWith(
                  (ref) => _response(state, {
                    'name': 'Waroeng MeJeng Kampoeng',
                    'address': 'Padang',
                    'timezone': 'Asia/Jakarta',
                    'tax_rate': 0.075,
                    'service_rate': 0.025,
                  }),
                ),
                productsProvider.overrideWith((ref) => _response(state, [])),
                categoriesProvider.overrideWith((ref) => _response(state, [])),
                catalogProductsProvider.overrideWith(
                  (ref) => _response(state, []),
                ),
                catalogCategoriesProvider.overrideWith(
                  (ref) => _response(state, []),
                ),
                qrDraftsProvider.overrideWith((ref) => _response(state, [])),
                tablesListProvider.overrideWith((ref) => _response(state, [])),
                tableTokensProvider.overrideWith((ref) async => {}),
                ingredientsProvider.overrideWith((ref) => _response(state, [])),
                purchasesProvider.overrideWith((ref) => _response(state, [])),
                recipeProductsProvider.overrideWith(
                  (ref) => _response(state, []),
                ),
                expensesProvider.overrideWith((ref) => _response(state, [])),
                salesListProvider.overrideWith(
                  (ref, search) => _response(state, []),
                ),
                cashStatusProvider.overrideWith(
                  (ref) =>
                      _response(state, const CashShiftStatus(isOpen: false)),
                ),
                reportProvider.overrideWith((ref) => _response(state, report)),
                dashboardReportProvider.overrideWith(
                  (ref) => _response(state, report),
                ),
                dashboardSummaryProvider.overrideWith(
                  (ref) => _response(
                    state,
                    const DashboardSummary(
                      todayRevenue: 0,
                      todayTransactions: 0,
                      todayRefunds: 0,
                      allTimeRevenue: 0,
                      allTimeTransactions: 0,
                    ),
                  ),
                ),
              ],
              child: MaterialApp(
                theme: buildAppTheme(),
                home: Scaffold(
                  appBar: AppBar(toolbarHeight: 64),
                  // Sisakan ruang sidebar/bottom navigation seperti AppShell.
                  body: Row(
                    children: [
                      if (size.width >= 840) const SizedBox(width: 249),
                      Expanded(child: page.value),
                    ],
                  ),
                  bottomNavigationBar: size.width < 840
                      ? const SizedBox(height: 80)
                      : null,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          expect(find.byType(page.value.runtimeType), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
