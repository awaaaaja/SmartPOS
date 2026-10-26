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
  });
}
