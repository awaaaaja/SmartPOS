import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Pengaturan',
      icon: Icons.settings_rounded,
      description:
          'Profil usaha, tarif pajak/layanan, preferensi perangkat, dan keluar sesi. Dibangun pada Sprint 02.',
      targetSprint: 'Sprint 02 (pengaturan usaha)',
    );
  }
}
