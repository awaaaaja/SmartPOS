import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/catalog_models.dart';
import 'package:pos_flutter/features/catalog/catalog_page.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Palsu katalog: mengembalikan data lokal tanpa menyentuh jaringan dan
/// mencatat pemanggilan un-arsip.
class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository({
    required List<Product> products,
    required List<ProductCategory> categories,
  }) : this._(
         SupabaseClient(
           'https://catalog-test.invalid',
           'sb_publishable_test',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
         products,
         categories,
       );

  _FakeCatalogRepository._(this.testClient, this.products, this.categories)
    : super(testClient);

  /// Client dipublikasikan agar test bisa dispose (timer auto-refresh auth).
  final SupabaseClient testClient;
  List<Product> products;
  List<ProductCategory> categories;
  final restoredProducts = <int>[];
  final restoredCategories = <int>[];

  @override
  Future<List<Product>> fetchProducts({bool includeArchived = false}) async =>
      includeArchived
      ? products
      : products.where((p) => !p.isArchived).toList();

  @override
  Future<List<ProductCategory>> fetchCategories({
    bool includeArchived = false,
  }) async => includeArchived
      ? categories
      : categories.where((c) => !c.isArchived).toList();

  @override
  Future<void> restoreProduct(int id) async {
    restoredProducts.add(id);
    products = [
      for (final p in products)
        p.id == id
            ? Product(
                id: p.id,
                name: p.name,
                price: p.price,
                categoryId: p.categoryId,
                isActive: p.isActive,
                modifiers: p.modifiers,
              )
            : p,
    ];
  }

  @override
  Future<void> restoreCategory(int id) async {
    restoredCategories.add(id);
    categories = [
      for (final c in categories)
        c.id == id ? ProductCategory(id: c.id, name: c.name) : c,
    ];
  }
}

Product _active(int id, String name) =>
    Product(id: id, name: name, price: 5000);

Product _archived(int id, String name) =>
    Product(id: id, name: name, price: 5000, archivedAt: DateTime(2026, 10, 1));

Future<void> _pump(WidgetTester tester, _FakeCatalogRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: buildAppTheme(), home: const CatalogPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filter Arsip hanya menampilkan produk arsip', (tester) async {
    final repo = _FakeCatalogRepository(
      products: [_active(1, 'Nasi Goreng'), _archived(2, 'Es Teh Lama')],
      categories: const [],
    );
    await _pump(tester, repo);

    expect(find.text('Nasi Goreng'), findsOneWidget);
    expect(find.text('Es Teh Lama'), findsNothing);

    await tester.tap(find.text('Arsip'));
    await tester.pumpAndSettle();

    expect(find.text('Es Teh Lama'), findsOneWidget);
    expect(find.text('Nasi Goreng'), findsNothing);
  });

  testWidgets('un-arsip produk memanggil repo dan produk pindah ke Aktif', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository(
      products: [_active(1, 'Nasi Goreng'), _archived(2, 'Es Teh Lama')],
      categories: const [],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Arsip'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Keluarkan dari arsip'));
    await tester.pumpAndSettle();

    expect(repo.restoredProducts, [2]);
    // Daftar Arsip tersegarkan: produk yang pulih langsung hilang dari sini.
    expect(find.text('Es Teh Lama'), findsNothing);

    await tester.tap(find.text('Aktif'));
    await tester.pumpAndSettle();
    expect(find.text('Es Teh Lama'), findsOneWidget);
  });

  testWidgets('tab Arsip kosong menampilkan pesan kosong khusus', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository(
      products: [_active(1, 'Nasi Goreng')],
      categories: const [],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Arsip'));
    await tester.pumpAndSettle();

    expect(find.text('Arsip kosong.'), findsOneWidget);
  });

  testWidgets('sheet kategori menampilkan arsip dan un-arsip memanggil repo', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository(
      products: const [],
      categories: [
        const ProductCategory(id: 1, name: 'Makanan'),
        ProductCategory(
          id: 2,
          name: 'Minuman Lama',
          archivedAt: DateTime(2026, 10, 1),
        ),
      ],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Kategori'));
    await tester.pumpAndSettle();

    // Kategori arsip tampil dengan tombol un-arsip (bukan arsip).
    expect(find.byIcon(Icons.unarchive_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Keluarkan dari arsip'));
    await tester.pumpAndSettle();

    expect(repo.restoredCategories, [2]);
    // 'Minuman Lama' pulih: tak lagi punya tombol un-arsip, dan kini ikut
    // tampil normal dengan tombol arsip (2 kategori aktif = 2 ikon archive).
    expect(find.byIcon(Icons.unarchive_rounded), findsNothing);
    expect(find.byIcon(Icons.archive_rounded), findsNWidgets(2));
    expect(find.byTooltip('Keluarkan dari arsip'), findsNothing);
  });
}
