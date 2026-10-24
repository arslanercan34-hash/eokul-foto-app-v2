import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:eokul_fotograf/models/app_settings.dart';
import 'package:eokul_fotograf/services/image_processing_service.dart';
import 'package:eokul_fotograf/services/storage_service.dart';

void main() {
  group('e-Okul modu', () {
    test('varsayılan spesifikasyon: 3:4, 300x400, <50 KB', () {
      const settings = AppSettings();
      final spec = settings.specFor(CaptureMode.eokul);

      expect(spec.aspect, closeTo(0.75, 1e-9));
      expect(spec.width, 300);
      expect(spec.height, 400);
      expect(spec.maxBytes, 49 * 1024);
      expect(spec.minBytes, 20 * 1024);
    });

    test('133x171 seçeneği oranını korur', () {
      const settings = AppSettings(eokulResolution: EokulResolution.r133x171);
      final spec = settings.specFor(CaptureMode.eokul);

      expect(spec.width, 133);
      expect(spec.height, 171);
      expect(
        spec.width / spec.height,
        closeTo(EokulResolution.r133x171.width /
            EokulResolution.r133x171.height,
            1e-9),
      );
    });

    test('düşük boyut sınırı 15 KB altına düşmez', () {
      final settings = const AppSettings().copyWith(eokulMaxKb: 500);
      expect(settings.eokulMaxKb, 50);
    });
  });

  group('Biyometrik modu', () {
    test('5:6 oranı ve boyut sınırı yok', () {
      const settings = AppSettings();
      final spec = settings.specFor(CaptureMode.biometric);

      expect(spec.aspect, closeTo(5 / 6, 1e-9));
      expect(spec.maxBytes, isNull);
      expect(spec.minBytes, isNull);
      expect(spec.width / spec.height, closeTo(5 / 6, 1e-6));
      expect(spec.quality, 95);
    });

    test('rozet açıkken dosya etiketi BIO olur', () {
      const settings = AppSettings(biometricTag: true);
      expect(settings.specFor(CaptureMode.biometric).fileTag, 'BIO');

      const off = AppSettings(biometricTag: false);
      expect(off.specFor(CaptureMode.biometric).fileTag, '');
    });
  });

  group('Yaka Kartı modu', () {
    test('3:4 oran, 600x800 ve bilgi bandı açık', () {
      const settings = AppSettings();
      final spec = settings.specFor(CaptureMode.badge);

      expect(spec.aspect, closeTo(0.75, 1e-9));
      expect(spec.width, 600);
      expect(spec.height, 800);
      expect(spec.drawInfoBand, isTrue);
    });
  });

  group('Ayar JSON dayanıklılığı', () {
    test('bozuk veri varsayılana düşer', () {
      final settings = AppSettings.fromJson(<String, dynamic>{'mode': 'yok'});
      expect(settings.mode, CaptureMode.eokul);
      expect(settings.eokulResolution, EokulResolution.r300x400);
    });

    test('tam çevrim (round-trip) değerleri korur', () {
      const original = AppSettings(
        mode: CaptureMode.badge,
        eokulResolution: EokulResolution.r133x171,
        biometricResolution: BiometricResolution.r1200x1440,
        eokulMaxKb: 25,
        biometricTag: true,
        timerSeconds: 3,
        suggestEnhance: false,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.mode, original.mode);
      expect(restored.eokulResolution, original.eokulResolution);
      expect(restored.biometricResolution, original.biometricResolution);
      expect(restored.eokulMaxKb, 25);
      expect(restored.biometricTag, isTrue);
      expect(restored.timerSeconds, 3);
      expect(restored.suggestEnhance, isFalse);
    });
  });

  group('Kılavuz çerçeve geometrisi', () {
    test('çerçeve modun oranını korur', () {
      const area = Rect.fromLTWH(0, 0, 1080, 2400);
      final frame34 = GuideGeometry.frameInside(area, aspect: 3 / 4);
      final frame56 = GuideGeometry.frameInside(area, aspect: 5 / 6);

      expect(frame34.width / frame34.height, closeTo(3 / 4, 1e-6));
      expect(frame56.width / frame56.height, closeTo(5 / 6, 1e-6));
    });

    test('çerçeve ekran içinde kalır', () {
      const area = Rect.fromLTWH(0, 0, 720, 1280);
      final frame = GuideGeometry.frameInside(area, aspect: 5 / 6);

      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(area.width));
      expect(frame.bottom, lessThanOrEqualTo(area.height));
    });

    test('yatay ekranda çerçeve taşmaz', () {
      const area = Rect.fromLTWH(0, 0, 2400, 1080);
      final frame = GuideGeometry.frameInside(area, aspect: 3 / 4);
      expect(frame.height, lessThanOrEqualTo(area.height));
      expect(frame.width / frame.height, closeTo(3 / 4, 1e-6));
    });
  });

  group('Otomatik iyileştirme parametreleri', () {
    test('karanlık görüntü için belirgin parlaklık artışı', () {
      final dark = ImageProcessingService.enhanceParameters(50);
      final bright = ImageProcessingService.enhanceParameters(200);

      expect(dark.brightness, greaterThan(bright.brightness));
      expect(dark.gamma, lessThan(1.0));
    });
  });

  group('Sınıf adı temizleme', () {
    test('geçerli adlar korunur', () {
      expect(StorageService.sanitizeClassName('5-A'), '5-A');
      expect(StorageService.sanitizeClassName('8/B'), '8-B');
    });

    test('Türkçe karakterler ASCII karşılığına çevrilir', () {
      expect(StorageService.sanitizeClassName('5-Şube'), '5-Sube');
      expect(StorageService.sanitizeClassName('5-ığ'), '5-ig');
    });

    test('geçersiz karakterler tireye dönüşür', () {
      expect(StorageService.sanitizeClassName('5/A!!'), '5-A');
    });

    test('boş girdi güvenli varsayılana döner', () {
      expect(StorageService.sanitizeClassName(''), 'Sinif');
      expect(StorageService.sanitizeClassName('   '), 'Sinif');
    });
  });
}
