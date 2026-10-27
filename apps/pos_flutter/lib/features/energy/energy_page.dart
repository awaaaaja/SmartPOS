import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../core/formatters.dart';
import '../operating_cost/operating_repository.dart';

/// S05-01/02: kalkulator energi interaktif. Pratinjau live kWh/biaya per
/// porsi memakai rumus murni klien; saat "Simpan sebagai Estimasi" server
/// menghitung ulang dan hasilnya selalu menjadi expense ESTIMATED —
/// asumsi tidak pernah berubah menjadi biaya aktual diam-diam.
class EnergyPage extends ConsumerStatefulWidget {
  const EnergyPage({super.key});

  @override
  ConsumerState<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends ConsumerState<EnergyPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  // Listrik (asumsi wajar: 800 W, 3 jam, 80%, tarif 1.500 Rp/kWh).
  final _watt = TextEditingController(text: '800');
  final _hours = TextEditingController(text: '3');
  final _load = TextEditingController(text: '80');
  final _tariff = TextEditingController(text: '1500');

  // LPG (isi ulang 3 kg ≈ Rp 22.000, tabung ≈ 20 jam nyala).
  final _refill = TextEditingController(text: '22000');
  final _effHours = TextEditingController(text: '20');
  final _batchHours = TextEditingController(text: '2.5');

