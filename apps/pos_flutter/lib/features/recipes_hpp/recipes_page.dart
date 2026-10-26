import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class RecipesHppPage extends StatelessWidget {
  const RecipesHppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Resep & HPP',
      icon: Icons.menu_book_rounded,
      description:
          'Resep per menu, takaran, yield, dan perhitungan HPP per porsi. Dibangun pada Sprint 04.',
      targetSprint: 'Sprint 04 (resep dan HPP)',
    );
  }
}
