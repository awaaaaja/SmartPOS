import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/mutation_retry.dart';
import 'package:pos_flutter/features/energy/energy_page.dart';
import 'package:pos_flutter/features/expenses/expenses_page.dart';
import 'package:pos_flutter/features/inventory/inventory_repository.dart';
import 'package:pos_flutter/features/operating_cost/operating_repository.dart';
import 'package:pos_flutter/features/purchases/purchases_page.dart';
import 'package:pos_flutter/features/recipes_hpp/recipes_page.dart';
// (hppAlertsProvider & energyCalibrationProvider di-override agar kartu
// rekomendasi read-only tidak memanggil transport mock — di luar skop uji.)
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/memory_preferences.dart';

// Repository dan serialisasi RPC nyata; hanya transport/server yang dipalsukan.
class _Server {
  final preferences = MemoryPreferences();
  final reply = Completer<void>();
  final calls = <Map<String, dynamic>>[];
  final results = <String, Map<String, dynamic>>{};
  late final SupabaseClient client;
  late final http.Client transport;
  bool loseFirst = true;

  MutationRetryStore get store => MutationRetryStore(preferences);
  InventoryRepository get inventory => InventoryRepository(client, store);
  OperatingRepository get operating => OperatingRepository(client, store);

  Future<void> start() async {
    transport = MockClient((request) async {
      final operation = request.url.pathSegments.last;
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(params);
      final key = params['p_idempotency_key'] as String?;
      if (key != null) {
        final pending = await store.pending(
          'operator',
          operation,
          operation == 'inv_produce_batch' ? 1 : 0,
        );
        expect(pending!.key, key);
      }
      final response = results.putIfAbsent(
        '$operation:${key ?? 'edit'}',
        () => switch (operation) {
          'inv_create_purchase' => {'purchase_id': results.length + 1},
          'inv_produce_batch' => {'batch_id': results.length + 1},
          'exp_save' => {
            'id': params['p_id'] ?? results.length + 1,
            'type': params['p_type'],
            'description': params['p_description'],
            'amount': params['p_amount'],
            'kind': params['p_kind'],
            'expense_date': params['p_expense_date'] ?? '2026-10-27',
            'evidence_url': params['p_evidence_url'],
          },
          'energy_save_estimate' => {
            'estimate_id': results.length + 1,
            'expense_id': results.length + 1,
            'kind': params['p_kind'],
            'cost': 2880,
            'portions': params['p_portions'],
            'kwh': params['p_kind'] == 'ELECTRICITY' ? 1.92 : null,
          },
          _ => throw StateError('Unexpected RPC $operation'),
        },
      );
      if (loseFirst && calls.length == 1) {
        await reply.future;
        throw TimeoutException('committed but response lost');
      }
      return http.Response(
        jsonEncode(response),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    client = SupabaseClient(
      'https://retry.invalid',
      'sb_publishable_test',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    final payload = base64Url
        .encode(utf8.encode('{"exp":4102444800}'))
        .replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'e30.$payload.test',
        'token_type': 'bearer',
        'user': {'id': 'operator', 'aud': 'authenticated'},
      }),
    );
  }

  Future<void> close() async {
    if (!reply.isCompleted) reply.complete();
    await client.dispose();
    transport.close();
  }
}

Widget _app(_Server server, String operation) => ProviderScope(
  overrides: [
    inventoryRepositoryProvider.overrideWithValue(server.inventory),
    operatingRepositoryProvider.overrideWithValue(server.operating),
    ingredientsProvider.overrideWith(
      (ref) async => const [
        Ingredient(
          id: 1,
          name: 'Tepung QA',
          baseUnit: 'g',
          balance: 100,
          reorderLevel: 0,
          unitCost: 1,
        ),
      ],
    ),
    purchasesProvider.overrideWith((ref) async => const []),
    expensesProvider.overrideWith((ref) async => const []),
    recipeProductsProvider.overrideWith(
      (ref) async => const [
        RecipeProduct(
          id: 1,
          name: 'Gorengan QA',
          price: 5000,
          stockMode: 'BATCH',
        ),
      ],
    ),
    hppProvider.overrideWith(
      (ref, id) async => const RecipeHpp(
        productId: 1,
        hasRecipe: true,
        version: 1,
        yieldQty: 1,
        hppPerPortion: 10,
        items: [],
      ),
    ),
    recipeVersionsProvider.overrideWith((ref, id) async => const []),
    // Kartu rekomendasi read-only (non-ML) tidak diuji di sini; di-override
    // agar tidak menambah panggilan transport mock yang dihitung tes mutasi.
    hppAlertsProvider.overrideWith(
      (ref) async => const HppAlerts(thresholdPct: 10, windowDays: 90),
    ),
    energyCalibrationProvider.overrideWith(
      (ref) async => EnergyCalibration(
        from: DateTime(2026, 10, 3),
        to: DateTime(2026, 11, 1),
        estimatedTotal: 0,
        actualTotal: 0,
        comparedEstimated: 0,
        comparedActual: 0,
        deviationPct: null,
        suggestedFactor: null,
        enoughData: false,
      ),
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: switch (operation) {
      'inv_create_purchase' => const PurchasesPage(),
      'inv_produce_batch' => const RecipesHppPage(),
      'exp_save' => const ExpensesPage(),
      _ => const EnergyPage(),
    },
  ),
);

Future<void> _open(WidgetTester tester, String operation) async {
  switch (operation) {
    case 'inv_create_purchase':
      await tester.tap(find.text('Pembelian baru'));
    case 'inv_produce_batch':
      await tester.tap(find.text('Gorengan QA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Produksi batch'));
    case 'exp_save':
      await tester.tap(find.text('Biaya Baru'));
  }
  await tester.pumpAndSettle();
}

void main() {
  late _Server server;
  setUp(() async {
    server = _Server();
    await server.start();
  });
  tearDown(() => server.close());

  for (final (operation, submit, retry) in [
    ('inv_create_purchase', 'Simpan', 'Ulangi pembelian yang sama'),
    ('inv_produce_batch', 'Catat produksi', 'Ulangi produksi yang sama'),
    ('exp_save', 'Simpan', 'Ulangi biaya yang sama'),
    (
      'energy_save_estimate',
      'Simpan sebagai Biaya Estimasi',
      'Ulangi estimasi yang sama',
    ),
    (
      'energy_lpg',
      'Simpan sebagai Biaya Estimasi',
      'Ulangi estimasi yang sama',
    ),
  ]) {
    testWidgets(
      '$operation: timeout, relaunch, replay memakai key dan isian lama',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(server, operation));
        await tester.pumpAndSettle();
        await _open(tester, operation);
        switch (operation) {
          case 'inv_create_purchase':
            await tester.enterText(find.byType(TextField).first, 'Supplier QA');
            await tester.enterText(find.byType(TextField).at(2), '2');
            await tester.enterText(find.byType(TextField).at(3), '1000');
          case 'inv_produce_batch':
            await tester.enterText(find.byType(TextField).first, '2');
            await tester.enterText(find.byType(TextField).last, 'produksi QA');
          case 'exp_save':
            await tester.enterText(find.byType(TextField).first, 'Biaya QA');
            await tester.enterText(find.byType(TextField).at(1), '1000');
          case 'energy_lpg':
            await tester.tap(find.text('LPG'));
            await tester.pumpAndSettle();
        }
        await tester.tap(find.text(submit));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(server.calls, hasLength(1));
        if (operation == 'exp_save' || operation.startsWith('energy')) {
          expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, submit))
                .onPressed,
            isNull,
          );
        }
        final first = server.calls.single;
        await tester.runAsync(() async {
          server.reply.complete();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();

        // Buat ulang repository/store, bukan hanya mengosongkan field form.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(_app(server, operation));
        await tester.pumpAndSettle();
        await _open(tester, operation);
        expect(
          find.textContaining('sebelumnya belum terkonfirmasi'),
          findsOneWidget,
        );
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        )) {
          expect(field.enabled, isFalse);
        }
        if (operation == 'inv_create_purchase') {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).at(2))
                .controller!
                .text,
            '2.0',
          );
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            'Supplier QA',
          );
        }
        if (operation == 'energy_lpg') {
          expect(find.text('Pratinjau estimasi LPG'), findsOneWidget);
        }
        await tester.tap(find.text(retry));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(server.calls, hasLength(2));
        expect(server.calls.last, first);
        expect(server.results, hasLength(1));
        final rpc = operation == 'energy_lpg'
            ? 'energy_save_estimate'
            : operation;
        expect(
          await server.store.pending(
            'operator',
            rpc,
            rpc == 'inv_produce_batch' ? 1 : 0,
          ),
          isNull,
        );
        expect(tester.takeException(), isNull);

        // Niat berikutnya boleh identik, tetapi harus mendapatkan key baru.
        await tester.runAsync(() async {
          switch (rpc) {
            case 'inv_create_purchase':
              await server.inventory.createPurchase(
                supplier: first['p_supplier'] as String?,
                items: (first['p_items'] as List).cast<Map<String, dynamic>>(),
                status: first['p_status'] as String,
                purchasedAt: DateTime.parse(first['p_purchased_at'] as String),
              );
            case 'inv_produce_batch':
              await server.inventory.produceBatch(
                productId: 1,
                qtyProduced: 2,
                note: 'produksi QA',
              );
            case 'exp_save':
              await server.operating.saveExpense(
                type: 'LISTRIK',
                description: 'Biaya QA',
                amount: 1000,
                kind: 'ACTUAL',
              );
            case 'energy_save_estimate':
              await server.operating.saveEnergyEstimate(
                kind: first['p_kind'] as String,
                portions: 10,
                watt: 800,
                hours: 3,
                loadFactor: 80,
                tariff: 1500,
                refillPrice: 22000,
                effectiveHours: 20,
                batchHours: 2.5,
              );
          }
        });
        expect(
          server.calls.last['p_idempotency_key'],
          isNot(first['p_idempotency_key']),
        );
        expect(server.results, hasLength(2));
      },
    );
  }

  test(
    'edit expense remains repeatable without a key or pending slot',
    () async {
      server.loseFirst = false;
      for (var i = 0; i < 2; i++) {
        await server.operating.saveExpense(
          id: 7,
          type: 'AIR',
          description: 'Revisi QA',
          amount: 2000,
          kind: 'ACTUAL',
        );
      }
      expect(server.calls, hasLength(2));
      expect(
        server.calls.every((p) => !p.containsKey('p_idempotency_key')),
        isTrue,
      );
      expect(server.preferences.values, isEmpty);
    },
  );
}
