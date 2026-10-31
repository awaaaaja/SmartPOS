// Bagikan PNG (QR meja): unduhan browser di web, lembar berbagi di platform lain.
import 'png_share_stub.dart'
    if (dart.library.js_interop) 'png_share_web.dart'
    as impl;

/// Jalur berbagi PNG; dipisah supaya bisa dipancang di unit test (tulis file
/// dan share sheet asli hanya bisa diverifikasi di device).
Future<bool> Function(String filename, List<int> bytes) sharePngHandler =
    impl.sharePngFile;

/// Buka lembar berbagi berisi PNG; `false` bila lembar berbagi tak tersedia.
Future<bool> sharePngFile(String filename, List<int> bytes) =>
    sharePngHandler(filename, bytes);
