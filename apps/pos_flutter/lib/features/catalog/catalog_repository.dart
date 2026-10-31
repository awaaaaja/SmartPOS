import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/catalog_models.dart';
import '../auth/auth_repository.dart';

/// Akses katalog (S02-01/02/03): kategori, produk, foto, modifier, arsip.
class CatalogRepository {
  CatalogRepository(this._client);

  final SupabaseClient _client;

  static const _productSelect =
      'id,category_id,name,price,photo_url,is_active,archived_at,'
      'category:product_categories(name),'
      'product_modifiers(min_select,max_select,'
      'modifier:modifiers(id,name,price_delta,is_active))';

  Future<List<ProductCategory>> fetchCategories({
    bool includeArchived = false,
  }) async {
    var query = _client.from('product_categories').select();
    if (!includeArchived) query = query.isFilter('archived_at', null);
    final rows = await query.order('sort_order').order('name');
    return (rows as List)
        .map(
          (e) => ProductCategory.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<ProductCategory> createCategory(String name) async {
    final row = await _client
        .from('product_categories')
        .insert({'name': name.trim()})
        .select()
        .single();
    return ProductCategory.fromJson(row);
  }

  Future<void> archiveCategory(int id) => _client
      .from('product_categories')
      .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);

  Future<List<Product>> fetchProducts({bool includeArchived = false}) async {
    var query = _client.from('products').select(_productSelect);
    if (!includeArchived) query = query.isFilter('archived_at', null);
    final rows = await query.order('name');
    return (rows as List)
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Product> upsertProduct({
    int? id,
    required String name,
    required int price,
    int? categoryId,
    String? photoUrl,
    required bool isActive,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'price': price,
      'category_id': categoryId,
      'photo_url': photoUrl,
      'is_active': isActive,
    };
    final row = id == null
        ? await _client
              .from('products')
              .insert(payload)
              .select(_productSelect)
              .single()
        : await _client
              .from('products')
              .update(payload)
              .eq('id', id)
              .select(_productSelect)
              .single();
    return Product.fromJson(row);
  }

  Future<void> setProductActive(int id, bool active) =>
      _client.from('products').update({'is_active': active}).eq('id', id);

  Future<void> archiveProduct(int id) => _client
      .from('products')
      .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);

  Future<List<PriceHistoryEntry>> fetchPriceHistory(int productId) async {
    final rows = await _client
        .from('product_price_history')
        .select('old_price,new_price,reason,effective_at')
        .eq('product_id', productId)
        .order('effective_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map(
          (e) =>
              PriceHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<List<Modifier>> fetchModifiers() async {
    final rows = await _client
        .from('modifiers')
        .select('id,name,price_delta,is_active')
        .order('name');
    return (rows as List)
        .map((e) => Modifier.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Modifier> createModifier(String name, int priceDelta) async {
    final row = await _client
        .from('modifiers')
        .insert({'name': name.trim(), 'price_delta': priceDelta})
        .select('id,name,price_delta,is_active')
        .single();
    return Modifier.fromJson(row);
  }

  /// Pasang/hapus modifier produk sekaligus atur min/max (varian & topping).
  Future<void> setProductModifiers(
    int productId,
    List<Modifier> modifiers,
  ) async {
    await _client
        .from('product_modifiers')
        .delete()
        .eq('product_id', productId);
    if (modifiers.isEmpty) return;
    await _client.from('product_modifiers').insert([
      for (final m in modifiers)
        {
          'product_id': productId,
          'modifier_id': m.id,
          'min_select': m.minSelect,
          'max_select': m.maxSelect,
        },
    ]);
  }

  /// Upload foto produk ke bucket publik `product-photos` (S02-01).
  Future<String> uploadPhoto(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = 'menu-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage
        .from('product-photos')
        .upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return _client.storage.from('product-photos').getPublicUrl(path);
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(supabaseClientProvider)),
);

/// Daftar produk aktif untuk POS dan katalog.
// Produk & kategori di-cache selama sesi (tanpa autoDispose): semua mutasi
// katalog memanggil ref.invalidate di catalog_page, sehingga pindah halaman
// tidak lagi refetch + spinner — navigasi POS/katalog terasa jauh lebih ringan.
final productsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).fetchProducts(),
);

final categoriesProvider = FutureProvider<List<ProductCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).fetchCategories(),
);

final modifiersProvider = FutureProvider.autoDispose<List<Modifier>>(
  (ref) => ref.watch(catalogRepositoryProvider).fetchModifiers(),
);
