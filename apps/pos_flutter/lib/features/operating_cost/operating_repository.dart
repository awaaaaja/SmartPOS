import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/formatters.dart';
import '../../core/mutation_retry.dart';
import '../auth/auth_repository.dart';

/// Kalkulator energi (S05-01): rumus murni di sisi klien untuk pratinjau
/// live. Saat menyimpan, server menghitung ULANG rumus yang sama — angka
/// final selalu milik server (PRD §6.3).
class EnergyCalculator {
  const EnergyCalculator._();

  /// kWh = (watt x jam x faktor_beban%) / 100 / 1000.
  static double kwh({
    required double watt,
    required double hours,
    required double loadFactor,
  }) => (watt * hours * loadFactor / 100 / 1000);

  /// Biaya listrik = kWh x tarif (Rp/kWh), dibulatkan ke integer.
  static int electricityCost({
    required double watt,
    required double hours,
    required double loadFactor,
    required double tariff,
  }) =>
      (kwh(watt: watt, hours: hours, loadFactor: loadFactor) * tariff).round();

  /// Biaya LPG per batch = (isi ulang / jam efektif) x jam batch.
  static int lpgCost({
    required int refillPrice,
    required double effectiveHours,
    required double batchHours,
  }) => (refillPrice / effectiveHours * batchHours).round();

  /// Biaya per porsi = biaya batch / jumlah porsi valid.
  static int costPerPortion(int cost, int portions) =>
      portions <= 0 ? 0 : (cost / portions).round();
}

/// Hasil simpan estimasi energi dari server (angka final server).
class EnergyEstimate {
  const EnergyEstimate({
    required this.estimateId,
    required this.kind,
    required this.cost,
    required this.portions,
    required this.expenseId,
    this.kwh,
  });

  final int estimateId;
  final String kind;
  final int cost;
  final int portions;
  final int expenseId;
  final double? kwh;

  int get costPerPortion => EnergyCalculator.costPerPortion(cost, portions);

  factory EnergyEstimate.fromJson(Map<String, dynamic> j) => EnergyEstimate(
    estimateId: (j['estimate_id'] as num).toInt(),
    kind: j['kind'] as String,
    cost: (j['cost'] as num).toInt(),
    portions: (j['portions'] as num).toInt(),
    expenseId: (j['expense_id'] as num).toInt(),
    kwh: (j['kwh'] as num?)?.toDouble(),
  );
}

/// Satu baris biaya operasional (S05-03): ESTIMATED vs ACTUAL dipisah.
class Expense {
  const Expense({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.kind,
    required this.expenseDate,
    this.evidenceUrl,
    this.sourceRef,
  });

  final int id;
  final String type;
  final String description;
  final int amount;
  final String kind;
  final DateTime expenseDate;
  final String? evidenceUrl;
  final String? sourceRef;

  bool get isEstimated => kind == 'ESTIMATED';

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: (j['id'] as num).toInt(),
    type: j['type'] as String,
    description: j['description'] as String,
    amount: (j['amount'] as num).toInt(),
    kind: j['kind'] as String,
    expenseDate: DateTime.parse(j['expense_date'] as String),
    evidenceUrl: j['evidence_url'] as String?,
    sourceRef: j['source_ref'] as String?,
  );
}

/// Satu baris alokasi biaya (S05-04): total per sumber ≤ nominal sumber.
class CostAllocation {
  const CostAllocation({
    required this.id,
    required this.expenseId,
    required this.targetRef,
    required this.amount,
  });

  final int id;
  final int expenseId;
  final String targetRef;
  final int amount;

  factory CostAllocation.fromJson(Map<String, dynamic> j) => CostAllocation(
    id: (j['id'] as num).toInt(),
    expenseId: (j['expense_id'] as num).toInt(),
    targetRef: j['target_ref'] as String,
    amount: (j['amount'] as num).toInt(),
  );
}

