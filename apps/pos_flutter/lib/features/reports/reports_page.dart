import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Laporan',
      icon: Icons.bar_chart_rounded,
      description:
          'Laporan historis: pendapatan, menu terlaris, biaya per kategori. Hanya data aktual, tanpa prediksi. Dibangun pada Sprint 05.',
      targetSprint: 'Sprint 05 (laporan)',
    );
  }
}
