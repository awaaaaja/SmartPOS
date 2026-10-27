import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../../core/mutation_retry.dart';
import '../operating_cost/operating_repository.dart';

/// S05-03/04: pengeluaran operasional dengan penanda ESTIMATED vs ACTUAL
/// serta alokasi per sumber (total alokasi ≤ nominal, dicegah server).
class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  static const _types = [
    'LISTRIK',
    'LPG',
    'AIR',
    'KEMASAN',
    'SEWA',
    'INTERNET',
    'LAINNYA',
  ];

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(expensesProvider);
    await ref.read(expensesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expenses = ref.watch(expensesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Biaya Operasional',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        'Estimasi (asumsi) dan aktual (tagihan nyata) tidak '
                        'pernah digabung.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showEditor(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Biaya Baru'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: expenses.when(
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
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text(
                        'Belum ada biaya operasional.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _refresh(ref),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final e = list[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: e.isEstimated
                                    ? warningColor.withValues(alpha: 0.12)
                                    : successColor.withValues(alpha: 0.12),
                                child: Icon(
                                  e.isEstimated
                                      ? Icons.lightbulb_outline_rounded
                                      : Icons.receipt_long_rounded,
                                  color: e.isEstimated
                                      ? warningColor
                                      : successColor,
                                ),
                              ),
                              title: Text(e.description),
                              subtitle: Text(
                                '${e.type} · ${e.isEstimated ? 'ESTIMASI' : 'AKTUAL'}'
                                ' · ${formatWibDate(e.expenseDate.toUtc())}'
                                '${e.sourceRef != null ? ' · dari kalkulator' : ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatRupiah(e.amount),
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (v) {
                                      if (v == 'edit') {
                                        _showEditor(context, expense: e);
                                      } else {
                                        showModalBottomSheet<void>(
                                          context: context,
                                          isScrollControlled: true,
                                          builder: (_) => Padding(
                                            padding: EdgeInsets.only(
                                              bottom: MediaQuery.of(
                                                context,
                                              ).viewInsets.bottom,
                                            ),
                                            child: AllocationSheet(expense: e),
                                          ),
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Ubah biaya'),
                                      ),
                                      PopupMenuItem(
                                        value: 'allocate',
                                        child: Text('Alokasi biaya'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => _showEditor(context, expense: e),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, {Expense? expense}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ExpenseEditor(expense: expense),
      ),
    );
  }
}

class _ExpenseEditor extends ConsumerStatefulWidget {
  const _ExpenseEditor({this.expense});

  final Expense? expense;

  @override
  ConsumerState<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends ConsumerState<_ExpenseEditor> {
  final _formKey = GlobalKey<FormState>();
  late String _type = widget.expense?.type ?? 'LISTRIK';
  late String _kind = widget.expense?.kind ?? 'ACTUAL';
  late final _desc = TextEditingController(
    text: widget.expense?.description ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.expense == null ? '' : widget.expense!.amount.toString(),
  );
  late final _evidence = TextEditingController(
    text: widget.expense?.evidenceUrl ?? '',
  );
  late DateTime _date = widget.expense?.expenseDate ?? DateTime.now();
  bool _saving = false;
  bool _ready = false;
  PendingMutation? _pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final pending = widget.expense == null
          ? await ref.read(operatingRepositoryProvider).pendingExpense()
          : null;
      if (!mounted) return;
      if (pending != null) {
        final p = pending.params;
        _type = p['p_type'] as String;
        _kind = p['p_kind'] as String;
        _desc.text = p['p_description'] as String;
        _amount.text = '${p['p_amount']}';
        _evidence.text = p['p_evidence_url'] as String? ?? '';
        _date =
            DateTime.tryParse(p['p_expense_date'] as String? ?? '') ?? _date;
      }
      setState(() {
        _pending = pending;
        _ready = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _ready = false;
          _error = mapErrorToMessage(error);
        });
      }
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    _evidence.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_ready) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(operatingRepositoryProvider)
          .saveExpense(
            id: widget.expense?.id,
            type: _type,
            description: _desc.text.trim(),
            amount: int.parse(_amount.text.trim()),
            kind: _kind,
            expenseDate: _pending == null
                ? _date
                : DateTime.tryParse(
                    _pending!.params['p_expense_date'] as String? ?? '',
                  ),
            evidenceUrl: _pending == null
                ? _evidence.text.trim()
                : _pending!.params['p_evidence_url'] as String?,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(expensesProvider);
    } catch (e) {
      await _loadPending();
      if (mounted) {
        setState(() => _error = mapErrorToMessage(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editable = _ready && !_saving && _pending == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.expense == null ? 'Biaya Operasional Baru' : 'Ubah Biaya',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_type),
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Jenis',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in ExpensesPage._types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: editable
                  ? (v) => setState(() => _type = v ?? _type)
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _desc,
              enabled: editable,
              decoration: const InputDecoration(
                labelText: 'Keterangan',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Minimal 3 huruf' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _amount,
              enabled: editable,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nominal (Rp)',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n < 0) return 'Nominal tidak valid';
                return null;
              },
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'ACTUAL',
                  label: Text('AKTUAL'),
                  icon: Icon(Icons.receipt_long_rounded),
                ),
                ButtonSegment(
                  value: 'ESTIMATED',
                  label: Text('ESTIMASI'),
                  icon: Icon(Icons.lightbulb_outline_rounded),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: editable
                  ? (s) => setState(() => _kind = s.first)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              _kind == 'ACTUAL'
                  ? 'Aktual = tagihan/pengeluaran nyata.'
                  : 'Estimasi = asumsi operasional; jangan dipakai sebagai '
                        'bukti pembayaran.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _evidence,
              enabled: editable,
              decoration: const InputDecoration(
                labelText: 'URL bukti (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: !editable
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
              icon: const Icon(Icons.event_rounded),
              label: Text('Tanggal: ${formatWibDate(_date.toUtc())}'),
            ),
            if (_pending != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Permintaan sebelumnya belum terkonfirmasi. '
                'Ulangi biaya yang sama; jangan membuat biaya baru.',
              ),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: errorColor)),
            if (!_ready)
              TextButton(
                onPressed: _loadPending,
                child: const Text('Muat ulang permintaan'),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saving || !_ready ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _pending == null ? 'Simpan' : 'Ulangi biaya yang sama',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet alokasi biaya: target + nominal; server menolak total > sumber.
class AllocationSheet extends ConsumerStatefulWidget {
  const AllocationSheet({super.key, required this.expense});

  final Expense expense;

  @override
  ConsumerState<AllocationSheet> createState() => _AllocationSheetState();
}

class _AllocationSheetState extends ConsumerState<AllocationSheet> {
  final _target = TextEditingController();
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _target.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _allocate() async {
    final amount = int.tryParse(_amount.text.trim());
    final target = _target.text.trim();
    if (target.length < 2 || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target dan nominal tidak valid.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(operatingRepositoryProvider)
          .allocate(
            expenseId: widget.expense.id,
            targetRef: target,
            amount: amount,
          );
      _target.clear();
      _amount.clear();
      ref.invalidate(allocationsProvider(widget.expense.id));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = widget.expense.id;
    final allocations = ref.watch(allocationsProvider(id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Alokasi Biaya', style: theme.textTheme.titleLarge),
          Text(
            '${widget.expense.description} — sumber ${formatRupiah(widget.expense.amount)}. '
            'Total alokasi tidak boleh melebihi sumber (dicegah server).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          allocations.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(mapErrorToMessage(e)),
            data: (list) {
              final used = list.fold<int>(0, (n, a) => n + a.amount);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ter alokasi ${formatRupiah(used)} dari '
                    '${formatRupiah(widget.expense.amount)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final a in list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.targetRef),
                      trailing: Text(formatRupiah(a.amount)),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _target,
                    decoration: const InputDecoration(
                      labelText: 'Target (mis. batch-gorengan)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nominal alokasi (Rp)',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _allocate,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_split_rounded),
                    label: const Text('Alokasikan'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
