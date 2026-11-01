import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../../core/models/catalog_models.dart';
import '../catalog/catalog_repository.dart';
import '../pos/pos_repository.dart';
import '../tables_qr/tables_repository.dart';

/// Form pesanan manual (migrasi 0022) — tab Pesanan → [Buat Pesanan].
///
/// Operator menulis pesanan atas nama pelanggan (walk-in / telepon / di
/// meja tanpa scan QR): nama + WA opsional + pilih meja + pilih menu
/// (varian, qty, catatan). Pesanan lahir langsung kolom **Diterima**.
///
/// Uang jujur: item dikirim dengan bentuk `CartLine.toRpc()`; harga &
/// subtotal dihitung ulang SERVER lewat `pos_line_total` (snapshot), dan
/// total final tetap dari `pos_checkout` saat operator membayar.
Future<void> showCreateOrderSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CreateOrderSheet(),
    );

/// Tambah item pesanan aktif ("minta lagi", migrasi 0022): pemilih menu
/// yang sama tanpa isian nama/meja; server menolak draft non-aktif.
Future<void> showAddItemsSheet(BuildContext context, QrDraft draft) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AddItemsSheet(draft: draft),
    );

// ---------------------------------------------------------------------------
// Sheet buat pesanan manual
// ---------------------------------------------------------------------------

class _CreateOrderSheet extends ConsumerStatefulWidget {
  const _CreateOrderSheet();

  @override
  ConsumerState<_CreateOrderSheet> createState() => _CreateOrderSheetState();
}

class _CreateOrderSheetState extends ConsumerState<_CreateOrderSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _lines = <CartLine>[];
  int? _tableId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _subtotal => _lines.fold(0, (sum, l) => sum + l.lineTotal);

  bool get _canSubmit =>
      !_submitting &&
      _name.text.trim().isNotEmpty &&
      _tableId != null &&
      _lines.isNotEmpty;

  void _addLine(CartLine line) {
    setState(() {
      final idx = _lines.indexWhere((l) => l.sameAs(line));
      if (idx >= 0) {
        final old = _lines[idx];
        _lines[idx] = old.copyWith(qty: old.qty + line.qty);
      } else {
        _lines.add(line);
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final draft = await ref
          .read(qrDraftRepositoryProvider)
          .createManualOrder(
            tableId: _tableId!,
            customerName: _name.text.trim(),
            customerPhone: _phone.text.trim().isEmpty
                ? null
                : _phone.text.trim(),
            items: _lines.map((l) => l.toRpc()).toList(),
          );
      ref.invalidate(qrDraftsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pesanan ${draft.refCode} atas nama ${draft.customerName} dibuat '
            '— masuk kolom Diterima.',
          ),
        ),
      );
    } catch (e) {
      // Key tidak berubah; retry mengirim ulang id yang sama (server atomik).
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = mapErrorToMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(tablesListProvider);
    final tables = (tablesAsync.value ?? [])
        .where((t) => t.isEnabled)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buat Pesanan',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Pesanan manual (tanpa scan QR) — langsung masuk Diterima.',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama pesanan *',
                  hintText: 'mis. Bu Rina / Meja depan',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'No. HP / WA (opsional)',
                  hintText: 'mis. 628123456789',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey(_tableId),
                initialValue: _tableId,
                decoration: const InputDecoration(
                  labelText: 'Meja *',
                  isDense: true,
                ),
                items: [
                  for (final t in tables)
                    DropdownMenuItem(value: t.id, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _tableId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Menu dipesan',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Tambah menu'),
                    onPressed: () => _pickProduct(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada menu. Tekan [Tambah menu].',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                ),
              for (final line in _lines)
                _lineRow(line),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Perkiraan subtotal',
                      style: TextStyle(fontSize: 13, color: textSecondary),
                    ),
                  ),
                  Text(
                    formatRupiah(_subtotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: brandPrimary,
                    ),
                  ),
                ],
              ),
              const Text(
                'Harga dikunci server saat pesanan dibuat; total final '
                'dihitung saat pembayaran.',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: errorColor)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(_submitting ? 'Membuat…' : 'Buat Pesanan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineRow(CartLine line) {
    final idx = _lines.indexOf(line);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Kurangi',
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            onPressed: () => setState(() {
              if (line.qty > 1) {
                _lines[idx] = line.copyWith(qty: line.qty - 1);
              } else {
                _lines.removeAt(idx);
              }
            }),
          ),
          Text('${line.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Tambah',
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            onPressed: () => setState(() {
              _lines[idx] = line.copyWith(qty: line.qty + 1);
            }),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              [
                line.productName,
                if (line.modifiers.isNotEmpty)
                  line.modifiers
                      .map((m) => m['name'] as String? ?? '')
                      .join(', '),
                if (line.note.isNotEmpty) line.note,
              ].join(' · '),
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatRupiah(line.lineTotal),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Hapus menu',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _lines.removeAt(idx)),
          ),
        ],
      ),
    );
  }

  /// Pilih produk: langsung masuk bila tanpa varian; kalau ada varian/
  /// topping, buka sheet pemilihan (pola sama dengan Kasir POS).
  Future<void> _pickProduct(BuildContext context) async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ProductPickerSheet(),
    );
    if (product == null || !context.mounted) return;
    if (product.modifiers.isEmpty) {
      _addLine(
        CartLine(
          productId: product.id,
          productName: product.name,
          basePrice: product.price,
        ),
      );
      return;
    }
    final line = await showModalBottomSheet<CartLine>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _VariantSheet(product: product),
    );
    if (line != null) _addLine(line);
  }
}

