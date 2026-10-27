// Simpan CSV: unduhan browser di web, berkas sementara di platform lain.
import 'csv_export_stub.dart'
    if (dart.library.js_interop) 'csv_export_web.dart'
    as impl;

Future<void> saveCsvFile(String filename, String content) =>
    impl.saveCsvFile(filename, content);
