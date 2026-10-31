import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/destinations.dart';
import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../catalog/catalog_repository.dart';
import '../tables_qr/tables_repository.dart';
import 'pos_repository.dart';

/// Id draft yang sudah diambil ke keranjang perangkat INI (menunggu
/// checkout melunasinya). Global (Notifier) supaya tab Pesanan, Kasir POS,
/// dan dialog pembayaran memakai satu sumber yang sama — dipindah dari
/// field privat `PosPage` (rencana §C3).
final claimedDraftIdsProvider = NotifierProvider<ClaimedDraftIds, Set<int>>(
  ClaimedDraftIds.new,
);

class ClaimedDraftIds extends Notifier<Set<int>> {
  @override
  Set<int> build() => <int>{};

  void add(int id) => state = {...state, id};

  /// Ambil semua id lalu kosongkan (dipanggil setelah checkout sukses).
  Set<int> takeAll() {
    final ids = state;
    state = <int>{};
    return ids;
  }
}

/// Alur klaim draft ke keranjang POS (dipakai Kasir POS & tab Pesanan) —
/// logika konflik harga dipindah utuh dari `PosPage._claimDraft`.
class QrClaimService {
  const QrClaimService._();

  /// Klaim [draft] ke keranjang.
  ///
  /// - Status PENDING → klaim atomik di server dulu (batal bila sudah
  ///   diambil operator lain).
  /// - Status lain (sudah Diterima/Diproses/Selesai) → lanjutkan lokal:
  ///   item masuk keranjang & id tercatat untuk dilunasi checkout.
  /// - Snapshot harga berbeda dari harga katalog kini → dialog persetujuan
  ///   operator; item tak tersedia dilewati & dilaporkan.
  ///
  /// Mengembalikan true bila id tercatat di [claimedDraftIdsProvider].
  static Future<bool> claimDraft(
    WidgetRef ref,
    BuildContext context,
    QrDraft draft,
  ) async {
    if (ref.read(claimedDraftIdsProvider).contains(draft.draftId)) {
      return true; // Sudah di keranjang perangkat ini (invarian C1.2).
    }

    // Harga katalog DIREFRESH dulu; deteksi konflik harus memakai harga
    // terkini, bukan cache lama.
    final allProducts = await ref.refresh(productsProvider.future);
    final byId = {for (final p in allProducts) p.id: p};

    final conflicts = <String>[];
    final unavailable = <String>[];
    final lines = <CartLine>[];

    for (final item in draft.items) {
      final product = byId[item.productId];
      if (product == null || !product.sellable) {
        unavailable.add(item.productName);
        continue;
      }
      // Harga aktif sekarang = harga dasar + modifier terpilih (harga kini).
      final mods = product.modifiers
          .where((m) => item.modifierIds.contains(m.id))
          .toList();
      final currentUnit =
          product.price + mods.fold<int>(0, (sum, m) => sum + m.priceDelta);
      if (currentUnit != item.unitPrice) {
        conflicts.add(
          '${item.productName}: ${formatRupiah(item.unitPrice)} → '
          '${formatRupiah(currentUnit)}',
        );
      }
      lines.add(
        CartLine(
          productId: item.productId,
          productName: product.name,
          basePrice: product.price,
          qty: item.qty,
          note: item.note ?? '',
          modifierIds: item.modifierIds,
          modifiers: mods
              .map(
                (m) => {
                  'id': m.id,
                  'name': m.name,
                  'price_delta': m.priceDelta,
                },
              )
              .toList(),
        ),
      );
    }

    if (lines.isEmpty) {
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Tidak ada item valid'),
          content: Text(
            unavailable.isEmpty
                ? 'Seluruh item draft sudah tidak tersedia di katalog.'
                : 'Item tidak tersedia: ${unavailable.join(', ')}.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
      return false;
    }

    if (!context.mounted) return false;
    final proceed =
        conflicts.isEmpty ||
        (await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Konflik harga'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Harga katalog berubah sejak pesanan QR ${draft.refCode} '
                      'dikirim. Keranjang memakai harga terkini:',
                    ),
                    const SizedBox(height: 8),
                    for (final c in conflicts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(c, style: const TextStyle(fontSize: 13)),
                      ),
                    if (unavailable.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Dilewati (tidak tersedia): ${unavailable.join(', ')}',
                        style: const TextStyle(fontSize: 12, color: errorColor),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Pakai harga terkini'),
                  ),
                ],
              ),
            ) ??
            false);
    if (!proceed || !context.mounted) return false;

    // Klaim di server DULU untuk draft PENDING; batal bila sudah diambil
    // operator lain. Status lain diteruskan lokal (sudah pernah diambil).
    if (draft.status == 'PENDING') {
      try {
        await ref.read(qrDraftRepositoryProvider).claim(draft.draftId);
      } catch (e) {
        ref.invalidate(qrDraftsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Draft gagal diambil (mungkin sudah diambil '
                'operator lain): ${mapErrorToMessage(e)}',
              ),
            ),
          );
        }
        return false;
      }
    }

    ref.read(claimedDraftIdsProvider.notifier).add(draft.draftId);

    final cart = ref.read(cartControllerProvider.notifier);
    for (final line in lines) {
      cart.add(line);
    }
    ref.invalidate(qrDraftsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${draft.itemCount} item dari ${draft.tableLabel} masuk '
            'keranjang.',
          ),
        ),
      );
    }
    return true;
  }

  /// Tombol **[Bayar]**: pastikan draft ada di keranjang (klaim bila perlu),
  /// lalu pindah ke Kasir POS — keranjang adjustable sampai checkout.
  static Future<void> payDraft(
    WidgetRef ref,
    BuildContext context,
    QrDraft draft,
  ) async {
    final ok = await claimDraft(ref, context, draft);
    if (!ok) return;
    ref.read(selectedDestinationProvider.notifier).select(AppDestination.pos);
  }

  /// Setelah `pos_checkout` sukses: lunasi SEMUA draft dalam set perangkat
  /// ini (termasuk yang sudah COMPLETED-bayar-nanti) lalu kosongkan set.
  /// Gagal mengaitkan TIDAK memengaruhi uang (sale tetap tersimpan).
  static Future<void> completeClaimed(WidgetRef ref, int saleId) async {
    final ids = ref.read(claimedDraftIdsProvider.notifier).takeAll();
    final repo = ref.read(qrDraftRepositoryProvider);
    for (final id in ids) {
      try {
        await repo.complete(id, saleId);
      } catch (_) {
        // Draft tetap terbuka; tidak memengaruhi uang/omzet. Aman dilewati.
      }
    }
    ref.invalidate(qrDraftsProvider);
  }
}
