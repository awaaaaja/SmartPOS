import 'dart:io';

/// Fallback non-web (Android/iOS): tulis ke berkas sementara. Ekspor
/// unduhan browser hanya tersedia di web; shortcut: build Android MVP
/// menyimpan CSV ke temp, upgrade dengan share_plus bila perlu.
Future<void> saveCsvFile(String filename, String content) async {
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsString(content);
}
