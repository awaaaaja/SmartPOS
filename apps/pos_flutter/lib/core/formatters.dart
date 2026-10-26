import 'package:intl/intl.dart';

/// Format uang dan waktu untuk operator: Rupiah `id-ID`, jam WIB (UTC+7).
/// WIB dihitung manual dari UTC agar deterministik tanpa paket zona waktu.
const wibOffset = Duration(hours: 7);

String formatRupiah(num amount) {
  final abs = amount.abs().round();
  final body = NumberFormat.decimalPattern('id-ID').format(abs);
  return amount.isNegative ? '-Rp $body' : 'Rp $body';
}

String formatNumber(num value) =>
    NumberFormat.decimalPattern('id-ID').format(value);

DateTime toWib(DateTime utc) => utc.toUtc().add(wibOffset);

/// Nama bulan Indonesia disimpan manual agar deterministik tanpa
/// initializeDateFormatting (symbol intl butuh inisialisasi runtime).
const _monthsId = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String formatWib(DateTime utc, {bool withSeconds = false}) {
  final wib = toWib(utc);
  final base =
      '${_twoDigits(wib.day)} ${_monthsId[wib.month - 1]} ${wib.year}, '
      '${_twoDigits(wib.hour)}:${_twoDigits(wib.minute)}';
  final withSec = withSeconds
      ? '$base:${_twoDigits(wib.second)}'
      : base;
  return '$withSec WIB';
}

String formatWibDate(DateTime utc) {
  final wib = toWib(utc);
  return '${_twoDigits(wib.day)} ${_monthsId[wib.month - 1]} ${wib.year}';
}

String formatWibTime(DateTime utc) {
  final wib = toWib(utc);
  return '${_twoDigits(wib.hour)}:${_twoDigits(wib.minute)}';
}
