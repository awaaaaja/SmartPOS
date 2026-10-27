import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../operating_cost/operating_repository.dart';
import '../pos/pos_repository.dart';

/// S02-09: ringkasan omzet dari transaksi final (net refund) via server.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: summary.when(
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
                onPressed: () => ref.invalidate(dashboardSummaryProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text('Dashboard',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Ringkasan penjualan dari basis data. Belum ada badge QR '
                'atau stok kritis (Sprint 03).',
                style: const TextStyle(color: textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCol = constraints.maxWidth >= 700;
                final cards = [
                  _StatCard(
                    title: 'Omzet hari ini',
                    value: formatRupiah(s.todayRevenue),
                    icon: Icons.today_rounded,
                    color: brandPrimary,
                    subtitle:
                        '${formatNumber(s.todayTransactions)} transaksi final',
                  ),
                  _StatCard(
                    title: 'Refund hari ini',
                    value: formatRupiah(s.todayRefunds),
                    icon: Icons.undo_rounded,
                    color: warningColor,
                  ),
                  _StatCard(
                    title: 'Omzet sepanjang waktu',
                    value: formatRupiah(s.allTimeRevenue),
                    icon: Icons.account_balance_rounded,
                    color: successColor,
                    subtitle:
                        '${formatNumber(s.allTimeTransactions)} transaksi final',
                  ),
                ];
                final detail = ref.watch(dashboardReportProvider);
                final detailCards = detail.maybeWhen(
                  data: (r) => <Widget>[
                    _StatCard(
                      title: 'Biaya bahan hari ini (HPP resep, estimasi)',
                      value: formatRupiah(r.hppIngredientCost),
                      icon: Icons.inventory_2_rounded,
                      color: warningColor,
                      subtitle: 'resep aktif × harga bahan terkini',
                    ),
                    _StatCard(
                      title: 'Biaya aktual hari ini',
                      value: formatRupiah(r.expensesActualPeriod),
                      icon: Icons.receipt_long_rounded,
                      color: successColor,
                      subtitle: 'tagihan nyata tercatat di Biaya Operasional',
                    ),
                    _StatCard(
                      title: 'Overhead estimasi hari ini',
                      value: formatRupiah(r.expensesEstimatedPeriod),
                      icon: Icons.lightbulb_outline_rounded,
                      color: warningColor,
                      subtitle: 'asumsi/listrik-LPG dari kalkulator, bukan tagihan',
                    ),
                    _StatCard(
                      title: 'Estimasi hasil operasi hari ini',
                      value: formatRupiah(r.operatingMarginEstimate),
                      icon: Icons.trending_up_rounded,
                      color: brandPrimary,
                      subtitle: 'net sales − biaya bahan − biaya aktual. '
                          'Bukan laba bersih: tenaga kerja, susut & pajak '
                          'belum lengkap.',
                    ),
                  ],
                  orElse: () => const <Widget>[],
                );
                final primaryRow = twoCol
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(child: cards[i]),
                          ],
                        ],
                      )
                    : Column(
                        children: [
                          for (final c in cards) ...[
                            c,
                            const SizedBox(height: 12),
                          ],
                        ],
                      );
                return Column(
                  children: [
                    primaryRow,
                    if (detailCards.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      if (twoCol)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < detailCards.length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(child: detailCards[i]),
                            ],
                          ],
                        )
                      else
                        Column(
                          children: [
                            for (final c in detailCards) ...[
                              c,
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 12, color: textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
