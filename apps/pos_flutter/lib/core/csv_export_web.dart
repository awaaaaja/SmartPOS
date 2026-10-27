import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web: langsung unduh lewat anchor browser (Blob meng-encode UTF-8).
Future<void> saveCsvFile(String filename, String content) async {
  // BOM agar Excel membuka karakter non-ASCII dengan benar.
  final blob = web.Blob(
    ['\uFEFF$content'.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}
