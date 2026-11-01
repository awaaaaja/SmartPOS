import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/png_share.dart';
import 'tables_repository.dart';

/// Base URL web QR pelanggan (HTTPS), diisi saat build:
///   flutter build ... --dart-define=QR_WEB_URL=https://meja.contoh.id
const qrWebBaseUrl = String.fromEnvironment('QR_WEB_URL');

/// Nilai default = `qrWebBaseUrl` (dart-define saat build); di-override pada
/// unit test agar tautan QR dapat diverifikasi tanpa environment build.
final qrWebBaseUrlProvider = Provider<String>((_) => qrWebBaseUrl);

/// Susun tautan QR meja; null bila base kosong atau bukan HTTPS.
String? buildQrUrl(String base, String token) {
  final trimmed = base.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('https://')) return null;
  final withoutSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  return '$withoutSlash/?token=$token';
}

/// S03-01: Meja & QR. Daftar meja, buat/rotasi token (plaintext hanya
/// dikembalikan sekali oleh server), tampilkan QR menu pelanggan.
class TablesQrPage extends ConsumerWidget {
  const TablesQrPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesListProvider);
    final base = ref.watch(qrWebBaseUrlProvider);
    // Token tersimpan lokal per meja → QR tampil langsung di kartu dan bisa
    // dicetak ulang; meja tanpa token (mis. pindah perangkat) minta rotasi.
    final tokens =
        ref.watch(tableTokensProvider).value ?? const <int, String>{};

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Meja & QR',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                FilledButton.icon(
                  onPressed: () => _createTable(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Meja baru'),
                ),
              ],
            ),
          ),
          if (base.trim().isEmpty)
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
                      child: Text(
                        'Belum ada meja. Tambahkan meja pertama.',
                        style: TextStyle(color: textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final table = rows[i];
                        final token = tokens[table.id];
                        final url = token == null
                            ? null
                            : buildQrUrl(base, token);
                        return _TableCard(
                          table: table,
                          url: url,
                          onOpenQr: () => _showQrDialog(context, table, url!),
                          onRotate: () => _rotate(context, ref, table),
                          onToggle: (v) => _toggle(ref, table, v),
                          onDelete: () => _delete(context, ref, table),
                        );
                      },
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
            labelText: 'Label meja (mis. Meja 1)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    if (token == null || token.isEmpty || !context.mounted) return;
    try {
      final (tableId, plaintext) = await ref
          .read(tablesRepositoryProvider)
          .createTable(token);
      // Simpan lokal: server hanya mengembalikan plaintext sekali ini.
      await ref.read(tableTokenStoreProvider).save(tableId, plaintext);
      ref.invalidate(tableTokensProvider);
      ref.invalidate(tablesListProvider);
      if (context.mounted) {
        await _showTokenDialog(
          context,
          'Meja dibuat',
          plaintext,
          ref.read(qrWebBaseUrlProvider),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _rotate(
    BuildContext context,
    WidgetRef ref,
    DiningTableEntry table,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rotasi token ${table.label}?'),
        content: const Text(
          'QR lama berhenti berlaku seketika. Token baru hanya '
          'ditampilkan satu kali.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
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
      // Versi baru menimpa token lama di penyimpanan lokal.
      await ref.read(tableTokenStoreProvider).save(table.id, plaintext);
      ref.invalidate(tableTokensProvider);
      ref.invalidate(tablesListProvider);
      if (context.mounted) {
        await _showTokenDialog(
          context,
          'Token baru ${table.label}',
          plaintext,
          ref.read(qrWebBaseUrlProvider),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _toggle(
    WidgetRef ref,
    DiningTableEntry table,
    bool enabled,
  ) async {
    try {
      await ref.read(tablesRepositoryProvider).setEnabled(table.id, enabled);
      ref.invalidate(tablesListProvider);
    } catch (e) {
      // pesan singkat; daftar tetap segar lewat invalidate
      debugPrint('setEnabled gagal: $e');
    }
  }

  /// Hapus meja (migrasi 0021): konfirmasi tegas → server memblokir bila
  /// masih ada pesanan aktif; draft terminal ikut terhapus, riwayat
  /// penjualan tetap (hanya tautan meja dilepas). Token lokal dibuang.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    DiningTableEntry table,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${table.label}?'),
        content: const Text(
          'QR meja ini langsung tidak berlaku. Draft pesanan yang sudah '
          'selesai/kedaluwarsa ikut terhapus.\n\n'
          'Riwayat penjualan TIDAK dihapus — uang dan struk tetap aman, '
          'hanya tautan meja yang dilepas.\n\n'
          'Meja dengan pesanan masih aktif tidak bisa dihapus '
          '(selesaikan dulu di tab Pesanan).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus meja'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final result = await ref
          .read(tablesRepositoryProvider)
          .deleteTable(table.id);
      // Buang token lokal + segarkan daftar & token.
      await ref.read(tableTokenStoreProvider).remove(table.id);
      ref.invalidate(tableTokensProvider);
      ref.invalidate(tablesListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Meja ${table.label} dihapus — ${result.draftsRemoved} draft '
              'ikut terhapus, ${result.salesDetached} penjualan tetap '
              'tersimpan tanpa tautan meja.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  /// Token plaintext tampil sekali + QR bila URL tersedia.
  Future<void> _showTokenDialog(
    BuildContext context,
    String title,
    String token,
    String base,
  ) async {
    final url = buildQrUrl(base, token);
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
                    'QR_WEB_URL belum diatur. Salin token di bawah dan '
                    'bagikan manual.',
                    style: TextStyle(fontSize: 12, color: errorColor),
                  ),
                ),
              SelectableText(
                token,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              if (url != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  url,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url ?? token));
              if (ctx.mounted) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('Disalin.')));
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

  /// QR besar siap cetak: tampil di kartu meja, dibuka untuk dilihat/dicetak.
  /// 'Cetak / Bagikan' menangkap QR menjadi PNG lalu membuka lembar berbagi
  /// Android — dari sana operator memilih printer yang terhubung.
  Future<void> _showQrDialog(
    BuildContext context,
    DiningTableEntry table,
    String url,
  ) async {
    final boundaryKey = GlobalKey();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QR ${table.label}'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: boundaryKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(data: url, size: 240),
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Tautan disalin.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Salin tautan'),
          ),
          FilledButton.icon(
            onPressed: () => _shareQrPng(ctx, boundaryKey, table),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('Cetak / Bagikan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareQrPng(
    BuildContext ctx,
    GlobalKey boundaryKey,
    DiningTableEntry table,
  ) async {
    final bytes = await qrPngCapture(boundaryKey);
    if (bytes == null) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(const SnackBar(content: Text('QR gagal ditangkap.')));
      }
      return;
    }
    final label = table.label.replaceAll(RegExp(r'[^\w-]+'), '-');
    final ok = await sharePngFile('qr-$label.png', bytes);
    if (ctx.mounted && !ok) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Lembar berbagi tidak tersedia.')),
      );
    }
  }
}

/// Tangkapan QR → PNG (3× densitas → tajam untuk cetak). Terpisah agar bisa
/// dipancang di unit test; capture asli membutuhkan rasterisasi nyata —
/// diverifikasi di device, bukan di widget test yang fake-async.
Future<Uint8List?> Function(GlobalKey key) qrPngCapture = _captureQrPng;

Future<Uint8List?> _captureQrPng(GlobalKey key) async {
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 3);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.url,
    required this.onOpenQr,
    required this.onRotate,
    required this.onToggle,
    required this.onDelete,
  });

  final DiningTableEntry table;

  /// QR siap tampilkan/cetak; null bila token belum tersedia di perangkat ini.
  final String? url;
  final VoidCallback onOpenQr;
  final VoidCallback onRotate;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

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
                  Text(
                    table.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'v${table.tokenVersion} · '
                    '${table.isEnabled ? 'QR aktif' : 'QR nonaktif'}',
                    style: const TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ),
            if (url != null)
              // QR tampil langsung di kartu — tap untuk lihat besar & cetak.
              Tooltip(
                message: 'Ketuk untuk lihat besar dan cetak',
                child: InkWell(
                  key: ValueKey('table-qr-${table.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: onOpenQr,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: QrImageView(data: url!, size: 76),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'QR belum ada\ndi perangkat ini',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
            const SizedBox(width: 8),
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
            IconButton(
              key: ValueKey('table-delete-${table.id}'),
              tooltip: 'Hapus meja',
              icon: const Icon(Icons.delete_outline_rounded),
              color: errorColor,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
