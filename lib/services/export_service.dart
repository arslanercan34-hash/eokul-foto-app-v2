import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import 'storage_service.dart';

/// Hazırlanan dışa aktarma dosyası.
@immutable
class ExportArtifact {
  final File file;
  final String description;

  const ExportArtifact({required this.file, required this.description});

  String get fileName => p.basename(file.path);

  double get sizeInKb {
    try {
      return file.lengthSync() / 1024;
    } catch (_) {
      return 0;
    }
  }
}

/// Dışa aktarma hatası (kullanıcıya gösterilebilir).
class ExportException implements Exception {
  final String message;
  const ExportException(this.message);

  @override
  String toString() => message;
}

/// Görsel dışa aktarma araçları — yalnızca `image` kütüphanesi + saf Dart.
///
/// Kullanılan API'ler (image 4.x):
///   copyExpandCanvas / fillRect / drawRect / drawLine / drawString /
///   compositeImage / copyResize / decodeImage / encodeJpg / BitmapFont
class ExportService {
  ExportService._();

  static final ExportService instance = ExportService._();

  // Palet (RGB8).
  static img.Color _c(int r, int g, int b) => img.ColorRgb8(r, g, b);
  static final img.Color paper = _c(255, 255, 255);
  static final img.Color ink = _c(26, 30, 44);
  static final img.Color muted = _c(91, 100, 120);
  static final img.Color line = _c(201, 207, 221);
  static final img.Color cardBg = _c(228, 232, 241);

