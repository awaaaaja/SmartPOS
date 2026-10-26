import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Stok Bahan',
      icon: Icons.inventory_2_rounded,
      description:
          'Master bahan, saldo stok, batas minimum, dan mutasi beralasan. Dibangun pada Sprint 04.',
      targetSprint: 'Sprint 04 (stok bahan)',
    );
  }
}
