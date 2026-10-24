import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// İzin isteme sonucu.
enum PermissionOutcome {
  /// İzin verildi.
  granted,

  /// Reddedildi; tekrar istenebilir.
  denied,

  /// Kalıcı olarak reddedildi; yalnızca uygulama ayarlarından açılabilir.
  permanentlyDenied,

  /// Platform bu izni desteklemiyor.
  unsupported,
}

/// Kamera ve depolama izinlerini yönetir.
///
/// Not: Fotoğraflar uygulamaya ait özel dizine (`getExternalStorageDirectory`)
/// yazıldığı için Android 11+ üzerinde depolama izni GEREKMEZ. İzinler yine
/// de tanımlıdır ve Android 9 ve altında / bazı MIUI sürümlerinde istendiği
/// için burada yönetilir.
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  /// Kamera OTURUMU için gereken izinlerin tamamı (kamera + mikrofon).
  ///
  /// Mikrofon izni ses kaydı için DEĞİL, kamera oturumunun önizleme
  /// yüzeyinin açılması için gerekiyor (MIUI/HyperOS dahil bir çok HAL,
  /// ses yuvası olmadan preview'i başlatmıyor).
  ///
  /// İzin kalıcı reddedildiyse kamera sonucu önceliklidir; mikrofon
  /// reddedilirse session yine de denenebilir — bu yüzden dönen sonuç
  /// her zaman KAMERA izninin sonucudur.
  Future<PermissionOutcome> requireCapture() async {
    final camera = await requireCamera();

    try {
      final mic = await _request(Permission.microphone).timeout(
        const Duration(seconds: 5),
        onTimeout: () => PermissionOutcome.unsupported,
      );
      // Mikrofon reddedilmişse sessizce devam: kamera yine de çalışabilir;
      // çalışmasa bile izin ayarları teşhis sayfasında gösterilir.
      debugPrint('[permission] microphone: ${mic.name}');
    } catch (_) {}

    return camera;
  }

  /// Kamera iznini zorunlu olarak ister.
  ///
  /// MIUI/HyperOS düzeltmeleri:
  ///  * Bazı sürümlerde izin dialogu kapanır ama Future HİÇ DÖNMEZ →
  ///    5 saniyede kesilir; sonra gerçek izin durumu yeniden okunur.
  ///  * Bazı sürümlerde ilk istek izinsiz "denied" döner → bir kez daha
  ///    denenir.
  Future<PermissionOutcome> requireCamera() async {
    var outcome = await _request(Permission.camera).timeout(
      const Duration(seconds: 5),
      onTimeout: () => PermissionOutcome.unsupported, // aşağıda çözülür
    );

    if (outcome == PermissionOutcome.unsupported) {
      // Zaman aşımı: dialog kaybolmuş olabilir — durumu doğrudan sorgula.
      outcome = await _statusOnly(Permission.camera);
    }

    if (outcome == PermissionOutcome.denied) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final retry = await _request(Permission.camera).timeout(
        const Duration(seconds: 5),
        onTimeout: () => PermissionOutcome.unsupported,
      );
      outcome = retry == PermissionOutcome.unsupported
          ? await _statusOnly(Permission.camera)
          : retry;
    }

    return outcome;
  }

  /// Sadece mevcut izin durumunu okur (dialog göstermez).
  Future<PermissionOutcome> _statusOnly(Permission permission) async {
    try {
      final status = await permission.status
          .timeout(const Duration(seconds: 3));
      if (status.isGranted || status.isLimited) {
        return PermissionOutcome.granted;
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        return PermissionOutcome.permanentlyDenied;
      }
      return PermissionOutcome.denied;
    } catch (_) {
      // Durum bile okunamazsa: kamera açık olabilir; ilerlemeyi dene.
      return PermissionOutcome.granted;
    }
  }

  /// Depolama izinlerini ister. Sonuç "granted" olmasa bile uygulama kendi
  /// dizinine yazabildiği için kritik değildir.
  Future<PermissionOutcome> ensureStorage() async {
    if (!Platform.isAndroid) return PermissionOutcome.unsupported;

    // Android 13+ : READ_MEDIA_IMAGES ; Android <= 12 : READ/WRITE_STORAGE.
    // permission_handler her ikisini de tek çağrıda çözer: desteklenmeyen
    // izin "granted" ya da "restricted" olarak döner, hata fırlatmaz.
    try {
      final statuses = await <Permission>[
        Permission.photos,
        Permission.storage,
      ].request();

      var sawDenied = false;
      for (final status in statuses.values) {
        if (status.isGranted || status.isLimited) {
          return PermissionOutcome.granted;
        }
        if (status.isPermanentlyDenied) {
          sawDenied = true;
        }
      }
      return sawDenied
          ? PermissionOutcome.permanentlyDenied
          : PermissionOutcome.denied;
    } catch (_) {
      return PermissionOutcome.unsupported;
    }
  }

  /// Uygulama ayarlarını açar.
  Future<bool> openSettings() => openAppSettings();

  /// İzin durumunun şu an "kalıcı reddedildi" olup olmadığını döndürür.
  Future<bool> isCameraPermanentlyDenied() async {
    try {
      final status = await Permission.camera.status;
      return status.isPermanentlyDenied || status.isRestricted;
    } catch (_) {
      return false;
    }
  }

  Future<PermissionOutcome> _request(Permission permission) async {
    try {
      final status = await permission.status;
      if (status.isGranted || status.isLimited) {
        return PermissionOutcome.granted;
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        return PermissionOutcome.permanentlyDenied;
      }

      final result = await permission.request();
      if (result.isGranted || result.isLimited) {
        return PermissionOutcome.granted;
      }
      if (result.isPermanentlyDenied || result.isRestricted) {
        return PermissionOutcome.permanentlyDenied;
      }
      return PermissionOutcome.denied;
    } catch (_) {
      return PermissionOutcome.unsupported;
    }
  }
}
