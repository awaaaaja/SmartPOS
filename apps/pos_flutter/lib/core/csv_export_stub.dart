import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:share_plus/share_plus.dart';

/// Jalur lembar berbagi; dipisah supaya bisa dipancang di unit test
/// (share sheet asli hanya bisa diverifikasi di device).
@visibleForTesting
Future<ShareResult> Function(ShareParams params) shareSheetHandler =
    (params) => SharePlus.instance.share(params);

/// Fallback non-web (Android/iOS/desktop): tulis CSV ke berkas sementara lalu
/// buka lembar berbagi (share sheet) sehingga laporan bisa langsung dikirim ke
/// WhatsApp/email/dsb. Bila lembar berbagi tidak tersedia di perangkat,
/// lempar StateError('csv_share_unavailable') — CSV tetap tersimpan di temp.
Future<void> saveCsvFile(String filename, String content) async {
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsString(content);
  final result = await shareSheetHandler(
    ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]),
  );
  if (result.status == ShareResultStatus.unavailable) {
    throw StateError('csv_share_unavailable');
  }
}
