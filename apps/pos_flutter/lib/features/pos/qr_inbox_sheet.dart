import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../tables_qr/tables_repository.dart';

/// Label preferensi bayar dari wizard web untuk ditampilkan di kartu draft.
/// Null bila pelanggan tidak memilih (draft lama / skip langkah bayar).
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

/// S03: Panel "QR Masuk" di dalam layar POS — daftar draft PENDING dari
/// pelanggan + ambil-ke-keranjang / batalkan. Draft BUKAN sale.
class QrInboxSheet extends ConsumerWidget {
  const QrInboxSheet({super.key, required this.onClaim});

  final Future<void> Function(QrDraft draft) onClaim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(qrDraftsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Text('QR Masuk',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Muat ulang',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(qrDraftsProvider),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: drafts.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(mapErrorToMessage(e),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(qrDraftsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            ),
            data: (rows) => rows.isEmpty
                ? const Center(
                    child: Text(
                        'Belum ada pesanan QR menunggu.\n'
                        'Pelanggan mengirim dari QR meja; draft muncul di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textSecondary)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final d = rows[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${d.tableLabel} · ${d.refCode}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(formatRupiah(d.subtotal),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: brandPrimary)),
                                ],
                              ),
                              if (_preferenceLabel(d) != null ||
                                  d.customerName != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (_preferenceLabel(d) != null)
                                      _preferenceLabel(d)!,
                                    if (d.customerName?.isNotEmpty == true)
                                      d.customerName!,
                                    if (d.customerPhone?.isNotEmpty == true)
                                      'WA ${d.customerPhone}',
                                  ].join(' · '),
                                  style: const TextStyle(
                                      fontSize: 12, color: textSecondary),
                                ),
                              ],
                              const SizedBox(height: 4),
                              for (final it in d.items)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '${it.qty}× ${it.productName}'
                                    '${it.modifiers.isNotEmpty ? ' (${it.modifiers.map((m) => m['name']).join(', ')})' : ''}'
                                    '${it.note?.isNotEmpty == true ? ' · ${it.note}' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(qrDraftRepositoryProvider)
                                            .cancel(d.draftId);
                                        ref.invalidate(qrDraftsProvider);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      mapErrorToMessage(
                                                          e))));
                                        }
                                      }
                                    },
                                    child: const Text('Batalkan'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: () async {
                                      await onClaim(d);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                    icon: const Icon(
                                        Icons.shopping_cart_rounded,
                                        size: 18),
                                    label: const Text('Ambil ke keranjang'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
