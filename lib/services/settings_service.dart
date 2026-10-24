import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

/// Ayarları uygulama dizinindeki bir JSON dosyasında tutar.
///
/// `shared_preferences` gibi ek paket GEREKTİRMEZ — `pubspec.yaml`
/// değiştirilmez (CI uyumluluğu için kritik).
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _fileName = 'settings.json';

  AppSettings _cached = const AppSettings();
  bool _loaded = false;

  AppSettings get value => _cached;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Ayarları okur (ilk çağrıda). Bozuk dosya varsayılana düşer.
  Future<AppSettings> load() async {
    if (_loaded) return _cached;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cached = AppSettings.fromJson(decoded);
        }
      }
    } catch (_) {
      _cached = const AppSettings();
    }
    _loaded = true;
    return _cached;
  }

  /// Ayarları diske yazar ve önbelleği günceller.
  Future<AppSettings> save(AppSettings settings) async {
    _cached = settings;
    _loaded = true;
    try {
      final file = await _file();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
        flush: true,
      );
    } catch (_) {
      // Yazma başarısız olsa bile bellekteki değer geçerli kalır.
    }
    return _cached;
  }
}
