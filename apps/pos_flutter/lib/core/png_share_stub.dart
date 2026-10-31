import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'csv_export_stub.dart' show shareSheetHandler;

/// PNG lewat lembar berbagi Android/iOS/desktop — dari share sheet operator
/// memilih cetak (bila printer terhubung), WhatsApp, dsb. Handler yang sama
/// dengan ekspor CSV sehingga unit test dapat memancangnya.
Future<bool> sharePngFile(String filename, List<int> bytes) async {
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  final result = await shareSheetHandler(
    ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
  );
  return result.status != ShareResultStatus.unavailable;
}
