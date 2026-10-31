import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../../core/models/catalog_models.dart';
import 'catalog_repository.dart';

const _chipStyle = TextStyle(fontSize: 12);

/// S02-01/02/03: CRUD kategori, menu, foto, varian/topping, status
/// tersedia/habis, arsip (dengan un-arsip), dan riwayat harga.
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  /// false = tab Aktif (produk tanpa arsip), true = tab Arsip.
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(catalogProductsProvider);
    final filtered = products.maybeWhen(
      data: (items) => AsyncData(
        items.where((p) => p.isArchived == _showArchived).toList(),
      ),
      orElse: () => products,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Menu & Harga',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Aktif')),
                    ButtonSegment(value: true, label: Text('Arsip')),
                  ],
                  selected: {_showArchived},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (v) =>
                      setState(() => _showArchived = v.first),
                ),
                OutlinedButton.icon(
                  onPressed: () => _manageCategories(context, ref),
                  icon: const Icon(Icons.category_rounded, size: 18),
                  label: const Text('Kategori'),
                ),
                FilledButton.icon(
                  onPressed: () => _editProduct(context, ref, null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Menu baru'),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorRetry(
                message: mapErrorToMessage(e),
                onRetry: () => ref.invalidate(catalogProductsProvider),
              ),
              data: (items) => items.isEmpty
                  ? (_showArchived
                        ? const _EmptyArchive()
                        : const _EmptyCatalog())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _ProductTile(product: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manageCategories(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: _CategorySheet(),
      ),
    );
    ref.invalidate(categoriesProvider);
    ref.invalidate(catalogCategoriesProvider);
  }

  static Future<void> _editProduct(
    BuildContext context,
    WidgetRef ref,
    Product? existing,
  ) async {
    final repo = ref.read(catalogRepositoryProvider);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(repository: repo, existing: existing),
    );
    if (saved == true) {
      ref.invalidate(productsProvider);
      ref.invalidate(catalogProductsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(catalogCategoriesProvider);
    }
  }

  /// Segarkan semua turunan katalog setelah mutasi arsip/restore.
  static void invalidateCatalog(WidgetRef ref) {
    ref.invalidate(productsProvider);
    ref.invalidate(catalogProductsProvider);
  }
}

