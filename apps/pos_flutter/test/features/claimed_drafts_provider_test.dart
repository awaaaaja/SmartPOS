import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/features/pos/qr_claim_service.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repo QR palsu untuk uji pelunasan checkout (invarian C1.2 §C3).
class _FakeQrRepository extends QrDraftRepository {
  _FakeQrRepository()
    : super(
        SupabaseClient(
          'https://qr-test.invalid',
          'sb_publishable_test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final completes = <(int, int?)>[];
  bool failIds = false;

  @override
  Future<void> complete(int draftId, int? saleId) async {
    if (failIds) throw Exception('network unavailable');
    completes.add((draftId, saleId));
  }
}

/// Tombol pemicu: aksinya menerima `WidgetRef` sehingga uji bisa
/// memanggil service dengan ref sungguhan (pola trigger ConsumerWidget).
class _Trigger extends ConsumerWidget {
  const _Trigger(this.onPressed);

  final void Function(WidgetRef ref, BuildContext context) onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
    onPressed: () => onPressed(ref, context),
    child: const Text('go'),
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeQrRepository repo,
  void Function(WidgetRef ref, BuildContext context) onPressed,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [qrDraftRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: _Trigger(onPressed)),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(_Trigger)));
}

void main() {
  testWidgets('checkout sukses: semua id di set dilunasi dengan saleId, '
      'lalu set dikosongkan', (tester) async {
    final repo = _FakeQrRepository();
    late WidgetRef capturedRef;
    final c = await _pump(tester, repo, (ref, _) => capturedRef = ref);
    final notifier = c.read(claimedDraftIdsProvider.notifier);
    notifier.add(11);
    notifier.add(12);
    expect(c.read(claimedDraftIdsProvider), {11, 12});

    await tester.tap(find.byType(_Trigger));
    await QrClaimService.completeClaimed(capturedRef, 999);

    expect(repo.completes, [(11, 999), (12, 999)]);
    expect(c.read(claimedDraftIdsProvider), isEmpty); // set drained
  });

  testWidgets('set kosong = tidak memanggil RPC sama sekali', (tester) async {
    final repo = _FakeQrRepository();
    late WidgetRef capturedRef;
    final c = await _pump(tester, repo, (ref, _) => capturedRef = ref);

    await tester.tap(find.byType(_Trigger));
    await QrClaimService.completeClaimed(capturedRef, 1000);

    expect(repo.completes, isEmpty);
    expect(c.read(claimedDraftIdsProvider), isEmpty);
  });

  testWidgets('gagal mengaitkan TIDAK melempar; set tetap terkuras '
      '(sale asli tetap tersimpan di server)', (tester) async {
    final repo = _FakeQrRepository()..failIds = true;
    late WidgetRef capturedRef;
    final c = await _pump(tester, repo, (ref, _) => capturedRef = ref);
    c.read(claimedDraftIdsProvider.notifier).add(7);

    await tester.tap(find.byType(_Trigger));
    await QrClaimService.completeClaimed(capturedRef, 555); // tidak boleh throw

    expect(c.read(claimedDraftIdsProvider), isEmpty);
    // Draft tetap terbuka di server; operator masih bisa [Bayar] manual.
  });
}
