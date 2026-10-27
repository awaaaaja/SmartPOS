import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../operating_cost/operating_repository.dart';

/// S05-05: Kas Shift. Hanya penjualan TUNAI menambah uang fisik —
/// transfer/QRIS tercatat di laporan tapi tidak menambah kas diharapkan.
/// Selisih dihitung server saat menutup shift (actual − expected).
class CashShiftPage extends ConsumerWidget {
  const CashShiftPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(cashStatusProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(mapErrorToMessage(e), textAlign: TextAlign.center),
          ),
        ),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kas Shift', style: theme.textTheme.titleLarge),
                      Text(
                        'Uang tunai fisik kasir; non-tunai tidak dihitung.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(
                    s.isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                    size: 18,
                    color: s.isOpen ? successColor : warningColor,
                  ),
                  label: Text(s.isOpen ? 'Shift aktif' : 'Tidak ada shift'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!s.isOpen)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Buka Shift', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Hitung uang di laci sebelum mulai; ini menjadi kas '
                        'awal rekonsiliasi.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _openShift(context, ref),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Buka Shift Baru'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rekonsiliasi Kas',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _row(theme, 'Kas awal', s.openingCash),
                      _row(theme, 'Penjualan tunai net', s.cashSales),
                      const Divider(),
                      _row(theme, 'Kas diharapkan', s.expectedCash, bold: true),
                      const SizedBox(height: 4),
                      Text(
                        'Transfer/QRIS tidak menambah uang tunai fisik, '
                        'sehingga tidak ikut kas diharapkan.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _closeShift(context, ref, s),
                icon: const Icon(Icons.stop_circle_rounded),
                label: const Text('Hitung dan Tutup Kas'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, int amount, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: bold
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium,
            ),
            Text(
              formatRupiah(amount),
              style: bold
                  ? theme.textTheme.titleMedium?.copyWith(color: brandPrimary)
                  : theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );

  Future<void> _openShift(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: '100000');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kas Awal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Uang awal di laci (Rp)',
            prefixText: 'Rp ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Buka Shift'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final opening = int.tryParse(controller.text.trim()) ?? -1;
    if (opening < 0) return;
    try {
      await ref.read(operatingRepositoryProvider).openCashShift(opening);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Shift dibuka dengan kas awal '
              '${formatRupiah(opening)}.',
            ),
          ),
        );
      }
      ref.invalidate(cashStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _closeShift(
    BuildContext context,
    WidgetRef ref,
    CashShiftStatus s,
  ) async {
    final controller = TextEditingController(text: s.expectedCash.toString());
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hitung Uang Aktual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Kas diharapkan ${formatRupiah(s.expectedCash)}. '
              'Hitung fisik uang di laci.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Uang aktual dihitung (Rp)',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Catatan selisih (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Tutup Kas'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final actual = int.tryParse(controller.text.trim()) ?? -1;
    if (actual < 0) return;
    try {
      final result = await ref
          .read(operatingRepositoryProvider)
          .closeCashShift(actual, note.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kas ditutup. Selisih ${formatRupiah(result.variance)} '
              '(harap ${formatRupiah(result.expectedCash)}, fisik '
              '${formatRupiah(result.actualCash)}).',
            ),
          ),
        );
      }
      ref.invalidate(cashStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }
}
