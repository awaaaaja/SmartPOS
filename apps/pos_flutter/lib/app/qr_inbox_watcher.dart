import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notif_sound.dart';
import '../features/tables_qr/tables_repository.dart';
import 'destinations.dart';
import 'theme.dart';

/// Pemantau draft QR dari shell (§B1): polling 10 detik satu-satunya di
/// seluruh aplikasi (pindah dari PosPage) + deteksi pesanan PENDING baru
/// -> banner in-app + nada (bila aktif di Pengaturan).
///
/// Muat pertama = baseline (sunyi) supaya draft lama yang masih menunggu
/// tidak diumumkan ulang tiap aplikasi dibuka; deteksi in-memori (restart =
/// baseline baru). Status selain PENDING tidak memicu apa pun.
class QrInboxWatcher extends ConsumerStatefulWidget {
  const QrInboxWatcher({super.key});

  @override
  ConsumerState<QrInboxWatcher> createState() => _QrInboxWatcherState();
}

class _QrInboxWatcherState extends ConsumerState<QrInboxWatcher> {
  Timer? _timer;

  /// Id draft yang sudah dikenal (baseline + yang sudah diumumkan).
  final Set<int> _knownIds = {};
  bool _baselineLoaded = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => ref.invalidate(qrDraftsProvider),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(qrDraftsProvider, (previous, next) {
      final rows = next.value;
      if (rows == null) return; // masih loading / error — tunggu data.
      if (!_baselineLoaded) {
        _baselineLoaded = true;
        _knownIds.addAll(rows.map((d) => d.draftId));
        return;
      }
      final fresh = rows
          .where((d) => d.status == 'PENDING' && !_knownIds.contains(d.draftId))
          .toList();
      _knownIds
        ..clear()
        ..addAll(rows.map((d) => d.draftId));
      for (final draft in fresh) {
        _announce(draft);
      }
    });
    // Widget tanpa tampilan; hanya memegang listener + timer polling.
    return const SizedBox.shrink();
  }

  void _announce(QrDraft draft) {
    Future(() async {
      try {
        final prefs = NotifSoundPrefs();
        if (await prefs.enabled) {
          await notifSoundPlayer(await prefs.tone, await prefs.volume);
        }
      } catch (_) {
        // Preferensi tidak terbaca (platform tanpa SharedPreferences):
        // lanjut tanpa bunyi; banner tetap ditampilkan terpisah.
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: brandPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pesanan baru dari ${draft.tableLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.refCode} · ${draft.itemCount} item',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Banner → pindah tab Pesanan (destinasi global, §C3).
          action: SnackBarAction(
            label: 'LIHAT',
            textColor: Colors.white,
            onPressed: () => ref
                .read(selectedDestinationProvider.notifier)
                .select(AppDestination.orders),
          ),
        ),
      );
  }
}
