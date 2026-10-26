import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class PurchasesPage extends StatelessWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Pembelian',
      icon: Icons.shopping_basket_rounded,
      description:
          'Pencatatan pembelian dan penerimaan bahan yang menambah stok tepat sekali. Dibangun pada Sprint 04.',
      targetSprint: 'Sprint 04 (pembelian)',
    );
  }
}
