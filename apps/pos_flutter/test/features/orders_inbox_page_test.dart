import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/destinations.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/catalog_models.dart';
import 'package:pos_flutter/core/wa_link.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';
import 'package:pos_flutter/features/orders/orders_inbox_page.dart';
import 'package:pos_flutter/features/pos/pos_repository.dart';
import 'package:pos_flutter/features/pos/qr_claim_service.dart';
import 'package:pos_flutter/features/tables_qr/tables_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repo QR palsu: mencatat setiap panggilan tanpa jaringan.
class _FakeQrRepository extends QrDraftRepository {
  _FakeQrRepository()
    : super(
        SupabaseClient(
          'https://qr-test.invalid',
          'sb_publishable_test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final claims = <int>[];
  final cancels = <int>[];
  final prepares = <int>[];
  final completes = <(int, int?)>[];
  bool failClaim = false;

  @override
  Future<QrDraft> claim(int draftId) async {
    if (failClaim) throw Exception('draft_not_claimable');
    claims.add(draftId);
    return QrDraft(
      draftId: draftId,
      refCode: 'Q${draftId.toString().padLeft(5, '0')}',
      tableId: 3,
      tableLabel: 'Meja 3',
      status: 'CLAIMED',
      subtotal: 15000,
      itemCount: 1,
      createdAt: DateTime(2026, 11, 1, 10),
      items: const [],
    );
  }

  @override
  Future<void> cancel(int draftId) async => cancels.add(draftId);

  @override
  Future<void> markPreparing(int draftId) async => prepares.add(draftId);

  @override
  Future<void> complete(int draftId, int? saleId) async =>
      completes.add((draftId, saleId));
}

QrDraft _draft({
  int id = 42,
  String status = 'PENDING',
  int? saleId,
  String? payIntent,
  String? payMethod,
  String? customerName,
  String? customerPhone,
  int unitPrice = 15000,
}) => QrDraft(
  draftId: id,
  refCode: 'Q${id.toString().padLeft(5, '0')}',
  tableId: 3,
  tableLabel: 'Meja 3',
  status: status,
  saleId: saleId,
  subtotal: unitPrice,
  itemCount: 1,
  createdAt: DateTime(2026, 11, 1, 10),
  payIntent: payIntent,
  payMethod: payMethod,
  customerName: customerName,
  customerPhone: customerPhone,
  items: [
    QrDraftItem(
      productId: 1,
      productName: 'Nasi Goreng',
      unitPrice: unitPrice,
      qty: 1,
      note: 'pedas',
    ),
  ],
);

List<Product> _products({int price = 15000}) => [
  Product(id: 1, name: 'Nasi Goreng', price: price),
];

Widget _harness({
  required List<QrDraft> drafts,
  required _FakeQrRepository repo,
  List<Product>? products,
}) => ProviderScope(
  overrides: [
    qrDraftsProvider.overrideWith((ref) async => drafts),
    qrDraftRepositoryProvider.overrideWithValue(repo),
    productsProvider.overrideWith((ref) async => products ?? _products()),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: const OrdersPage()),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OrdersPage)));

