import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/shell.dart';
import 'app/theme.dart';

/// Konfigurasi lewat --dart-define, contoh:
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// Tidak ada secret server di aplikasi ini (Prompt.md §4.2).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    // Adapter jujur: tanpa konfigurasi aplikasi tidak berpura-pura terkoneksi.
    runApp(const ProviderScope(child: MissingConfigApp()));
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const ProviderScope(child: PosApp()));
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart POS Waroeng MeJeng',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// Layar konfigurasi: muncul hanya bila build tanpa SUPABASE_URL/ANON_KEY.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart POS Waroeng MeJeng',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Konfigurasi belum lengkap')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.settings_suggest_rounded,
                        size: 40, color: brandPrimary),
                    const SizedBox(height: 12),
                    Text(
                      'Aplikasi belum diberi alamat Supabase.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Jalankan ulang dengan konfigurasi berikut:\n\n'
                      'flutter run \\\n'
                      '  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \\\n'
                      '  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...\n\n'
                      'Nilai contoh ada di apps/pos_flutter/.env.example. '
                      'Kunci hanya boleh kunci publishable/anon, bukan service role.',
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
