import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/app_settings.dart';

/// Kılavuz çerçevenin, **ekranda görünen önizleme alanına** göre normalize
/// (0..1) konumu.
///
/// Kameranın çektiği görüntü ile önizlemenin en-boy oranı farklı olabilir.
/// Eşleme `BoxFit.cover` mantığıyla _cropToGuide içinde uygulanır.
@immutable
class GuideCrop {
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Önizleme alanının en-boy oranı.
  final double previewAspect;

  const GuideCrop({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.previewAspect,
  });

  double get width => right - left;
  double get height => bottom - top;
}

/// Piksel kalitesi denetiminin sonucu.
@immutable
class PhotoAnalysis {
  /// Ortalama parlaklık (0–255).
  final double brightness;

  /// Üst köşelerden alınan arka plan ortalaması (0–255).
  final double backgroundBrightness;

  /// Arka plan standart sapması (ne kadar dalgalı/kabarık).
  final double backgroundStdDev;

  /// Önizlemede gösterilecek uyarılar.
  final List<String> warnings;

  const PhotoAnalysis({
    required this.brightness,
    required this.backgroundBrightness,
    required this.backgroundStdDev,
    required this.warnings,
  });

  bool get hasWarnings => warnings.isNotEmpty;
}

/// İşlenmiş fotoğraf.
@immutable
class ProcessedPhoto {
  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;

  /// Piksel analizi (uyarı kutuları için).
  final PhotoAnalysis analysis;

  /// Uygulanan mod.
  final CaptureMode mode;

  /// Otomatik parlaklık/kontrast iyileştirme uygulanmış mı.
  final bool enhanced;

  const ProcessedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
    required this.analysis,
    required this.mode,
    this.enhanced = false,
  });

  int get sizeInBytes => bytes.lengthInBytes;
  double get sizeInKb => bytes.lengthInBytes / 1024;
}

class PhotoProcessingException implements Exception {
  final String message;
  const PhotoProcessingException(this.message);

  @override
  String toString() => message;
}

/// Vesikalık üretim hattı — mod aware.
///
/// 1) EXIF yönüne göre düzelt
/// 2) kılavuz çerçeveyi çekilen görüntüye eşle (cover mantığı)
/// 3) mod oranına (3:4 / 5:6) sabitleyerek kırp
/// 4) mod çözünürlüğüne ölçekle
/// 5) (Yaka Kartı) koyu bilgi bandı + sınıf/numara işle
/// 6) Boyut penceresi varsa JPEG kalitesini dinamik ayarla, yoksa sabit
/// 7) Piksel analizi: parlaklık + arka plan standart sapması
class ImageProcessingService {
  const ImageProcessingService();

  /// Ağır işi ayrı isolate'te çalıştırır.
  static Future<ProcessedPhoto> process({
    required String sourcePath,
    required GuideCrop crop,
    required CaptureSpec spec,
    required CaptureMode mode,
    String className = '',
    String schoolNumber = '',
    bool applyEnhance = false,
  }) async {
    final result = await compute(_processInIsolate, <String, dynamic>{
      'path': sourcePath,
      'left': crop.left,
      'top': crop.top,
      'right': crop.right,
      'bottom': crop.bottom,
      'previewAspect': crop.previewAspect,
      'aspect': spec.aspect,
      'width': spec.width,
      'height': spec.height,
      'maxBytes': spec.maxBytes,
      'minBytes': spec.minBytes,
      'quality': spec.quality,
      'drawInfoBand': spec.drawInfoBand,
      'mode': mode.index,
      'className': className,
      'schoolNumber': schoolNumber,
      'enhance': applyEnhance,
    });

    final error = result['error'];
    if (error is String) throw PhotoProcessingException(error);

    final analysisMap = result['analysis'] as Map<String, dynamic>;
    final rawWarnings = analysisMap['warnings'] as List<dynamic>;

    return ProcessedPhoto(
      bytes: result['bytes'] as Uint8List,
      width: result['width'] as int,
      height: result['height'] as int,
      quality: result['quality'] as int,
      mode: mode,
      enhanced: applyEnhance,
      analysis: PhotoAnalysis(
        brightness: (analysisMap['brightness'] as num).toDouble(),
        backgroundBrightness:
            (analysisMap['backgroundBrightness'] as num).toDouble(),
        backgroundStdDev: (analysisMap['backgroundStdDev'] as num).toDouble(),
        warnings: rawWarnings.map((e) => e.toString()).toList(),
      ),
    );
  }

