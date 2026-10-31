import 'package:url_launcher/url_launcher.dart';

/// Jalur membuka WhatsApp; dipisah supaya bisa dipancang di unit test
/// (peluncur asli hanya bisa diverifikasi di device) — pola
/// `shareSheetHandler` / `notifSoundPlayer`.
Future<void> Function(String url) waLaunchHandler = (String url) async {
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) throw StateError('wa_unavailable');
};

/// Normalisasi nomor WA ke format internasional tanpa `+` (`62…`).
///
/// Menerima `+62…`, `62…`, `0…`, dan `8…` (dengan spasi/`-`/`()` dibuang).
/// Mengembalikan null bila bukan nomor Indonesia yang masuk akal
/// (≤16 digit, diawali 62 setelah konversi) — tombol [Hubungi WA] jadi
/// nonaktif dengan tooltip "Nomor WA tidak valid".
String? normalizeWaPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return null;

  final String normalized;
  if (digits.startsWith('62')) {
    normalized = digits;
  } else if (digits.startsWith('0')) {
    normalized = '62${digits.substring(1)}';
  } else if (digits.startsWith('8')) {
    normalized = '62$digits';
  } else {
    return null;
  }
  // 62 + minimal 9 digit (nomor seluler Indonesia), maksimal wajar 16 digit.
  if (normalized.length < 11 || normalized.length > 16) return null;
  return normalized;
}

/// URL prabayar `wa.me` untuk menagih pesanan belum bayar.
/// [phone] sudah dinormalisasi oleh [normalizeWaPhone].
String waMessageUrl({required String phone, required String message}) =>
    'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';

/// Pesan penagihan contoh (Fase C4): jujur, sopan, tanpa menyebut data
/// lain selain pesanan.
String waBillMessage({
  required String? name,
  required String tableLabel,
  required String refCode,
}) {
  final who = (name == null || name.trim().isEmpty) ? '' : ' ${name.trim()}';
  return 'Halo$who, pesanan Anda di $tableLabel ($refCode) sudah selesai '
      'namun belum dibayar. Silakan lakukan pembayaran di kasir. '
      'Terima kasih 🙏';
}
