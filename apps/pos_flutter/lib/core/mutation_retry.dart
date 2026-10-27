import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingMutation {
  const PendingMutation(this.key, this.params);

  final String key;
  final Map<String, dynamic> params;

  factory PendingMutation.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final key = json['key'] as String;
    if (key.length < 8 || key.length > 128) {
      throw const FormatException('Invalid pending mutation key');
    }
    return PendingMutation(
      key,
      Map<String, dynamic>.from(json['params'] as Map),
    );
  }

  String encode() => jsonEncode({'key': key, 'params': params});
}

/// Identitas retry saja; bukan saldo uang/stok atau outbox offline.
class MutationRetryStore {
  MutationRetryStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  static final _active = <String>{};

  String _slot(String owner, String operation, int target) {
    if (owner.isEmpty) throw StateError('Operator session required');
    return 'pending-mutation:$owner:$operation:$target';
  }

  Future<PendingMutation?> pending(
    String owner,
    String operation,
    int target,
  ) async {
    final value = await _preferences.getString(_slot(owner, operation, target));
    return value == null ? null : PendingMutation.decode(value);
  }

  Future<T> run<T>({
    required String owner,
    required String operation,
    required int target,
    required Map<String, dynamic> params,
    required Future<T> Function(Map<String, dynamic>) send,
  }) async {
    final slot = _slot(owner, operation, target);
    if (!_active.add(slot)) throw StateError('Mutation already in progress');
    try {
      var request = await pending(owner, operation, target);
      if (request != null &&
          !const DeepCollectionEquality().equals(request.params, params)) {
        throw StateError('pending_mutation_conflict');
      }
      if (request == null) {
        final random = Random.secure();
        final key = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        request = PendingMutation(key, Map<String, dynamic>.from(params));
        // shortcut: storage wipe/power-loss recovery still requires ledger reconciliation.
        await _preferences.setString(slot, request.encode());
      }
      late final T result;
      try {
        result = await send({
          ...request.params,
          'p_idempotency_key': request.key,
        });
      } on PostgrestException catch (error) {
        // Validasi bisnis setelah cache lookup membuktikan key belum committed.
        if (error.code == 'P0001' &&
            error.message != 'idempotency_key_conflict' &&
            error.message != 'missing_idempotency_key') {
          await _preferences.remove(slot);
        }
        rethrow;
      }
      await _preferences.remove(slot);
      return result;
    } finally {
      _active.remove(slot);
    }
  }
}

final mutationRetryStoreProvider = Provider((ref) => MutationRetryStore());
