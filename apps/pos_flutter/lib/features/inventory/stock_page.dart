import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import 'inventory_repository.dart';

/// S04-02: Stok Bahan. Daftar master bahan + saldo, pencarian, status
/// minimum, tambah/ubah, dan koreksi/waste yang selalu beralasan
/// (semua tulisan lewat RPC definer -> ledger tercatat).
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(ingredientsProvider);
    await ref.read(ingredientsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ingredients = ref.watch(ingredientsProvider);
    final search = ref.watch(ingredientSearchProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Stok Bahan',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _editIngredient(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Bahan baru'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Cari bahan…',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(ingredientSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: ingredients.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        mapErrorToMessage(e),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(ingredientsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? Center(
                      child: Text(
                        search.trim().isEmpty
                            ? 'Belum ada bahan terdaftar. Tekan '
                                  '“Bahan baru” untuk menambah master bahan.'
                            : 'Tidak ada bahan yang cocok dengan '
                                  '“${search.trim()}”.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: textSecondary),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _IngredientTile(ingredient: rows[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editIngredient([Ingredient? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final reorderController = TextEditingController(
      text: existing == null ? '' : formatNumber(existing.reorderLevel),
    );
    final costController = TextEditingController(
      text: '${existing?.unitCost ?? 0}',
    );
    var baseUnit = existing?.baseUnit ?? 'g';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Bahan baru' : 'Ubah bahan'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nama bahan'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: baseUnit,
                  decoration: const InputDecoration(labelText: 'Satuan dasar'),
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('gram (g)')),
                    DropdownMenuItem(
                      value: 'ml',
                      child: Text('mililiter (ml)'),
                    ),
                    DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                  ],
                  onChanged: existing == null
                      ? (v) => setLocal(() => baseUnit = v ?? 'g')
                      : null,
                ),
                if (existing != null)
                  Text(
                    'Satuan dasar tidak dapat diubah setelah bahan dibuat.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: reorderController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Batas minimum (stok opname)',
                    helperText: 'Contoh: 500 untuk 500 g',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: costController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Biaya per satuan dasar (Rp)',
                    helperText: 'Ikut terisi otomatis saat pembelian diterima',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref
          .read(inventoryRepositoryProvider)
          .saveIngredient(
            id: existing?.id,
            name: nameController.text.trim(),
            baseUnit: baseUnit,
            reorderLevel: double.tryParse(reorderController.text.trim()) ?? 0,
            unitCost: int.tryParse(costController.text.trim()) ?? 0,
          );
      ref.invalidate(ingredientsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bahan tersimpan.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  /// Koreksi (bertanda +/-) atau waste (selalu pengurangan) — wajib alasan.
  Future<void> _adjust(Ingredient ingredient) async {
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    var source = 'ADJUSTMENT';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Mutasi stok — ${ingredient.name}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo saat ini: ${formatNumber(ingredient.balance)} '
                  '${ingredient.baseUnit}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'ADJUSTMENT',
                      label: Text('Koreksi'),
                      icon: Icon(Icons.tune_rounded),
                    ),
                    ButtonSegment(
                      value: 'WASTE',
                      label: Text('Waste'),
                      icon: Icon(Icons.delete_sweep_rounded),
                    ),
                  ],
                  selected: {source},
                  onSelectionChanged: (s) => setLocal(() => source = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: source == 'WASTE'
                        ? 'Jumlah yang hilang (${ingredient.baseUnit})'
                        : 'Penyesuaian (tanda +/-, '
                              '${ingredient.baseUnit})',
                    helperText: source == 'WASTE'
                        ? 'Selalu mengurangi stok.'
                        : 'Contoh: -25 bila fisik lebih sedikit.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Alasan (wajib, min. 3 huruf)',
                    hintText: 'mis. stock opname, jatuh ke lantai',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Catat mutasi'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref
          .read(inventoryRepositoryProvider)
          .adjustStock(
            ingredientId: ingredient.id,
            qty: double.tryParse(qtyController.text.trim()) ?? 0,
            reason: reasonController.text.trim(),
            source: source,
          );
      ref.invalidate(ingredientsProvider);
      ref.invalidate(stockMovementsProvider(ingredient.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mutasi tercatat di ledger.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  void _showHistory(Ingredient ingredient) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mutasi — ${ingredient.name}',
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 340,
              // Consumer: watch harus terjadi saat build agar provider
              // ter-subscribe (watch langsung dari builder sheet tidak
              // memicu rebuild saat data siap — loading permanen).
              child: Consumer(
                builder: (context, ref, _) => ref
                    .watch(stockMovementsProvider(ingredient.id))
                    .when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text(mapErrorToMessage(e))),
                      data: (rows) => rows.isEmpty
                          ? const Center(
                              child: Text('Belum ada mutasi tercatat.'),
                            )
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final m = rows[i];
                                final up = m.qtyDelta > 0;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    up
                                        ? Icons.arrow_circle_up_rounded
                                        : Icons.arrow_circle_down_rounded,
                                    color: up ? successColor : warningColor,
                                  ),
                                  title: Text(m.reason),
                                  subtitle: Text(
                                    '${m.source} • '
                                    '${formatWib(m.createdAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${up ? '+' : ''}'
                                        '${formatNumber(m.qtyDelta)} '
                                        '${ingredient.baseUnit}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: up ? successColor : errorColor,
                                        ),
                                      ),
                                      Text(
                                        'sisa '
                                        '${formatNumber(m.balanceAfter)}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ing = ingredient;
    final status = ing.isOut
        ? 'HABIS'
        : ing.isLow
        ? 'DI BAWAH MINIMUM'
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: PopupMenuButton<String>(
        onSelected: (v) {
          final state = context.findAncestorStateOfType<_InventoryPageState>();
          if (v == 'edit') state?._editIngredient(ing);
          if (v == 'adjust') state?._adjust(ing);
          if (v == 'history') state?._showHistory(ing);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Ubah bahan')),
          PopupMenuItem(value: 'adjust', child: Text('Koreksi / Waste')),
          PopupMenuItem(value: 'history', child: Text('Riwayat mutasi')),
        ],
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
                        Flexible(
                          child: Text(
                            ing.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: ing.isOut ? errorColor : warningColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bat. minimum ${formatNumber(ing.reorderLevel)} '
                      '${ing.baseUnit} • biaya '
                      '${formatRupiah(ing.unitCost)}/${ing.baseUnit}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatNumber(ing.balance)} ${ing.baseUnit}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ing.isOut
                          ? errorColor
                          : ing.isLow
                          ? warningColor
                          : textPrimary,
                    ),
                  ),
                  const Text(
                    'tersedia',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
