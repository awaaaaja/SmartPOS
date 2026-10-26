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

    test('error tak dikenal tetap aman ditampilkan', () {
      final message = mapErrorToMessage(StateError('boom'));
      expect(message, contains('kesalahan'));
    });
  });
}
