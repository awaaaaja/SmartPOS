import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Petakan error bisnis server (errcode P0001) ke pesan operator.
/// Pesan server memakai kode Inggris pendek; jangan tampilkan mentah.
String _mapBusinessError(String message) {
  final m = message.trim();
  if (m.startsWith('insufficient_stock')) {
    final detail = m.split(':').skip(1).join(':').trim();
    final names = detail.isEmpty ? '' : ' ($detail)';
    return 'Stok bahan kurang$names. Terima pembelian atau lakukan koreksi '
        'stok dengan alasan, lalu ulangi transaksi.';
  }
  if (m.startsWith('recipe_missing')) {
    return 'Resep belum ada untuk menu ini. Buat resep aktif dulu.';
  }
  if (m.startsWith('missing_reason')) {
    return 'Alasan wajib diisi (minimal 3 huruf).';
  }
  if (m.startsWith('invalid_qty') || m.startsWith('unit_mismatch') ||
      m.startsWith('invalid_unit')) {
    return 'Jumlah atau satuan tidak valid. Periksa isian.';
  }
  if (m.startsWith('purchase_already_received')) {
    return 'Pembelian sudah pernah diterima; stok tidak ditambah dua kali.';
  }
  if (m.startsWith('modifier_not_allowed')) {
    return 'Varian tidak tersedia untuk menu ini.';
  }
  return 'Data tidak valid. Periksa isian lalu coba lagi.';
}

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
      case 'P0001':
        return _mapBusinessError(error.message);
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
