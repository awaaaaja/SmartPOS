import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/qr_inbox_watcher.dart';
import 'package:pos_flutter/core/notif_sound.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

QrDraft _draft({int id = 42}) => QrDraft(
  draftId: id,
  refCode: 'Q000$id',
  tableId: 3,
  tableLabel: 'Meja 3',
  status: 'PENDING',
  subtotal: 25000,
  itemCount: 2,
  createdAt: DateTime(2026, 11, 1, 10),
  items: const [],
);

/// Pasang preference lokal in-memory (SharedPreferencesAsync butuh platform
/// instance eksplisit di test; mock legacy tidak menanganinya).
void _mockPrefs([Map<String, Object> values = const {}]) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(values);
}

/// Merekam panggilan pemutar nada alih-alih memutar audio (pola
/// shareSheetHandler: audio asli hanya bisa diverifikasi di device).
class _SoundRecorder {
  final calls = <(String tone, double volume)>[];
  Future<void> play(String tone, double volume) async {
    calls.add((tone, volume));
  }
}

/// Harness: watcher + Scaffold pembawa SnackBar, dengan data draft yang
/// bisa berubah lalu di-refresh lewat polling 10 detik (timer fake async).
Widget _harness(List<QrDraft> Function() drafts) => ProviderScope(
  overrides: [
    qrDraftsProvider.overrideWith((ref) async => drafts()),
  ],
  child: const MaterialApp(
    home: Scaffold(body: QrInboxWatcher()),
  ),
);

/// Kumpulan draft yang bisa dimutasi dari test.
class _DraftBox {
  List<QrDraft> rows = const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SoundRecorder recorder;
  final originalPlayer = notifSoundPlayer;

  setUp(() {
    _mockPrefs();
    recorder = _SoundRecorder();
    notifSoundPlayer = recorder.play;
  });

  tearDown(() {
    notifSoundPlayer = originalPlayer;
  });

  testWidgets('draft PENDING baru memicu banner + nada notifikasi', (
    tester,
  ) async {
    final box = _DraftBox();
    await tester.pumpWidget(_harness(() => box.rows));
    await tester.pumpAndSettle();
    // Muat pertama = baseline, sunyi.
    expect(recorder.calls, isEmpty);
    expect(find.byType(SnackBar), findsNothing);

    box.rows = [_draft()];
    await tester.pump(const Duration(seconds: 11)); // tick polling
    await tester.pumpAndSettle();

    expect(recorder.calls, hasLength(1));
    expect(recorder.calls.single.$1, 'confirmation_001');
    expect(
      find.text('Pesanan baru dari Meja 3 · Q00042'),
      findsOneWidget,
    );
  });

  testWidgets('muat pertama dengan draft lama = baseline sunyi', (
    tester,
  ) async {
    final box = _DraftBox()..rows = [_draft()];
    await tester.pumpWidget(_harness(() => box.rows));
    await tester.pumpAndSettle();

    expect(recorder.calls, isEmpty);
    expect(find.byType(SnackBar), findsNothing);

    // Draft yang sama (id sama) pada refresh berikutnya juga tidak diumumkan.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(recorder.calls, isEmpty);
  });

  testWidgets('suara mati di Pengaturan = senyap, banner tetap muncul', (
    tester,
  ) async {
    _mockPrefs({'notif-sound-enabled': false});
    final box = _DraftBox();
    await tester.pumpWidget(_harness(() => box.rows));
    await tester.pumpAndSettle();

    box.rows = [_draft()];
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    expect(recorder.calls, isEmpty);
    expect(
      find.text('Pesanan baru dari Meja 3 · Q00042'),
      findsOneWidget,
    );
  });

  test('NotifSoundPrefs: default aktif & preferensi tersimpan lokal', () async {
    _mockPrefs();
    final prefs = NotifSoundPrefs();
    expect(await prefs.enabled, isTrue);
    expect(await prefs.tone, 'confirmation_001');
    expect(await prefs.volume, 0.8);

    await prefs.setEnabled(false);
    await prefs.setTone('confirmation_003');
    await prefs.setVolume(0.25);

    final reread = NotifSoundPrefs();
    expect(await reread.enabled, isFalse);
    expect(await reread.tone, 'confirmation_003');
    expect(await reread.volume, 0.25);
  });
}
