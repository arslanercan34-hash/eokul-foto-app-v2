import 'package:flutter/foundation.dart';

/// Çekim modu. Her modun kendi oranı, çözünürlüğü ve dosya boyutu kuralı vardır.
@immutable
class CaptureSpec {
  /// Yatay/dikey en-boy oranı (genişlik / yükseklik).
  final double aspect;

  final int width;
  final int height;

  /// Dosya boyutu üst sınırı bayt cinsinden. null = sınır YOK (biyometrik).
  final int? maxBytes;

  /// Dosya boyutu alt sınırı bayt cinsinden. null = alt sınır yok.
  final int? minBytes;

  /// Sabit JPEG kalitesi (boyut penceresi yoksa kullanılır).
  final int quality;

  /// Dosya adının başına/sonuna eklenecek ayırt edici etiket ('' = yok).
  final String fileTag;

  /// Yaka kartında çizilecek koyu bant var mı.
  final bool drawInfoBand;

  const CaptureSpec({
    required this.aspect,
    required this.width,
    required this.height,
    this.maxBytes,
    this.minBytes,
    required this.quality,
    this.fileTag = '',
    this.drawInfoBand = false,
  });

  bool get hasSizeWindow => maxBytes != null;
}

/// e-Okul modu çözünürlük seçenekleri.
enum EokulResolution {
  r133x171('133 × 171 px (Küçük)', 133, 171),
  r300x400('300 × 400 px (Standart)', 300, 400);

  final String label;
  final int width;
  final int height;

  const EokulResolution(this.label, this.width, this.height);
}

/// Biyometrik mod çözünürlük seçenekleri.
enum BiometricResolution {
  r600x720('600 × 720 px (Yüksek Kalite)', 600, 720),
  r1200x1440('1200 × 1440 px (Baskı Kalitesi)', 1200, 1440);

  final String label;
  final int width;
  final int height;

  const BiometricResolution(this.label, this.width, this.height);
}

/// Çekim modları.
enum CaptureMode {
  eokul('e-Okul', '3:4 · <50 KB'),
  biometric('Biyometrik', '5:6 · %95 kalite'),
  badge('Yaka Kartı', '3:4 · isimli bant');

  final String label;
  final String subtitle;

  const CaptureMode(this.label, this.subtitle);
}

/// Kullanıcı ayarları (JSON olarak diske yazılır).
///
/// `pubspec.yaml`'a paket EKLENMEZ; `dart:convert` + `dart:io` kullanılır.
@immutable
class AppSettings {
  final CaptureMode mode;
  final EokulResolution eokulResolution;
  final BiometricResolution biometricResolution;

  /// e-Okul modu üst dosya boyutu sınırı (KB). 15–50 arası.
  final int eokulMaxKb;

  /// Biyometrik dosya adına "BIO" etiketi eklensin mi.
  final bool biometricTag;

  /// Geri sayım süresi saniye (0 = kapalı, 3 = 3 sn).
  final int timerSeconds;

  /// Çekimden sonra otomatik parlaklık/kontrast iyileştirme öner.
  final bool suggestEnhance;

  const AppSettings({
    this.mode = CaptureMode.eokul,
    this.eokulResolution = EokulResolution.r300x400,
    this.biometricResolution = BiometricResolution.r600x720,
    this.eokulMaxKb = 49,
    this.biometricTag = false,
    this.timerSeconds = 0,
    this.suggestEnhance = true,
  });

  AppSettings copyWith({
    CaptureMode? mode,
    EokulResolution? eokulResolution,
    BiometricResolution? biometricResolution,
    int? eokulMaxKb,
    bool? biometricTag,
    int? timerSeconds,
    bool? suggestEnhance,
  }) {
    return AppSettings(
      mode: mode ?? this.mode,
      eokulResolution: eokulResolution ?? this.eokulResolution,
      biometricResolution: biometricResolution ?? this.biometricResolution,
      // Sınır: 15–50 KB (fromJson ile aynı kural — tek doğruluk kaynağı).
      eokulMaxKb: (eokulMaxKb ?? this.eokulMaxKb).clamp(15, 50),
      biometricTag: biometricTag ?? this.biometricTag,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      suggestEnhance: suggestEnhance ?? this.suggestEnhance,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.name,
        'eokulResolution': eokulResolution.name,
        'biometricResolution': biometricResolution.name,
        'eokulMaxKb': eokulMaxKb,
        'biometricTag': biometricTag,
        'timerSeconds': timerSeconds,
        'suggestEnhance': suggestEnhance,
      };

  static AppSettings fromJson(Map<String, dynamic> json) {
    CaptureMode mode = CaptureMode.eokul;
    try {
      mode = CaptureMode.values.firstWhere(
        (m) => m.name == json['mode'],
      );
    } catch (_) {}

    EokulResolution eokulRes = EokulResolution.r300x400;
    try {
      eokulRes = EokulResolution.values.firstWhere(
        (r) => r.name == json['eokulResolution'],
      );
    } catch (_) {}

    BiometricResolution bioRes = BiometricResolution.r600x720;
    try {
      bioRes = BiometricResolution.values.firstWhere(
        (r) => r.name == json['biometricResolution'],
      );
    } catch (_) {}

    final maxKb = (json['eokulMaxKb'] as num?)?.toInt() ?? 49;
    final timer = (json['timerSeconds'] as num?)?.toInt() ?? 0;

    return AppSettings(
      mode: mode,
      eokulResolution: eokulRes,
      biometricResolution: bioRes,
      eokulMaxKb: maxKb.clamp(15, 50),
      biometricTag: json['biometricTag'] == true,
      timerSeconds: timer == 3 ? 3 : 0,
      suggestEnhance: json['suggestEnhance'] != false,
    );
  }

  /// Aktif mod için işlem spesifikasyonu üretir.
  CaptureSpec specFor(CaptureMode m) {
    switch (m) {
      case CaptureMode.eokul:
        return CaptureSpec(
          aspect: 3 / 4,
          width: eokulResolution.width,
          height: eokulResolution.height,
          maxBytes: eokulMaxKb * 1024,
          minBytes: 20 * 1024,
          quality: 95,
        );
      case CaptureMode.biometric:
        // 5:6 oranı (50 × 60 mm). 600/720 = 5/6.
        return CaptureSpec(
          aspect: 5 / 6,
          width: biometricResolution.width,
          height: biometricResolution.height,
          maxBytes: null,
          minBytes: null,
          quality: 95,
          fileTag: biometricTag ? 'BIO' : '',
        );
      case CaptureMode.badge:
        return const CaptureSpec(
          aspect: 3 / 4,
          width: 600,
          height: 800,
          maxBytes: 900 * 1024,
          minBytes: null,
          quality: 93,
          drawInfoBand: true,
        );
    }
  }
}
