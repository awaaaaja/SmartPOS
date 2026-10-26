import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import 'tables_repository.dart';

/// Base URL web QR pelanggan (HTTPS), diisi saat build:
///   flutter build ... --dart-define=QR_WEB_URL=https://meja.contoh.id
const qrWebBaseUrl = String.fromEnvironment('QR_WEB_URL');

/// S03-01: Meja & QR. Daftar meja, buat/rotasi token (plaintext hanya
/// dikembalikan sekali oleh server), tampilkan QR menu pelanggan.
class TablesQrPage extends ConsumerWidget {
  const TablesQrPage({super.key});

  String? qrUrlFor(String token) {
    final base = qrWebBaseUrl.trim();
    if (base.isEmpty || !base.startsWith('https://')) return null;
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/?token=$token';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text('Meja & QR',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _createTable(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Meja baru'),
                ),
              ],
            ),
          ),
          if (qrWebBaseUrl.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'QR_WEB_URL belum diatur. Bangun aplikasi dengan '
                '--dart-define=QR_WEB_URL=https://… (web menu pelanggan '
                'HTTPS) agar QR menampilkan tautan yang benar.',
                style: TextStyle(color: errorColor, fontSize: 12),
              ),
            ),
          Expanded(
            child: tables.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(mapErrorToMessage(e)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(tablesListProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const Center(
                      child: Text('Belum ada meja. Tambahkan meja pertama.',
                          style: TextStyle(color: textSecondary)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _TableCard(
                        table: rows[i],
                        qrUrlFor: qrUrlFor,
                        onRotate: () => _rotate(context, ref, rows[i]),
                        onToggle: (v) => _toggle(ref, rows[i], v),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createTable(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Meja baru'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Label meja (mis. Meja 1)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    if (token == null || token.isEmpty || !context.mounted) return;
    try {
      final plaintext =
          await ref.read(tablesRepositoryProvider).createTable(token);
      ref.invalidate(tablesListProvider);
      if (context.mounted) {
        await _showTokenDialog(context, 'Meja dibuat', plaintext);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _rotate(
      BuildContext context, WidgetRef ref, DiningTableEntry table) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rotasi token ${table.label}?'),
        content: const Text(
            'QR lama berhenti berlaku seketika. Token baru hanya '
            'ditampilkan satu kali.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rotasi'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final plaintext = await ref
          .read(tablesRepositoryProvider)
          .rotateToken(table.id);
      ref.invalidate(tablesListProvider);
      if (context.mounted) {
        await _showTokenDialog(context, 'Token baru ${table.label}', plaintext);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _toggle(
      WidgetRef ref, DiningTableEntry table, bool enabled) async {
    try {
      await ref.read(tablesRepositoryProvider).setEnabled(table.id, enabled);
      ref.invalidate(tablesListProvider);
    } catch (e) {
      // pesan singkat; daftar tetap segar lewat invalidate
      debugPrint('setEnabled gagal: $e');
    }
  }

  /// Token plaintext tampil sekali + QR bila URL tersedia.
  Future<void> _showTokenDialog(
      BuildContext context, String title, String token) async {
    final url = qrUrlFor(token);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (url != null) ...[
                QrImageView(data: url, size: 200),
                const SizedBox(height: 12),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'QR_WEB_URL belum diatur — salin token di bawah dan '
                    'bagikan manual.',
                    style: TextStyle(fontSize: 12, color: errorColor),
                  ),
                ),
              SelectableText(token,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace')),
              if (url != null) ...[
                const SizedBox(height: 8),
                SelectableText(url,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: textSecondary)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url ?? token));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Disalin.')));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Salin'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.qrUrlFor,
    required this.onRotate,
    required this.onToggle,
  });

  final DiningTableEntry table;
  final String? Function(String token) qrUrlFor;
  final VoidCallback onRotate;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.table_restaurant_rounded, color: brandPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(table.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    'v${table.tokenVersion} · '
                    '${table.isEnabled ? 'QR aktif' : 'QR nonaktif'}',
                    style: const TextStyle(
                        fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: table.isEnabled,
              onChanged: onToggle,
              activeThumbColor: Colors.white,
            ),
            IconButton(
              tooltip: 'Rotasi token (QR lama mati)',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: onRotate,
            ),
          ],
        ),
      ),
    );
  }
}
