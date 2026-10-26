import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class SalesHistoryPage extends StatelessWidget {
  const SalesHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Riwayat Penjualan',
      icon: Icons.receipt_long_rounded,
      description:
          'Riwayat penjualan final, struk snapshot, dan refund beralasan. Dibangun pada Sprint 02.',
      targetSprint: 'Sprint 02 (riwayat dan struk)',
    );
  }
}
