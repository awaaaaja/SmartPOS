import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Satu operator, tanpa halaman Dapur/Pegawai (PRD v2.1 §2.2). Tab
/// "Pesanan" = evolusi panel QR Masuk (docs/plan-qr-wizard-notif.md §C5):
/// satu sumber draft, hanya rumah UI yang pindah ke destinasi sendiri.
enum AppDestination {
  dashboard('Dashboard', Icons.dashboard_rounded, _groupMain, 'Beranda'),
  pos('Kasir POS', Icons.point_of_sale_rounded, _groupMain, 'Kasir'),
  orders('Pesanan', Icons.receipt_long_rounded, _groupMain, 'Pesanan'),
  tablesQr('Meja & QR', Icons.qr_code_2_rounded, _groupMain),
  catalog('Menu & Harga', Icons.restaurant_menu_rounded, _groupProduct),
  inventory('Stok Bahan', Icons.inventory_2_rounded, _groupProduct, 'Stok'),
  recipesHpp('Resep & HPP', Icons.menu_book_rounded, _groupProduct),
  purchases('Pembelian', Icons.shopping_basket_rounded, _groupProduct),
  expenses(
    'Biaya Operasional',
    Icons.account_balance_wallet_rounded,
    _groupFinance,
  ),
  energy('Kalkulator Energi', Icons.bolt_rounded, _groupFinance),
  cashShift('Kas Shift', Icons.payments_rounded, _groupFinance),
  salesHistory('Riwayat Penjualan', Icons.receipt_long_rounded, _groupFinance),
  reports('Laporan', Icons.bar_chart_rounded, _groupFinance, 'Laporan'),
  settings('Pengaturan', Icons.settings_rounded, _groupFinance);

  const AppDestination(this.label, this.icon, this.group, [this.mobileLabel]);

  final String label;
  final IconData icon;
  final String group;

  /// Label ringkas untuk bottom nav HP; hanya 5 tujuan utama.
  final String? mobileLabel;

  static const _groupMain = 'Utama';
  static const _groupProduct = 'Produk & Persediaan';
  static const _groupFinance = 'Keuangan & Lainnya';

  static List<String> get groups => [_groupMain, _groupProduct, _groupFinance];

  static List<AppDestination> byGroup(String group) =>
      values.where((d) => d.group == group).toList();
}

/// Lima tab bottom navigation HP: Beranda, Kasir, Pesanan, Stok, Laporan.
const mobileNavDestinations = [
  AppDestination.dashboard,
  AppDestination.pos,
  AppDestination.orders,
  AppDestination.inventory,
  AppDestination.reports,
];

/// Destinasi terpilih GLOBAL — supaya banner notifikasi dan tombol [Bayar]
/// bisa memindah tab dari mana pun (bukan state privat shell).
final selectedDestinationProvider =
    NotifierProvider<_SelectedDestination, AppDestination>(
      _SelectedDestination.new,
    );

class _SelectedDestination extends Notifier<AppDestination> {
  @override
  AppDestination build() => AppDestination.dashboard;

  void select(AppDestination destination) => state = destination;
}