/// Status kas shift (S05-05): expected dihitung server dari penjualan
/// TUNAI saja; transfer/QRIS tidak menambah uang fisik.
class CashShiftStatus {
  const CashShiftStatus({
    required this.isOpen,
    this.shiftId,
    this.openingCash = 0,
    this.cashSales = 0,
    this.expectedCash = 0,
    this.openedAt,
  });

  final bool isOpen;
  final int? shiftId;
  final int openingCash;
  final int cashSales;
  final int expectedCash;
  final DateTime? openedAt;

  factory CashShiftStatus.fromJson(Map<String, dynamic> j) => CashShiftStatus(
    isOpen: j['open'] == true,
    shiftId: (j['shift_id'] as num?)?.toInt(),
    openingCash: (j['opening_cash'] as num?)?.toInt() ?? 0,
    cashSales: (j['cash_sales'] as num?)?.toInt() ?? 0,
    expectedCash: (j['expected_cash'] as num?)?.toInt() ?? 0,
    openedAt: j['opened_at'] == null
        ? null
        : DateTime.parse(j['opened_at'] as String),
  );
}

/// Hasil tutup kas dengan selisih (boleh negatif).
class CashShiftResult {
  const CashShiftResult({
    required this.expectedCash,
    required this.actualCash,
    required this.variance,
  });

  final int expectedCash;
  final int actualCash;
  final int variance;

  factory CashShiftResult.fromJson(Map<String, dynamic> j) => CashShiftResult(
    expectedCash: (j['expected_cash'] as num).toInt(),
    actualCash: (j['actual_cash'] as num).toInt(),
    variance: (j['variance'] as num).toInt(),
  );
}

/// Deret harian tren (S05-07).
class ReportTrendPoint {
  const ReportTrendPoint({
    required this.day,
    required this.revenue,
    required this.tx,
  });

  final String day;
  final int revenue;
  final int tx;

  factory ReportTrendPoint.fromJson(Map<String, dynamic> j) => ReportTrendPoint(
    day: j['day'] as String,
    revenue: (j['revenue'] as num).toInt(),
    tx: (j['tx'] as num).toInt(),
  );
}

/// Menu terlaris pada rentang laporan.
class TopProduct {
  const TopProduct({
    required this.name,
    required this.qty,
    required this.revenue,
  });

  final String name;
  final int qty;
  final int revenue;

  factory TopProduct.fromJson(Map<String, dynamic> j) => TopProduct(
    name: j['name'] as String,
    qty: (j['qty'] as num).toInt(),
    revenue: (j['revenue'] as num).toInt(),
  );
}

/// Biaya per kategori, terpisah aktual vs estimasi.
class ExpenseByType {
  const ExpenseByType({
    required this.type,
    required this.actualAmount,
    required this.estimatedAmount,
  });

  final String type;
  final int actualAmount;
  final int estimatedAmount;

  factory ExpenseByType.fromJson(Map<String, dynamic> j) => ExpenseByType(
    type: j['type'] as String,
    actualAmount: (j['actual_amount'] as num).toInt(),
    estimatedAmount: (j['estimated_amount'] as num).toInt(),
  );
}

/// Laporan deskriptif (S05-07): BUKAN forecast/labu bersih. HPP bahan =
/// resep aktif x unit_cost terkini (estimasi, dilabeli jujur).
class ReportSummary {
  const ReportSummary({
    required this.from,
    required this.to,
    required this.netSales,
    required this.refunds,
    required this.transactions,
    required this.trend,
    required this.topProducts,
    required this.hppIngredientCost,
    required this.expensesActual,
    required this.expensesEstimated,
    required this.expensesActualPeriod,
    required this.expensesEstimatedPeriod,
    required this.expensesByType,
    required this.allocatedTotal,
  });

  final DateTime from;
  final DateTime to;
  final int netSales;
  final int refunds;
  final int transactions;
  final List<ReportTrendPoint> trend;
  final List<TopProduct> topProducts;
  final int hppIngredientCost;
  final int expensesActual;
  final int expensesEstimated;