class _ProductTile extends ConsumerStatefulWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends ConsumerState<_ProductTile> {
  Product get product => widget.product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _PhotoThumb(url: product.photoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (product.categoryName != null) product.categoryName!,
                      formatRupiah(product.price),
                      if (product.modifiers.isNotEmpty)
                        '${product.modifiers.length} varian/topping',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Riwayat harga',
              icon: const Icon(Icons.history_rounded),
              onPressed: _showPriceHistory,
            ),
            IconButton(
              tooltip: product.isActive ? 'Tandai habis' : 'Aktifkan',
              icon: Icon(
                product.isActive
                    ? Icons.toggle_on_rounded
                    : Icons.toggle_off_rounded,
              ),
              color: product.isActive ? successColor : textSecondary,
              onPressed: _toggleActive,
            ),
            IconButton(
              tooltip: 'Ubah',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => _CatalogPageState._editProduct(
                context,
                ref,
                product,
              ),
            ),
            if (product.isArchived)
              IconButton(
                tooltip: 'Keluarkan dari arsip',
                icon: const Icon(Icons.unarchive_rounded),
                onPressed: _restore,
              )
            else
              IconButton(
                tooltip: 'Arsipkan',
                icon: const Icon(Icons.archive_rounded),
                onPressed: _confirmArchive,
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip() {
    if (product.isArchived) {
      return const Chip(
        label: Text('Diarsipkan', style: _chipStyle),
        visualDensity: VisualDensity.compact,
        backgroundColor: Color(0xFFF3F0F1),
        side: BorderSide.none,
      );
    }
    if (!product.isActive) {
      return const Chip(
        label: Text('Habis', style: _chipStyle),
        visualDensity: VisualDensity.compact,
        backgroundColor: Color(0xFFFBF0E2),
        side: BorderSide.none,
      );
    }
    return const Chip(
      label: Text('Tersedia', style: _chipStyle),
      visualDensity: VisualDensity.compact,
      backgroundColor: Color(0xFFE5F3EB),
      side: BorderSide.none,
    );
  }

  Future<void> _toggleActive() async {
    try {
      await ref
          .read(catalogRepositoryProvider)
          .setProductActive(product.id, !product.isActive);
      _CatalogPageState.invalidateCatalog(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _confirmArchive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Arsipkan ${product.name}?'),
        content: const Text(
          'Menu disembunyikan dari POS dan QR. Riwayat penjualan dan '
          'harga tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arsipkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).archiveProduct(product.id);
      _CatalogPageState.invalidateCatalog(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _restore() async {
    try {
      await ref.read(catalogRepositoryProvider).restoreProduct(product.id);
      _CatalogPageState.invalidateCatalog(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  void _showPriceHistory() {
    final repo = ref.read(catalogRepositoryProvider);
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
              'Riwayat harga: ${product.name}',
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: FutureBuilder<List<PriceHistoryEntry>>(
                future: repo.fetchPriceHistory(product.id),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text(mapErrorToMessage(snap.error!)));
                  }
                  final entries = snap.data ?? const [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('Belum ada perubahan harga tercatat.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.swap_vert_rounded,
                          color: brandPrimary,
                        ),
                        title: Text(
                          '${formatRupiah(e.oldPrice)} → ${formatRupiah(e.newPrice)}',
                        ),
                        subtitle: Text(
                          formatWib(e.effectiveAt, withSeconds: true),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_menu_rounded, size: 48, color: brandSoft),
          SizedBox(height: 12),
          Text(
            'Belum ada menu.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Tambahkan menu pertama untuk mulai berjualan.',
            style: TextStyle(color: textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.archive_rounded, size: 48, color: brandSoft),
          SizedBox(height: 12),
          Text(
            'Arsip kosong.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Menu yang diarsipkan bisa dipulihkan dari sini.',
            style: TextStyle(color: textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: warningColor,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.restaurant_rounded, color: brandPrimary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        color: brandSoft,
        alignment: Alignment.center,
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                width: 52,
                height: 52,
                // Thumbnail 52 dp; foto asli tidak perlu didecode ukuran penuh.
                cacheWidth: 160,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet();

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(catalogCategoriesProvider);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Text(
          'Kelola kategori',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Nama kategori baru (mis. Minuman)',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _addCategory,
              child: const Text('Tambah'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...cats.when(
          loading: () => [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [Text(mapErrorToMessage(e))],
          data: (items) => [
            for (final c in items)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.label_rounded,
                  color: c.isArchived ? textSecondary : brandPrimary,
                ),
                title: Text(
                  c.name,
                  style: c.isArchived
                      ? const TextStyle(color: textSecondary)
                      : null,
                ),
                trailing: IconButton(
                  tooltip: c.isArchived
                      ? 'Keluarkan dari arsip'
                      : 'Arsipkan',
                  icon: Icon(
                    c.isArchived
                        ? Icons.unarchive_rounded
                        : Icons.archive_rounded,
                  ),
                  onPressed: () => _toggleArchive(c),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleArchive(ProductCategory c) async {
    try {
      final repo = ref.read(catalogRepositoryProvider);
      if (c.isArchived) {
        await repo.restoreCategory(c.id);
      } else {
        await repo.archiveCategory(c.id);
      }
      ref.invalidate(categoriesProvider);
      ref.invalidate(catalogCategoriesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    }
  }

  Future<void> _addCategory() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(catalogRepositoryProvider).createCategory(name);
      _controller.clear();
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog({required this.repository, required this.existing});

  final CatalogRepository repository;
  final Product? existing;

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  int? _categoryId;
  bool _isActive = true;
  String? _photoUrl;
  bool _uploading = false;
  bool _saving = false;
  List<Modifier> _allModifiers = [];
  List<Modifier> _attached = [];

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(text: p == null ? '' : '${p.price}');
    _categoryId = p?.categoryId;
    _isActive = p?.isActive ?? true;
    _photoUrl = p?.photoUrl;
    _attached = [...?p?.modifiers];
    _loadModifiers();
  }

  Future<void> _loadModifiers() async {
    try {
      final mods = await widget.repository.fetchModifiers();
      if (mounted) setState(() => _allModifiers = mods);
    } catch (_) {
      // Gagal memuat modifier global bukan penghalang simpan produk.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  bool _isAttached(Modifier m) => _attached.any((a) => a.id == m.id);

  void _setAttached(Modifier base, {int? minSelect, int? maxSelect}) {
    final idx = _attached.indexWhere((x) => x.id == base.id);
    if (idx < 0) return;
    final cur = _attached[idx];
    var min = minSelect ?? cur.minSelect;
    var max = maxSelect ?? cur.maxSelect;
    if (min > max) max = min;
    if (max < min) min = max;
    _attached[idx] = Modifier(
      id: cur.id,
      name: cur.name,
      priceDelta: cur.priceDelta,
      minSelect: min,
      maxSelect: max,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? 'Tambah menu' : 'Ubah ${existing.name}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama menu'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Nama wajib diisi'
                      : null,
                ),
                const SizedBox(height: 12),
                categories.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                    mapErrorToMessage(e),
                    style: const TextStyle(fontSize: 12),
                  ),
                  data: (cats) => DropdownButtonFormField<int>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Tanpa kategori'),
                      ),
                      for (final c in cats)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  decoration: const InputDecoration(
                    labelText: 'Harga jual (Rp)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 0) return 'Harga harus angka ≥ 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploading ? null : _pickAndUploadPhoto,
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_camera_rounded),
                        label: Text(
                          _photoUrl == null ? 'Pilih foto' : 'Ganti foto',
                        ),
                      ),
                    ),
                    if (_photoUrl != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Hapus foto',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _photoUrl = null),
                      ),
                    ],
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tersedia dijual'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
                const Divider(),
                Text(
                  'Varian / topping',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                if (_allModifiers.isEmpty)
                  const Text(
                    'Belum ada modifier global; biarkan kosong untuk menu '
                    'biasa.',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                for (final m in _allModifiers)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${m.name} (+${formatRupiah(m.priceDelta)})'),
                    value: _isAttached(m),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _attached.add(m);
                        } else {
                          _attached.removeWhere((a) => a.id == m.id);
                        }
                      });
                    },
                  ),
                if (_attached.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final a in _attached)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(a.name)),
                          const SizedBox(width: 8),
                          const Text('Min', style: TextStyle(fontSize: 12)),
                          SizedBox(
                            width: 56,
                            child: TextFormField(
                              initialValue: '${a.minSelect}',
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n >= 0) {
                                  setState(() => _setAttached(a, minSelect: n));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Maks', style: TextStyle(fontSize: 12)),
                          SizedBox(
                            width: 56,
                            child: TextFormField(
                              initialValue: '${a.maxSelect}',
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 13),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n >= 1) {
                                  setState(() => _setAttached(a, maxSelect: n));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (existing != null) ...[
                  const Divider(),
                  Text(
                    'Tambah modifier baru untuk produk ini',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _NewModifierForm(
                    onCreate: (name, delta) async {
                      final mod = await widget.repository.createModifier(
                        name,
                        delta,
                      );
                      setState(() {
                        _allModifiers = [..._allModifiers, mod];
                        _attached.add(mod);
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await widget.repository.uploadPhoto(File(picked.path));
      setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final price = int.parse(_price.text.trim());
      final saved = await widget.repository.upsertProduct(
        id: widget.existing?.id,
        name: _name.text,
        price: price,
        categoryId: _categoryId,
        photoUrl: _photoUrl,
        isActive: _isActive,
      );
      await widget.repository.setProductModifiers(saved.id, _attached);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mapErrorToMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _NewModifierForm extends StatefulWidget {
  const _NewModifierForm({required this.onCreate});

  final Future<void> Function(String name, int priceDelta) onCreate;

  @override
  State<_NewModifierForm> createState() => _NewModifierFormState();
}

class _NewModifierFormState extends State<_NewModifierForm> {
  final _name = TextEditingController();
  final _delta = TextEditingController(text: '0');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _delta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _name,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Nama (mis. Porsi Besar)',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _delta,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: '+Rp', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () async {
                  final name = _name.text.trim();
                  final delta = int.tryParse(_delta.text.trim()) ?? 0;
                  if (name.isEmpty) return;
                  setState(() => _busy = true);
                  try {
                    await widget.onCreate(name, delta);
                    _name.clear();
                    _delta.text = '0';
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(mapErrorToMessage(e))),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Buat'),
        ),
      ],
    );
  }
}
