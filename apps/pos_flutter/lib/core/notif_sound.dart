import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nada notifikasi pesanan QR (Kenney Interface Sounds, CC0 — lihat
/// `assets/sounds/README.md` untuk sumber & lisensi).
const Map<String, String> kNotifTones = {
  'confirmation_001': 'Konfirmasi 1',
  'confirmation_002': 'Konfirmasi 2',
  'confirmation_003': 'Konfirmasi 3',
  'confirmation_004': 'Konfirmasi 4',
};

/// Jalur pemutar nada; dipisah supaya bisa dipancang di unit test
/// (audio asli hanya bisa diverifikasi di device) — pola `shareSheetHandler`.
Future<void> Function(String toneId, double volume) notifSoundPlayer = (
  String toneId,
  double volume,
) async {
  final player = AudioPlayer();
  try {
    await player.setVolume(volume.clamp(0.0, 1.0));
    await player.play(AssetSource('sounds/$toneId.ogg'));
  } catch (_) {
    // Bunyi gagal bukan penghalang operasi POS (mis. perangkat tanpa speaker).
  }
};

/// Preferensi notifikasi pesanan (lokal, perangkat — SharedPreferences).
/// Default: suara aktif, nada `confirmation_001`, volume 0.8.
///
/// Platform async tidak selalu tersedia (mis. unit test tanpa mock / web
/// tertentu); dalam kasus itu baca mengembalikan default dan tulis jadi
/// no-op — preferensi lokal tidak pernah menjatuhkan aplikasi.
class NotifSoundPrefs {
  NotifSoundPrefs([SharedPreferencesAsync? preferences])
    : _provided = preferences;

  static const _enabledKey = 'notif-sound-enabled';
  static const _toneKey = 'notif-sound-tone';
  static const _volumeKey = 'notif-sound-volume';

  final SharedPreferencesAsync? _provided;
  SharedPreferencesAsync? _lazy;

  /// Null bila SharedPreferencesAsync tak bisa dibuat (StateError platform).
  SharedPreferencesAsync? _store() {
    if (_provided != null) return _provided;
    if (_lazy != null) return _lazy;
    try {
      _lazy = SharedPreferencesAsync();
    } on StateError {
      return null;
    }
    return _lazy;
  }

  Future<bool> get enabled async =>
      await _store()?.getBool(_enabledKey) ?? true;

  Future<String> get tone async =>
      await _store()?.getString(_toneKey) ?? kNotifTones.keys.first;

  Future<double> get volume async =>
      await _store()?.getDouble(_volumeKey) ?? 0.8;

  Future<void> setEnabled(bool value) async =>
      _store()?.setBool(_enabledKey, value);

  Future<void> setTone(String value) async =>
      _store()?.setString(_toneKey, value);

  Future<void> setVolume(double value) async =>
      _store()?.setDouble(_volumeKey, value);
}