  /// Biaya aktual/estimasi yang tanggalnya jatuh pada rentang laporan.
  final int expensesActualPeriod;
  final int expensesEstimatedPeriod;
  final List<ExpenseByType> expensesByType;
  final int allocatedTotal;

  /// Margin operasional sebelum tenaga kerja/susut — bukan laba bersih.
  int get operatingMarginEstimate =>
      netSales - hppIngredientCost - expensesActualPeriod;

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
    from: DateTime.parse(j['d_from'] as String),
    to: DateTime.parse(j['d_to'] as String),
    netSales: (j['net_sales'] as num).toInt(),
    refunds: (j['refunds'] as num).toInt(),
    transactions: (j['transactions'] as num).toInt(),
    trend: (j['trend'] as List)
        .map((e) => ReportTrendPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    topProducts: (j['top_products'] as List)
        .map((e) => TopProduct.fromJson(e as Map<String, dynamic>))
        .toList(),
    hppIngredientCost: (j['hpp_ingredient_cost'] as num).toInt(),
    expensesActual: (j['expenses_actual'] as num).toInt(),
    expensesEstimated: (j['expenses_estimated'] as num).toInt(),
    expensesActualPeriod: (j['expenses_actual_period'] as num).toInt(),
    expensesEstimatedPeriod: (j['expenses_estimated_period'] as num).toInt(),
    expensesByType: (j['expenses_by_type'] as List)
        .map((e) => ExpenseByType.fromJson(e as Map<String, dynamic>))
        .toList(),
    allocatedTotal: (j['allocated_total'] as num).toInt(),
  );
}

/// Repository operasional: semua tulisan lewat RPC definer (pola Sprint 04).
class OperatingRepository {
  OperatingRepository(this._client, this._retries);

  final SupabaseClient _client;
  final MutationRetryStore _retries;

  Future<PendingMutation?> pendingEnergyEstimate() => _retries.pending(
    _client.auth.currentUser?.id ?? '',
    'energy_save_estimate',
    0,
  );

  Future<EnergyEstimate> saveEnergyEstimate({
    required String kind,
    double? watt,
    double? hours,
    double? loadFactor,
    double? tariff,
    int? refillPrice,
    double? effectiveHours,
    double? batchHours,
    required int portions,
    String? note,
  }) => _retries.run(
    owner: _client.auth.currentUser?.id ?? '',
    operation: 'energy_save_estimate',
    target: 0,
    params: {
      'p_kind': kind,
      'p_watt': watt,
      'p_hours': hours,
      'p_load_factor': loadFactor,
      'p_tariff': tariff,
      'p_refill_price': refillPrice,
      'p_effective_hours': effectiveHours,
      'p_batch_hours': batchHours,
      'p_portions': portions,
      'p_note': note,
    },
    send: (params) async {
      final j = await _client.rpc('energy_save_estimate', params: params);
      return EnergyEstimate.fromJson(j as Map<String, dynamic>);
    },
  );