// ---------------------------------------------------------------------------
// Sheet tambah item pesanan aktif ("minta lagi")
// ---------------------------------------------------------------------------

class _AddItemsSheet extends ConsumerStatefulWidget {
  const _AddItemsSheet({required this.draft});

  final QrDraft draft;

  @override
  ConsumerState<_AddItemsSheet> createState() => _AddItemsSheetState();
}

class _AddItemsSheetState extends ConsumerState<_AddItemsSheet> {
  final _lines = <CartLine>[];
  bool _submitting = false;
  String? _error;

  void _addLine(CartLine line) {
    setState(() {
      final idx = _lines.indexWhere((l) => l.sameAs(line));
      if (idx >= 0) {
        final old = _lines[idx];
        _lines[idx] = old.copyWith(qty: old.qty + line.qty);
      } else {
        _lines.add(line);
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(qrDraftRepositoryProvider)
          .addDraftItems(
            widget.draft.draftId,
            _lines.map((l) => l.toRpc()).toList(),
          );
      ref.invalidate(qrDraftsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_lines.length} menu ditambahkan ke ${updated.refCode} — '
            'subtotal kini ${formatRupiah(updated.subtotal)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = mapErrorToMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _lines.fold(0, (sum, l) => sum + l.lineTotal);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tambah item — ${widget.draft.refCode}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${widget.draft.tableLabel} · ${widget.draft.customerName ?? 'Tanpa nama'}',
                style: const TextStyle(fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah menu'),
                onPressed: () => _pickProduct(context),
              ),
              const SizedBox(height: 6),
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada menu tambahan.',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                ),
              for (final line in _lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Kurangi',
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(() {
                          final idx = _lines.indexOf(line);
                          if (line.qty > 1) {
                            _lines[idx] = line.copyWith(qty: line.qty - 1);
                          } else {
                            _lines.removeAt(idx);
                          }
                        }),
                      ),
                      Text(
                        '${line.qty}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Tambah',
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(() {
                          final idx = _lines.indexOf(line);
                          _lines[idx] = line.copyWith(qty: line.qty + 1);
                        }),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            line.productName,
                            if (line.modifiers.isNotEmpty)
                              line.modifiers
                                  .map((m) => m['name'] as String? ?? '')
                                  .join(', '),
                            if (line.note.isNotEmpty) line.note,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formatRupiah(line.lineTotal),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hapus menu',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () =>
                            setState(() => _lines.remove(line)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: errorColor)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _lines.isNotEmpty && !_submitting
                      ? _submit
                      : null,
                  child: Text(
                    _submitting
                        ? 'Menyimpan…'
                        : _lines.isEmpty
                        ? 'Pilih menu dulu'
                        : 'Tambah ${_lines.length} menu '
                              '(${formatRupiah(subtotal)})',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickProduct(BuildContext context) async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ProductPickerSheet(),
    );
    if (product == null || !context.mounted) return;
    if (product.modifiers.isEmpty) {
      _addLine(
        CartLine(
          productId: product.id,
          productName: product.name,
          basePrice: product.price,
        ),
      );
      return;
    }
    final line = await showModalBottomSheet<CartLine>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _VariantSheet(product: product),
    );
    if (line != null) _addLine(line);
  }
}

// ---------------------------------------------------------------------------
// Pemilih produk (menu aktif + pencarian)
// ---------------------------------------------------------------------------

class _ProductPickerSheet extends ConsumerStatefulWidget {
  const _ProductPickerSheet();

  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cari menu',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    mapErrorToMessage(e),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (products) {
                final sellable = products
                    .where(
                      (p) =>
                          p.sellable &&
                          (_query.isEmpty ||
                              p.name.toLowerCase().contains(_query)),
                    )
                    .toList();
                if (sellable.isEmpty) {
                  return const Center(
                    child: Text(
                      'Tidak ada menu cocok.',
                      style: TextStyle(color: textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: sellable.length,
                  itemBuilder: (context, i) {
                    final p = sellable[i];
                    return ListTile(
                      dense: true,
                      title: Text(p.name),
                      subtitle: p.modifiers.isNotEmpty
                          ? const Text(
                              'Ada varian',
                              style: TextStyle(fontSize: 11),
                            )
                          : null,
                      trailing: Text(
                        formatRupiah(p.price),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: brandPrimary,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet varian (modifier + qty + catatan) — pola sama dengan Kasir POS
// ---------------------------------------------------------------------------

class _VariantSheet extends ConsumerStatefulWidget {
  const _VariantSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends ConsumerState<_VariantSheet> {
  final Set<int> _selected = {};
  int _qty = 1;
  final _note = TextEditingController();

  Product get product => widget.product;

  int get _minRequired =>
      product.modifiers.fold(0, (sum, m) => sum + m.minSelect);
  int get _maxAllowed =>
      product.modifiers.fold(0, (sum, m) => sum + m.maxSelect);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chosen = product.modifiers
        .where((m) => _selected.contains(m.id))
        .toList();
    final delta = chosen.fold<int>(0, (sum, m) => sum + m.priceDelta);
    final canAdd =
        _selected.length >= _minRequired && _selected.length <= _maxAllowed;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              formatRupiah(product.price),
              style: const TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 12),
            for (final m in product.modifiers)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('${m.name} (+${formatRupiah(m.priceDelta)})'),
                subtitle: m.minSelect > 0
                    ? Text(
                        'Pilih minimal ${m.minSelect}',
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
                value: _selected.contains(m.id),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      if (_selected.length < _maxAllowed) {
                        _selected.add(m.id);
                      }
                    } else {
                      _selected.remove(m.id);
                    }
                  });
                },
              ),
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
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
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
                      ? () => Navigator.pop(
                          context,
                          CartLine(
                            productId: product.id,
                            productName: product.name,
                            basePrice: product.price,
                            qty: _qty,
                            note: _note.text.trim(),
                            modifierIds: chosen.map((m) => m.id).toList(),
                            modifiers: [
                              for (final m in chosen)
                                {
                                  'id': m.id,
                                  'name': m.name,
                                  'price_delta': m.priceDelta,
                                },
                            ],
                          ),
                        )
                      : null,
                  child: Text(
                    'Tambah (${formatRupiah((product.price + delta) * _qty)})',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