void main() {
  // --- Papan aktif: 4 seksi + lencana + identitas + preferensi (§C3/§A3) ---
  testWidgets('4 seksi papan aktif, lencana bayar, identitas & preferensi', (
    tester,
  ) async {
    // Papan penuh (5 kartu) — perbesar layar uji agar seluruh seksi terbangun.
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        repo: repo,
        drafts: [
          _draft(
            id: 42,
            payIntent: 'PAY_NOW',
            payMethod: 'QRIS',
            customerName: 'Bu Rina',
            customerPhone: '6281234567890',
          ),
          _draft(id: 43, status: 'CLAIMED'),
          _draft(id: 44, status: 'PREPARING'),
          _draft(id: 45, status: 'COMPLETED'),
          _draft(id: 46, status: 'COMPLETED', saleId: 7),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Baru masuk'), findsOneWidget);
    expect(find.text('Diterima'), findsWidgets); // seksi + tombol kartu
    expect(find.text('Diproses'), findsWidgets);
    expect(find.text('Selesai — belum bayar'), findsOneWidget);

    expect(find.text('Meja 3 · Q00042'), findsOneWidget);
    expect(find.text('Meja 3 · Q00046'), findsOneWidget);

    // Lencana bayar diturunkan dari sale_id (dimensi 2).
    expect(find.text('BELUM BAYAR'), findsNWidgets(4));
    expect(find.text('SUDAH BAYAR'), findsOneWidget);

    // Identitas + chip preferensi dari wizard web.
    expect(find.text('Bu Rina · WA 6281234567890'), findsOneWidget);
    expect(find.text('Bayar sekarang · QRIS'), findsOneWidget);

    // Catatan jujur total & item snapshot.
    expect(
      find.text('Total akhir = keranjang saat bayar (bisa bertambah).'),
      findsNWidgets(5),
    );
    expect(find.text('1× Nasi Goreng · pedas'), findsNWidgets(5));

    // [Hubungi WA] hanya di kartu BELUM BAYAR ber-identitas.
    expect(find.text('Hubungi WA'), findsOneWidget);
  });

  // --- Aksi per status ---
  testWidgets('[Diterima] klaim atomik + item masuk keranjang + id tercatat', (
    tester,
  ) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(_harness(drafts: [_draft()], repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Diterima'));
    await tester.pumpAndSettle();

    expect(repo.claims, [42]);
    final c = _container(tester);
    expect(
      c.read(cartControllerProvider).lines.single.productName,
      'Nasi Goreng',
    );
    expect(c.read(claimedDraftIdsProvider), contains(42));
  });

  testWidgets('[Diterima] konflik harga meminta persetujuan operator', (
    tester,
  ) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        drafts: [_draft(unitPrice: 15000)],
        repo: repo,
        products: _products(price: 18000),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Diterima'));
    await tester.pumpAndSettle();

    expect(find.text('Konflik harga'), findsOneWidget);
    expect(find.text('Nasi Goreng: Rp 15.000 → Rp 18.000'), findsOneWidget);
    expect(repo.claims, isEmpty); // belum disetujui

    await tester.tap(find.text('Pakai harga terkini'));
    await tester.pumpAndSettle();

    expect(repo.claims, [42]);
    final line = _container(tester).read(cartControllerProvider).lines.single;
    expect(line.basePrice, 18000); // harga terkini, bukan snapshot lama
  });

  testWidgets('[Diproses] memanggil qr_mark_preparing', (tester) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        drafts: [_draft(status: 'CLAIMED')],
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Diproses'));
    await tester.pumpAndSettle();

    expect(repo.prepares, [42]);
  });

  testWidgets('[Tandai selesai] complete tanpa sale (belum bayar)', (
    tester,
  ) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        drafts: [_draft(status: 'PREPARING')],
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tandai selesai'));
    await tester.pumpAndSettle();

    expect(repo.completes, [(42, null)]);
  });

  testWidgets('[Batalkan] memanggil qr_cancel_draft', (tester) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(_harness(drafts: [_draft()], repo: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();

    expect(repo.cancels, [42]);
  });

  // --- [Bayar] (rancangan v4) ---
  testWidgets('[Bayar] draft belum di set: masuk keranjang lalu ke Kasir POS', (
    tester,
  ) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        drafts: [_draft(status: 'COMPLETED')],
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    final c = _container(tester);
    expect(c.read(claimedDraftIdsProvider), contains(42));
    expect(c.read(cartControllerProvider).lines, hasLength(1));
    expect(c.read(selectedDestinationProvider), AppDestination.pos);
  });

  testWidgets('[Bayar] draft sudah di set: cukup pindah, tanpa duplikasi', (
    tester,
  ) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        drafts: [_draft(status: 'CLAIMED')],
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();
    _container(tester).read(claimedDraftIdsProvider.notifier).add(42);

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    final c = _container(tester);
    expect(c.read(selectedDestinationProvider), AppDestination.pos);
    expect(c.read(cartControllerProvider).lines, isEmpty);
    expect(repo.claims, isEmpty); // tidak klaim ulang
  });

  // --- [Hubungi WA] (C4) ---
  testWidgets('[Hubungi WA] membuka wa.me dengan pesan prabayar', (
    tester,
  ) async {
    final calls = <String>[];
    final original = waLaunchHandler;
    waLaunchHandler = (url) async => calls.add(url);
    addTearDown(() => waLaunchHandler = original);

    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        repo: repo,
        drafts: [
          _draft(
            status: 'COMPLETED',
            customerName: 'Budi',
            customerPhone: '0812-3456-7890',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hubungi WA'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single, startsWith('https://wa.me/6281234567890?text='));
    final message = Uri.decodeComponent(calls.single.split('text=').last);
    expect(message, contains('Halo Budi'));
    expect(message, contains('Meja 3'));
    expect(message, contains('Q00042'));
    expect(message, contains('belum dibayar'));
  });

  testWidgets('nomor WA tidak valid -> tombol nonaktif + tooltip jujur', (
    tester,
  ) async {
    final repo = _FakeQrRepository();
    await tester.pumpWidget(
      _harness(
        repo: repo,
        drafts: [_draft(status: 'COMPLETED', customerPhone: 'bukan-nomor')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Nomor WA tidak valid'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hubungi WA'),
    );
    expect(button.onPressed, isNull);
  });

  // --- Empty & error state ---
  testWidgets('papan kosong = pesan jujur, tanpa angka palsu', (tester) async {
    await tester.pumpWidget(
      _harness(drafts: const [], repo: _FakeQrRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belum ada pesanan.'), findsOneWidget);
    expect(
      find.text('Pesanan dari QR meja akan muncul di sini.'),
      findsOneWidget,
    );
    expect(find.text('0'), findsNothing);
  });

  testWidgets('gagal memuat menampilkan pesan + Coba lagi', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qrDraftsProvider.overrideWith((ref) async {
            throw Exception('network unavailable');
          }),
          qrDraftRepositoryProvider.overrideWithValue(_FakeQrRepository()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const OrdersPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coba lagi'), findsOneWidget);
  });

  // --- Parsing server (pindahan dari qr_inbox_sheet_test, §A3) ---
  test('fromJson membaca status/sale_id/preferensi/identitas', () {
    final draft = QrDraft.fromJson(const {
      'draft_id': 7,
      'ref_code': 'Q00007',
      'table_id': 2,
      'table_label': 'Meja 2',
      'status': 'COMPLETED',
      'subtotal': 30000,
      'item_count': 1,
      'created_at': '2026-10-31T10:00:00Z',
      'sale_id': 99,
      'pay_intent': 'OPEN_BILL',
      'pay_method': null,
      'customer_name': 'Pak Ade',
      'customer_phone': '628999',
      'items': [],
    });
    expect(draft.status, 'COMPLETED');
    expect(draft.saleId, 99);
    expect(draft.payIntent, 'OPEN_BILL');
    expect(draft.payMethod, isNull);
    expect(draft.customerName, 'Pak Ade');
    expect(draft.customerPhone, '628999');
  });

  test('fromJson draft lama tanpa kolom 0018/0019 tetap sah (null)', () {
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
    expect(draft.saleId, isNull);
    expect(draft.payIntent, isNull);
    expect(draft.customerName, isNull);
  });
}
