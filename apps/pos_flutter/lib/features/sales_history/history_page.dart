import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../../core/models/sale_models.dart';
import '../pos/pos_repository.dart';

/// S02-08: riwayat penjualan final + struk snapshot + refund beralasan.
class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesListProvider(_search));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Riwayat Penjualan',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cari no. struk...',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sales.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 40, color: warningColor),
                    const SizedBox(height: 12),
                    Text(mapErrorToMessage(e), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(salesListProvider(_search)),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? const Center(
                      child: Text('Belum ada transaksi.',
                          style: TextStyle(color: textSecondary)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _SaleTile(sale: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});

  final SaleSummary sale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: sale.status == 'REFUNDED'
              ? const Color(0xFFFBE9E7)
              : brandSoft,
          child: Icon(
            sale.status == 'REFUNDED'
                ? Icons.undo_rounded
                : Icons.receipt_long_rounded,
            color: sale.status == 'REFUNDED' ? errorColor : brandPrimary,
          ),
        ),
        title: Text(sale.receiptNo,
            style:
                const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${formatWib(sale.createdAt)} · ${_methodLabel(sale.method)}'
          '${sale.refundAmount > 0 ? ' · refund ${formatRupiah(sale.refundAmount)}' : ''}',
          style: const TextStyle(fontSize: 12, color: textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatRupiah(sale.total - sale.refundAmount),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                _statusChip(),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Lihat struk & refund',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _openDetail(context, sale),
            ),
          ],
        ),
        onTap: () => _openDetail(context, sale),
      ),
    );
  }

  Widget _statusChip() {
    final (label, color) = switch (sale.status) {
      'REFUNDED' => ('Refund penuh', errorColor),
      'PARTIALLY_REFUNDED' => ('Refund sebagian', warningColor),
      _ => ('Final', successColor),
    };
    return Text(label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600));
  }

  static String _methodLabel(String? method) => switch (method) {
        'CASH' => 'Tunai',
        'TRANSFER' => 'Transfer',
        'QRIS' => 'QRIS',
        _ => '-',
      };

  static void _openDetail(BuildContext context, SaleSummary sale) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SaleDetailSheet(saleId: sale.id),
    );
  }
}

class _SaleDetailSheet extends ConsumerStatefulWidget {
  const _SaleDetailSheet({required this.saleId});

  final int saleId;

  @override
  ConsumerState<_SaleDetailSheet> createState() => _SaleDetailSheetState();
}

class _SaleDetailSheetState extends ConsumerState<_SaleDetailSheet> {
  late final Future<Receipt> _receipt;

  @override
  void initState() {
    super.initState();
    _receipt =
        ref.read(posRepositoryProvider).saleReceipt(widget.saleId);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: FutureBuilder<Receipt>(
          future: _receipt,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return SizedBox(
                height: 240,
                child: Center(child: Text(mapErrorToMessage(snap.error!))),
              );
            }
            final receipt = snap.data!;
            return _ReceiptBody(receipt: receipt);
          },
        ),
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRefund = receipt.status != 'REFUNDED';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(receipt.receiptNo,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(formatWib(receipt.createdAt),
                style: const TextStyle(fontSize: 12, color: textSecondary)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Total ${formatRupiah(receipt.total - receipt.refundAmount)}'
            '${receipt.refundAmount > 0 ? ' (sebelumnya ${formatRupiah(receipt.total)})' : ''}',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: brandPrimary)),
        const Divider(height: 20),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in receipt.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${item.qty}× ${item.productName} @${formatRupiah(item.unitPrice)}'),
                              if (item.modifiers.isNotEmpty)
                                Text(
                                  item.modifiers
                                      .map((m) =>
                                          '${m['name']} (+${formatRupiah((m['price_delta'] as int?) ?? 0)})')
                                      .join(', '),
                                  style: const TextStyle(
                                      fontSize: 11, color: textSecondary),
                                ),
                              if (item.note != null &&
                                  item.note!.isNotEmpty)
                                Text('Catatan: ${item.note}',
                                    style: const TextStyle(
                                        fontSize: 11, color: textSecondary)),
                            ],
                          ),
                        ),
                        Text(formatRupiah(item.lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                _row('Subtotal', formatRupiah(receipt.subtotal)),
                if (receipt.discountAmount > 0)
                  _row('Diskon', '-${formatRupiah(receipt.discountAmount)}'),
                if (receipt.taxAmount > 0)
                  _row('Pajak', formatRupiah(receipt.taxAmount)),
                if (receipt.serviceAmount > 0)
                  _row('Biaya layanan', formatRupiah(receipt.serviceAmount)),
                _row('Metode', receipt.method ?? '-'),
                if (receipt.paid != null)
                  _row('Diterima', formatRupiah(receipt.paid!)),
                if (receipt.changeAmount != null)
                  _row('Kembalian', formatRupiah(receipt.changeAmount!)),
                if (receipt.refunds.isNotEmpty) ...[
                  const Divider(height: 20),
                  Text('Riwayat refund',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final r in receipt.refunds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _row(
                        formatRupiah((r['amount'] as int?) ?? 0),
                        '${r['reason'] ?? ''}',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (canRefund) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Proses Refund'),
              onPressed: () => _openRefund(context, receipt),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: textSecondary))),
            Text(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );

  static Future<void> _openRefund(
      BuildContext context, Receipt receipt) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _RefundDialog(receipt: receipt),
    );
    if (result == true && context.mounted) {
      Navigator.pop(context); // tutup sheet detail, muat ulang dari caller
    }
  }
}

class _RefundDialog extends ConsumerStatefulWidget {
  const _RefundDialog({required this.receipt});

  final Receipt receipt;

  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  int get _maxRefund =>
      widget.receipt.total - widget.receipt.refundAmount;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refund Transaksi'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Struk ${widget.receipt.receiptNo}. Sisa yang boleh '
              'direfund: ${formatRupiah(_maxRefund)}.',
              style: const TextStyle(fontSize: 13, color: textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Nominal refund (Rp)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                  labelText: 'Alasan refund (wajib)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style:
                      const TextStyle(color: errorColor, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Simpan Refund'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amount.text.trim());
    final reason = _reason.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Nominal harus angka > 0.');
      return;
    }
    if (amount > _maxRefund) {
      setState(() => _error =
          'Melebihi sisa refund (${formatRupiah(_maxRefund)}).');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'Alasan minimal 3 karakter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(posRepositoryProvider)
          .refund(widget.receipt.saleId, amount, reason);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(salesListProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = mapErrorToMessage(e);
        });
      }
    }
  }
}

/// Daftar sale untuk riwayat; key = kata kunci pencarian.
final salesListProvider = FutureProvider.autoDispose
    .family<List<SaleSummary>, String>(
  (ref, search) =>
      ref.watch(posRepositoryProvider).fetchSales(search: search),
);
