import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Dashboard',
      icon: Icons.dashboard_rounded,
      description:
          'Omzet dari transaksi final, jumlah lunas, QR masuk, dan stok kritis akan tampil di sini langsung dari basis data. Belum ada data yang diambil.',
      targetSprint: 'Sprint 02 (omzet transaksi) dan Sprint 03 (badge QR)',
    );
  }
}
