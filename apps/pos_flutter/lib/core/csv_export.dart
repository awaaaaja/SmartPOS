/// Simpan CSV ke lokasi yang sesuai platform: unduhan browser di web,
/// berkas sementara di platform lain (MVP diuji lewat web).
import 'csv_export_stub.dart'
    if (dart.library.html) 'csv_export_web.dart' as impl;

Future<void> saveCsvFile(String filename, String content) =>
    impl.saveCsvFile(filename, content);
