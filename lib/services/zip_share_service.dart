import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_settings.dart';
import 'export_service.dart';
import 'storage_service.dart';

/// ZIP oluşturma sonucu.
class ZipResult {
  final File file;
  final int photoCount;

  const ZipResult({required this.file, required this.photoCount});

  String get fileName => p.basename(file.path);

  double get sizeInMb {
    try {
      return file.lengthSync() / (1024 * 1024);
    } catch (_) {
      return 0;
    }
  }
}

/// ZIP paylaşma servisi.
///
/// Üç üretici:
///   * `buildClassZip`            — sınıf içinde düz (`1042.jpg`)
///   * `buildWholeSchoolZip`      — okul geneli hiyerarşik (`5-A/1042.jpg`)
///   * `buildConvertedEokulZip`   — biyometrikten e-Okul'a dönüştürülmüş
class ZipShareService {
  ZipShareService._();

  static final ZipShareService instance = ZipShareService._();

  Future<Directory> _cacheDirectory() async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'zips'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _writeZip(String fileName, Archive archive) async {
    // JPEG'ler zaten sıkıştırılmıştır; varsayılan seviye yeterlidir.
    final Uint8List encoded = ZipEncoder().encodeBytes(archive);
    if (encoded.isEmpty) {
      throw const ZipShareException('ZIP arşivi oluşturulamadı.');
    }

    final file = File(p.join((await _cacheDirectory()).path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  // ---------------------------------------------------------------------------
  // Sınıf ZIP'i
  // ---------------------------------------------------------------------------

  /// `[Sinif_Adi]_eOkul_Fotograflari.zip` — içeriği düz `1042.jpg`.
  Future<ZipResult> buildClassZip(ClassFolder classFolder) async {
    if (classFolder.photos.isEmpty) {
      throw const ZipShareException('Bu sınıfta henüz fotoğraf yok.');
    }

    final archive = Archive();
    var added = 0;

    for (final photo in classFolder.sortedPhotos) {
      try {
        final bytes = await photo.file.readAsBytes();
        archive.addFile(
          ArchiveFile('${photo.schoolNumber}.jpg', bytes.length, bytes),
        );
        added++;
      } catch (_) {
        // Okunamayan tek dosya tüm arşivi düşürmesin.
      }
    }

    if (added == 0) {
      throw const ZipShareException('Fotoğraf dosyaları okunamadı.');
    }

    final file = await _writeZip(
      '${classFolder.name}_eOkul_Fotograflari.zip',
      archive,
    );
    return ZipResult(file: file, photoCount: added);
  }

  Future<ZipResult> shareClass(
    ClassFolder classFolder, {
    Rect? sharePositionOrigin,
  }) async {
    final result = await buildClassZip(classFolder);
    await _share(
      file: result.file,
      subject: '${classFolder.name} - e-Okul Fotoğrafları',
      text: '${classFolder.name} sınıfı e-Okul vesikalık fotoğrafları '
          '(${result.photoCount} öğrenci).',
      sharePositionOrigin: sharePositionOrigin,
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // Okul geneli ZIP (hiyerarşik)
  // ---------------------------------------------------------------------------

  /// Tüm sınıfları tek arşive: `SinifAdi/OkulNo.jpg`.
  Future<ZipResult> buildWholeSchoolZip(List<ClassFolder> classes) async {
    final archive = Archive();
    var added = 0;

    for (final classFolder in classes) {
      for (final photo in classFolder.photos) {
        try {
          final bytes = await photo.file.readAsBytes();
          final name =
              '${classFolder.name}/${photo.schoolNumber}.jpg';
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
          added++;
        } catch (_) {
          // Tek dosya hatası arşivi düşürmesin.
        }
      }
    }

    if (added == 0) {
      throw const ZipShareException('Hiç fotoğraf bulunamadı.');
    }

    final file = await _writeZip('Tum_Okul_eOkul_Fotograflari.zip', archive);
    return ZipResult(file: file, photoCount: added);
  }

  Future<ZipResult> shareWholeSchool(
    List<ClassFolder> classes, {
    Rect? sharePositionOrigin,
  }) async {
    final result = await buildWholeSchoolZip(classes);
    await _share(
      file: result.file,
      subject: 'Okul Geneli e-Okul Fotoğrafları',
      text: 'Okulun tüm sınıflarından ${result.photoCount} vesikalık '
          '(${classes.length} sınıf, klasör yapısıyla).',
      sharePositionOrigin: sharePositionOrigin,
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // Biyometrik → e-Okul dönüştürme ZIP'i
  // ---------------------------------------------------------------------------

  /// Sınıfın fotoğraflarını (çözünürlüğü ne olursa olsun) e-Okul
  /// spesifikasyonuna (300×400, 20–50 KB) dönüştürüp ZIP'ler.
  Future<ZipResult> buildConvertedEokulZip(
    ClassFolder classFolder, {
    AppSettings? settings,
  }) async {
    if (classFolder.photos.isEmpty) {
      throw const ZipShareException('Bu sınıfta fotoğraf yok.');
    }

    final export = ExportService.instance;
    final converted = await export.convertToEokul(
      classFolder.photos,
      settings: settings ?? const AppSettings(),
    );

    if (converted.isEmpty) {
      throw const ZipShareException(
        'Fotoğraflar dönüştürülemedi (dosyalar okunamadı).',
      );
    }

    final archive = Archive();
    for (final (number, bytes) in converted) {
      archive.addFile(ArchiveFile('$number.jpg', bytes.length, bytes));
    }

    final file = await _writeZip(
      '${classFolder.name}_eOkul_Donusturulmus.zip',
      archive,
    );
    return ZipResult(file: file, photoCount: converted.length);
  }

  Future<ZipResult> shareConvertedEokul(
    ClassFolder classFolder, {
    AppSettings? settings,
    Rect? sharePositionOrigin,
  }) async {
    final result = await buildConvertedEokulZip(
      classFolder,
      settings: settings,
    );
    await _share(
      file: result.file,
      subject: '${classFolder.name} - e-Okul Formatına Dönüştürüldü',
      text: '${classFolder.name}: ${result.photoCount} fotoğraf 300×400 px, '
          '20–50 KB e-Okul formatına dönüştürüldü.',
      sharePositionOrigin: sharePositionOrigin,
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // Genel paylaşım yardımcısı
  // ---------------------------------------------------------------------------

  /// Herhangi bir dosyayı Android paylaşım menüsüyle açar.
  Future<void> shareFile(
    File file, {
    required String subject,
    required String text,
    Rect? sharePositionOrigin,
  }) {
    return _share(
      file: file,
      subject: subject,
      text: text,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<void> _share({
    required File file,
    required String subject,
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/zip')],
        subject: subject,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}

/// Kullanıcıya gösterilebilecek ZIP hatası.
class ZipShareException implements Exception {
  final String message;
  const ZipShareException(this.message);

  @override
  String toString() => message;
}
