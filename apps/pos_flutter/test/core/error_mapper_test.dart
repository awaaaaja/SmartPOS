import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/error_mapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapErrorToMessage', () {
    test('kredensial salah', () {
      final message = mapErrorToMessage(
        const AuthException('Invalid login credentials'),
      );
      expect(message, contains('Email atau kata sandi salah'));
    });

    test('koneksi terputus', () {
      final message = mapErrorToMessage(const SocketException('no network'));
      expect(message, contains('koneksi internet'));
    });

    // Jalur pesanan QR: kode draft_not_* harus dipetakan sendiri (bukan
    // jatuh ke fallback "Data tidak valid" generik).
    test('draft_not_claimable (status berubah / tap ganda)', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'draft_not_claimable: already claimed',
        code: 'P0001',
      ));
      expect(message, contains('sudah berubah'));
      expect(message, isNot(contains('Data tidak valid')));
    });

    test('draft_not_claimed (belum diterima)', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'draft_not_claimed',
        code: 'P0001',
      ));
      expect(message, contains('belum diterima'));
    });

    test('draft_not_completable', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'draft_not_completable',
        code: 'P0001',
      ));
      expect(message, contains('belum bisa ditandai selesai'));
    });

    test('draft_not_cancelable', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'draft_not_cancelable',
        code: 'P0001',
      ));
      expect(message, contains('tidak bisa dibatalkan'));
    });

    // Meja & QR: tambah/hapus meja.
    test('invalid_label (label meja tidak valid)', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'invalid_label',
        code: 'P0001',
      ));
      expect(message, contains('Label meja'));
    });

    test('table_not_found', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'table_not_found',
        code: 'P0001',
      ));
      expect(message, contains('Meja tidak ditemukan'));
    });

    test('table_has_active_orders (hapus meja diblokir)', () {
      final message = mapErrorToMessage(const PostgrestException(
        message: 'table_has_active_orders',
        code: 'P0001',
      ));
      expect(message, contains('pesanan aktif'));
    });

    test('timeout', () {
      final message =
          mapErrorToMessage(TimeoutException('slow', const Duration(seconds: 1)));
      expect(message, contains('Waktu tunggu habis'));
    });

    test('pelanggaran constraint unik', () {
      final message = mapErrorToMessage(
        const PostgrestException(message: 'dup', code: '23505'),
      );
      expect(message, contains('duplikat'));
    });

    test('stok kurang (P0001 insufficient_stock) memakai pesan Indonesia',
        () {
      final message = mapErrorToMessage(const PostgrestException(
          message: 'insufficient_stock: Tepung Terigu', code: 'P0001'));
      expect(message, contains('Stok bahan kurang'));
      expect(message, contains('Tepung Terigu'));
    });

    test('resep belum ada (P0001 recipe_missing)', () {
      final message = mapErrorToMessage(const PostgrestException(
          message: 'recipe_missing', code: 'P0001'));
      expect(message, contains('Resep belum ada'));
    });

    test('alasan wajib (P0001 missing_reason)', () {
      final message = mapErrorToMessage(const PostgrestException(
          message: 'missing_reason', code: 'P0001'));
      expect(message, contains('Alasan wajib'));
    });

    test('error tak dikenal tetap aman ditampilkan', () {
      final message = mapErrorToMessage(StateError('boom'));
      expect(message, contains('kesalahan'));
    });

    test('koneksi putus tidak mengklaim mutasi pasti belum tersimpan', () {
      final message = mapErrorToMessage(const SocketException('lost response'));
      expect(message, contains('belum terkonfirmasi'));
      expect(message, isNot(contains('Transaksi belum tersimpan')));
    });

    test('key konflik dan request pending memberi arahan aman', () {
      expect(mapErrorToMessage(const PostgrestException(
          message: 'idempotency_key_conflict', code: 'P0001')),
          contains('Jangan membuat operasi baru'));
      expect(mapErrorToMessage(StateError('pending_mutation_conflict')),
          contains('Buka ulang form'));
    });
  });
}
