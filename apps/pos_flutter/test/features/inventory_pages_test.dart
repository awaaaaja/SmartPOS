import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/features/inventory/inventory_repository.dart';
import 'package:pos_flutter/features/inventory/stock_page.dart';
import 'package:pos_flutter/features/purchases/purchases_page.dart';
import 'package:pos_flutter/features/recipes_hpp/recipes_page.dart';

/// Halaman nyata Sprint 04 diuji dengan data palsu lewat override
/// provider (tanpa jaringan): empty state jujur, status minimum,
/// dan status "resep belum ada".

Widget _app(Widget child) => ProviderScope(
      child: MaterialApp(
          theme: buildAppTheme(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets('stok: daftar menampilkan saldo, status minimum, pencarian',
      (tester) async {
    const ingredients = [
      Ingredient(
          id: 1,
          name: 'Tepung Terigu',
          baseUnit: 'g',
          balance: 250,
          reorderLevel: 500,
          unitCost: 13),
      Ingredient(
          id: 2,
          name: 'Minyak Goreng',
          baseUnit: 'ml',
          balance: 2000,
          reorderLevel: 0,
          unitCost: 5),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ingredientsProvider.overrideWith((ref) async => ingredients),
        ingredientSearchProvider.overrideWith((ref) => ''),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: InventoryPage()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tepung Terigu'), findsOneWidget);
    expect(find.text('Minyak Goreng'), findsOneWidget);
    // Status minimum jujur: 250 g <= batas 500 g.
    expect(find.text('DI BAWAH MINIMUM'), findsOneWidget);
    expect(find.textContaining('250 g'), findsOneWidget);
    // Tidak ada klaim angka stok palsu untuk bahan kosong.
    expect(find.text('HABIS'), findsNothing);
  });

  testWidgets('stok: empty state jujur saat belum ada bahan',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ingredientsProvider.overrideWith((ref) async => const []),
        ingredientSearchProvider.overrideWith((ref) => ''),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: InventoryPage()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Belum ada bahan terdaftar'), findsOneWidget);
    expect(find.text('Bahan baru'), findsOneWidget);
  });

  testWidgets('pembelian: empty state jujur', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        purchasesProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: PurchasesPage()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum ada pembelian tercatat'),
        findsOneWidget);
    expect(find.text('Pembelian baru'), findsOneWidget);
  });

  testWidgets('resep: menu tanpa resep menampilkan status "resep belum ada"',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        recipeProductsProvider.overrideWith((ref) async => const [
              RecipeProduct(
                  id: 10,
                  name: 'Es Teh Manis',
                  price: 10000,
                  stockMode: 'RECIPE'),
            ]),
        hppProvider.overrideWith(
            (ref, id) async => const RecipeHpp(productId: 10, hasRecipe: false)),
        recipeVersionsProvider.overrideWith((ref, id) async => const []),
        ingredientsProvider.overrideWith((ref) async => const []),
        hppAlertsProvider.overrideWith((ref) async => const HppAlerts(
            thresholdPct: 10, windowDays: 90, alerts: [])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: RecipesHppPage()),
      ),
    ));
    await tester.pumpAndSettle();

    // Pilih menu dulu -> detail tampil.
    await tester.tap(find.text('Es Teh Manis'));
    await tester.pumpAndSettle();

    expect(find.text('resep belum ada'), findsOneWidget);
    expect(
        find.textContaining('Stok bahan TIDAK dipotong otomatis'),
        findsOneWidget);
    expect(find.text('Buat resep pertama'), findsOneWidget);
    // Tanpa resep: tidak ada angka HPP palsu.
    expect(find.text('HPP per porsi'), findsNothing);
  });

  testWidgets('resep: HPP per porsi dan riwayat versi tampil untuk resep aktif',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        recipeProductsProvider.overrideWith((ref) async => const [
              RecipeProduct(
                  id: 11,
                  name: 'Nasi Goreng',
                  price: 21000,
                  stockMode: 'RECIPE'),
            ]),
        hppProvider.overrideWith((ref, id) async => const RecipeHpp(
              productId: 11,
              hasRecipe: true,
              version: 2,
              yieldQty: 1,
              hppPerPortion: 8500,
              items: [
                RecipeItemCost(
                    ingredientId: 1,
                    name: 'Beras',
                    baseUnit: 'g',
                    qty: 300,
                    unitCost: 15,
                    cost: 4500,
                    balance: 40000),
              ],
            )),
        recipeVersionsProvider.overrideWith((ref, id) async => [
              RecipeVersion(
                  id: 3,
                  productId: 11,
                  version: 2,
                  yieldQty: 1,
                  isActive: true,
                  createdAt: DateTime.utc(2026, 10, 26, 3)),
            ]),
        ingredientsProvider.overrideWith((ref) async => const []),
        hppAlertsProvider.overrideWith((ref) async => const HppAlerts(
            thresholdPct: 10, windowDays: 90, alerts: [])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: RecipesHppPage()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nasi Goreng'));
    await tester.pumpAndSettle();

    expect(find.text('HPP per porsi'), findsOneWidget);
    expect(find.text('Rp 8.500'), findsOneWidget);
    expect(find.text('Beras'), findsOneWidget);
    expect(find.textContaining('Versi 2'), findsWidgets); // ringkasan + riwayat
    expect(find.text('resep belum ada'), findsNothing);
  });

  // _app dipakai bila hanya butuh kerangka tanpa override.
  testWidgets('kerangka halaman kosong tidak overflow', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const InventoryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
