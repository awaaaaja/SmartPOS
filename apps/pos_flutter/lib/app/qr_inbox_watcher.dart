import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notif_sound.dart';
import '../features/auth/auth_repository.dart';
import '../features/tables_qr/tables_repository.dart';
import 'destinations.dart';
import 'theme.dart';

/// Pemantau draft QR dari shell (§B1) — 3 lapis supaya pesanan TIDAK delay
/// (laporan: notifikasi kadang telat, papan harus refresh manual):
///
///   1. Realtime push (migrasi 0024): langganan `postgres_changes` pada
///      `qr_drafts` -> refresh seketika saat pesanan masuk/diubah,
///      tanpa menunggu siklus polling berikutnya.
///   2. Refresh saat app kembali ke depan (resume) — isolate sempat berhenti
///      di background, jadi jangan tunggu timer polling.
///   3. Polling 10 detik sebagai FALLBACK bila websocket tidak tersedia
///      (jaringan memblokir, dsb.) — perilaku lama yang tetap menjamin data.
///
/// Deteksi pesanan PENDING baru -> banner in-app + nada (bila aktif di
/// Pengaturan).
///
/// Muat pertama = baseline (sunyi) supaya draft lama yang masih menunggu
/// tidak diumumkan ulang tiap aplikasi dibuka; deteksi in-memori (restart =
/// baseline baru). Status selain PENDING tidak memicu apa pun.
class QrInboxWatcher extends ConsumerStatefulWidget {
  const QrInboxWatcher({super.key});

  @override
  ConsumerState<QrInboxWatcher> createState() => _QrInboxWatcherState();
}

class _QrInboxWatcherState extends ConsumerState<QrInboxWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;
  RealtimeChannel? _channel;
  SupabaseClient? _client; // disimpan untuk lepas channel saat dispose

  /// Id draft yang sudah dikenal (baseline + yang sudah diumumkan).
  final Set<int> _knownIds = {};
  bool _baselineLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refresh(), // fallback bila realtime mati
    );
    _subscribeRealtime();
  }

  /// Muat ulang papan pesanan (dipanggil realtime, resume, & polling).
  void _refresh() {
    if (mounted) ref.invalidate(qrDraftsProvider);
  }

  /// Langganan event `qr_drafts` (INSERT/UPDATE/DELETE) — push seketika.
  /// Segala kegagalan ditelan: polling fallback tetap menjamin data segar
  /// (`Supabase.instance` juga melempar pada widget test sebelum init —
  /// sengaja ditangkap supaya test lama tetap lulus).
  void _subscribeRealtime() {
    try {
      final client = ref.read(supabaseClientProvider);
      _client = client;
      _channel = client
          .channel('qr-inbox-watcher')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'qr_drafts',
            callback: (_) => _refresh(),
          )
          ..subscribe();
    } catch (_) {
      _channel = null; // Supabase belum siap (test/startup) -> polling saja.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    final channel = _channel;
    final client = _client;
    if (channel != null && client != null) {
      try {
        client.removeChannel(channel);
      } catch (_) {
        // Supabase sudah dilepas sebelum watcher — channel mati sendiri.
      }
    }
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
                      // Meja virtual pesanan online (migrasi 0023) berlabel
                      // 'Pesanan Online' — frasa "dari Pesanan Online"
                      // janggal, jadi diberi label khusus.
                      draft.tableLabel == 'Pesanan Online'
                          ? 'Pesanan online baru'
                          : 'Pesanan baru dari ${draft.tableLabel}',
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
