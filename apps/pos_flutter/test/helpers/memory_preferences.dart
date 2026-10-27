import 'package:shared_preferences/shared_preferences.dart';

class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};
  final failures = <String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failures.contains('write')) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (failures.contains('remove')) throw StateError('storage unavailable');
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
