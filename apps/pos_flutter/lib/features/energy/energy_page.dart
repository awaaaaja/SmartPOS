import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class EnergyPage extends StatelessWidget {
  const EnergyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Kalkulator Energi',
      icon: Icons.bolt_rounded,
      description:
          'Kalkulator listrik dan LPG: watt, durasi, faktor beban, tarif, dan biaya per porsi. Dibangun pada Sprint 05.',
      targetSprint: 'Sprint 05 (kalkulator energi)',
    );
  }
}
