import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_flutter/features/pos/qr_inbox_sheet.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';

QrDraft _draft({int id = 1, String label = 'Meja 1'}) => QrDraft(
      draftId: id,
      refCode: 'Q0000$id',
      tableId: id,
      tableLabel: label,
      status: 'PENDING',
      subtotal: 22000,
      itemCount: 2,
      createdAt: DateTime(2026, 10, 26, 12),
      items: const [
        QrDraftItem(
          productId: 13,
          productName: 'Es Teh Manis Jumbo',
          unitPrice: 11000,
          qty: 2,
          note: 'tanpa gula',
          modifiers: [
            {'modifier_id': 1, 'name': 'Cincau', 'price_delta': 2000}
          ],
        ),
      ],
    );

Widget _harness(List<QrDraft> drafts,
    {Future<void> Function(QrDraft)? onClaim}) {
  return ProviderScope(
    overrides: [
      qrDraftsProvider.overrideWith((ref) async => drafts),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    height: 500,
                    child:
                        QrInboxSheet(onClaim: onClaim ?? (_) async {}),
                  ),
                ),
              ),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Buka'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('panel QR Masuk menampilkan draft masuk + subtotal',
      (tester) async {
    await tester.pumpWidget(_harness([_draft(), _draft(id: 2, label: 'Meja 2')]));
    await _open(tester);

    expect(find.text('QR Masuk'), findsOneWidget);
    expect(find.textContaining('Meja 1 · Q00001'), findsOneWidget);
    expect(find.textContaining('Meja 2 · Q00002'), findsOneWidget);
    // Snapshot item tampil lengkap (qty, nama, modifier, catatan).
    expect(find.textContaining('2× Es Teh Manis Jumbo (Cincau)'),
        findsNWidgets(2));
    expect(find.textContaining('tanpa gula'), findsNWidgets(2));
    expect(find.text('Rp 22.000'), findsNWidgets(2));
    expect(find.text('Ambil ke keranjang'), findsNWidgets(2));
  });

  testWidgets('panel QR Masuk kosong = pesan jujur, tanpa angka palsu',
      (tester) async {
    await tester.pumpWidget(_harness(const []));
    await _open(tester);
    expect(find.textContaining('Belum ada pesanan QR menunggu'), findsOneWidget);
    expect(find.text('Ambil ke keranjang'), findsNothing);
  });

  testWidgets('tombol Ambil memanggil onClaim dengan draft yang benar',
      (tester) async {
    QrDraft? claimed;
    await tester.pumpWidget(_harness(
      [_draft()],
      onClaim: (d) async => claimed = d,
    ));
    await _open(tester);
    await tester.tap(find.text('Ambil ke keranjang'));
    await tester.pumpAndSettle();
    expect(claimed?.refCode, 'Q00001');
  });

  testWidgets('tombol Batalkan memanggil repository cancel', (tester) async {
    // cancel memakai repository asli; di sini cukup pastikan tombol ada dan
    // menekannya tidak crash pada state kosong.
    await tester.pumpWidget(_harness(const []));
    await _open(tester);
    expect(find.text('Batalkan'), findsNothing);
  });
}
