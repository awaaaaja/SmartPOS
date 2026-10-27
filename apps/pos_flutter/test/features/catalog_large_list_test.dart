import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';
import 'package:pos_flutter/core/models/catalog_models.dart';
import 'package:pos_flutter/features/catalog/catalog_page.dart';
import 'package:pos_flutter/features/catalog/catalog_repository.dart';

void main() {
  testWidgets('katalog 1000 menu dirender lazy dan tetap dapat digulir', (
    tester,
  ) async {
    final products = List.generate(
      1000,
      (i) => Product(id: i + 1, name: 'Menu uji $i', price: 10000),
    );
    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productsProvider.overrideWith((ref) async => products)],
        child: MaterialApp(theme: buildAppTheme(), home: const CatalogPage()),
      ),
    );
    await tester.pumpAndSettle();
    final initialMs = watch.elapsedMilliseconds;
    expect(find.text('Menu uji 0'), findsOneWidget);
    expect(find.text('Menu uji 999'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(100));
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    watch.stop();
    expect(tester.takeException(), isNull);
    // Debug/widget harness, bukan angka FPS atau profil tablet native.
    debugPrint(
      'S06 catalog 1000: initial=${initialMs}ms, '
      'including scroll=${watch.elapsedMilliseconds}ms',
    );
  });
}
