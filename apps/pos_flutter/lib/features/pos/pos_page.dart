import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../../core/models/catalog_models.dart';
import '../../core/models/sale_models.dart';
import '../catalog/catalog_repository.dart';
import '../tables_qr/tables_repository.dart';
import 'pos_repository.dart';
import 'qr_inbox_sheet.dart';

/// S02-04/06: Kasir POS satu layar.
/// Tablet (lebar ≥840dp): katalog + keranjang bersamaan.
/// HP: katalog penuh + tombol keranjang yang membuka sheet.
class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  String _search = '';
  String _categoryFilter = 'Semua';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Polling ringan draft QR; panel terbuka atau tidak, badge tetap segar.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => ref.invalidate(qrDraftsProvider),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final categories = ref.watch(categoriesProvider);
    final cart = ref.watch(cartControllerProvider);
    final drafts = ref.watch(qrDraftsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          return products.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => _CenteredMessage(
              icon: Icons.error_outline_rounded,
              message: mapErrorToMessage(e),
              onRetry: () => ref.invalidate(productsProvider),
            ),
            data: (allProducts) {
              final sellable =
                  allProducts.where((p) => p.sellable).toList();
              final categoryNames = [
                'Semua',
                ...?categories.value?.map((c) => c.name),
              ];
              final filtered = sellable.where((p) {
                final okCat = _categoryFilter == 'Semua' ||
                    p.categoryName == _categoryFilter;
                final okSearch = _search.isEmpty ||
                    p.name.toLowerCase().contains(_search.toLowerCase());
                return okCat && okSearch;
              }).toList();

              final catalog = _CatalogPane(
                products: filtered,
                categoryNames: categoryNames,
                categoryFilter: _categoryFilter,
                search: _search,
                qrBadge: drafts.value?.length ?? 0,
                onSearch: (v) => setState(() => _search = v),
                onCategory: (v) =>
                    setState(() => _categoryFilter = v),
                onPick: (p) => _pickProduct(p),
                onOpenQr: () => _openQrInbox(),
              );

              if (wide) {
                return Row(
                  children: [
                    Expanded(child: catalog),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 380,
                      child: _CartPane(
                        cart: cart,
                        onQty: (i, d) => ref
                            .read(cartControllerProvider.notifier)
                            .changeQty(i, d),
                        onRemove: (i) => ref
                            .read(cartControllerProvider.notifier)
                            .removeAt(i),
                        onDiscount: (v) => ref
                            .read(cartControllerProvider.notifier)
                            .setDiscount(v),
                        onPay: () => _openPayment(cart),
                      ),
                    ),
                  ],
                );
              }

              // HP: katalog penuh, keranjang lewat sheet.
              return Column(
                children: [
                  Expanded(child: catalog),
                  if (!cart.isEmpty)
                    _MobileCartBar(
                      cart: cart,
                      onOpen: () => _openCartSheet(cart),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Pilih produk: langsung masuk bila tanpa modifier; kalau ada varian/
  /// topping, buka sheet pemilihan (S02-02).
  Future<void> _pickProduct(Product product) async {
    if (product.modifiers.isEmpty) {
      ref.read(cartControllerProvider.notifier).add(CartLine(
            productId: product.id,
            productName: product.name,
            basePrice: product.price,
          ));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ModifierSheet(product: product),
    );
  }

  Future<void> _openCartSheet(CartState cart) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: _CartPane(
          cart: cart,
          onQty: (i, d) =>
              ref.read(cartControllerProvider.notifier).changeQty(i, d),
          onRemove: (i) =>
              ref.read(cartControllerProvider.notifier).removeAt(i),
          onDiscount: (v) =>
              ref.read(cartControllerProvider.notifier).setDiscount(v),
          onPay: () {
            Navigator.pop(ctx);
            _openPayment(cart);
          },
        ),
      ),
    );
  }

  Future<void> _openPayment(CartState cart) async {
    if (cart.isEmpty) return;
    final receipt = await showModalBottomSheet<Receipt>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(cart: cart),
    );
    if (receipt == null) return;
    ref.read(cartControllerProvider.notifier).clear();
    ref.invalidate(dashboardSummaryProvider);
    // Draft yang menopang keranjang ini ditandai selesai (jejak audit).
    await _completeClaimedDrafts(receipt.saleId);
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _ReceiptDialog(receipt: receipt),
      );
    }
  }

  // -------------------------------------------------------------------------
  // S03: Panel QR Masuk di dalam layar POS.
  // -------------------------------------------------------------------------

  /// Draft yang sudah diambil ke keranjang (menunggu checkout menyelesaikannya).
  final Set<int> _claimedDraftIds = {};

  Future<void> _openQrInbox() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: QrInboxSheet(
          onClaim: (draft) => _claimDraft(draft),
        ),
      ),
    );
    ref.invalidate(qrDraftsProvider);
  }

  /// Ambil draft ke keranjang. Harga TIDAK diam-diam dipakai: bila snapshot
  /// harga pelanggan berbeda dari harga katalog sekarang, operator diminta
  /// memilih (konflik harga).
  Future<void> _claimDraft(QrDraft draft) async {
    // Harga katalog DIREFRESH dulu; deteksi konflik harus memakai harga
    // terkini, bukan cache lama.
    final allProducts = await ref.refresh(productsProvider.future);
    final byId = {for (final p in allProducts) p.id: p};

    final conflicts = <String>[];
    final unavailable = <String>[];
    final lines = <CartLine>[];

    for (final item in draft.items) {
      final product = byId[item.productId];
      if (product == null || !product.sellable) {
        unavailable.add(item.productName);
        continue;
      }
      // Harga aktif sekarang = harga dasar + modifier terpilih (harga kini).
      final mods = product.modifiers
          .where((m) => item.modifierIds.contains(m.id))
          .toList();
      final currentUnit = product.price +
          mods.fold<int>(0, (sum, m) => sum + m.priceDelta);
      if (currentUnit != item.unitPrice) {
        conflicts.add(
            '${item.productName}: ${formatRupiah(item.unitPrice)} → '
            '${formatRupiah(currentUnit)}');
      }
      lines.add(CartLine(
        productId: item.productId,
        productName: product.name,
        basePrice: product.price,
        qty: item.qty,
        note: item.note ?? '',
        modifierIds: item.modifierIds,
        modifiers: mods
            .map((m) => {
                  'id': m.id,
                  'name': m.name,
                  'price_delta': m.priceDelta,
                })
            .toList(),
      ));
    }

    if (lines.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Tidak ada item valid'),
          content: Text(unavailable.isEmpty
              ? 'Seluruh item draft sudah tidak tersedia di katalog.'
              : 'Item tidak tersedia: ${unavailable.join(', ')}.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup')),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final proceed = conflicts.isEmpty
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Konflik harga'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Harga katalog berubah sejak pesanan QR ${draft.refCode} '
                      'dikirim. Keranjang memakai harga terkini:'),
                  const SizedBox(height: 8),
                  for (final c in conflicts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(c, style: const TextStyle(fontSize: 13)),
                    ),
                  if (unavailable.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Dilewati (tidak tersedia): '
                        '${unavailable.join(', ')}',
                        style: const TextStyle(
                            fontSize: 12, color: errorColor)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Pakai harga terkini'),
                ),
              ],
            ),
          ) ??
          false;
    if (!proceed || !mounted) return;

    // Klaim di server DULU; batal bila sudah diambil operator lain.
    QrDraft claimed;
    try {
      claimed = await ref.read(qrDraftRepositoryProvider).claim(draft.draftId);
    } catch (e) {
      ref.invalidate(qrDraftsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Draft gagal diambil (mungkin sudah diambil '
                'operator lain): ${mapErrorToMessage(e)}')));
      }
      return;
    }
    _claimedDraftIds.add(claimed.draftId);

    final cart = ref.read(cartControllerProvider.notifier);
    for (final line in lines) {
      cart.add(line);
    }
    ref.invalidate(qrDraftsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${draft.itemCount} item dari ${draft.tableLabel} masuk '
              'keranjang.')));
    }
  }

  Future<void> _completeClaimedDrafts(int saleId) async {
    for (final id in _claimedDraftIds) {
      try {
        await ref.read(qrDraftRepositoryProvider).complete(id, saleId);
      } catch (_) {
        // Draft tetap CLAIMED; tidak memengaruhi uang/omzet. Aman dilewati.
      }
    }
    _claimedDraftIds.clear();
  }
}

