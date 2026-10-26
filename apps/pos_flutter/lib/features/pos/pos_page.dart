import 'package:flutter/material.dart';

import '../../core/widgets/module_placeholder.dart';

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Kasir POS',
      icon: Icons.point_of_sale_rounded,
      description:
          'Layar kasir: katalog menu, keranjang aktif, panel QR Masuk, dan pembayaran. Dibangun pada Sprint 02 setelah katalog tersedia.',
      targetSprint: 'Sprint 02 (POS dan checkout)',
    );
  }
}