  final _portions = TextEditingController(text: '10');
  final _note = TextEditingController();
  bool _saving = false;
  EnergyEstimate? _last;

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _watt, _hours, _load, _tariff, _refill, _effHours, _batchHours,
      _portions, _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save(bool isElectric) async {
    final portions = int.tryParse(_portions.text.trim());
    if (portions == null || portions <= 0) {
      _toast('Jumlah porsi valid wajib diisi.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref.read(operatingRepositoryProvider).saveEnergyEstimate(
            kind: isElectric ? 'ELECTRICITY' : 'LPG',
            watt: isElectric ? _num(_watt) : null,
            hours: isElectric ? _num(_hours) : null,
            loadFactor: isElectric ? _num(_load) : null,
            tariff: isElectric ? _num(_tariff) : null,
            refillPrice: isElectric ? null : int.tryParse(_refill.text.trim()),
            effectiveHours: isElectric ? null : _num(_effHours),
            batchHours: isElectric ? null : _num(_batchHours),
            portions: portions,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (!mounted) return;
      setState(() => _last = result);
      ref.invalidate(expensesProvider);
      _toast('Estimasi tersimpan sebagai biaya ESTIMATED '
          '${formatRupiah(result.cost)} (bukan biaya aktual).');
    } catch (e) {
      if (mounted) _toast(mapErrorToMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Kalkulator Energi', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Estimasi listrik dan LPG per batch. Angka akhir dihitung ulang '
              'server; hasil selalu dicatat sebagai ESTIMATED, bukan tagihan '
              'nyata.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TabBar(
              controller: _tabs,
              labelColor: brandPrimary,
              unselectedLabelColor: theme.hintColor,
              indicatorColor: brandPrimary,
              tabs: const [
                Tab(icon: Icon(Icons.bolt_rounded), text: 'Listrik'),
                Tab(icon: Icon(Icons.local_fire_department_rounded), text: 'LPG'),
              ],
            ),
          ),
          Expanded(
          child: TabBarView(
              controller: _tabs,
              children: [
                _electricForm(theme),
                _lpgForm(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _electricForm(ThemeData theme) {
    final watt = _num(_watt) ?? 0;
    final hours = _num(_hours) ?? 0;
    final load = _num(_load) ?? 0;
    final tariff = _num(_tariff) ?? 0;
    final portions = int.tryParse(_portions.text.trim()) ?? 0;
    final valid = watt > 0 && hours > 0 && load > 0 && load <= 100 &&
        tariff >= 0 && portions > 0;
    final kwh = valid ? EnergyCalculator.kwh(
        watt: watt, hours: hours, loadFactor: load) : 0.0;
    final cost = valid
        ? EnergyCalculator.electricityCost(
            watt: watt, hours: hours, loadFactor: load, tariff: tariff)
        : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _resultCard(
          theme,
          title: 'Pratinjau estimasi listrik',
          rows: [
            ('Konsumsi', '${kwh.toStringAsFixed(3)} kWh'),
            ('Biaya estimasi', formatRupiah(cost)),
            if (portions > 0)
              ('Biaya per porsi',
                  formatRupiah(EnergyCalculator.costPerPortion(cost, portions))),
          ],
          note: valid
              ? 'kWh = (W x jam x load% ÷ 100) ÷ 1000; biaya = kWh x tarif. '
                  'Jika meter listrik gabung rumah, isi hanya porsi pemakaian '
                  'usaha.'
              : 'Isi semua kolom dengan benar untuk melihat pratinjau.',
        ),
        const SizedBox(height: 12),
        _field(_watt, 'Daya (W)', Icons.bolt_rounded),
        _field(_hours, 'Durasi pemakaian (jam)', Icons.schedule_rounded),
        _field(_load, 'Faktor beban (%)', Icons.speed_rounded),
        _field(_tariff, 'Tarif (Rp/kWh)', Icons.payments_rounded),
        _portionsField(),
        _noteField(),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(true),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
          label: const Text('Simpan sebagai Biaya Estimasi'),
        ),
        if (_last != null && _last!.kind == 'ELECTRICITY') ...[
          const SizedBox(height: 8),
          Text(
            'Tersimpan: ${_last!.kwh?.toStringAsFixed(3)} kWh → '
            '${formatRupiah(_last!.cost)} ESTIMATED, '
            '${formatRupiah(_last!.costPerPortion)} per porsi '
            '(nilai server).',
            style: theme.textTheme.bodySmall?.copyWith(color: successColor),
          ),
        ],
      ],
    );
  }

  Widget _lpgForm(ThemeData theme) {
    final refill = int.tryParse(_refill.text.trim()) ?? 0;
    final eff = _num(_effHours) ?? 0;
    final batch = _num(_batchHours) ?? 0;
    final portions = int.tryParse(_portions.text.trim()) ?? 0;
    final valid = refill >= 0 && eff > 0 && batch >= 0 && portions > 0;
    final cost = valid
        ? EnergyCalculator.lpgCost(
            refillPrice: refill, effectiveHours: eff, batchHours: batch)
        : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _resultCard(
          theme,
          title: 'Pratinjau estimasi LPG',
          rows: [
            ('Biaya per jam nyala',
                formatRupiah(eff > 0 ? (refill / eff).round() : 0)),
            ('Biaya batch ${batch.toStringAsFixed(1)} jam',
                formatRupiah(cost)),
            if (portions > 0)
              ('Biaya per porsi',
                  formatRupiah(EnergyCalculator.costPerPortion(cost, portions))),
          ],
          note: valid
              ? 'Biaya = (isi ulang ÷ jam efektif tabung) x jam batch.'
              : 'Isi semua kolom dengan benar untuk melihat pratinjau.',
        ),
        const SizedBox(height: 12),
        _field(_refill, 'Harga isi ulang tabung (Rp)', Icons.local_gas_station_rounded),
        _field(_effHours, 'Jam efektif per tabung (jam)', Icons.hourglass_bottom_rounded),
        _field(_batchHours, 'Durasi batch (jam)', Icons.timer_rounded),
        _portionsField(),
        _noteField(),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(false),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
          label: const Text('Simpan sebagai Biaya Estimasi'),
        ),
        if (_last != null && _last!.kind == 'LPG') ...[
          const SizedBox(height: 8),
          Text(
            'Tersimpan: ${formatRupiah(_last!.cost)} ESTIMATED, '
            '${formatRupiah(_last!.costPerPortion)} per porsi (nilai server).',
            style: theme.textTheme.bodySmall?.copyWith(color: successColor),
          ),
        ],
      ],
    );
  }

  Widget _resultCard(
    ThemeData theme, {
    required String title,
    required List<(String, String)> rows,
    required String note,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: theme.textTheme.bodyMedium),
                      Text(value,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: brandPrimary)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(note, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );

  Widget _field(TextEditingController c, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _portionsField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _portions,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Jumlah porsi valid',
            prefixIcon: Icon(Icons.restaurant_rounded),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _noteField() => TextField(
        controller: _note,
        decoration: const InputDecoration(
          labelText: 'Catatan (opsional)',
          prefixIcon: Icon(Icons.notes_rounded),
          border: OutlineInputBorder(),
        ),
      );
}
