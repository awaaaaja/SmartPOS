import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/app/theme.dart';

void main() {
  test('primary brand wajib #930031', () {
    expect(brandPrimary, const Color(0xFF930031));
  });

  test('theme memakai Material 3 dengan primary brand', () {
    final theme = buildAppTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, brandPrimary);
    expect(theme.colorScheme.onPrimary, Colors.white);
    expect(theme.scaffoldBackgroundColor, canvasColor);
  });
}
