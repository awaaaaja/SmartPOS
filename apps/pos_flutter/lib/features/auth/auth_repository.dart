import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Akses Supabase client tunggal; di-test dengan override provider.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Satu akun operator (PRD FR-01). Bukan sistem role.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<void> signIn({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();

  User? get currentUser => _client.auth.currentUser;
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// Perubahan sesi: null = belum masuk.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// true bila ada sesi valid yang bisa dipakai memanggil API privat.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final async = ref.watch(authStateProvider);
  return async.maybeWhen(
    data: (state) => state.session != null,
    orElse: () => false,
  );
});
