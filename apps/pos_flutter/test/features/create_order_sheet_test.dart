import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';
import 'package:pos_flutter/features/orders/create_order_sheet.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';
import 'package:pos_flutter/core/models/catalog_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repo draft palsu: mencatat panggilan RPC manual tanpa jaringan.
class _FakeDraftRepo extends QrDraftRepository {
  _FakeDraftRepo()
    : super(
        SupabaseClient(
          'https://manual-test.invalid',
          'sb_publishable_test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  ({int tableId, String name, String? phone, List<Map<String, dynamic>> items})?
  created;
  ({int draftId, List<Map<String, dynamic>> items})? added;
  PostgrestException? failWith;

  @override
  Future<QrDraft> createManualOrder({
    required int tableId,
    required String customerName,
    String? customerPhone,
    required List<Map<String, dynamic>> items,
  }) async {
    final fail = failWith;
    if (fail != null) throw fail;    created = (
      tableId: tableId,
      name: customerName,
      phone: customerPhone,
      items: items,
    );
    return QrDraft(
      draftId: 99,
      refCode: 'Q00099',
      tableId: tableId,
      tableLabel: 'Meja 1',
      status: 'CLAIMED',
      subtotal: 15000,
      itemCount: items.length,
      createdAt: DateTime(2026, 11, 1, 12),
      customerName: customerName,
      items: const [],
    );
  }

  @override
  Future<QrDraft> addDraftItems(
    int draftId,
    List<Map<String, dynamic>> items,
  ) async {
    final fail = failWith;
    if (fail != null) throw fail;
    added = (draftId: draftId, items: items);
    return QrDraft(
      draftId: draftId,
      refCode: 'Q00042',
      tableId: 3,
      tableLabel: 'Meja 3',
      status: 'CLAIMED',
      subtotal: 30000,
      itemCount: 2,
      createdAt: DateTime(2026, 11, 1, 10),
      items: const [],
    );
  }
}

DiningTableEntry _table({int id = 1, String label = 'Meja 1'}) =>
    DiningTableEntry(id: id, label: label, isEnabled: true, tokenVersion: 1);

List<Product> _products() => [
  Product(id: 7, name: 'Nasi Goreng', price: 15000),
];

Widget _harness({
  required _FakeDraftRepo repo,
  required VoidCallback open,
}) => ProviderScope(
  overrides: [
    qrDraftRepositoryProvider.overrideWithValue(repo),
    tablesListProvider.overrideWith((ref) async => [_table()]),
    productsProvider.overrideWith((ref) async => _products()),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Center(
        child: FilledButton(onPressed: open, child: const Text('Buka')),
      ),
    ),
  ),
);

/// Buka sheet via tombol (meniru pemakaian nyata dari tab Pesanan).
Future<void> _pumpTrigger(
  WidgetTester tester,
  Future<void> Function(BuildContext) show,
  _FakeDraftRepo repo,
) async {
  await tester.pumpWidget(
    _harness(repo: repo, open: () => show(tester.element(find.byType(Scaffold)))),
  );
  await tester.tap(find.text('Buka'));
  await tester.pumpAndSettle();
}

/// Pilih menu lewat sheet pemilih (produk tanpa varian = langsung masuk).
Future<void> _pickProduct(WidgetTester tester) async {
  await tester.tap(find.text('Tambah menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nasi Goreng'));
  await tester.pumpAndSettle();
}

void main() {
  group('Buat Pesanan (pesanan manual)', () {
    testWidgets('tombol nonaktif sampai nama, meja, dan menu terisi', (
      tester,
    ) async {
      await _pumpTrigger(tester, showCreateOrderSheet, _FakeDraftRepo());

      FilledButton submit() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Buat Pesanan'),
      );
      expect(submit().onPressed, isNull, reason: 'awal: belum valid');

      await tester.enterText(find.byType(TextField).first, 'Bu Rina');
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull, reason: 'tanpa meja & menu');

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meja 1'));
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNull, reason: 'tanpa menu');

      await _pickProduct(tester);
      expect(submit().onPressed, isNotNull, reason: 'lengkap');
    });

