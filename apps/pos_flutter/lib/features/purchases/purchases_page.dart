import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../inventory/inventory_repository.dart';

/// S04-03: Pembelian. Supplier opsional, bahan + qty (boleh kg/liter,
/// server konversi), harga, tanggal, status ORDERED/RECEIVED. Penerimaan
/// menambah saldo tepat sekali (guard status di server).
class PurchasesPage extends ConsumerWidget {
  const PurchasesPage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(purchasesProvider);
    ref.invalidate(ingredientsProvider);
    await ref.read(purchasesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final purchases = ref.watch(purchasesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text('Pembelian',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _createPurchase(context, ref),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Pembelian baru'),
                ),
              ],
            ),
          ),
          Expanded(
            child: purchases.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(mapErrorToMessage(e),
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(purchasesProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada pembelian tercatat. Tekan '
                        '“Pembelian baru” untuk mencatat belanja bahan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textSecondary),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _refresh(ref),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) => _PurchaseTile(
                          purchase: rows[i],
                          onReceive: () =>
                              _receive(context, ref, rows[i]),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _receive(
      BuildContext context, WidgetRef ref, Purchase purchase) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Terima pembelian #${purchase.id}?'),
        content: Text(
          'Saldo bahan bertambah tepat sekali senilai '
          '${formatRupiah(purchase.total)}. Penerimaan ganda '
          'ditolak server.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Terima')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await ref
          .read(inventoryRepositoryProvider)
          .receivePurchase(purchase.id);
      await _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pembelian diterima; stok bertambah.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapErrorToMessage(e))),
        );
      }
    }
  }

  /// Form pembelian multi-bahan. Satuan mengikuti satuan dasar bahan
  /// (dan kg/liter yang dikonversi server).
  Future<void> _createPurchase(BuildContext context, WidgetRef ref) async {
    final ingredients =
        await ref.read(ingredientsProvider.future);
    if (!context.mounted) return;
    if (ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tambahkan bahan dulu di halaman Stok Bahan.')),
      );
      return;
    }

    final supplierController = TextEditingController();
    final dateController = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
    var status = 'RECEIVED';
    final lines = [
      _LineState(ingredientId: ingredients.first.id, qty: '', price: '')
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Field "Total harga" = total baris (semantik server `total_price`);
          // jangan dikalikan qty lagi — unit cost = total / qty dihitung server.
          double lineTotal(_LineState l) =>
              (double.tryParse(l.price) ?? 0);
          final total =
              lines.fold<double>(0, (sum, l) => sum + lineTotal(l));
          String unitOf(int id) => ingredients
              .firstWhere((e) => e.id == id,
                  orElse: () => ingredients.first)
              .baseUnit;

          return AlertDialog(
            title: const Text('Pembelian baru'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: supplierController,
                      decoration: const InputDecoration(
                        labelText: 'Supplier (opsional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: dateController,
                            decoration: const InputDecoration(
                              labelText: 'Tanggal (YYYY-MM-DD)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'RECEIVED', label: Text('Terima')),
                            ButtonSegment(
                                value: 'ORDERED', label: Text('Pesanan')),
                          ],
                          selected: {status},
                          onSelectionChanged: (s) =>
                              setLocal(() => status = s.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: DropdownButtonFormField<int>(
                                initialValue: lines[i].ingredientId,
                                isExpanded: true,
                                items: ingredients
                                    .map((e) => DropdownMenuItem(
                                          value: e.id,
                                          child: Text(e.name,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: (v) => setLocal(
                                    () => lines[i].ingredientId =
                                        v ?? lines[i].ingredientId),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: lines[i].qty,
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText:
                                      'Qty (${unitOf(lines[i].ingredientId)})',
                                  isDense: true,
                                ),
                                onChanged: (v) =>
                                    setLocal(() => lines[i].qty = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                initialValue: lines[i].price,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Total harga (Rp)',
                                  isDense: true,
                                ),
                                onChanged: (v) =>
                                    setLocal(() => lines[i].price = v),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: lines.length == 1
                                  ? null
                                  : () => setLocal(() => lines.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => setLocal(() => lines.add(_LineState(
                          ingredientId: ingredients.first.id,
                          qty: '',
                          price: ''))),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah baris'),
                    ),
                    const Divider(),
                    Text(
                      'Total: ${formatRupiah(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      status == 'RECEIVED'
                          ? 'Stok langsung bertambah saat disimpan.'
                          : 'Belum menambah stok; terima lewat daftar '
                              'pembelian.',
                      style: const TextStyle(
                          fontSize: 12, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Simpan')),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;

    final items = <Map<String, dynamic>>[
      for (final l in lines)
        {
          'ingredient_id': l.ingredientId,
          'qty': double.tryParse(l.qty.trim()) ?? 0,
          'unit': unitFor(ingredients, l.ingredientId),
          'total_price': (double.tryParse(l.price.trim()) ?? 0).round(),
        },
    ];

    try {
      await ref.read(inventoryRepositoryProvider).createPurchase(
            supplier: supplierController.text.trim(),
            items: items,
            status: status,
            purchasedAt: DateTime.tryParse(dateController.text.trim()),
          );
      await _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(status == 'RECEIVED'
                  ? 'Pembelian tercatat; stok dan biaya diperbarui.'
                  : 'Pesanan tercatat; tunggu penerimaan.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapErrorToMessage(e))),
        );
      }
    }
  }

  static String unitFor(List<Ingredient> ingredients, int id) =>
      ingredients
          .firstWhere((e) => e.id == id,
              orElse: () => ingredients.first)
          .baseUnit;
}

class _LineState {
  _LineState({required this.ingredientId, required this.qty, required this.price});
  int ingredientId;
  String qty;
  String price;
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.purchase, required this.onReceive});

  final Purchase purchase;
  final VoidCallback onReceive;

  /// Tanggal pembelian hanya berupa tanggal (kolom date) — tampil apa adanya.
  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = purchase;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${p.id} • ${p.supplier ?? 'Tanpa supplier'}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.isReceived ? successColor : warningColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.isReceived ? 'DITERIMA' : 'PESANAN',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDate(p.purchasedAt)} • '
                    '${p.items.length} bahan',
                    style: const TextStyle(
                        fontSize: 12, color: textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.items
                        .map((l) =>
                            '${l.ingredientName} ${formatNumber(l.qty)}'
                            '${l.baseUnit}')
                        .join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatRupiah(p.total),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (!p.isReceived)
                  FilledButton.tonal(
                    onPressed: onReceive,
                    child: const Text('Terima'),
                  )
                else
                  const Text('stok +1x',
                      style: TextStyle(fontSize: 11, color: textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
