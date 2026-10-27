import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error_mapper.dart';
import '../auth/auth_repository.dart';

final businessSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref
          .watch(supabaseClientProvider)
          .from('business_settings')
          .select('name,address,timezone,tax_rate,service_rate')
          .eq('id', 1)
          .single(),
    );

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(businessSettingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mapErrorToMessage(error), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(businessSettingsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
          data: (settings) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Pengaturan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final entry in {
                'Nama usaha': settings['name'],
                'Alamat': settings['address'] ?? 'Belum diisi',
                'Zona waktu': settings['timezone'],
                'Pajak':
                    '${((settings['tax_rate'] as num) * 100).toStringAsFixed(2)}%',
                'Biaya layanan':
                    '${((settings['service_rate'] as num) * 100).toStringAsFixed(2)}%',
              }.entries)
                ListTile(
                  title: Text(entry.key),
                  subtitle: Text('${entry.value}'),
                ),
              const SizedBox(height: 12),
              const Text(
                'Konfigurasi saat ini dibaca dari Supabase. Perubahan profil '
                'dan tarif dilakukan oleh pengelola database sesuai panduan setup; '
                'preferensi printer dan mode offline belum tersedia.',
              ),
            ],
          ),
        );
  }
}