  /// Otomatik parlaklık/kontrast iyileştirme tahminini hesaplar.
  ///
  /// Karanlık fotoğraflar için brightness artırılır; gamma ile orta tonlar
  /// açılır. Kontrast, çok karanlık/gürültülü olmayan görsellerde hafif
  /// yükseltilir.
  static ({double brightness, double contrast, double gamma})
      enhanceParameters(double brightness) {
    if (brightness >= 150) {
      return (brightness: 0.0, contrast: 0.08, gamma: 1.0);
    }
    if (brightness >= 110) {
      return (brightness: 0.12, contrast: 0.10, gamma: 0.94);
    }
    if (brightness >= 75) {
      return (brightness: 0.25, contrast: 0.14, gamma: 0.85);
    }
    if (brightness >= 45) {
      return (brightness: 0.42, contrast: 0.18, gamma: 0.74);
    }
    return (brightness: 0.6, contrast: 0.22, gamma: 0.62);
  }
}

// -----------------------------------------------------------------------------
// Isolate gövdesi
// -----------------------------------------------------------------------------

Map<String, dynamic> _processInIsolate(Map<String, dynamic> a) {
  final path = a['path'] as String;
  final aspect = a['aspect'] as double;
  final width = a['width'] as int;
  final height = a['height'] as int;
  final maxBytes = a['maxBytes'] as int?;
  final minBytes = a['minBytes'] as int?;
  final quality = a['quality'] as int;
  final drawInfoBand = a['drawInfoBand'] as bool;
  final modeIndex = a['mode'] as int;
  final className = a['className'] as String;
  final schoolNumber = a['schoolNumber'] as String;
  final applyEnhance = a['enhance'] as bool;

  try {
    final file = File(path);
    if (!file.existsSync()) {
      return <String, dynamic>{'error': 'Çekilen fotoğraf dosyası bulunamadı.'};
    }

    var decoded = img.decodeImage(file.readAsBytesSync());
    if (decoded == null) {
      return <String, dynamic>{
        'error': 'Fotoğraf çözümlenemedi (bozuk görüntü).',
      };
    }

    decoded = img.bakeOrientation(decoded);

    final cropped = _cropToGuide(
      decoded,
      left: a['left'] as double,
      top: a['top'] as double,
      right: a['right'] as double,
      bottom: a['bottom'] as double,
      previewAspect: a['previewAspect'] as double,
      targetAspect: aspect,
    );
    if (cropped == null) {
      return <String, dynamic>{'error': 'Kırpma alanı görüntü dışında kaldı.'};
    }

    // Analiz, ölçeklemeden ÖNCE kaynak üzerinde daha doğrudur;
    // yine de normalizasyon için boyutu küçük tutup analizi final
    // görüntüde yapıyoruz ki kullanıcı gerçekten kaydedilecek görseli görsün.
    img.Image base = img.copyResize(
      cropped,
      width: width,
      height: height,
      interpolation: img.Interpolation.cubic,
    );

    // Yaka kartı: altına koyu bant + sınıf / okul numarası.
    if (drawInfoBand) {
      base = _drawInfoBand(base, className: className, number: schoolNumber);
    }

    // Kullanıcı tetikliyse otomatik iyileştirme.
    if (applyEnhance) {
      final pre = _safeAnalyze(base, isBiometric: modeIndex == 1);
      final params = ImageProcessingService.enhanceParameters(pre.brightness);
      try {
        base = img.adjustColor(
          base,
          brightness: params.brightness,
          contrast: params.contrast,
          gamma: params.gamma,
        );
      } catch (_) {
        // İyileştirme başarısızsa orijinal görünüm korunur.
      }
    }

    final analysis = _safeAnalyze(
      base,
      isBiometric: modeIndex == 1,
      wantEnhance: applyEnhance,
    );

    final int usedQuality;
    final Uint8List bytes;

    if (maxBytes == null) {
      // Boyut sınırı yok (biyometrik): sabit yüksek kalite.
      usedQuality = quality;
      bytes = img.encodeJpg(base, quality: usedQuality);
    } else {
      final encoded = _encodeIntoWindow(
        base,
        maxBytes: maxBytes,
        minBytes: minBytes,
        fallbackQuality: quality,
      );
      if (encoded == null) {
        // Pencereye girilemedi: üst sınırı aşmayan en iyi sürüm.
        var q = 60;
        var out = img.encodeJpg(base, quality: q);
        while (out.lengthInBytes > maxBytes && q > 30) {
          q -= 5;
          out = img.encodeJpg(base, quality: q);
        }
        usedQuality = q;
        bytes = out;
      } else {
        usedQuality = encoded.quality;
        bytes = encoded.bytes;
      }
    }

    return <String, dynamic>{
      'bytes': bytes,
      'width': base.width,
      'height': base.height,
      'quality': usedQuality,
      'analysis': <String, dynamic>{
        'brightness': analysis.brightness,
        'backgroundBrightness': analysis.backgroundBrightness,
        'backgroundStdDev': analysis.backgroundStdDev,
        'warnings': analysis.warnings,
      },
    };
  } catch (e) {
    return <String, dynamic>{'error': 'Fotoğraf işlenirken hata oluştu: $e'};
  }
}

