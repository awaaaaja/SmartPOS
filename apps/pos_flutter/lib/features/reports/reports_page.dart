import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/csv_export.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../operating_cost/operating_repository.dart';

/// Bangun isi CSV laporan (S05-08): angka memakai integer Rupiah polos
/// (tanpa titik) agar makna tidak berubah saat dibuka di lembar kerja.
String buildReportCsv(ReportSummary r) {
  final b = StringBuffer()
    ..writeln('Bagian,Kunci,Nilai')
    ..writeln('Periode,Dari,${r.from.toIso8601String().split('T').first}')
    ..writeln('Periode,Sampai,${r.to.toIso8601String().split('T').first}')
    ..writeln('Penjualan,Net sales,${r.netSales}')
    ..writeln('Penjualan,Refund,${r.refunds}')
    ..writeln('Penjualan,Transaksi,${r.transactions}')
    ..writeln('Biaya,Biaya bahan (HPP resep) estimasi,${r.hppIngredientCost}')
    ..writeln('Biaya,Aktual periode,${r.expensesActualPeriod}')
    ..writeln('Biaya,Estimasi periode,${r.expensesEstimatedPeriod}')
    ..writeln('Biaya,Ter alokasi,${r.allocatedTotal}')
    ..writeln()
    ..writeln('Tren,Tanggal,Omzet,Transaksi');
  for (final t in r.trend) {
    b.writeln('Tren,${t.day},${t.revenue},${t.tx}');
  }
  b
    ..writeln()
    ..writeln('Menu terlaris,Menu,Qty,Omzet');
  for (final p in r.topProducts) {
    b.writeln('Menu terlaris,"${p.name.replaceAll('"', '""')}",${p.qty},${p.revenue}');
  }
  b
    ..writeln()
    ..writeln('Biaya per kategori,Jenis,Aktual,Estimasi');
  for (final e in r.expensesByType) {
    b.writeln('Biaya per kategori,${e.type},${e.actualAmount},'
        '${e.estimatedAmount}');
  }
  return b.toString();
}

/// S05-07: laporan deskriptif — statistik, BUKAN forecast. Nilai berasal
/// langsung dari server (pos_reports); refund mengurangi net sales.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(reportProvider);
    await ref.read(reportProvider.future);
  }

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: ref.read(reportRangeProvider).from ??
          now.subtract(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (from == null || !context.mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: from,
      lastDate: DateTime(2100),
    );
    if (to == null) return;
    ref.read(reportRangeProvider.notifier).state =
        ReportRange(from: from, to: to);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(reportProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Laporan', style: theme.textTheme.titleLarge),
                      Text(
                        'Statistik deskriptif dari data tersimpan — bukan '
                        'proyeksi laba bersih.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickRange(context, ref),
                  icon: const Icon(Icons.date_range_rounded),
                  label: const Text('Filter Tanggal'),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Muat ulang',
                  onPressed: () => _refresh(ref),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(mapErrorToMessage(e),
                      textAlign: TextAlign.center),
                ),
              ),
              data: (r) => RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(
                      'Periode ${formatWibDate(r.from.toUtc())} – '
                      '${formatWibDate(r.to.toUtc())}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    _statsGrid(theme, r),
                    const SizedBox(height: 12),
                    _card(
                      theme,
                      title: 'Tren omzet harian',
                      child: r.trend.isEmpty
                          ? Text('Belum ada transaksi pada periode ini.',
                              style: theme.textTheme.bodySmall)
                          : Column(
                              children: [
                                for (final t in r.trend)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 3),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                            width: 84,
                                            child: Text(t.day,
                                                style: theme
                                                    .textTheme.bodySmall)),
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            child: LinearProgressIndicator(
                                              value: r.trend
                                                          .map((e) => e.revenue)
                                                          .reduce(
                                                              (a, b) => a > b
                                                                  ? a
                                                                  : b) ==
                                                      0
                                                  ? 0
                                                  : t.revenue /
                                                      r.trend
                                                          .map((e) => e.revenue)
                                                          .reduce((a, b) =>
                                                              a > b ? a : b),
                                              minHeight: 10,
                                              backgroundColor:
                                                  brandPrimary.withValues(
                                                      alpha: 0.10),
                                              color: brandPrimary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            formatRupiah(t.revenue),
                                            textAlign: TextAlign.right,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      theme,
                      title: 'Menu terlaris',
                      child: r.topProducts.isEmpty
                          ? Text('Belum ada menu terjual pada periode ini.',
                              style: theme.textTheme.bodySmall)
                          : Column(
                              children: [
                                for (final p in r.topProducts)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.restaurant_rounded,
                                        size: 20),
                                    title: Text(p.name),
                                    subtitle:
                                        Text('${formatNumber(p.qty)} porsi'),
                                    trailing: Text(formatRupiah(p.revenue),
                                        style:
                                            theme.textTheme.titleSmall),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      theme,
                      title: 'Biaya per kategori',
                      child: r.expensesByType.isEmpty
                          ? Text('Belum ada biaya operasional.',
                              style: theme.textTheme.bodySmall)
                          : Column(
                              children: [
                                for (final e in r.expensesByType)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 3),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(e.type)),
                                        Text(
                                            'Aktual ${formatRupiah(e.actualAmount)}',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                                    color: successColor)),
                                        const SizedBox(width: 10),
                                        Text(
                                            'Est ${formatRupiah(e.estimatedAmount)}',
                                            style: theme
                                                .textTheme.bodySmall
                                                ?.copyWith(
                                                    color: warningColor)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _card(
                      theme,
                      title: 'Catatan jujur',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• Biaya bahan (HPP) di atas adalah estimasi dari '
                            'resep aktif × harga bahan terkini, bukan mutasi '
                            'persis.\n'
                            '• Biaya ESTIMASI berasal dari asumsi/kalkulator; '
                            'hanya AKTUAL yang mewakili tagihan nyata.\n'
                            '• Angka belum termasuk tenaga kerja, susut, dan '
                            'pajak — ini bukan pernyataan laba bersih.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              try {
                                await saveCsvFile(
                                    'laporan-pos-${r.to.toIso8601String().split('T').first}.csv',
                                    buildReportCsv(r));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'CSV laporan berhasil diekspor.')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text(mapErrorToMessage(e))));
                                }
                              }
                            },
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Ekspor CSV'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(ThemeData theme, ReportSummary r) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.1,
        children: [
          _stat(theme, 'Net sales', formatRupiah(r.netSales), brandPrimary),
          _stat(theme, 'Refund', formatRupiah(r.refunds), warningColor),
          _stat(theme, 'Transaksi', formatNumber(r.transactions), brandPrimary),
          _stat(theme, 'Biaya bahan (estimasi)',
              formatRupiah(r.hppIngredientCost), warningColor),
          _stat(theme, 'Biaya aktual periode',
              formatRupiah(r.expensesActualPeriod), successColor),
          _stat(theme, 'Biaya estimasi periode',
              formatRupiah(r.expensesEstimatedPeriod), warningColor),
          _stat(theme, 'Ter alokasi', formatRupiah(r.allocatedTotal), brandPrimary),
          _stat(
              theme,
              'Selisih setelah HPP & biaya aktual*',
              formatRupiah(r.operatingMarginEstimate),
              brandPrimary),
        ],
      );

  Widget _stat(ThemeData theme, String label, String value, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                      overflow: TextOverflow.ellipsis),
                  maxLines: 2),
              const SizedBox(height: 2),
              Text(value,
                  style: theme.textTheme.titleMedium?.copyWith(color: color)),
            ],
          ),
        ),
      );

  Widget _card(ThemeData theme,
          {required String title, required Widget child}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
}
