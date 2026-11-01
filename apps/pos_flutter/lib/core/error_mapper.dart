import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Petakan error bisnis server (errcode P0001) ke pesan operator.
/// Pesan server memakai kode Inggris pendek; jangan tampilkan mentah.
String _mapBusinessError(String message) {
  final m = message.trim();
  if (m == 'idempotency_key_conflict') {
    return 'Kunci permintaan sudah dipakai untuk isian berbeda. '
        'Jangan membuat operasi baru; periksa riwayat.';
  }
  if (m == 'missing_idempotency_key') {
    return 'Identitas permintaan tidak valid. Perbarui aplikasi sebelum melanjutkan.';
  }
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
  if (m.startsWith('allocation_exceeds_source')) {
    return 'Total alokasi melebihi nominal biaya. Kurangi alokasi atau '
        'ubah nominal biaya dulu.';
  }
  if (m.startsWith('invalid_name')) {
    return 'Nama usaha wajib diisi 2 sampai 80 huruf.';
  }
  if (m.startsWith('invalid_address')) {
    return 'Alamat maksimal 200 huruf. Kosongkan bila tidak perlu.';
  }
  if (m.startsWith('invalid_timezone')) {
    return 'Zona waktu tidak dikenal. Pakai format seperti Asia/Jakarta.';
  }
  if (m.startsWith('invalid_tax_rate')) {
    return 'Pajak harus antara 0% dan 100%.';
  }
  if (m.startsWith('invalid_service_rate')) {
    return 'Biaya layanan harus antara 0% dan 100%.';
  }
  if (m == 'settings_not_found') {
    return 'Data pengaturan usaha belum ada. Hubungi pengelola database.';
  }
  if (m.startsWith('shift_already_open')) {
    return 'Sudah ada kas shift terbuka. Tutup dulu sebelum buka baru.';
  }
  if (m.startsWith('no_open_shift')) {
    return 'Tidak ada kas shift terbuka. Buka shift dulu.';
  }
  // --- Jalur pesanan QR (tab Pesanan) — jangan jatuh ke fallback generik. ---
  if (m.startsWith('draft_not_claimable')) {
    return 'Status pesanan sudah berubah (sudah diambil, dibatalkan, atau '
        'kedaluwarsa). Daftar diperbarui otomatis; periksa status terbaru.';
  }
  if (m.startsWith('draft_not_claimed')) {
    return 'Pesanan belum diterima. Tekan "Diterima" dulu sebelum '
        'melanjutkan.';
  }
  if (m.startsWith('draft_not_completable')) {
    return 'Pesanan belum bisa ditandai selesai atau dibayar pada status '
        'ini. Periksa status terbaru di papan pesanan.';
  }
  if (m.startsWith('draft_not_cancelable')) {
    return 'Pesanan tidak bisa dibatalkan pada status ini (mungkin sudah '
        'selesai atau terlambat). Periksa status terbaru.';
  }
  // --- Meja & QR (tambah/hapus meja) ---
  if (m.startsWith('invalid_label')) {
    return 'Label meja wajib 1 sampai 40 huruf.';
  }
  if (m.startsWith('table_not_found')) {
    return 'Meja tidak ditemukan. Muat ulang daftar meja lalu coba lagi.';
  }
  if (m.startsWith('table_has_active_orders')) {
    return 'Masih ada pesanan aktif di meja ini. Selesaikan atau batalkan '
        'semua pesanan di tab Pesanan dulu, baru hapus mejanya.';
  }
  // --- Pesanan manual (migrasi 0022: buat & tambah item) ---
  if (m.startsWith('invalid_customer_name')) {
    return 'Nama pesanan wajib diisi (maksimal 60 huruf).';
  }
  if (m.startsWith('invalid_customer_phone')) {
    return 'Nomor HP tidak valid (maksimal 24 karakter).';
  }
  if (m.startsWith('draft_not_editable')) {
    return 'Hanya pesanan yang masih aktif (Baru masuk, Diterima, atau '
        'Diproses) yang bisa ditambah itemnya. Pesanan yang sudah selesai, '
        'dibatalkan, atau kedaluwarsa tidak bisa diubah.';
  }
  if (m.startsWith('product_unavailable')) {
    return 'Menu tidak tersedia (sudah diarsipkan atau dinonaktifkan). '
        'Pilih menu lain.';
  }
  if (m.startsWith('product_not_found')) {
    return 'Menu tidak ditemukan di katalog. Muat ulang lalu coba lagi.';
  }
  if (m.startsWith('modifier_max_exceeded')) {
    return 'Jumlah pilihan varian/melebihi batas yang diizinkan menu ini.';
  }
  if (m.startsWith('invalid_items')) {
    return 'Daftar menu pesanan tidak valid. Pilih minimal satu menu lalu '
        'coba lagi.';
  }
  return 'Data tidak valid. Periksa isian lalu coba lagi.';
}

/// Petakan exception teknis ke pesan yang bisa dipahami operator.
/// Pesan mentah server tidak ditampilkan langsung (bisa berbahaya/inggris).
String mapErrorToMessage(Object error) {
  if (error is StateError && error.message == 'csv_share_unavailable') {
    return 'CSV sudah disimpan sementara, tetapi lembar berbagi tidak '
        'tersedia di perangkat ini. Coba lagi dari aplikasi lain.';
  }
  if (error is StateError && error.message == 'pending_mutation_conflict') {
    return 'Masih ada permintaan belum terkonfirmasi. Buka ulang form '
        'untuk mengulangi isian sebelumnya.';
  }
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
      case '42501':
        return 'Hanya akun operator yang boleh mengubah data ini. '
            'Masuk ulang dengan akun operator.';
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
    return 'Tidak ada koneksi internet. Status penyimpanan belum terkonfirmasi; '
        'periksa riwayat atau ulangi permintaan yang sama.';
  }
  return 'Terjadi kesalahan tak terduga. Coba lagi.';
}