  Future<List<Expense>> expenses() async {
    final rows = await _client
        .from('expenses')
        .select()
        .order('expense_date', ascending: false)
        .order('id', ascending: false);
    return (rows as List)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PendingMutation?> pendingExpense() =>
      _retries.pending(_client.auth.currentUser?.id ?? '', 'exp_save', 0);

  Future<Expense> saveExpense({
    int? id,
    required String type,
    required String description,
    required int amount,
    required String kind,
    DateTime? expenseDate,
    String? evidenceUrl,
  }) async {
    final params = <String, dynamic>{
      'p_id': id,
      'p_type': type,
      'p_description': description,
      'p_amount': amount,
      'p_kind': kind,
      'p_expense_date': expenseDate?.toIso8601String().split('T').first,
      'p_evidence_url': evidenceUrl,
    };
    Future<Expense> send(Map<String, dynamic> params) async {
      final j = await _client.rpc('exp_save', params: params);
      return Expense.fromJson(j as Map<String, dynamic>);
    }

    if (id != null) return send(params);
    return _retries.run(
      owner: _client.auth.currentUser?.id ?? '',
      operation: 'exp_save',
      target: 0,
      params: params,
      send: send,
    );
  }

  Future<List<CostAllocation>> allocations(int expenseId) async {
    final rows = await _client
        .from('cost_allocations')
        .select()
        .eq('expense_id', expenseId)
        .order('id', ascending: true);
    return (rows as List)
        .map((e) => CostAllocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> allocatedTotal(int expenseId) async {
    final rows = await _client
        .from('cost_allocations')
        .select('amount')
        .eq('expense_id', expenseId);
    return (rows as List).fold<int>(
      0,
      (n, e) => n + ((e['amount'] as num).toInt()),
    );
  }

  Future<Map<String, dynamic>> allocate({
    required int expenseId,
    required String targetRef,
    required int amount,
  }) async {
    final j = await _client.rpc(
      'cost_allocate',
      params: {
        'p_expense_id': expenseId,
        'p_target_ref': targetRef,
        'p_amount': amount,
      },
    );
    return j as Map<String, dynamic>;
  }

  Future<CashShiftStatus> cashStatus() async {
    final j =
        await _client.rpc('cash_shift_status', params: {})
            as Map<String, dynamic>;
    return CashShiftStatus.fromJson(j);
  }

  Future<void> openCashShift(int openingCash) =>
      _client.rpc('cash_shift_open', params: {'p_opening_cash': openingCash});

  Future<CashShiftResult> closeCashShift(int actualCash, String? note) async {
    final j =
        await _client.rpc(
              'cash_shift_close',
              params: {'p_actual_cash': actualCash, 'p_note': note},
            )
            as Map<String, dynamic>;
    return CashShiftResult.fromJson(j);
  }

  Future<ReportSummary> report({DateTime? from, DateTime? to}) async {
    final j =
        await _client.rpc(
              'pos_reports',
              params: {
                'p_from': from?.toIso8601String().split('T').first,
                'p_to': to?.toIso8601String().split('T').first,
              },
            )
            as Map<String, dynamic>;
    return ReportSummary.fromJson(j);
  }
}

final operatingRepositoryProvider = Provider<OperatingRepository>(
  (ref) => OperatingRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(mutationRetryStoreProvider),
  ),
);

/// Daftar biaya operasional, terbaru di atas.
final expensesProvider = FutureProvider.autoDispose<List<Expense>>(
  (ref) => ref.watch(operatingRepositoryProvider).expenses(),
);

/// Daftar alokasi untuk satu expense.
final allocationsProvider = FutureProvider.autoDispose
    .family<List<CostAllocation>, int>(
      (ref, expenseId) =>
          ref.watch(operatingRepositoryProvider).allocations(expenseId),
    );

/// Status kas shift live saat shift terbuka.
final cashStatusProvider = FutureProvider.autoDispose<CashShiftStatus>(
  (ref) => ref.watch(operatingRepositoryProvider).cashStatus(),
);

/// Laporan deskriptif per rentang tanggal (default 7 hari terakhir).
class ReportRange {
  const ReportRange({this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

final reportRangeProvider = StateProvider<ReportRange>(
  (ref) => const ReportRange(),
);

final reportProvider = FutureProvider.autoDispose<ReportSummary>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref
      .watch(operatingRepositoryProvider)
      .report(from: range.from, to: range.to);
});

/// Laporan hari ini (WIB) untuk kartu detail dashboard S05-06 —
/// semua angka telusur ke laporan/DB yang sama.
final dashboardReportProvider = FutureProvider.autoDispose<ReportSummary>((
  ref,
) {
  final nowWib = toWib(DateTime.now());
  final day = DateTime(nowWib.year, nowWib.month, nowWib.day);
  return ref.watch(operatingRepositoryProvider).report(from: day, to: day);
});
