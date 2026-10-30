import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';

/// Pengaturan usaha (business_settings, baris tunggal id = 1).
/// Pembacaan langsung dari tabel; penulisan lewat RPC guarded settings_save
/// yang memvalidasi di server dan mencatat audit_events.
class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> fetch() =>
      _client
          .from('business_settings')
          .select('name,address,timezone,tax_rate,service_rate')
          .eq('id', 1)
          .single();

  /// Simpan pengaturan. Tarif dikirim sebagai fraksi (0.075 = 7,5%).
  /// Melempar PostgrestException (P0001 validasi, 42501 non-operator).
  Future<void> save({
    required String name,
    String? address,
    required String timezone,
    required double taxRate,
    required double serviceRate,
  }) =>
      _client.rpc(
        'settings_save',
        params: {
          'p_name': name,
          'p_address': address,
          'p_timezone': timezone,
          'p_tax_rate': taxRate,
          'p_service_rate': serviceRate,
        },
      );
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseClientProvider)),
);
