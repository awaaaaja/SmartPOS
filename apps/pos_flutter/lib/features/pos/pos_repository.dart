import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/sale_models.dart';
import '../../core/mutation_retry.dart';
import '../auth/auth_repository.dart';

/// Baris keranjang aktif kasir (belum final; total final dari server).
class CartLine {
  const CartLine({
    required this.productId,
    required this.productName,
    required this.basePrice,
    this.qty = 1,
    this.note = '',
    this.modifierIds = const [],
    this.modifiers = const [],
  });

  final int productId;
  final String productName;
  final int basePrice;
  final int qty;
  final String note;
  final List<int> modifierIds;

  /// [{id, name, price_delta}]
  final List<Map<String, dynamic>> modifiers;

  int get modifierDelta => modifiers.fold<int>(
    0,
    (sum, m) => sum + ((m['price_delta'] as int?) ?? 0),
  );
  int get unitPrice => basePrice + modifierDelta;
  int get lineTotal => unitPrice * qty;

  /// Kunci gabung: produk + modifier + catatan sama = satu baris.
  bool sameAs(CartLine other) =>
      productId == other.productId &&
      note == other.note &&
      _sameIds(modifierIds, other.modifierIds);

  CartLine copyWith({int? qty}) => CartLine(
    productId: productId,
    productName: productName,
    basePrice: basePrice,
    qty: qty ?? this.qty,
    note: note,
    modifierIds: modifierIds,
    modifiers: modifiers,
  );

  Map<String, dynamic> toRpc() => {
    'product_id': productId,
    'qty': qty,
    'modifier_ids': modifierIds,
    if (note.isNotEmpty) 'note': note,
  };

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort();
    final sb = [...b]..sort();
    for (var i = 0; i < sa.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }
}

/// State keranjang kasir: daftar baris + diskon persen.
class CartState {
  const CartState({this.lines = const [], this.discountPct = 0});

  final List<CartLine> lines;
  final double discountPct;

  int get itemCount => lines.fold(0, (n, l) => n + l.qty);
  bool get isEmpty => lines.isEmpty;

  int get estimatedSubtotal => lines.fold(0, (sum, l) => sum + l.lineTotal);

  CartState _withLines(List<CartLine> newLines, {double? discount}) =>
      CartState(lines: newLines, discountPct: discount ?? discountPct);

  CartState add(CartLine line) {
    final idx = lines.indexWhere((l) => l.sameAs(line));
    if (idx < 0) return _withLines([...lines, line]);
    final updated = [...lines];
    updated[idx] = updated[idx].copyWith(qty: updated[idx].qty + line.qty);
    return _withLines(updated);
  }

  CartState changeQty(int index, int delta) {
    if (index < 0 || index >= lines.length) return this;
    final updated = [...lines];
    final newQty = updated[index].qty + delta;
    if (newQty <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(qty: newQty);
    }
    return _withLines(updated);
  }

  CartState removeAt(int index) {
    if (index < 0 || index >= lines.length) return this;
    final updated = [...lines]..removeAt(index);
    return _withLines(updated);
  }

  CartState withDiscount(double pct) => _withLines([...lines], discount: pct);

  CartState clear() => const CartState();
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(CartLine line) => state = state.add(line);
  void changeQty(int index, int delta) => state = state.changeQty(index, delta);
  void removeAt(int index) => state = state.removeAt(index);
  void setDiscount(double pct) => state = state.withDiscount(pct);
  void clear() => state = state.clear();
}

final cartControllerProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

/// API POS: quote, checkout, riwayat, refund, ringkasan.
class PosRepository {
  PosRepository(this._client, this._retries);

  final SupabaseClient _client;
  final MutationRetryStore _retries;

  Future<Quote> quote(List<CartLine> lines, double discountPct) async {
    final result = await _client.rpc(
      'pos_quote',
      params: {
        'p_items': lines.map((l) => l.toRpc()).toList(),
        'p_discount_pct': discountPct,
      },
    );
    return Quote.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<Receipt> checkout({
    required List<CartLine> lines,
    required String method,
    required int paid,
    required String idempotencyKey,
    double discountPct = 0,
    String diningType = 'TAKEAWAY',
    int? tableId,
  }) async {
    final result = await _client.rpc(
      'pos_checkout',
      params: {
        'p_items': lines.map((l) => l.toRpc()).toList(),
        'p_method': method,
        'p_paid': paid,
        'p_dining_type': diningType,
        'p_table_id': tableId,
        'p_discount_pct': discountPct,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return Receipt.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<Receipt> saleReceipt(int saleId) async {
    final result = await _client.rpc(
      'pos_sale_receipt',
      params: {'p_sale_id': saleId},
    );
    return Receipt.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<PendingMutation?> pendingRefund(int saleId) => _retries.pending(
    _client.auth.currentUser?.id ?? '',
    'pos_refund',
    saleId,
  );

  Future<Receipt> refund(int saleId, int amount, String reason) => _retries.run(
    owner: _client.auth.currentUser?.id ?? '',
    operation: 'pos_refund',
    target: saleId,
    params: {'p_sale_id': saleId, 'p_amount': amount, 'p_reason': reason},
    send: (params) async {
      final result = await _client.rpc('pos_refund', params: params);
      return Receipt.fromJson(Map<String, dynamic>.from(result as Map));
    },
  );

  Future<List<SaleSummary>> fetchSales({String? search}) async {
    var query = _client
        .from('sales')
        .select(
          'id,receipt_no,status,total,refund_amount,created_at,'
          'payments(method)',
        );
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('receipt_no', '%${search.trim()}%');
    }
    final rows = await query.order('created_at', ascending: false).limit(100);
    return (rows as List)
        .map((e) => SaleSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DashboardSummary> dashboardSummary() async {
    final result = await _client.rpc('pos_dashboard_summary');
    return DashboardSummary.fromJson(Map<String, dynamic>.from(result as Map));
  }
}

final posRepositoryProvider = Provider<PosRepository>(
  (ref) => PosRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(mutationRetryStoreProvider),
  ),
);

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>(
  (ref) => ref.watch(posRepositoryProvider).dashboardSummary(),
);
