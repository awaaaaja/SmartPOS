import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../inventory/inventory_repository.dart';

/// S04-04/S04-07: Resep & HPP. Pilih menu -> tampil status resep jujur
/// ("resep belum ada"), versi aktif, takaran per bahan, yield per batch,
/// dan HPP per porsi dari unit cost. Simpan perubahan selalu jadi versi
/// baru (jejak biaya telusur). Produk BATCH bisa mencatat produksi batch.
class RecipesHppPage extends ConsumerStatefulWidget {
  const RecipesHppPage({super.key});

  @override
  ConsumerState<RecipesHppPage> createState() => _RecipesHppPageState();
}

class _RecipesHppPageState extends ConsumerState<RecipesHppPage> {
  int? _selectedProductId;

  Future<void> _refresh(int productId) async {
    ref.invalidate(hppProvider(productId));
    ref.invalidate(recipeVersionsProvider(productId));
    ref.invalidate(ingredientsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(recipeProductsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text('Resep & HPP',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _selectedProductId == null
                      ? null
                      : () => _editRecipe(_selectedProductId!),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Simpan resep baru'),
                ),
              ],
            ),
          ),
          Expanded(
            child: products.when(
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
                      onPressed: () => ref.invalidate(recipeProductsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      'Belum ada menu aktif. Tambahkan menu di '
                      'katalog dahulu.',
                      style: TextStyle(color: textSecondary),
                    ),
                  );
                }
                final selected = _selectedProductId == null
                    ? null
                    : rows
                        .where((p) => p.id == _selectedProductId)
                        .firstOrNull;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Daftar menu (kiri).
                    SizedBox(
                      width: 260,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 0, 24),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final p = rows[i];
                          final active = p.id == _selectedProductId;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: active ? brandSoft : null,
                            child: ListTile(
                              dense: true,
                              selected: active,
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${formatRupiah(p.price)} • '
                                '${p.stockMode == 'BATCH'
                                    ? 'pre-made per batch'
                                    : 'make-to-order'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () => setState(
                                  () => _selectedProductId = p.id),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Detail HPP (kanan).
                    Expanded(
                      child: selected == null
                          ? const Center(
                              child: Text(
                                'Pilih menu di sebelah kiri untuk melihat '
                                'resep dan HPP.',
                                style: TextStyle(color: textSecondary),
                              ),
                            )
                          : _HppDetail(
                              key: ValueKey(selected.id),
                              product: selected,
                              onEdit: () => _editRecipe(selected.id),
                              onBatch: selected.stockMode == 'BATCH'
                                  ? () => _produceBatch(selected)
                                  : null,
                              onChanged: () => _refresh(selected.id),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editRecipe(int productId) async {
    final ingredients = await ref.read(ingredientsProvider.future);
    if (!context.mounted) return;
    if (ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tambahkan bahan dulu di halaman Stok Bahan.')),
      );
      return;
    }

    final yieldController = TextEditingController(text: '1');
    final lines = [
      _RecipeLine(ingredientId: ingredients.first.id, qty: '')
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Simpan resep (versi baru)'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: yieldController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Yield per batch (porsi)',
                      helperText:
                          'Takaran di bawah adalah kebutuhan SATU batch '
                          'utuh; HPP dibagi yield.',
                      isDense: true,
                    ),
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
                                        child: Text(
                                            '${e.name} (${e.baseUnit})',
                                            overflow:
                                                TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (v) => setLocal(() =>
                                  lines[i].ingredientId =
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
                              decoration: const InputDecoration(
                                labelText: 'Takaran',
                                isDense: true,
                              ),
                              onChanged: (v) =>
                                  setLocal(() => lines[i].qty = v),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: lines.length == 1
                                ? null
                                : () =>
                                    setLocal(() => lines.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => setLocal(() => lines.add(_RecipeLine(
                        ingredientId: ingredients.first.id, qty: ''))),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah bahan'),
                  ),
                  Text(
                    'Versi lama tetap tersimpan untuk jejak HPP.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
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
                child: const Text('Simpan versi')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(inventoryRepositoryProvider).saveRecipe(
            productId: productId,
            yieldQty:
                double.tryParse(yieldController.text.trim()) ?? 1,
            items: [
              for (final l in lines)
                {
                  'ingredient_id': l.ingredientId,
                  'qty': double.tryParse(l.qty.trim()) ?? 0,
                },
            ],
          );
      await _refresh(productId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Resep tersimpan sebagai versi terbaru.')),
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

  Future<void> _produceBatch(RecipeProduct product) async {
    final qtyController = TextEditingController(text: '1');
    final noteController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Produksi batch — ${product.name}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: qtyController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Jumlah yang dihasilkan (porsi)',
                  helperText:
                      'Bahan dipotong di sini; penjualan tidak '
                      'memotong lagi.',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Catat produksi')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(inventoryRepositoryProvider).produceBatch(
            productId: product.id,
            qtyProduced:
                double.tryParse(qtyController.text.trim()) ?? 0,
            note: noteController.text.trim().isEmpty
                ? null
                : noteController.text.trim(),
          );
      await _refresh(product.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Batch tercatat; bahan terpotong sekali.')),
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
}

class _RecipeLine {
  _RecipeLine({required this.ingredientId, required this.qty});
  int ingredientId;
  String qty;
}

/// Detail satu menu: status resep, tabel bahan + biaya, HPP per porsi,
/// margin dari komponen berdata saja, dan riwayat versi.
class _HppDetail extends ConsumerWidget {
  const _HppDetail({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onBatch,
    required this.onChanged,
  });

  final RecipeProduct product;
  final VoidCallback onEdit;
  final VoidCallback? onBatch;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hpp = ref.watch(hppProvider(product.id));
    final versions = ref.watch(recipeVersionsProvider(product.id));

    return hpp.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(mapErrorToMessage(e), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref.invalidate(hppProvider(product.id)),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
      data: (data) {
        if (!data.hasRecipe) {
          // Status jujur: tanpa resep aktif tidak ada klaim stok (S04-07).
          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 48, color: Colors.grey.shade500),
                    const SizedBox(height: 12),
                    Text('resep belum ada',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                      'Menu ini dijual tanpa perhitungan stok bahan. '
                      'Stok bahan TIDAK dipotong otomatis dan HPP belum '
                      'dapat dihitung sampai resep aktif dibuat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Buat resep pertama'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final hppPer = data.hppPerPortion ?? 0;
        final margin = product.price - hppPer.round();
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 20, 24),
          children: [
            // Ringkasan atas.
            Row(
              children: [
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HPP per porsi',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: textSecondary)),
                          Text(formatRupiah(hppPer.round()),
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: brandPrimary)),
                          const SizedBox(height: 4),
                          Text(
                            'Versi ${data.version} • yield '
                            '${formatNumber(data.yieldQty ?? 1)} porsi/batch',
                            style: const TextStyle(
                                fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Margin per porsi',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: textSecondary)),
                          Text(formatRupiah(margin),
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: margin >= 0
                                        ? successColor
                                        : errorColor,
                                  )),
                          const SizedBox(height: 4),
                          Text(
                            'Harga jual ${formatRupiah(product.price)} '
                            '− HPP (komponen berdata)',
                            style: const TextStyle(
                                fontSize: 12, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (onBatch != null) ...[
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: onBatch,
                    icon: const Icon(Icons.factory_rounded),
                    label: const Text('Produksi batch'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Tabel bahan.
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Biaya bahan per batch (versi aktif)',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    DataTable(
                      columnSpacing: 24,
                      horizontalMargin: 0,
                      columns: const [
                        DataColumn(label: Text('Bahan')),
                        DataColumn(label: Text('Takaran'), numeric: true),
                        DataColumn(label: Text('Biaya/satuan'), numeric: true),
                        DataColumn(label: Text('Biaya'), numeric: true),
                      ],
                      rows: [
                        for (final it in data.items)
                          DataRow(cells: [
                            DataCell(Text(it.name)),
                            DataCell(Text(
                                '${formatNumber(it.qty)} ${it.baseUnit}')),
                            DataCell(Text(formatRupiah(it.unitCost))),
                            DataCell(Text(formatRupiah(it.cost))),
                          ]),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Jumlah per batch '
                          '${formatNumber(data.yieldQty ?? 1)} porsi',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          formatRupiah(data.items.fold<int>(
                              0, (sum, it) => sum + it.cost)),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Riwayat versi.
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Riwayat versi resep',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    versions.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(8),
                        child: LinearProgressIndicator(),
                      ),
                      error: (e, _) => Text(mapErrorToMessage(e)),
                      data: (rows) => Column(
                        children: [
                          for (final v in rows)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                v.isActive
                                    ? Icons.check_circle_rounded
                                    : Icons.history_rounded,
                                color: v.isActive
                                    ? successColor
                                    : textSecondary,
                              ),
                              title: Text(
                                'Versi ${v.version} — yield '
                                '${formatNumber(v.yieldQty)} porsi',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${formatWib(v.createdAt)}'
                                '${v.isActive ? ' • aktif' : ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
