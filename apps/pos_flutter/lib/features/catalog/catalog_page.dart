import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Menu & Harga',
      icon: Icons.restaurant_menu_rounded,
      description:
          'CRUD menu, kategori, foto, harga, varian, topping, dan status tersedia. Dibangun pada Sprint 02.',
      targetSprint: 'Sprint 02 (katalog dan harga)',
    );
  }
}
