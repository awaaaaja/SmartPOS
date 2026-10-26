import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Biaya Operasional',
      icon: Icons.account_balance_wallet_rounded,
      description:
          'Pengeluaran operasional dengan penanda estimasi atau aktual, beserta bukti opsional. Dibangun pada Sprint 05.',
      targetSprint: 'Sprint 05 (biaya operasional)',
    );
  }
}
