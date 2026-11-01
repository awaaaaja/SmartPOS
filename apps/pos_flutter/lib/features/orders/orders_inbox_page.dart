import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../../core/wa_link.dart';
import '../pos/qr_claim_service.dart';
import '../tables_qr/tables_repository.dart';

/// Id draft yang aksinya sedang berjalan di server. Tombol dinonaktifkan
/// selama RPC berjalan supaya tap ganda tidak mengirim dua permintaan —
/// pemicu utama `draft_not_claimable` ("Status pesanan sudah berubah")
/// saat menekan Diterima/Diproses/Selesai berulang di perangkat lambat.
final orderActionBusyProvider = NotifierProvider<OrderActionBusy, Set<int>>(
  OrderActionBusy.new,
);

class OrderActionBusy extends Notifier<Set<int>> {
  @override
  Set<int> build() => <int>{};

  bool contains(int id) => state.contains(id);

  void add(int id) => state = {...state, id};

  void remove(int id) => state = {...state}..remove(id);
}

/// Tab Pesanan (rencana §C3): papan aktif draft QR — Baru masuk (PENDING) ·
/// Diterima (CLAIMED) · Diproses (PREPARING) · Selesai — belum bayar
/// (COMPLETED, sale null). Evolusi panel QR Masuk: satu sumber draft
/// (`qrDraftsProvider`, polling `QrInboxWatcher`), hanya rumah UI yang baru.
class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  static const _sections = [
    ('Baru masuk', 'PENDING'),
    ('Diterima', 'CLAIMED'),
    ('Diproses', 'PREPARING'),
    ('Selesai — belum bayar', 'UNPAID'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(qrDraftsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pesanan',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Segarkan',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => ref.invalidate(qrDraftsProvider),
                ),
              ],
            ),
          ),
          Expanded(
            child: drafts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(mapErrorToMessage(e)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(qrDraftsProvider),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                final sections = [
                  for (final (label, key) in _sections)
                    (label, _ofSection(items, key)),
                ];
                final total = items.length;
                if (total == 0) return const _EmptyOrders();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    for (final (label, rows) in sections) ...[
                      if (rows.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              label,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: brandSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${rows.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: brandPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final d in rows) ...[
                          _OrderCard(draft: d),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static List<QrDraft> _ofSection(List<QrDraft> all, String key) =>
      switch (key) {
        'PENDING' => all.where((d) => d.status == 'PENDING').toList(),
        'CLAIMED' => all.where((d) => d.status == 'CLAIMED').toList(),
        'PREPARING' => all.where((d) => d.status == 'PREPARING').toList(),
        // COMPLETED tampil semua: yang belum bayar (sale null) menetap di
        // papan; yang sudah dilunasi menampilkan lencana hijau sejenak lalu
        // hilang dari `qr_list_drafts` pada refresh berikutnya.
        _ => all.where((d) => d.status == 'COMPLETED').toList(),
      };
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, size: 48, color: brandSoft),
          SizedBox(height: 12),
          Text(
            'Belum ada pesanan.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Pesanan dari QR meja akan muncul di sini.',
            style: TextStyle(color: textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Kartu satu draft pesanan + aksi sesuai status (tabel §C3).
class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.draft});

  final QrDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paid = draft.saleId != null;
    final name = draft.customerName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final rawPhone = draft.customerPhone ?? '';
    final waPhone = normalizeWaPhone(rawPhone);
    final pref = _preferenceLabel(draft);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${draft.tableLabel} · ${draft.refCode}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _PaymentBadge(paid: paid),
                if (draft.createdAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _ago(draft.createdAt!),
                    style: const TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ],
            ),
            if (hasName || rawPhone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (hasName) name,
                        if (rawPhone.isNotEmpty) 'WA $rawPhone',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  if (!paid && rawPhone.isNotEmpty)
                    Tooltip(
                      message: waPhone == null
                          ? 'Nomor WA tidak valid'
                          : 'Chat WhatsApp pelanggan',
                      child: OutlinedButton.icon(
                        onPressed: waPhone == null
                            ? null
                            : () => _contactWa(waPhone),
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: const Text('Hubungi WA'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (pref != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: brandSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pref,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brandPrimary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final item in draft.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${item.qty}× ${item.productName}'
                  '${_modifierSuffix(item)}'
                  '${item.note == null || item.note!.isEmpty ? '' : ' · ${item.note}'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Subtotal pesanan',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                ),
                Text(
                  formatRupiah(draft.subtotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: brandPrimary,
                  ),
                ),
              ],
            ),
            const Text(
              'Total akhir = keranjang saat bayar (bisa bertambah).',
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: _actions(context, ref)),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    // Kunci seluruh tombol selama aksi draft ini masih berjalan (tap ganda).
    final busy = ref.watch(
      orderActionBusyProvider,
    ).contains(draft.draftId);
    switch (draft.status) {
      case 'PENDING':
        return [
          FilledButton(
            onPressed: busy ? null : () => _receive(context, ref),
            child: const Text('Diterima'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _run(
                    context,
                    ref,
                    () =>
                        ref.read(qrDraftRepositoryProvider).cancel(draft.draftId),
                    success: 'Pesanan dibatalkan.',
                  ),
            child: const Text('Batalkan'),
          ),
        ];
      case 'CLAIMED':
        return [
          FilledButton(
            onPressed: busy
                ? null
                : () => _run(
                    context,
                    ref,
                    () => ref
                        .read(qrDraftRepositoryProvider)
                        .markPreparing(draft.draftId),
                    success: 'Pesanan sedang diproses.',
                  ),
            child: const Text('Diproses'),
          ),
          FilledButton.tonal(
            onPressed: busy
                ? null
                : () => QrClaimService.payDraft(ref, context, draft),
            child: const Text('Bayar'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _run(
                    context,
                    ref,
                    () =>
                        ref.read(qrDraftRepositoryProvider).cancel(draft.draftId),
                    success: 'Pesanan dibatalkan.',
                  ),
            child: const Text('Batalkan'),
          ),
        ];
      case 'PREPARING':
        return [
          FilledButton(
            onPressed: busy
                ? null
                : () => _run(
                    context,
                    ref,
                    // Selesai BELUM bayar: sale_id null; id tetap di set
                    // perangkat sehingga checkout berikutnya melunasi
                    // (invarian C1.2).
                    () => ref
                        .read(qrDraftRepositoryProvider)
                        .complete(draft.draftId, null),
                    success: 'Pesanan selesai — menunggu pembayaran.',
                  ),
            child: const Text('Tandai selesai'),
          ),
          FilledButton.tonal(
            onPressed: busy
                ? null
                : () => QrClaimService.payDraft(ref, context, draft),
            child: const Text('Bayar'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _run(
                    context,
                    ref,
                    () =>
                        ref.read(qrDraftRepositoryProvider).cancel(draft.draftId),
                    success: 'Pesanan dibatalkan.',
                  ),
            child: const Text('Batalkan'),
          ),
        ];
      default: // COMPLETED + sale null — Selesai, belum bayar.
        return [
          FilledButton(
            onPressed: busy
                ? null
                : () => QrClaimService.payDraft(ref, context, draft),
            child: const Text('Bayar'),
          ),
        ];
    }
  }

  Future<void> _receive(BuildContext context, WidgetRef ref) async {
    final busy = ref.read(orderActionBusyProvider.notifier);
    if (busy.contains(draft.draftId)) return;
    busy.add(draft.draftId);
    try {
      final ok = await QrClaimService.claimDraft(ref, context, draft);
      if (ok) {
        ref.invalidate(qrDraftsProvider);
      }
    } finally {
      busy.remove(draft.draftId);
    }
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    required String success,
  }) async {
    final busy = ref.read(orderActionBusyProvider.notifier);
    if (busy.contains(draft.draftId)) return;
    busy.add(draft.draftId);
    try {
      await action();
      ref.invalidate(qrDraftsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    } finally {
      busy.remove(draft.draftId);
    }
  }

  void _contactWa(String phone) {
    final url = waMessageUrl(
      phone: phone,
      message: waBillMessage(
        name: draft.customerName,
        tableLabel: draft.tableLabel,
        refCode: draft.refCode,
      ),
    );
    // Gagal membuka WhatsApp bukan penghalang operasi (dilaporkan jujur).
    waLaunchHandler(url).catchError((Object _) {
      // Sengaja tanpa UI tambahan: tombol sudah menunjukkan niat operator.
    });
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: paid ? const Color(0xFFE6F4EC) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        paid ? 'SUDAH BAYAR' : 'BELUM BAYAR',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: paid ? successColor : warningColor,
        ),
      ),
    );
  }
}

/// Label preferensi bayar dari wizard web (sama dengan kartu §A3).
String? _preferenceLabel(QrDraft d) {
  final intent = switch (d.payIntent) {
    'PAY_NOW' => 'Bayar sekarang',
    'OPEN_BILL' => 'Buka bill',
    _ => null,
  };
  final method = switch (d.payMethod) {
    'CASH' => 'Tunai',
    'QRIS' => 'QRIS',
    'TRANSFER' => 'Transfer',
    _ => null,
  };
  if (intent == null) return method;
  return method == null ? intent : '$intent · $method';
}

String _modifierSuffix(QrDraftItem item) {
  final names = item.modifiers
      .map((m) => m['name'] as String? ?? '')
      .where((n) => n.isNotEmpty)
      .join('+');
  return names.isEmpty ? '' : ' · $names';
}

String _ago(DateTime createdAt) {
  final d = DateTime.now().toLocal().difference(createdAt.toLocal());
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}
