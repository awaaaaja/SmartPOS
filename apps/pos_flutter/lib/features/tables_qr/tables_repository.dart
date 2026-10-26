import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';

/// Satu baris draft QR pelanggan (bukan sale; total final dari checkout).
class QrDraftItem {
  const QrDraftItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.qty,
    this.note,
    this.modifiers = const [],
  });

  final int productId;
  final String productName;

  /// Snapshot harga per satuan saat pelanggan submit.
  final int unitPrice;
  final int qty;
  final String? note;

  /// [{modifier_id, name, price_delta}]
  final List<Map<String, dynamic>> modifiers;

  int get lineTotal => unitPrice * qty;

  List<int> get modifierIds => modifiers
      .map((m) => (m['modifier_id'] as num?)?.toInt() ?? 0)
      .where((id) => id > 0)
      .toList();

  static QrDraftItem fromJson(Map<String, dynamic> j) => QrDraftItem(
        productId: (j['product_id'] as num).toInt(),
        productName: j['product_name'] as String? ?? '',
        unitPrice: (j['unit_price'] as num).toInt(),
        qty: (j['qty'] as num).toInt(),
        note: j['note'] as String?,
        modifiers: (j['modifiers'] as List? ?? [])
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList(),
      );
}

class QrDraft {
  const QrDraft({
    required this.draftId,
    required this.refCode,
    required this.tableId,
    required this.tableLabel,
    required this.status,
    required this.subtotal,
    required this.itemCount,
    required this.createdAt,
    required this.items,
  });

  final int draftId;
  final String refCode;
  final int tableId;
  final String tableLabel;
  final String status;
  final int subtotal;
  final int itemCount;
  final DateTime? createdAt;
  final List<QrDraftItem> items;

  static QrDraft fromJson(Map<String, dynamic> j) => QrDraft(
        draftId: (j['draft_id'] as num).toInt(),
        refCode: j['ref_code'] as String? ?? '',
        tableId: (j['table_id'] as num).toInt(),
        tableLabel: j['table_label'] as String? ?? '',
        status: j['status'] as String? ?? '',
        subtotal: (j['subtotal'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'] as String),
        items: (j['items'] as List? ?? [])
            .map((i) => QrDraftItem.fromJson(Map<String, dynamic>.from(i as Map)))
            .toList(),
      );
}

/// API draft QR: daftar, ambil (claim), batalkan, tandai selesai.
class QrDraftRepository {
  QrDraftRepository(this._client);

  final SupabaseClient _client;

  Future<List<QrDraft>> listPending() async {
    final result = await _client.rpc('qr_list_drafts');
    return (result as List)
        .map((e) => QrDraft.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<QrDraft> claim(int draftId) async {
    final result =
        await _client.rpc('qr_claim_draft', params: {'p_draft_id': draftId});
    return QrDraft.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> cancel(int draftId) async {
    await _client.rpc('qr_cancel_draft', params: {'p_draft_id': draftId});
  }

  Future<void> complete(int draftId, int saleId) async {
    await _client.rpc('qr_complete_draft', params: {
      'p_draft_id': draftId,
      'p_sale_id': saleId,
    });
  }
}

final qrDraftRepositoryProvider = Provider<QrDraftRepository>(
  (ref) => QrDraftRepository(ref.watch(supabaseClientProvider)),
);

/// Draft PENDING; di-refresh manual dari panel QR Masuk (polling ringan).
final qrDraftsProvider = FutureProvider.autoDispose<List<QrDraft>>(
  (ref) => ref.watch(qrDraftRepositoryProvider).listPending(),
);

/// Satu meja + token plaintext (hanya dikembalikan sekali saat dibuat/
/// dirotasi; di UI hanya ditampilkan untuk dicetak).
class DiningTableEntry {
  const DiningTableEntry({
    required this.id,
    required this.label,
    required this.isEnabled,
    required this.tokenVersion,
  });

  final int id;
  final String label;
  final bool isEnabled;
  final int tokenVersion;

  static DiningTableEntry fromJson(Map<String, dynamic> j) =>
      DiningTableEntry(
        id: (j['id'] as num).toInt(),
        label: j['label'] as String? ?? '',
        isEnabled: j['is_enabled'] as bool? ?? true,
        tokenVersion: (j['token_version'] as num?)?.toInt() ?? 1,
      );
}

/// API Meja & QR: daftar meja (RLS operator), buat, rotasi token.
class TablesRepository {
  TablesRepository(this._client);

  final SupabaseClient _client;

  Future<List<DiningTableEntry>> fetchTables() async {
    final rows = await _client
        .from('dining_tables')
        .select('id,label,is_enabled,token_version')
        .order('id');
    return (rows as List)
        .map((e) =>
            DiningTableEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> setEnabled(int id, bool enabled) async {
    await _client
        .from('dining_tables')
        .update({'is_enabled': enabled}).eq('id', id);
  }

  /// Mengembalikan token plaintext SEKALI; simpan sebagai QR URL.
  Future<String> createTable(String label) async {
    final result = await _client
        .rpc('qr_create_table', params: {'p_label': label.trim()});
    return Map<String, dynamic>.from(result as Map)['token'] as String;
  }

  Future<String> rotateToken(int tableId) async {
    final result = await _client
        .rpc('qr_rotate_token', params: {'p_table_id': tableId});
    return Map<String, dynamic>.from(result as Map)['token'] as String;
  }
}

final tablesRepositoryProvider = Provider<TablesRepository>(
  (ref) => TablesRepository(ref.watch(supabaseClientProvider)),
);

final tablesListProvider = FutureProvider.autoDispose<List<DiningTableEntry>>(
  (ref) => ref.watch(tablesRepositoryProvider).fetchTables(),
);