/// Ekranda görülen alanı kaynak görüntüdeki bölgeye çevirir ve modun
/// en-boy oranına sabitleyerek kırpar (BoxFit.cover mantığı).
img.Image? _cropToGuide(
  img.Image source, {
  required double left,
  required double top,
  required double right,
  required double bottom,
  required double previewAspect,
  required double targetAspect,
}) {
  final srcW = source.width.toDouble();
  final srcH = source.height.toDouble();
  if (srcW <= 0 || srcH <= 0) return null;
  if (previewAspect <= 0) return null;

  final srcAspect = srcW / srcH;

  double visibleW;
  double visibleH;
  double offsetX;
  double offsetY;

  if (srcAspect > previewAspect) {
    visibleH = 1.0;
    visibleW = previewAspect / srcAspect;
    offsetX = (1.0 - visibleW) / 2;
    offsetY = 0.0;
  } else {
    visibleW = 1.0;
    visibleH = srcAspect / previewAspect;
    offsetX = 0.0;
    offsetY = (1.0 - visibleH) / 2;
  }

  final nLeft = offsetX + left * visibleW;
  final nTop = offsetY + top * visibleH;
  final nRight = offsetX + right * visibleW;
  final nBottom = offsetY + bottom * visibleH;

  var x0 = (nLeft * srcW).round();
  var y0 = (nTop * srcH).round();
  var w = ((nRight - nLeft) * srcW).round();
  var h = ((nBottom - nTop) * srcH).round();

  if (w <= 0 || h <= 0) return null;

  // Hedef orana sabitle: alanı büyütmeden merkezden daralt.
  final currentAspect = w / h;
  if (currentAspect > targetAspect) {
    final newW = (h * targetAspect).round();
    x0 += ((w - newW) / 2).round();
    w = newW;
  } else if (currentAspect < targetAspect) {
    final newH = (w / targetAspect).round();
    y0 += ((h - newH) / 2).round();
    h = newH;
  }

  if (x0 < 0) {
    w += x0;
    x0 = 0;
  }
  if (y0 < 0) {
    h += y0;
    y0 = 0;
  }
  if (x0 + w > srcW) w = srcW.round() - x0;
  if (y0 + h > srcH) h = srcH.round() - y0;
  if (w <= 0 || h <= 0) return null;

  return img.copyCrop(source, x: x0, y: y0, width: w, height: h);
}

class _Encoded {
  final Uint8List bytes;
  final int quality;
  const _Encoded(this.bytes, this.quality);
}

