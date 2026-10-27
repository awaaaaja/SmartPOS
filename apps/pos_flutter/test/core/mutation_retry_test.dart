import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/mutation_retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/memory_preferences.dart';

void main() {
  late MemoryPreferences preferences;
  late MutationRetryStore store;
  const params = {'p_sale_id': 1, 'p_amount': 100, 'p_reason': 'retry QA'};

  Future<int> submit(
    Future<int> Function(Map<String, dynamic>) send, {
    Map<String, dynamic> payload = params,
    String owner = 'operator',
  }) => store.run(
    owner: owner,
    operation: 'pos_refund',
    target: 1,
    params: payload,
    send: send,
  );

  setUp(() {
    preferences = MemoryPreferences();
    store = MutationRetryStore(preferences);
  });

  test(
    'persist key before RPC; timeout + recreated store replay; next intent gets new key',
    () async {
      final ledger = <String, int>{};
      String? firstKey;
      await expectLater(
        submit((wire) async {
          final pending = await store.pending('operator', 'pos_refund', 1);
          firstKey = wire['p_idempotency_key'] as String;
          expect(pending!.key, firstKey);
          expect(firstKey, matches(RegExp(r'^[0-9a-f]{32}$')));
          ledger[firstKey!] = 100;
          throw TimeoutException('response lost after commit');
        }),
        throwsA(isA<TimeoutException>()),
      );
      store = MutationRetryStore(preferences);
      await submit((wire) async {
        expect(wire['p_idempotency_key'], firstKey);
        ledger.putIfAbsent(wire['p_idempotency_key'] as String, () => 100);
        return 100;
      });
      expect(ledger.length, 1);
      expect(await store.pending('operator', 'pos_refund', 1), isNull);
      await submit((wire) async {
        expect(wire['p_idempotency_key'], isNot(firstKey));
        return 100;
      });
    },
  );

  test('different payload cannot replace unresolved request', () async {
    await expectLater(
      submit((_) async => throw TimeoutException('lost')),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      submit(
        (_) async => fail('must not send modified request'),
        payload: {...params, 'p_amount': 200},
      ),
      throwsStateError,
    );
    expect((await store.pending('operator', 'pos_refund', 1))!.params, params);
  });

  test(
    'nested purchase items survive serialization and reject changed lines',
    () async {
      const payload = {
        'p_items': [
          {'ingredient_id': 1, 'qty': 2.0, 'unit': 'kg', 'total_price': 13000},
        ],
      };
      String? key;
      await expectLater(
        submit((wire) async {
          key = wire['p_idempotency_key'] as String;
          throw TimeoutException('lost');
        }, payload: payload),
        throwsA(isA<TimeoutException>()),
      );
      store = MutationRetryStore(preferences);
      await expectLater(
        submit(
          (_) async => fail('changed item must not reach RPC'),
          payload: {
            'p_items': [
              {
                'ingredient_id': 1,
                'qty': 3.0,
                'unit': 'kg',
                'total_price': 13000,
              },
            ],
          },
        ),
        throwsStateError,
      );
      await submit((wire) async {
        expect(wire['p_idempotency_key'], key);
        return 1;
      }, payload: payload);
    },
  );

  test(
    'business rejection allows correction, authorization/transport/conflict retain identity',
    () async {
      await expectLater(
        submit(
          (_) async => throw const PostgrestException(
            message: 'refund_exceeds_total',
            code: 'P0001',
          ),
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(await store.pending('operator', 'pos_refund', 1), isNull);
      for (final error in [
        const PostgrestException(message: 'operator_required', code: '42501'),
        const PostgrestException(message: 'expired', code: 'PGRST301'),
        const PostgrestException(message: 'upstream failed', code: '503'),
        const PostgrestException(
          message: 'idempotency_key_conflict',
          code: 'P0001',
        ),
      ]) {
        await expectLater(
          submit((_) async => throw error),
          throwsA(same(error)),
        );
        expect(await store.pending('operator', 'pos_refund', 1), isNotNull);
      }
    },
  );

  test('storage write failure prevents any RPC', () async {
    preferences.failures.add('write');
    await expectLater(
      submit((_) async => fail('RPC before durable identity')),
      throwsStateError,
    );
  });

  test('acknowledgement cleanup failure keeps same retry key', () async {
    preferences.failures.add('remove');
    String? key;
    await expectLater(
      submit((wire) async {
        key = wire['p_idempotency_key'] as String;
        return 100;
      }),
      throwsStateError,
    );
    preferences.failures.remove('remove');
    await submit((wire) async {
      expect(wire['p_idempotency_key'], key);
      return 100;
    });
  });

  test('double submit is rejected while first RPC is pending', () async {
    final started = Completer<void>();
    final response = Completer<int>();
    final first = submit((_) {
      started.complete();
      return response.future;
    });
    await started.future;
    await expectLater(
      submit((_) async => fail('duplicate RPC')),
      throwsStateError,
    );
    response.complete(100);
    expect(await first, 100);
  });

  test('different accounts cannot reuse each other pending request', () async {
    await expectLater(
      submit((_) async => throw TimeoutException('lost')),
      throwsA(isA<TimeoutException>()),
    );
    expect(await store.pending('other', 'pos_refund', 1), isNull);
    await submit((_) async => 100, owner: 'other');
    expect(await store.pending('operator', 'pos_refund', 1), isNotNull);
  });

  test(
    'corrupt pending data fails closed rather than generating a new identity',
    () async {
      preferences.values['pending-mutation:operator:pos_refund:1'] = 'not JSON';
      await expectLater(
        submit((_) async => fail('must not replace corrupt entry')),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
