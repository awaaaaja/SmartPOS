import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Petakan exception teknis ke pesan yang bisa dipahami operator.
/// Pesan mentah server tidak ditampilkan langsung (bisa berbahaya/inggris).
String mapErrorToMessage(Object error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login') ||
        message.contains('invalid credentials') ||
        message.contains('email not confirmed')) {
      return 'Email atau kata sandi salah.';
    }
    if (message.contains('rate limit')) {
      return 'Terlalu banyak percobaan. Coba lagi sebentar lagi.';
    }
    if (error is AuthRetryableFetchException ||
        message.contains('network') ||
        message.contains('fetch')) {
      return 'Gagal menghubungi layanan. Periksa koneksi internet.';
    }
    return 'Gagal masuk: ${error.message}';
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '401':
      case '403':
        return 'Sesi tidak berwenang. Masuk ulang sebagai operator.';
      case '404':
        return 'Data tidak ditemukan.';
      case '23505':
        return 'Data duplikat. Periksa sebelum menyimpan.';
      case 'PGRST301':
        return 'Sesi berakhir. Masuk ulang sebagai operator.';
      default:
        return 'Kesalahan basis data. Coba lagi; jika berulang, laporkan.';
    }
  }
  if (error is TimeoutException) {
    return 'Waktu tunggu habis. Periksa koneksi lalu coba lagi.';
  }
  if (error is SocketException || error is HandshakeException) {
    return 'Tidak ada koneksi internet. Transaksi belum tersimpan.';
  }
  return 'Terjadi kesalahan tak terduga. Coba lagi.';
}