  Future<Directory> _cache() async {
    final root = Directory(
      p.join((await getTemporaryDirectory()).path, 'exports'),
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  // ---------------------------------------------------------------------------
  // 1) Fotoğraflı Sınıf Listesi (Tablo / Albüm)
  // ---------------------------------------------------------------------------

  /// Sınıfın tüm fotoğraflarını beyaz tuvale ızgara dizip altlarına okul
  /// numaralarını yazar. Sonuç: tek yüksek çözünürlüklü `.jpg`.
  Future<ExportArtifact> buildClassRoster(ClassFolder classFolder) async {
    if (classFolder.photos.isEmpty) {
      throw const ExportException('Sınıfta fotoğraf yok.');
    }

    const columns = 6;
    const cellWidth = 220;
    const cellImageHeight = 293; // 3:4
    const captionHeight = 46;
    const padding = 16;
    const headerHeight = 96;
    const footerHeight = 34;

    final photos = classFolder.sortedPhotos;
    final rows = (photos.length / columns).ceil();

    final canvasWidth = columns * cellWidth + (columns + 1) * padding;
    final canvasHeight = headerHeight +
        rows * (cellImageHeight + captionHeight + padding) +
        footerHeight +
        padding;

    final canvas = _newCanvas(canvasWidth, canvasHeight, paper);

    // Başlık bandı.
    img.fillRect(
      canvas,
      x1: 0,
      y1: 0,
      x2: canvasWidth,
      y2: headerHeight,
      color: ink,
    );
    _writeCentered(
      canvas,
      '${classFolder.name} - ${photos.length} Ogrenci',
      img.arial48,
      canvasWidth,
      28,
      paper,
    );
    _writeCentered(
      canvas,
      'e-Okul Vesikalik Albm Listesi',
      img.arial24,
      canvasWidth,
      72,
      _c(185, 196, 220),
    );

    for (var i = 0; i < photos.length; i++) {
      final row = i ~/ columns;
      final col = i % columns;

      final x = padding + col * (cellWidth + padding);
      final y = headerHeight +
          padding +
          row * (cellImageHeight + captionHeight + padding);

      img.Image? photo;
      try {
        final bytes = await photos[i].file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        photo = decoded != null
            ? img.copyResize(
                decoded,
                width: cellWidth,
                height: cellImageHeight,
                interpolation: img.Interpolation.cubic,
              )
            : null;
      } catch (_) {
        photo = null;
      }

      // Hücre zemini + çerçeve.
      img.fillRect(
        canvas,
        x1: x,
        y1: y,
        x2: x + cellWidth,
        y2: y + cellImageHeight,
        color: cardBg,
      );
      if (photo != null) {
        img.compositeImage(canvas, photo, dstX: x, dstY: y);
      }
      img.drawRect(
        canvas,
        x1: x,
        y1: y,
        x2: x + cellWidth - 1,
        y2: y + cellImageHeight - 1,
        color: line,
      );

      // Alt yazı: okul numarası.
      _writeCentered(
        canvas,
        photos[i].schoolNumber,
        img.arial24,
        cellWidth,
        y + cellImageHeight + 10,
        muted,
        originX: x,
      );
    }

    // Alt bilgi.
    _writeCentered(
      canvas,
      'e-Okul & Biyometrik Vesikalik Pro - Ercan ARSLAN',
      img.arial24,
      canvasWidth,
      canvasHeight - footerHeight,
      muted,
    );

    final out = File(
      p.join((await _cache()).path, '${classFolder.name}_Sinif_Listesi.jpg'),
    );
    await _writeJpeg(out, canvas, 92);
    return ExportArtifact(
      file: out,
      description: '${photos.length} fotoğraflı sınıf listesi',
    );
  }

  // ---------------------------------------------------------------------------
  // 2) Çoklu Vesikalık Baskı Şablonu (10×15 cm — 8'li)
  // ---------------------------------------------------------------------------

  /// Bir fotoğrafı, standart 10×15 cm fotoğraf kağıdına 4 sütun × 2 satır
  /// (8 adet) kesim çizgili olarak dizer. 300 dpi → 1772 × 1181 px.
  Future<ExportArtifact> buildPrintSheet(StudentPhoto photo) async {
    const canvasW = 1772;
    const canvasH = 1181;
    const columns = 4;
    const rows = 2;

    final cellW = canvasW ~/ columns;
    final cellH = canvasH ~/ rows;

    final decoded = img.decodeImage(await photo.file.readAsBytes());
    if (decoded == null) {
      throw const ExportException('Fotoğraf çözümlenemedi.');
    }

    final canvas = _newCanvas(canvasW, canvasH, paper);
    final fitted = _coverFit(decoded, cellW, cellH);

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final x = c * cellW + (cellW - fitted.width) ~/ 2;
        final y = r * cellH + (cellH - fitted.height) ~/ 2;
        img.compositeImage(canvas, fitted, dstX: x, dstY: y);
      }
    }

    // Kesim çizgileri.
    for (var c = 1; c < columns; c++) {
      img.drawLine(
        canvas,
        x1: c * cellW,
        y1: 0,
        x2: c * cellW,
        y2: canvasH,
        color: line,
        thickness: 2,
      );
    }
    for (var r = 1; r < rows; r++) {
      img.drawLine(
        canvas,
        x1: 0,
        y1: r * cellH,
        x2: canvasW,
        y2: r * cellH,
        color: line,
        thickness: 2,
      );
    }

    final out = File(
      p.join(
        (await _cache()).path,
        'Baski_${photo.schoolNumber}_8li_10x15.jpg',
      ),
    );
    await _writeJpeg(out, canvas, 95);
    return ExportArtifact(
      file: out,
      description: '10×15 cm baskı şablonu (8 adet, kesim çizgili)',
    );
  }

  // ---------------------------------------------------------------------------
  // 3) Biyometrik → e-Okul toplu dönüştürme
  // ---------------------------------------------------------------------------

  /// Verilen fotoğrafları e-Okul spesifikasyonuna (300×400, 20–50 KB)
  /// dönüştürür: `(okulNumarası, jpegBaytları)` çiftleri döndürür.
  Future<List<(String, List<int>)>> convertToEokul(
    List<StudentPhoto> photos, {
    AppSettings settings = const AppSettings(),
  }) async {
    final spec = settings.specFor(CaptureMode.eokul);
    final converted = <(String, List<int>)>[];

    for (final photo in photos) {
      final bytes = await _convertOne(photo.file, spec);
      if (bytes != null) {
        converted.add((photo.schoolNumber, bytes));
      }
    }
    return converted;
  }

