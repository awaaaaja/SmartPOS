import 'dart:html' as html;

/// Web: langsung unduh lewat anchor browser (Blob meng-encode UTF-8).
Future<void> saveCsvFile(String filename, String content) async {
  // BOM agar Excel membuka karakter non-ASCII dengan benar.
  final blob =
      html.Blob(['\uFEFF$content'], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