// ---------------------------------------------------------------------------
// Katalog
// ---------------------------------------------------------------------------

class _CatalogPane extends StatelessWidget {
  const _CatalogPane({
    required this.products,
    required this.categoryNames,
    required this.categoryFilter,
    required this.search,
    required this.qrBadge,
    required this.onSearch,
    required this.onCategory,
    required this.onPick,
    required this.onOpenQr,
  });

  final List<Product> products;
  final List<String> categoryNames;
  final String categoryFilter;
  final String search;
  final int qrBadge;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onCategory;
  final ValueChanged<Product> onPick;
  final VoidCallback onOpenQr;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Cari makanan atau minuman...',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: onSearch,
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: onOpenQr,
              icon: Badge(
                isLabelVisible: qrBadge > 0,
                label: Text('$qrBadge'),
                child: const Icon(Icons.qr_code_2_rounded, size: 20),
              ),
              label: const Text('QR Masuk'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in categoryNames)
              ChoiceChip(
                label: Text(c),
                selected: c == categoryFilter,
                onSelected: (_) => onCategory(c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('Tidak ada menu yang cocok.',
                  style: TextStyle(color: textSecondary)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 0.95,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) {
              final p = products[i];
              return _ProductCard(product: p, onTap: () => onPick(p));
            },
          ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fallback = Icon(Icons.restaurant_rounded,
        size: 34, color: brandPrimary);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: product.photoUrl == null ||
                          product.photoUrl!.isEmpty
                      ? fallback
                      : Image.network(
                          product.photoUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => fallback,
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                formatRupiah(product.price),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: brandPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pemilih modifier (varian / topping) dengan batas min-max dari server
// ---------------------------------------------------------------------------

class _ModifierSheet extends ConsumerStatefulWidget {
  const _ModifierSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends ConsumerState<_ModifierSheet> {
  final Set<int> _selected = {};
  int _qty = 1;
  final _note = TextEditingController();

  Product get product => widget.product;

  int get _minRequired =>
      product.modifiers.fold(0, (sum, m) => sum + m.minSelect);
  int get _maxAllowed =>
      product.modifiers.fold(0, (sum, m) => sum + m.maxSelect);

  /// Jumlah terpilih pada grup modifier (semua modifier di sini per produk).
  int get _totalSelected => _selected.length;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delta = product.modifiers
        .where((m) => _selected.contains(m.id))
        .fold<int>(0, (sum, m) => sum + m.priceDelta);
    final unit = product.price + delta;
    final canAdd = _totalSelected >= _minRequired &&
        _totalSelected <= _maxAllowed;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(formatRupiah(product.price),
                style: const TextStyle(color: textSecondary)),
            const SizedBox(height: 12),
            for (final m in product.modifiers)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                    '${m.name} (+${formatRupiah(m.priceDelta)})'),
                subtitle: m.minSelect > 0
                    ? Text('Pilih minimal ${m.minSelect}',
                        style: const TextStyle(fontSize: 11))
                    : null,
                value: _selected.contains(m.id),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      if (_totalSelected < _maxAllowed) {
                        _selected.add(m.id);
                      }
                    } else {
                      _selected.remove(m.id);
                    }
                  });
                },
              ),
            const SizedBox(height: 4),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Kurangi',
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _qty > 1
                      ? () => setState(() => _qty--)
                      : null,
                ),
                Text('$_qty', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  tooltip: 'Tambah',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () => setState(() => _qty++),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: canAdd
                      ? () {
                          ref
                              .read(cartControllerProvider.notifier)
                              .add(CartLine(
                                productId: product.id,
                                productName: product.name,
                                basePrice: product.price,
                                qty: _qty,
                                note: _note.text.trim(),
                                modifierIds: _selected.toList(),
                                modifiers: product.modifiers
                                    .where(
                                        (m) => _selected.contains(m.id))
                                    .map((m) => {
                                          'id': m.id,
                                          'name': m.name,
                                          'price_delta': m.priceDelta,
                                        })
                                    .toList(),
                              ));
                          Navigator.pop(context);
                        }
                      : null,
                  child: Text('Tambah · ${formatRupiah(unit * _qty)}'),
                ),
              ],
            ),
            if (!canAdd)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Pilih minimal $_minRequired dan maksimal '
                  '$_maxAllowed tambahan.',
                  style: const TextStyle(color: errorColor, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Keranjang
// ---------------------------------------------------------------------------

class _CartPane extends StatelessWidget {
  const _CartPane({
    required this.cart,
    required this.onQty,
    required this.onRemove,
    required this.onDiscount,
    required this.onPay,
  });

  final CartState cart;
  final void Function(int index, int delta) onQty;
  final void Function(int index) onRemove;
  final ValueChanged<double> onDiscount;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Keranjang Kasir',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Chip(
                label: Text('${cart.itemCount} item'),
                backgroundColor: brandSoft,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: cart.isEmpty
              ? const Center(
                  child: Text('Keranjang kosong.\nPilih menu untuk '
                      'menambahkan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final line = cart.lines[i];
                    return _CartLineTile(
                      line: line,
                      onIncrease: () => onQty(i, 1),
                      onDecrease: () => onQty(i, -1),
                      onRemove: () => onRemove(i),
                    );
                  },
                ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Diskon %'),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TextFormField(
                  key: ValueKey('discount-${cart.discountPct}'),
                  initialValue: cart.discountPct == 0
                      ? '0'
                      : '${cart.discountPct}',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) {
                    final parsed = double.tryParse(v) ?? 0;
                    onDiscount(parsed.clamp(0, 100).toDouble());
                  },
                ),
              ),
              const Spacer(),
              Text('Perkiraan: ${formatRupiah(cart.estimatedSubtotal)}',
                  style:
                      const TextStyle(fontSize: 12, color: textSecondary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: cart.isEmpty ? null : onPay,
            icon: const Icon(Icons.payment_rounded),
            label: const Text('Bayar'),
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  final CartLine line;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mods = line.modifiers
        .map((m) => m['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (mods.isNotEmpty || line.note.isNotEmpty)
                  Text(
                    [
                      if (mods.isNotEmpty) mods,
                      if (line.note.isNotEmpty) 'Catatan: ${line.note}',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11, color: textSecondary),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kurangi',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            onPressed: onDecrease,
          ),
          Text('${line.qty}'),
          IconButton(
            tooltip: 'Tambah',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: onIncrease,
          ),
          SizedBox(
            width: 92,
            child: Text(
              formatRupiah(line.lineTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Hapus',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({required this.cart, required this.onOpen});

  final CartState cart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: brandPrimary,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${cart.itemCount} item · perkiraan '
                    '${formatRupiah(cart.estimatedSubtotal)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('Bayar →',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pembayaran (S02-05/06): quote & checkout dari server
// ---------------------------------------------------------------------------

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.cart});

  final CartState cart;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final String _idempotencyKey;
  Future<Quote>? _quoteFuture;
  String _method = 'CASH';
  final _paid = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Key dibuat SEKALI per percobaan pembayaran; retry memakai key yang
    // sama sehingga server mengembalikan sale yang sama (idempoten).
    _idempotencyKey =
        'pos-${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';
    _quoteFuture = _fetchQuote();
  }

  static String _randomSuffix() {
    final r = Random();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<Quote> _fetchQuote() {
    return ref
        .read(posRepositoryProvider)
        .quote(widget.cart.lines, widget.cart.discountPct);
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: FutureBuilder<Quote>(
          future: _quoteFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return SizedBox(
                height: 220,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(mapErrorToMessage(snap.error!),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => setState(() {
                          _error = null;
                          _quoteFuture = _fetchQuote();
                        }),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Ulangi'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final quote = snap.data!;
            final total = quote.total;
            final paid = int.tryParse(_paid.text.trim());
            final change = paid == null ? 0 : max(0, paid - total);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pembayaran',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _moneyRow('Subtotal', quote.subtotal),
                _moneyRow('Diskon', -quote.discountAmount),
                _moneyRow('Pajak', quote.taxAmount),
                _moneyRow('Biaya layanan', quote.serviceAmount),
                const Divider(),
                Row(
                  children: [
                    const Expanded(
                        child: Text('Total',
                            style:
                                TextStyle(fontWeight: FontWeight.w700))),
                    Text(formatRupiah(total),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: brandPrimary)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration:
                      const InputDecoration(labelText: 'Metode pembayaran'),
                  items: const [
                    DropdownMenuItem(
                        value: 'CASH', child: Text('Tunai')),
                    DropdownMenuItem(
                        value: 'TRANSFER',
                        child: Text('Transfer (verifikasi manual)')),
                    DropdownMenuItem(
                        value: 'QRIS',
                        child: Text('QRIS (verifikasi manual)')),
                  ],
                  onChanged: (v) =>
                      setState(() => _method = v ?? 'CASH'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _paid,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Nominal diterima (Rp)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text('Kembalian: ${formatRupiah(change)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: paid != null && paid < total
                            ? errorColor
                            : successColor)),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style:
                          const TextStyle(color: errorColor, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ||
                            paid == null ||
                            paid < total ||
                            widget.cart.isEmpty
                        ? null
                        : () => _submit(total),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Konfirmasi & Simpan Penjualan'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _moneyRow(String label, int amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: textSecondary))),
            Text(formatRupiah(amount)),
          ],
        ),
      );

  Future<void> _submit(int total) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final paid = int.parse(_paid.text.trim());
      final receipt = await ref.read(posRepositoryProvider).checkout(
            lines: widget.cart.lines,
            method: _method,
            paid: paid,
            discountPct: widget.cart.discountPct,
            idempotencyKey: _idempotencyKey,
          );
      if (mounted) Navigator.pop(context, receipt);
    } catch (e) {
      if (mounted) {
        // Key TIDAK diganti: retry akan idempoten di server.
        setState(() {
          _submitting = false;
          _error = mapErrorToMessage(e);
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Struk
// ---------------------------------------------------------------------------

class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Transaksi Tersimpan'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: successColor, size: 44),
                  const SizedBox(height: 8),
                  Text(formatRupiah(receipt.total),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(receipt.receiptNo,
                      style: const TextStyle(color: textSecondary)),
                  if (receipt.idempotentReplay)
                    const Text('Transaksi ini sudah tersimpan sebelumnya '
                        '(retry aman).',
                        style: TextStyle(
                            fontSize: 11, color: textSecondary)),
                ],
              ),
            ),
            const Divider(height: 24),
            for (final item in receipt.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.qty}× ${item.productName}'
                        '${item.modifiers.isNotEmpty ? ' (${item.modifiers.map((m) => m['name']).join(', ')})' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(formatRupiah(item.lineTotal),
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            const Divider(height: 20),
            _row(context, 'Metode', receipt.method ?? '-'),
            _row(context, 'Diterima', formatRupiah(receipt.paid ?? 0)),
            _row(context, 'Kembalian',
                formatRupiah(receipt.changeAmount ?? 0)),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Selesai'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: textSecondary))),
            Text(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: warningColor),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ],
      ),
    );
  }
}
