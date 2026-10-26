import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Empty state jujur untuk modul yang datanya belum diisi sprint berikutnya.
/// Tidak menampilkan angka atau fitur seolah sudah terkoneksi.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    required this.targetSprint,
  });

  final String title;
  final IconData icon;
  final String description;
  final String targetSprint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // LayoutBuilder+minHeight: kartu tetap terpusat bila cukup ruang,
    // dan bisa di-scroll di viewport pendek (landscape HP) tanpa overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: brandSoft,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(icon, size: 32, color: brandPrimary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Chip(
                          avatar: const Icon(Icons.hourglass_top_rounded,
                              size: 18),
                          label: Text(
                            'Menyusul: $targetSprint',
                            softWrap: true,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: brandSoft,
                          side: BorderSide.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
