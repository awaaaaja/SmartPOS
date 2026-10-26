import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class TablesQrPage extends StatelessWidget {
  const TablesQrPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Meja & QR',
      icon: Icons.qr_code_2_rounded,
      description:
          'Daftar meja, token QR yang dapat dirotasi, dan tautan menu pelanggan. Dibangun pada Sprint 03.',
      targetSprint: 'Sprint 03 (meja dan QR)',
    );
  }
}
