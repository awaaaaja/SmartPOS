import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class CashShiftPage extends StatelessWidget {
  const CashShiftPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Kas Shift',
      icon: Icons.payments_rounded,
      description:
          'Buka dan tutup shift, kas awal, uang fisik, serta selisih kas tunai. Dibangun pada Sprint 05.',
      targetSprint: 'Sprint 05 (kas shift)',
    );
  }
}