/// JPEG kalitesini ikili arama ile boyut penceresine oturtur.
_Encoded? _encodeIntoWindow(
  img.Image image, {
  required int maxBytes,
  required int? minBytes,
  required int fallbackQuality,
}) {
  const lower = 35;
  const upper = 100;

  final best = img.encodeJpg(image, quality: upper);
  if (best.lengthInBytes <= maxBytes) {
    if (minBytes == null || best.lengthInBytes >= minBytes) {
      return _Encoded(best, upper);
    }
    return null; // Çok küçük.
  }

  var lo = lower;
  var hi = upper;
  _Encoded? candidate;

  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final encoded = img.encodeJpg(image, quality: mid);
    if (encoded.lengthInBytes <= maxBytes) {
      candidate = _Encoded(encoded, mid);
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  if (candidate == null) return null;
  if (minBytes != null && candidate.bytes.lengthInBytes < minBytes) {
    return null;
  }
  return candidate;
}

/// Yaka kartı için alt kısma koyu bant çizer ve üzerine sınıf + okul numarası
/// yazar. Fotoğraf oranı korunur, yan boşluklar beyaz çerçeve olur.
img.Image _drawInfoBand(
  img.Image photo, {
  required String className,
  required String number,
}) {
  final w = photo.width;
  final h = photo.height;
  final bandH = (h * 0.2).round();

  // Tuval: beyaz zemin + fotoğraf.
  final canvas = img.copyExpandCanvas(
    photo,
    newWidth: w,
    newHeight: h,
    backgroundColor: img.ColorRgb8(255, 255, 255),
  );

  // Fotoğrafı bant dışında kalan alana, oranı korunarak yerleştir.
  final photoH = h - bandH;
  final scaled = img.copyResize(
    photo,
    height: photoH,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(canvas, scaled, dstX: ((w - scaled.width) / 2).round());

  // Koyu bant (dolgu dikdörtgen).
  img.fillRect(
    canvas,
    x1: 0,
    y1: photoH,
    x2: w,
    y2: h,
    color: img.ColorRgb8(24, 34, 58),
  );

  // Sınıf + okul numarası — yatayda ortalanmış iki satır.
  final baseFont = w >= 800 ? img.arial48 : img.arial24;
  final line2 = number.isEmpty ? '' : 'Okul No: $number';

  final y1 = photoH + (bandH * 0.24).round();
  final y2 = photoH + (bandH * 0.58).round();

  if (className.isNotEmpty) {
    _drawCentered(canvas, className, baseFont, w, y1,
        img.ColorRgb8(255, 255, 255));
  }
  if (line2.isNotEmpty) {
    _drawCentered(
        canvas, line2, baseFont, w, y2, img.ColorRgb8(180, 205, 255));
  }

  return canvas;
}

/// Metni verilen `y` konumunda, yatayda ortalanmış çizer.
void _drawCentered(
  img.Image canvas,
  String text,
  img.BitmapFont font,
  int canvasWidth,
  int y,
  img.Color color,
) {
  final safe = _asciiSafe(text);
  if (safe.isEmpty) return;

  // Her karakterin advance (ilerleme) miktarını topla — BitmapFont'ta
  // sabit genişlik garantisi yoktur.
  var textWidth = 0;
  for (var i = 0; i < safe.length; i++) {
    textWidth += font.characterXAdvance(safe[i]);
  }

  final x = ((canvasWidth - textWidth) / 2).round().clamp(0, canvasWidth);
  try {
    img.drawString(canvas, safe, font: font, x: x, y: y, color: color);
  } catch (_) {
    // Font çizimi başarısızsa görsel yine geçerli kalır.
  }
}

/// Bitmap fontlar Türkçe karakteri kapsamaz; klasör adları ASCII'ye
/// zaten çevrilidir (StorageService), burada ek güvenlik sağlaması yaparız.
String _asciiSafe(String input) {
  const map = <String, String>{
    'ı': 'i', 'İ': 'I', 'ş': 's', 'Ş': 'S', 'ğ': 'g', 'Ğ': 'G',
    'ü': 'u', 'Ü': 'U', 'ö': 'o', 'Ö': 'O', 'ç': 'c', 'Ç': 'C',
  };
  final b = StringBuffer();
  for (final r in input.runes) {
    final ch = String.fromCharCode(r);
    if (map.containsKey(ch)) {
      b.write(map[ch]);
    } else if (r < 128) {
      b.write(ch);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// Analiz hatası üretim süreçini durdurmasın diye emniyet katmanı.
PhotoAnalysis _safeAnalyze(
  img.Image image, {
  required bool isBiometric,
  bool wantEnhance = false,
}) {
  try {
    return _analyze(image, isBiometric: isBiometric, wantEnhance: wantEnhance);
  } catch (_) {
    return const PhotoAnalysis(
      brightness: 128,
      backgroundBrightness: 200,
      backgroundStdDev: 0,
      warnings: <String>[],
    );
  }
}

/// Piksel analizi: ortalama parlaklık + üst köşelerden arka plan örneği.
PhotoAnalysis _analyze(
  img.Image image, {
  required bool isBiometric,
  bool wantEnhance = false,
}) {
  // Örnekleme: her N. piksel — tek isolate'te hızlı kalsın.
  const step = 4;
  var sum = 0.0;
  var count = 0;

  for (var y = 0; y < image.height; y += step) {
    for (var x = 0; x < image.width; x += step) {
      final p = image.getPixel(x, y);
      sum += _luma(p.r, p.g, p.b);
      count++;
    }
  }
  final brightness = count == 0 ? 128.0 : sum / count;

  // Arka plan: dört üst köşeden %18'lik kareler.
  final corner = (image.width * 0.18).round().clamp(8, 200);
  final regions = <(int, int)>[
    (0, 0),
    (image.width - corner, 0),
    (0, (image.height * 0.10).round()),
    (image.width - corner, (image.height * 0.10).round()),
  ];

  var bgSum = 0.0;
  var bgCount = 0;
  final samples = <double>[];

  for (final (rx, ry) in regions) {
    for (var y = ry; y < ry + corner && y < image.height; y += 2) {
      for (var x = rx; x < rx + corner && x < image.width; x += 2) {
        final p = image.getPixel(x, y);
        final v = _luma(p.r, p.g, p.b);
        samples.add(v);
        bgSum += v;
        bgCount++;
      }
    }
  }

  final bgMean = bgCount == 0 ? 0.0 : bgSum / bgCount;
  var variance = 0.0;
  if (samples.isNotEmpty) {
    for (final s in samples) {
      variance += (s - bgMean) * (s - bgMean);
    }
    variance /= samples.length;
  }
  final bgStd = variance <= 0 ? 0.0 : _sqrt(variance);

  final warnings = <String>[];

  if (brightness < 78) {
    warnings.add(
      'Fotoğraf karanlık çıktı! Pozlamayı artırıp yeniden çekmeniz önerilir.',
    );
  } else if (brightness < 105) {
    warnings.add(
      'Ortam ışığı biraz düşük görünüyor. "Parlaklığı İyileştir" '
      'etkinleştirebilir veya pencereye yaklaşabilirsiniz.',
    );
  }

  if (isBiometric) {
    if (bgMean < 150) {
      warnings.add('Biyometrik arka plan koyu görünüyor! Beyaz/açık renk '
          'arka plan tercih edin.');
    } else if (bgStd > 42) {
      warnings.add('Biyometrik arka plan dalgalı/gölgelidir! Düz zemin '
          'kullanın (standart: beyaz, gölgesiz).');
    }
  }

  return PhotoAnalysis(
    brightness: brightness,
    backgroundBrightness: bgMean,
    backgroundStdDev: bgStd,
    warnings: warnings,
  );
}

double _luma(num r, num g, num b) {
  // Rec.709 luma ağırlıkları.
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Karekök — math paketi import etmeden, Newton yaklaşımı.
double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 24; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

/// Ekranda çizilecek kılavuz çerçevenin geometrisi (mod oranına göre).
class GuideGeometry {
  const GuideGeometry._();

  /// [area] içine yerleşen, [aspect] oranında kılavuz çerçeve.
  static Rect frameInside(
    Rect area, {
    double aspect = 3 / 4,
    double widthFactor = 0.76,
  }) {
    var w = area.width * widthFactor;
    var h = w / aspect;

    final maxHeight = area.height * 0.80;
    if (h > maxHeight) {
      h = maxHeight;
      w = h * aspect;
    }

    final left = area.left + (area.width - w) / 2;
    final top = area.top + (area.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }
}
