import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error_mapper.dart';
import 'settings_repository.dart';

final businessSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>(
      (ref) => ref.watch(settingsRepositoryProvider).fetch(),
    );

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> settings,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SettingsEditDialog(initial: settings),
    );
    if (saved != true) return;
    ref.invalidate(businessSettingsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan usaha tersimpan.')),
      );
    }
  }

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pengaturan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openEdit(context, ref, settings),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit pengaturan'),
                  ),
                ],
              ),
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
                'Profil usaha, zona waktu, dan tarif pajak/biaya layanan bisa '
                'diubah lewat tombol Edit; perubahan divalidasi di server dan '
                'tercatat di riwayat audit. Preferensi printer dan mode '
                'offline belum tersedia.',
              ),
            ],
          ),
        );
  }
}

/// Form edit pengaturan usaha. Angka persen dikirim sebagai fraksi ke RPC
/// settings_save; validasi ringan di klien, keputusan akhir di server.
class _SettingsEditDialog extends ConsumerStatefulWidget {
  const _SettingsEditDialog({required this.initial});

  final Map<String, dynamic> initial;

  @override
  ConsumerState<_SettingsEditDialog> createState() =>
      _SettingsEditDialogState();
}

class _SettingsEditDialogState extends ConsumerState<_SettingsEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _timezone;
  late final TextEditingController _tax;
  late final TextEditingController _service;
  bool _saving = false;

  /// 0.075 -> '7.5'; 0 -> '0'; 0.105 -> '10.5'.
  static String _percentText(num rate) =>
      (rate * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  static double? _parsePercent(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _name = TextEditingController(text: '${s['name'] ?? ''}');
    _address = TextEditingController(text: '${s['address'] ?? ''}');
    _timezone = TextEditingController(text: '${s['timezone'] ?? ''}');
    _tax = TextEditingController(
      text: _percentText((s['tax_rate'] as num?) ?? 0),
    );
    _service = TextEditingController(
      text: _percentText((s['service_rate'] as num?) ?? 0),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _timezone.dispose();
    _tax.dispose();
    _service.dispose();
    super.dispose();
  }

  String? _percentValidator(String? value) {
    final n = _parsePercent(value ?? '');
    if (n == null || n < 0 || n > 100) return 'Persen antara 0 sampai 100';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final address = _address.text.trim();
    try {
      await ref
          .read(settingsRepositoryProvider)
          .save(
            name: _name.text.trim(),
            address: address.isEmpty ? null : address,
            timezone: _timezone.text.trim(),
            taxRate: _parsePercent(_tax.text)! / 100,
            serviceRate: _parsePercent(_service.text)! / 100,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit pengaturan usaha'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama usaha'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 2) return 'Nama wajib diisi (min. 2 huruf)';
                    if (t.length > 80) return 'Maksimal 80 huruf';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Alamat',
                    helperText: 'Boleh dikosongkan; maksimal 200 huruf',
                  ),
                  maxLines: 2,
                  validator: (v) => (v ?? '').trim().length > 200
                      ? 'Maksimal 200 huruf'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timezone,
                  decoration: const InputDecoration(
                    labelText: 'Zona waktu',
                    helperText: 'Contoh: Asia/Jakarta, Asia/Makassar',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Zona waktu wajib diisi';
                    if (t.length > 64) return 'Maksimal 64 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _tax,
                        decoration: const InputDecoration(
                          labelText: 'Pajak (%)',
                          helperText: '0-100',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _percentValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _service,
                        decoration: const InputDecoration(
                          labelText: 'Biaya layanan (%)',
                          helperText: '0-100',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _percentValidator,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('Simpan'),
        ),
      ],
    );
  }
}