    testWidgets('submit mengirim nama, meja, dan item (qty + catatan) ke RPC', (
      tester,
    ) async {
      final repo = _FakeDraftRepo();
      await _pumpTrigger(tester, showCreateOrderSheet, repo);

      await tester.enterText(find.byType(TextField).first, 'Bu Rina');
      await tester.enterText(find.byType(TextField).at(1), '6281234567890');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meja 1'));
      await tester.pumpAndSettle();
      await _pickProduct(tester);

      // Naikkan qty jadi 2 lewat tombol + di baris item (sibling teks —
      // pakai tooltip langsung; hanya ada satu di sheet ini).
      await tester.tap(find.byTooltip('Tambah'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Buat Pesanan'));
      await tester.pumpAndSettle();

      expect(repo.created, isNotNull);
      expect(repo.created!.tableId, 1);
      expect(repo.created!.name, 'Bu Rina');
      expect(repo.created!.phone, '6281234567890');
      expect(repo.created!.items, hasLength(1));
      expect(repo.created!.items.single['product_id'], 7);
      expect(repo.created!.items.single['qty'], 2);
      // Sheet tertutup setelah sukses.
      expect(find.text('Buat Pesanan'), findsNothing);
    });

    testWidgets('server menolak: pesan error tampil, isian tidak hilang', (
      tester,
    ) async {
      final repo = _FakeDraftRepo()
        ..failWith = const PostgrestException(
          message: 'invalid_customer_name',
          code: 'P0001',
        );
      await _pumpTrigger(tester, showCreateOrderSheet, repo);

      await tester.enterText(find.byType(TextField).first, 'Bu Rina');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meja 1'));
      await tester.pumpAndSettle();
      await _pickProduct(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Buat Pesanan'));
      await tester.pumpAndSettle();

      expect(
        find.text('Nama pesanan wajib diisi (maksimal 60 huruf).'),
        findsOneWidget,
      );
      expect(find.text('Bu Rina'), findsOneWidget, reason: 'isian bertahan');
      expect(
        find.widgetWithText(FilledButton, 'Buat Pesanan'),
        findsOneWidget,
        reason: 'sheet terbuka',
      );
    });
  });

  group('Tambah item pesanan aktif', () {
    testWidgets('kirim draftId + item terpilih ke qr_draft_add_items', (
      tester,
    ) async {
      final repo = _FakeDraftRepo();
      final draft = QrDraft(
        draftId: 42,
        refCode: 'Q00042',
        tableId: 3,
        tableLabel: 'Meja 3',
        status: 'CLAIMED',
        subtotal: 15000,
        itemCount: 1,
        createdAt: DateTime(2026, 11, 1, 10),
        customerName: 'Bu Rina',
        items: const [],
      );
      await _pumpTrigger(
        tester,
        (context) => showAddItemsSheet(context, draft),
        repo,
      );

      await _pickProduct(tester);
      // Label tombol memuat jumlah menu & subtotal perkiraan.
      expect(find.text('Tambah 1 menu (Rp 15.000)'), findsOneWidget);

      await tester.tap(find.text('Tambah 1 menu (Rp 15.000)'));
      await tester.pumpAndSettle();

      expect(repo.added, isNotNull);
      expect(repo.added!.draftId, 42);
      expect(repo.added!.items, hasLength(1));
      expect(repo.added!.items.single['product_id'], 7);
      // Sheet tertutup + umpan balik subtotal server (30.000 dari repo).
      expect(find.textContaining('subtotal kini Rp 30.000'), findsOneWidget);
    });

    testWidgets('server menolak draft non-aktif: pesan jujur tampil', (
      tester,
    ) async {
      final repo = _FakeDraftRepo()
        ..failWith = const PostgrestException(
          message: 'draft_not_editable',
          code: 'P0001',
        );
      final draft = QrDraft(
        draftId: 42,
        refCode: 'Q00042',
        tableId: 3,
        tableLabel: 'Meja 3',
        status: 'COMPLETED',
        subtotal: 15000,
        itemCount: 1,
        createdAt: DateTime(2026, 11, 1, 10),
        items: const [],
      );
      await _pumpTrigger(
        tester,
        (context) => showAddItemsSheet(context, draft),
        repo,
      );
      await _pickProduct(tester);
      await tester.tap(find.textContaining('Tambah 1 menu'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hanya pesanan yang masih aktif'),
        findsOneWidget,
      );
      expect(find.textContaining('Tambah item'), findsOneWidget);
    });
  });
}
