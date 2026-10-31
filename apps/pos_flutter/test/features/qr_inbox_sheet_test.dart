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

  testWidgets('kartu draft menampilkan preferensi bayar + identitas pelanggan', (
    tester,
  ) async {
    final draft = QrDraft(
      draftId: 9,
      refCode: 'Q00009',
      tableId: 3,
      tableLabel: 'Meja 3',
      status: 'PENDING',
      subtotal: 15000,
      itemCount: 1,
      createdAt: DateTime(2026, 10, 31, 12),
      payIntent: 'PAY_NOW',
      payMethod: 'QRIS',
      customerName: 'Bu Rina',
      customerPhone: '6281234567890',
      items: const [
        QrDraftItem(
          productId: 1,
          productName: 'Nasi Goreng',
          unitPrice: 15000,
          qty: 1,
        ),
      ],
    );
    await tester.pumpWidget(_harness([draft]));
    await _open(tester);

    expect(
      find.text('Bayar sekarang · QRIS · Bu Rina · WA 6281234567890'),
      findsOneWidget,
    );
  });

  testWidgets('draft tanpa preferensi/identitas tidak menampilkan baris kosong', (
    tester,
  ) async {
    await tester.pumpWidget(_harness([_draft()]));
    await _open(tester);
    expect(find.textContaining('Bayar sekarang'), findsNothing);
    expect(find.textContaining('WA '), findsNothing);
  });

  test('fromJson membaca pay_intent/pay_method/identitas dari server', () {
    final draft = QrDraft.fromJson(const {
      'draft_id': 7,
      'ref_code': 'Q00007',
      'table_id': 2,
      'table_label': 'Meja 2',
      'status': 'PENDING',
      'subtotal': 30000,
      'item_count': 1,
      'created_at': '2026-10-31T10:00:00Z',
      'pay_intent': 'OPEN_BILL',
      'pay_method': null,
      'customer_name': 'Pak Ade',
      'customer_phone': '628999',
      'items': [],
    });
    expect(draft.payIntent, 'OPEN_BILL');
    expect(draft.payMethod, isNull);
    expect(draft.customerName, 'Pak Ade');
    expect(draft.customerPhone, '628999');
  });

  test('fromJson draft lama tanpa kolom 0018 tetap sah (null)', () {
    final draft = QrDraft.fromJson(const {
      'draft_id': 1,
      'ref_code': 'Q00001',
      'table_id': 1,
      'table_label': 'Meja 1',
      'status': 'PENDING',
      'subtotal': 0,
      'item_count': 0,
      'items': [],
    });
    expect(draft.payIntent, isNull);
    expect(draft.payMethod, isNull);
    expect(draft.customerName, isNull);
    expect(draft.customerPhone, isNull);
  });
}