  Future<List<int>?> _convertOne(File file, CaptureSpec spec) async {
    try {
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return null;

      final base = img.copyResize(
        decoded,
        width: spec.width,
        height: spec.height,
        interpolation: img.Interpolation.cubic,
      );

      final maxBytes = spec.maxBytes ?? 49 * 1024;
      final minBytes = spec.minBytes ?? 20 * 1024;

      // İkili arama: üst sınırı aşmayan en yüksek kalite.
      var lo = 35;
      var hi = 100;
      Uint8List? best;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final encoded = img.encodeJpg(base, quality: mid);
        if (encoded.lengthInBytes <= maxBytes) {
          best = encoded;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }

      if (best == null) {
        var q = 70;
        var out = img.encodeJpg(base, quality: q);
        while (out.lengthInBytes > maxBytes && q > 30) {
          q -= 5;
          out = img.encodeJpg(base, quality: q);
        }
        return out;
      }

      // Alt sınır aşılırsa üst sınırı koruyan en iyi sürüm geri döner.
      if (best.lengthInBytes < minBytes) {
        return img.encodeJpg(base, quality: 95);
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------------

  img.Image _newCanvas(int width, int height, img.Color background) {
    // NOT: image 4.12'de Image() constructor'ı NAMED parametreli
    //   Image(width: ..., height: ...)
    return img.copyExpandCanvas(
      img.Image(width: width, height: height),
      newWidth: width,
      newHeight: height,
      backgroundColor: background,
    );
  }

  /// Görseli [cellW]×[cellH] alana BoxFit.cover ile sığdırır.
  img.Image _coverFit(img.Image src, int cellW, int cellH) {
    final srcAspect = src.width / src.height;
    final dstAspect = cellW / cellH;

    if (srcAspect > dstAspect) {
      return img.copyResize(
        src,
        width: (src.height * dstAspect).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
    return img.copyResize(
      src,
      height: (src.width / dstAspect).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  void _writeCentered(
    img.Image canvas,
    String text,
    img.BitmapFont font,
    int regionWidth,
    int y,
    img.Color color, {
    int originX = 0,
  }) {
    final safe = _ascii(text);
    if (safe.isEmpty) return;

    var textWidth = 0;
    for (var i = 0; i < safe.length; i++) {
      textWidth += font.characterXAdvance(safe[i]);
    }

    final offset =
        ((regionWidth - textWidth) / 2).round().clamp(0, regionWidth);
    final x = (originX + offset).clamp(0, canvas.width - 1);
    try {
      img.drawString(canvas, safe, font: font, x: x, y: y, color: color);
    } catch (_) {
      // Font çizimi başarısızsa görsel yine geçerli kalır.
    }
  }

  /// Bitmap fontlar Türkçe karakteri kapsamaz.
  String _ascii(String input) {
    const map = <String, String>{
      'ı': 'i', 'İ': 'I', 'ş': 's', 'Ş': 'S', 'ğ': 'g', 'Ğ': 'G',
      'ü': 'u', 'Ü': 'U', 'ö': 'o', 'Ö': 'O', 'ç': 'c', 'Ç': 'C',
      'â': 'a', 'î': 'i', 'û': 'u',
    };
    final b = StringBuffer();
    for (final r in input.runes) {
      final ch = String.fromCharCode(r);
      if (map.containsKey(ch)) {
        b.write(map[ch]);
      } else if (r < 128) {
        b.write(ch);
      } else {
        b.write(' ');
      }
    }
    return b.toString().trim();
  }

  Future<void> _writeJpeg(File file, img.Image image, int quality) async {
    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsBytes(
      img.encodeJpg(image, quality: quality),
      flush: true,
    );
  }
}
