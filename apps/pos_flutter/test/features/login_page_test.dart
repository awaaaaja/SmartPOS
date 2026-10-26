import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/features/auth/auth_repository.dart';
import 'package:pos_flutter/features/auth/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingAuthRepository implements AuthRepository {
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
  }

  @override
  Future<void> signOut() async {}

  @override
  User? get currentUser => null;
}

Future<void> _pumpLogin(WidgetTester tester, _RecordingAuthRepository repo) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: buildAppTheme(), home: const LoginPage()),
    ),
  );
}

void main() {
  testWidgets('validasi email dan kata sandi sebelum mengirim', (tester) async {
    final repo = _RecordingAuthRepository();
    await _pumpLogin(tester, repo);

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Masukkan email yang valid'), findsOneWidget);
    expect(find.text('Masukkan kata sandi'), findsOneWidget);
    expect(repo.lastEmail, isNull);
  });

  testWidgets('login mengirim email ter-trim ke repository', (tester) async {
    final repo = _RecordingAuthRepository();
    await _pumpLogin(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      '  operator@mejeng.id  ',
    );
    await tester.enterText(find.byType(TextFormField).last, 'rahasia123');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(repo.lastEmail, 'operator@mejeng.id');
    expect(repo.lastPassword, 'rahasia123');
  });
}
