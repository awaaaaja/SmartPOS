import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';

/// Satu baris master bahan (S04-01). Satuan dasar hanya g/ml/pcs;
/// kg dan liter dikonversi server (inv_to_base).
class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.baseUnit,
    required this.balance,
    required this.reorderLevel,
    required this.unitCost,
  });

  final int id;
  final String name;
  final String baseUnit;
  final double balance;
  final double reorderLevel;

  /// Biaya per satuan dasar (Rp), diperbarui saat pembelian diterima.
  final int unitCost;

  /// Status minimum jujur: saldo tidak lagi di atas batas minimum.
  bool get isLow => balance <= reorderLevel;

  bool get isOut => balance <= 0;

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        baseUnit: j['base_unit'] as String,
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
        reorderLevel: (j['reorder_level'] as num?)?.toDouble() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toInt() ?? 0,
      );
}

/// Satu baris ledger mutasi (append-only, S04-05).
class StockMovement {
  const StockMovement({
    required this.id,
    required this.ingredientId,
    required this.qtyDelta,
    required this.balanceAfter,
    required this.source,
    required this.reason,
    this.ref,
    required this.createdAt,
  });

  final int id;
  final int ingredientId;
  final double qtyDelta;
  final double balanceAfter;
  final String source;
  final String reason;
  final String? ref;
  final DateTime createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        id: (j['id'] as num).toInt(),
        ingredientId: (j['ingredient_id'] as num).toInt(),
        qtyDelta: (j['qty_delta'] as num).toDouble(),
        balanceAfter: (j['balance_after'] as num).toDouble(),
        source: j['source'] as String,
        reason: j['reason'] as String,
        ref: j['ref'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// Satu baris pembelian beserta bahan terkait.
class PurchaseLine {
  const PurchaseLine({
    required this.ingredientId,
    required this.ingredientName,
    required this.baseUnit,
    required this.qty,
    required this.unitCost,
    required this.total,
  });

  final int ingredientId;
  final String ingredientName;
  final String baseUnit;
  final double qty;
  final int unitCost;
  final int total;

  factory PurchaseLine.fromJson(Map<String, dynamic> j) {
    final ing = (j['ingredient'] as Map<String, dynamic>?) ?? const {};
    return PurchaseLine(
      ingredientId: (j['ingredient_id'] as num).toInt(),
      ingredientName: ing['name'] as String? ?? '-',
      baseUnit: ing['base_unit'] as String? ?? '',
      qty: (j['qty'] as num).toDouble(),
      unitCost: (j['unit_cost'] as num).toInt(),
      total: (j['total'] as num).toInt(),
    );
  }
}

class Purchase {
  const Purchase({
    required this.id,
    required this.supplier,
    required this.purchasedAt,
    required this.status,
    required this.total,
    required this.items,
  });

  final int id;
  final String? supplier;
  final DateTime purchasedAt;
  final String status;
  final int total;
  final List<PurchaseLine> items;

  bool get isReceived => status == 'RECEIVED';

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        id: (j['id'] as num).toInt(),
        supplier: j['supplier'] as String?,
        purchasedAt: DateTime.parse(j['purchased_at'] as String),
        status: j['status'] as String,
        total: (j['total'] as num?)?.toInt() ?? 0,
        items: ((j['purchase_items'] as List?) ?? const [])
            .map((e) =>
                PurchaseLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Hasil inv_hpp: bahan + biaya per porsi dari resep aktif (UAT-08).
class RecipeHpp {
  const RecipeHpp({
    required this.productId,
    required this.hasRecipe,
    this.version,
    this.yieldQty,
    this.items = const [],
    this.hppPerPortion,
  });

  final int productId;
  final bool hasRecipe;
  final int? version;
  final double? yieldQty;
  final List<RecipeItemCost> items;
  final double? hppPerPortion;

  factory RecipeHpp.fromJson(Map<String, dynamic> j) => RecipeHpp(
        productId: (j['product_id'] as num).toInt(),
        hasRecipe: (j['has_recipe'] as bool?) ?? false,
        version: (j['version'] as num?)?.toInt(),
        yieldQty: (j['yield_qty'] as num?)?.toDouble(),
        hppPerPortion: (j['hpp_per_portion'] as num?)?.toDouble(),
        items: ((j['items'] as List?) ?? const [])
            .map((e) =>
                RecipeItemCost.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class RecipeItemCost {
  const RecipeItemCost({
    required this.ingredientId,
    required this.name,
    required this.baseUnit,
    required this.qty,
    required this.unitCost,
    required this.cost,
    required this.balance,
  });

  final int ingredientId;
  final String name;
  final String baseUnit;
  final double qty;
  final int unitCost;
  final int cost;
  final double balance;

  factory RecipeItemCost.fromJson(Map<String, dynamic> j) => RecipeItemCost(
        ingredientId: (j['ingredient_id'] as num).toInt(),
        name: j['name'] as String? ?? '-',
        baseUnit: j['base_unit'] as String? ?? '',
        qty: (j['qty'] as num).toDouble(),
        unitCost: (j['unit_cost'] as num).toInt(),
        cost: (j['cost'] as num).toInt(),
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
      );
}

/// Satu baris riwayat versi resep (versi lama tidak dihapus).
class RecipeVersion {
  const RecipeVersion({
    required this.id,
    required this.productId,
    required this.version,
    required this.yieldQty,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final int productId;
  final int version;
  final double yieldQty;
  final bool isActive;
  final DateTime createdAt;

  factory RecipeVersion.fromJson(Map<String, dynamic> j) => RecipeVersion(
        id: (j['id'] as num).toInt(),
        productId: (j['product_id'] as num).toInt(),
        version: (j['version'] as num).toInt(),
        yieldQty: (j['yield_qty'] as num).toDouble(),
        isActive: (j['is_active'] as bool?) ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// Menu untuk halaman resep: mode stok ikut terbaca (RECIPE/BATCH).
class RecipeProduct {
  const RecipeProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.stockMode,
  });

  final int id;
  final String name;
  final int price;
  final String stockMode;

  factory RecipeProduct.fromJson(Map<String, dynamic> j) => RecipeProduct(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        price: (j['price'] as num).toInt(),
        stockMode: j['stock_mode'] as String? ?? 'RECIPE',
      );
}

/// Akses inventori Sprint 04 (S04-01…09). Baca tabel langsung (RLS
/// SELECT-only operator); tulisan hanya lewat RPC SECURITY DEFINER.
class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  static const _ingredientSelect =
      'id,name,base_unit,balance,reorder_level,unit_cost';

  Future<List<Ingredient>> fetchIngredients({String search = ''}) async {
    var query = _client.from('ingredients').select(_ingredientSelect);
    final q = search.trim();
    if (q.isNotEmpty) {
      query = query.ilike('name', '%$q%');
    }
    // postgrest-dart default descending — daftar bahan harus A→Z.
    final rows = await query.order('name', ascending: true);
    return (rows as List)
        .map((e) => Ingredient.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Ingredient> saveIngredient({
    int? id,
    required String name,
    required String baseUnit,
    required double reorderLevel,
    required int unitCost,
  }) async {
    final row = await _client.rpc('inv_save_ingredient', params: {
      'p_id': id,
      'p_name': name,
      'p_base_unit': baseUnit,
      'p_reorder_level': reorderLevel,
      'p_unit_cost': unitCost,
    });
    return Ingredient.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Koreksi (naik/turun sesuai tanda) atau waste (selalu pengurangan),
  /// wajib beralasan — kebijakan audit Sprint 04.
  Future<Ingredient> adjustStock({
    required int ingredientId,
    required double qty,
    String? unit,
    required String reason,
    required String source,
  }) async {
    final row = await _client.rpc('inv_adjust_stock', params: {
      'p_ingredient_id': ingredientId,
      'p_qty': qty,
      'p_unit': unit,
      'p_reason': reason,
      'p_source': source,
    });
    return Ingredient.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<StockMovement>> fetchMovements(int ingredientId) async {
    final rows = await _client
        .from('stock_movements')
        .select()
        .eq('ingredient_id', ingredientId)
        .order('id', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) =>
            StockMovement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Purchase>> fetchPurchases() async {
    final rows = await _client.from('purchases').select('''
          id,supplier,purchased_at,status,total,
          purchase_items(ingredient_id,qty,unit_cost,total,
            ingredient:ingredients(name,base_unit))
        ''').order('id', ascending: false).limit(100);
    return (rows as List)
        .map((e) => Purchase.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// items: [{ingredient_id, qty, unit, total_price}] — qty boleh dalam
  /// kg/liter; server konversi ke satuan dasar.
  Future<int> createPurchase({
    String? supplier,
    required List<Map<String, dynamic>> items,
    required String status,
    DateTime? purchasedAt,
  }) async {
    final row = await _client.rpc('inv_create_purchase', params: {
      'p_supplier': supplier,
      'p_items': items,
      'p_purchased_at':
          (purchasedAt ?? DateTime.now()).toIso8601String().substring(0, 10),
      'p_status': status,
    });
    return (Map<String, dynamic>.from(row as Map)['purchase_id'] as num)
        .toInt();
  }

  Future<void> receivePurchase(int purchaseId) =>
      _client.rpc('inv_receive_purchase', params: {
        'p_purchase_id': purchaseId,
      });

  Future<List<RecipeProduct>> fetchRecipeProducts() async {
    final rows = await _client
        .from('products')
        .select('id,name,price,stock_mode')
        .eq('is_active', true)
        .isFilter('archived_at', null)
        .order('name', ascending: true);
    return (rows as List)
        .map((e) =>
            RecipeProduct.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<RecipeHpp> fetchHpp(int productId) async {
    final row =
        await _client.rpc('inv_hpp', params: {'p_product_id': productId});
    return RecipeHpp.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Simpan resep sebagai VERSI BARU (versi lama tetap tersimpan).
  Future<RecipeHpp> saveRecipe({
    required int productId,
    required double yieldQty,
    required List<Map<String, dynamic>> items,
  }) async {
    final row = await _client.rpc('inv_save_recipe', params: {
      'p_product_id': productId,
      'p_yield_qty': yieldQty,
      'p_items': items,
    });
    return RecipeHpp.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<RecipeVersion>> fetchVersions(int productId) async {
    final rows = await _client
        .from('recipe_versions')
        .select()
        .eq('product_id', productId)
        .order('version', ascending: false);
    return (rows as List)
        .map((e) =>
            RecipeVersion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Produksi batch (gorengan): bahan dipotong sekali di sini.
  Future<void> produceBatch({
    required int productId,
    required double qtyProduced,
    String? note,
  }) =>
      _client.rpc('inv_produce_batch', params: {
        'p_product_id': productId,
        'p_qty_produced': qtyProduced,
        'p_note': note,
      });
}

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(supabaseClientProvider)),
);

final ingredientsProvider =
    FutureProvider.autoDispose<List<Ingredient>>((ref) {
  final search = ref.watch(ingredientSearchProvider);
  return ref.watch(inventoryRepositoryProvider).fetchIngredients(search: search);
});

/// Pencarian lokal di halaman stok (S04-02).
final ingredientSearchProvider = StateProvider<String>((ref) => '');

final purchasesProvider = FutureProvider.autoDispose<List<Purchase>>((ref) =>
    ref.watch(inventoryRepositoryProvider).fetchPurchases());

final recipeProductsProvider = FutureProvider.autoDispose<List<RecipeProduct>>(
    (ref) => ref.watch(inventoryRepositoryProvider).fetchRecipeProducts());

/// HPP per produk: `has_recipe=false` = status jujur "resep belum ada".
final hppProvider = FutureProvider.autoDispose
    .family<RecipeHpp, int>(
        (ref, productId) =>
            ref.watch(inventoryRepositoryProvider).fetchHpp(productId));

final recipeVersionsProvider = FutureProvider.autoDispose
    .family<List<RecipeVersion>, int>(
        (ref, productId) =>
            ref.watch(inventoryRepositoryProvider).fetchVersions(productId));

final stockMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, int>(
        (ref, ingredientId) =>
            ref.watch(inventoryRepositoryProvider).fetchMovements(ingredientId));
