import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/camera_service.dart';
import '../services/image_processing_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/guide_overlay.dart';

/// Biyometrik stüdyo uyarıları — 3 saniyede bir değişir.
const List<String> kBiometricTips = <String>[
  'Gözleri yatay yeşil şeridin içine hizalayın',
  'Baş dik, yüz kameraya tam dönük olmalı',
  'Ağzınızı kapatın, nötr ifade koruyun (gülümsemeyin)',
  'Saçlar yüzü kapatmamalı, kulaklar görünür olmalı',
  'Arka plan düz beyaz/açık renk ve gölgesiz olmalı',
];

/// Ekran 3 — Kamera ve vesikalık çekimi (v3.0 Stüdyo modu).
class CameraScreen extends StatefulWidget {
  final String className;
  final String? initialSchoolNumber;

  const CameraScreen({
    super.key,
    required this.className,
    this.initialSchoolNumber,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final CameraService _camera = CameraService();
  final StorageService _storage = StorageService.instance;
  final PermissionService _permissions = PermissionService.instance;
  final SettingsService _settingsService = SettingsService.instance;

  final GlobalKey _previewKey = GlobalKey();

  AppSettings _settings = const AppSettings();

  bool _initializing = true;
  bool _capturing = false;
  bool _saving = false;
  String? _error;
  bool _permissionBlocked = false;

  String? _lastSavedNumber;
  int _savedCount = 0;

  cam.FlashMode _flashMode = cam.FlashMode.off;
  double? _exposureValue;
  bool _torchOn = false;

  // Geri sayım.
  Timer? _countdownTimer;
  int _countdown = 0;

  // Uyarı rotasyonu (biyometrik stüdyo).
  Timer? _tipTimer;
  int _tipIndex = 0;

  String? _lastShotPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTipTimer();
    _countdownTimer?.cancel();
    _camera.dispose();
    super.dispose();
  }

  CaptureMode get _mode => _settings.mode;
  CaptureSpec get _spec => _settings.specFor(_mode);

  Future<void> _bootstrap() async {
    _settings = await _settingsService.load();
    if (mounted && _mode == CaptureMode.biometric) {
      _startTipTimer();
    }
    await _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // MIUI/HyperOS: arka planda kamera servisi serbest bırakılmazsa dönüşte
    // donma/siyah ekran olur.
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (!_saving && !_capturing) _camera.suspend();
        _stopTipTimer();
        break;
      case AppLifecycleState.resumed:
        if (!_saving && !_capturing) _recoverCamera();
        if (_mode == CaptureMode.biometric) _startTipTimer();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Kamera yaşam döngüsü
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _permissionBlocked = false;
      });
    }

    try {
      // Önce izin: MIUI'da izin verilmeden initialize() kamera servisini
      // kilitleyebiliyor. Oturum için mikrofon da istenir (önizleme
      // yüzeyinin açılması şart — "siyah ekran" senaryosuna karşı).
      final outcome = await _permissions.requireCapture();
      if (!mounted) return;

      if (outcome == PermissionOutcome.permanentlyDenied) {
        setState(() {
          _initializing = false;
          _error = 'Kamera izni kalıcı olarak reddedilmiş. Devam etmek için '
              'uygulama ayarlarından kamera iznini açın.';
          _permissionBlocked = true;
        });
        return;
      }
      if (outcome == PermissionOutcome.denied) {
        setState(() {
          _initializing = false;
          _error = 'Kamera izni verilmedi. Vesikalık çekmek için kamera '
              'erişimine izin vermeniz gerekir.';
        });
        return;
      }

      await _camera.initialize();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = null;
        _exposureValue = _camera.exposureRange.value;
      });
      // MIUI'da doku yüzeyi hiç bağlanmazsa otomatik kurtarma kur.
      _schedulePreviewRecovery();
    } on CameraServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = e.message;
        _permissionBlocked = e.isPermissionIssue;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Kamera başlatılamadı: $e';
      });
    }
  }

  Future<void> _recoverCamera() async {
    if (_camera.isReady) return;
    try {
      await _camera.resume();
      if (!mounted) return;
      setState(() => _error = null);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Mod / hızlı kontroller
  // ---------------------------------------------------------------------------

  Future<void> _setMode(CaptureMode mode) async {
    if (mode == _mode) return;
    final updated = _settings.copyWith(mode: mode);
    await _settingsService.save(updated);
    if (!mounted) return;
    setState(() => _settings = updated);

    if (mode == CaptureMode.biometric) {
      _startTipTimer();
    } else {
      _stopTipTimer();
    }
  }

  void _startTipTimer() {
    _stopTipTimer();
    _tipTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _mode != CaptureMode.biometric) return;
      setState(() => _tipIndex = (_tipIndex + 1) % kBiometricTips.length);
    });
  }

  void _stopTipTimer() {
    _tipTimer?.cancel();
    _tipTimer = null;
  }

  void _cycleFlash() {
    const order = <cam.FlashMode>[
      cam.FlashMode.off,
      cam.FlashMode.auto,
      cam.FlashMode.always,
      cam.FlashMode.torch,
    ];
    final next = order[(_flashMode.index + 1) % order.length];
    setState(() {
      _flashMode = next;
      _torchOn = next == cam.FlashMode.torch;
    });
    _camera.setFlashMode(next);
  }

  Future<void> _switchCamera() async {
    if (_capturing || _saving || !_camera.isReady) return;
    final changed = await _camera.switchCamera();
    if (!changed || !mounted) return;
    setState(() {
      _exposureValue = _camera.exposureRange.value;
      _flashMode = cam.FlashMode.off;
      _torchOn = false;
    });
    AppSnackbar.warning(context, 'Kamera yönü değiştirildi.');
  }

  void _onExposureChanged(double value) {
    _exposureValue = value;
    _camera.setExposureOffset(value);
  }

  // ---------------------------------------------------------------------------
  // Geri sayım + çekim
  // ---------------------------------------------------------------------------

  void _onShutterPressed() {
    if (_capturing || _saving) return;

    if (_settings.timerSeconds > 0 && _countdown == 0) {
      _beginCountdown();
      return;
    }
    _capture();
  }

  void _beginCountdown() {
    var left = _settings.timerSeconds;
    setState(() => _countdown = left);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      left--;
      if (left <= 0) {
        t.cancel();
        setState(() => _countdown = 0);
        _capture();
      } else {
        setState(() => _countdown = left);
      }
    });
  }

  /// Ekrandaki kılavuz çerçeveyi önizleme alanına göre normalize eder.
  GuideCrop _currentGuideCrop() {
    final previewBox = _previewKey.currentContext?.findRenderObject()
        as RenderBox?;

    final screenSize = MediaQuery.sizeOf(context);
    final previewRect = previewBox == null
        ? Rect.fromLTWH(0, 0, screenSize.width, screenSize.height)
        : previewBox.localToGlobal(Offset.zero) & previewBox.size;

    if (previewRect.width <= 0 || previewRect.height <= 0) {
      return const GuideCrop(
        left: 0.12,
        top: 0.10,
        right: 0.88,
        bottom: 0.90,
        previewAspect: 0.5625,
      );
    }

    final aspect = _spec.aspect;
    final frame = GuideGeometry.frameInside(previewRect, aspect: aspect);

    return GuideCrop(
      left: ((frame.left - previewRect.left) / previewRect.width)
          .clamp(0.0, 1.0),
      top: ((frame.top - previewRect.top) / previewRect.height)
          .clamp(0.0, 1.0),
      right: ((frame.right - previewRect.left) / previewRect.width)
          .clamp(0.0, 1.0),
      bottom: ((frame.bottom - previewRect.top) / previewRect.height)
          .clamp(0.0, 1.0),
      previewAspect: previewRect.width / previewRect.height,
    );
  }

  Future<ProcessedPhoto> _processShot({required bool enhance}) {
    return ImageProcessingService.process(
      sourcePath: _lastShotPath!,
      crop: _currentGuideCrop(),
      spec: _spec,
      mode: _mode,
      className: widget.className,
      // Okul numarası diyalogda girilir; bant metni kayıt anında (save)
      // numarayla yeniden çizilir.
      schoolNumber: '',
      applyEnhance: enhance,
    );
  }

  Future<void> _capture() async {
    if (_capturing || _saving || !_camera.isReady) return;

    setState(() {
      _capturing = true;
      _error = null;
    });

    File? rawFile;
    try {
      final shot = await _camera.takePicture();
      _lastShotPath = shot.path;
      rawFile = File(shot.path);

      final processed = await _processShot(enhance: false);
      if (!mounted) return;
      setState(() => _capturing = false);

      final result = await showDialog<(String, ProcessedPhoto)>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhotoConfirmDialog(
          initial: processed,
          process: (enhance) => _processShot(enhance: enhance),
          className: widget.className,
          suggestedNumber: _nextSuggestedNumber(),
          onExists: (n) => _storage.photoExists(widget.className, n),
          mode: _mode,
          showWarnings: _settings.suggestEnhance,
        ),
      );

      if (result == null || !mounted) return; // Yeniden çek: kamera hazır.
      await _save(result.$2, result.$1);
    } on CameraServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = e.message;
        _permissionBlocked = e.isPermissionIssue;
      });
    } on PhotoProcessingException catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      AppSnackbar.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      AppSnackbar.error(context, 'Çekim başarısız: $e');
    } finally {
      if (rawFile != null) {
        try {
          if (await rawFile.exists()) await rawFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Seri çekim: son kayıttan bir fazlasını öner.
  String? _nextSuggestedNumber() {
    if (widget.initialSchoolNumber != null) return widget.initialSchoolNumber;
    final last = _lastSavedNumber;
    if (last == null) return null;
    final n = int.tryParse(last);
    if (n == null) return last;
    return '${n + 1}';
  }

  Future<void> _save(ProcessedPhoto photo, String schoolNumber) async {
    setState(() => _saving = true);
    try {
      var toSave = photo;

      // Yaka Kartı: bilgi bandındaki okul numarası, kullanıcı numarayı
      // girdikten SONRA bilinebilir. Kaydet anında bandı doğru numarayla
      // yeniden çizeriz (bant moduna özel tek ek işlem).
      if (_spec.drawInfoBand && _lastShotPath != null) {
        toSave = await ImageProcessingService.process(
          sourcePath: _lastShotPath!,
          crop: _currentGuideCrop(),
          spec: _spec,
          mode: _mode,
          className: widget.className,
          schoolNumber: schoolNumber,
          applyEnhance: photo.enhanced,
        );
      }

      final bytes = toSave.bytes;
      final tag = _spec.fileTag;

      await _storage.savePhoto(
        className: widget.className,
        schoolNumber: schoolNumber,
        tag: tag,
        bytes: bytes,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastSavedNumber = schoolNumber;
        _savedCount++;
      });

      HapticFeedback.mediumImpact();
      AppSnackbar.success(
        context,
        '$schoolNumber kaydedildi · ${toSave.width}×${toSave.height} · '
        '${toSave.sizeInKb.toStringAsFixed(0)} KB'
        '${tag.isEmpty ? '' : ' · $tag'}',
      );
      // Kamera açık kalır: sıradaki öğrenci için hazır.
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.error(context, 'Kaydedilemedi: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildPreview()),
            if (_error == null && !_initializing) _buildGuideLayer(),
            _buildTopBar(),
            if (_error == null && !_initializing) ...[
              _buildTipsLayer(),
              _buildBottomBar(),
            ],
            if (_countdown > 0) _buildCountdownOverlay(),
            if (_initializing) _buildInitializing(),
            if (_error != null) _buildError(),
            if (_saving) _buildSavingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    // Önizleme deseni: Sınırlı landscape kutu + FittedBox.cover.
    //
    // Texture'ın doğru çalışması için kameranın KENDİ landscape
    // boyutları (örn. 1920×1080) verilir; FittedBox cover bunu portre
    // ekrana sığdırır. Sınırsız/AspectRatio yolu bazı cihazlarda doku
    // yüzeyinin yanlış boyutta açılmasına ve siyah kalmasına yol açabiliyor.
    return LayoutBuilder(
      key: _previewKey,
      builder: (context, constraints) {
        final preview = controller.value.previewSize;

        double width;
        double height;
        if (preview == null || preview.width <= 0 || preview.height <= 0) {
          // Fallback: ekran kadar, varsayılan 4:3 landscape.
          width = constraints.maxWidth * 4;
          height = constraints.maxHeight * 3;
        } else if (preview.width >= preview.height) {
          width = preview.width;
          height = preview.height;
        } else {
          // Nadir: portrait dönen previewSize — yine uzun kenarı genişlik yap.
          width = preview.height;
          height = preview.width;
        }

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: width,
              height: height,
              child: cam.CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Teşhis + otomatik kurtarma (siyah ekran senaryoları için)
  // ---------------------------------------------------------------------------

  /// İlk birkaç saniyede önizleme yüzeyi bağlanmamışsa kamerayı yeniden
  /// başlatır (MIUI'da takılan doku yüzeyi için otomatik kurtarma).
  void _schedulePreviewRecovery() {
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final ctrl = _camera.controller;
      if (ctrl == null || !ctrl.value.isInitialized) return;
      if (ctrl.value.previewSize != null) return; // yüzey bağlanmış.

      debugPrint('[camera] previewSize yok — otomatik kurtarma deneniyor.');
      _autoRecover();
    });
  }

  bool _autoRecovering = false;

  Future<void> _autoRecover() async {
    if (_autoRecovering || _saving || _capturing) return;
    _autoRecovering = true;
    try {
      await _camera.suspend();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _camera.initialize();
    } catch (_) {
      // Hata durumunda _start() zaten arayüze mesaj yazar.
    } finally {
      _autoRecovering = false;
      if (mounted) setState(() {});
    }
  }

  /// Teşhis sayfası: siyah ekran raporunda istenecek bilgiler.
  void _showDiagnostics() {
    final ctrl = _camera.controller;
    final value = ctrl?.value;
    final range = _camera.exposureRange;

    var cameras = '<okunamadı>';
    try {
      // Senkron olmayan keşif yerine bilinen açıklama kullanılır.
      cameras = _camera.description == null
          ? 'yok'
          : '${_camera.description!.name} (${_camera.description!.lensDirection.name})';
    } catch (_) {}

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kamera Teşhisi',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _diagRow('Servis hazır', '${_camera.isReady}'),
              _diagRow('initialize değeri', '${value?.isInitialized ?? false}'),
              _diagRow('previewSize', '${value?.previewSize ?? 'null'}'),
              _diagRow('Ses (oturum)', '${value?.isRecordingVideo == true ? "aktif" : "varsayılan"} · enableAudio: true'),
              _diagRow('Kamera', cameras),
              _diagRow(
                'Pozlama aralığı',
                '${range.min} … ${range.max} (şu an ${range.value})',
              ),
              _diagRow('Flaş', '${_flashMode.name}'),
              _diagRow('Mod', '${_mode.label} · ${_spec.width}×${_spec.height}'),
              _diagRow('Hata', _error ?? 'yok'),
              _diagRow('Arayüz durumu',
                  'init:$_initializing çekim:$_capturing kayıt:$_saving'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _autoRecover();
                      },
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Kamerayı Yeniden Başlat'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: GuideOverlay(
          mode: _mode,
          instruction: switch (_mode) {
            CaptureMode.eokul => _savedCount == 0
                ? 'Yüzü çerçeveye ortalayın'
                : '$_savedCount kaydedildi · sıradaki öğrenci',
            CaptureMode.biometric => 'Biyometrik hedef — yüzü ovale hizalayın',
            CaptureMode.badge => 'Fotoğraf bant için 3:4 alana sığdırılır',
          },
        ),
      ),
    );
  }

  /// Biyometrik stüdyo: animasyonlu uyarı rozeti (3 sn'de bir değişir).
  Widget _buildTipsLayer() {
    if (_mode != CaptureMode.biometric) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      top: 138,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        child: Container(
          key: ValueKey<int>(_tipIndex),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF101A2E).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF3DFFB0).withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 17)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kBiometricTips[_tipIndex],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final theme = Theme.of(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Kapat',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.groups_rounded,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        widget.className,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _cycleFlash,
                  tooltip: 'Flaş',
                  icon: Icon(
                    _torchOn
                        ? Icons.flashlight_on_rounded
                        : switch (_flashMode) {
                            cam.FlashMode.off => Icons.flash_off_rounded,
                            cam.FlashMode.auto => Icons.flash_auto_rounded,
                            _ => Icons.flash_on_rounded,
                          },
                    color: _torchOn
                        ? const Color(0xFFFFD54F)
                        : Colors.white,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _switchCamera,
                  tooltip: 'Ön/Arka',
                  icon: const Icon(Icons.cameraswitch_rounded,
                      color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _showDiagnostics,
                  tooltip: 'Kamera teşhisi',
                  icon: const Icon(Icons.info_outline_rounded,
                      color: Colors.white70),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Hızlı çekim modu geçişi.
          SizedBox(
            height: 38,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<CaptureMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFF2D6CDF);
                      }
                      return Colors.black.withValues(alpha: 0.42);
                    },
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.white
                        : Colors.white70,
                  ),
                  side: const WidgetStatePropertyAll(
                    BorderSide(color: Colors.white24),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12),
                  ),
                  minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                ),
                segments: CaptureMode.values
                    .map(
                      (m) => ButtonSegment(value: m, label: Text(m.label)),
                    )
                    .toList(),
                selected: <CaptureMode>{_mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '${_spec.width}×${_spec.height} · ${_spec.maxBytes == null ? '%95 kalite' : '<${_spec.maxBytes! ~/ 1024} KB'}',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white60,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final exposure = _camera.exposureRange;
    final canAdjustExposure = exposure.max > exposure.min;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.76),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_lastSavedNumber != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Son kayıt: $_lastSavedNumber'
                  '${_nextSuggestedNumber() != null ? '  →  sıradaki: ${_nextSuggestedNumber()}' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (canAdjustExposure)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.brightness_low_rounded,
                        size: 16, color: Colors.white60),
                    Expanded(
                      child: Slider(
                        value: (_exposureValue ?? exposure.value)
                            .clamp(exposure.min, exposure.max),
                        min: exposure.min,
                        max: exposure.max,
                        onChanged: _capturing || _saving
                            ? null
                            : _onExposureChanged,
                        activeColor: Colors.amber,
                        inactiveColor: Colors.white24,
                      ),
                    ),
                    const Icon(Icons.brightness_high_rounded,
                        size: 16, color: Colors.white60),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 56,
                  child: _settings.timerSeconds > 0
                      ? Chip(
                          avatar: const Icon(Icons.timer_rounded,
                              size: 15, color: Colors.white),
                          label: Text(
                            '${_settings.timerSeconds} sn',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                          backgroundColor: Colors.white24,
                          side: const BorderSide(color: Colors.white24),
                          padding: EdgeInsets.zero,
                        )
                      : const SizedBox.shrink(),
                ),
                _ShutterButton(
                  busy: _capturing || _saving,
                  onPressed: _onShutterPressed,
                ),
                SizedBox(
                  width: 56,
                  child: IconButton(
                    onPressed:
                        _capturing || _saving ? null : _recoverCamera,
                    tooltip: 'Odağı yenile',
                    icon: const Icon(Icons.center_focus_strong_rounded,
                        color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _capturing
                  ? 'Fotoğraf işleniyor…'
                  : _settings.timerSeconds > 0
                      ? 'Deklanşör → ${_settings.timerSeconds} sn geri sayım → otomatik çekim'
                      : 'Deklanşöre basın, ardından okul numarasını girin',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _countdown.toDouble()),
            duration: const Duration(milliseconds: 250),
            builder: (context, value, _) => Text(
              '${value.round()}',
              style: TextStyle(
                fontSize: 150,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.9),
                shadows: const [
                  Shadow(blurRadius: 24, color: Colors.black54),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitializing() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
              SizedBox(height: 18),
              Text('Kamera hazırlanıyor…',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _permissionBlocked
                      ? Icons.lock_outline_rounded
                      : Icons.videocam_off_rounded,
                  size: 52,
                  color: Colors.white54,
                ),
                const SizedBox(height: 20),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 26),
                if (_permissionBlocked)
                  FilledButton.icon(
                    onPressed: () async {
                      await _permissions.openSettings();
                      if (!mounted) return;
                      await _start();
                    },
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Ayarları Aç'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Yeniden Dene'),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Geri Dön',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavingOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              ),
              SizedBox(height: 16),
              Text('Kaydediliyor…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Deklanşör
// -----------------------------------------------------------------------------

class _ShutterButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;

  const _ShutterButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Fotoğraf çek',
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            color: busy ? Colors.white24 : Colors.white12,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: busy ? 26 : 56,
              height: busy ? 26 : 56,
              decoration: BoxDecoration(
                shape: busy ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: busy ? BorderRadius.circular(6) : null,
                color: busy ? Colors.white38 : Colors.white,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Çekim sonrası onay diyaloğu — analiz + iyileştirme + numara
// -----------------------------------------------------------------------------

/// Onay/önizleme ekranı:
///  * Kalite denetimi uyarıları (karanlık / biyometrik arka plan)
///  * "Parlaklık & Kontrast İyileştir" anahtarı (canlı yeniden işleme)
///  * Okul numarası (rakam, çakışma uyarısı, seri çekim önerisi)
///
/// Pop sonucu: `(okulNumarası, kaydedilecek ProcessedPhoto)` — iyileştirilmiş
/// görselin kendisi döner.
class PhotoConfirmDialog extends StatefulWidget {
  final ProcessedPhoto initial;
  final Future<ProcessedPhoto> Function(bool enhance) process;
  final String className;
  final String? suggestedNumber;
  final Future<bool> Function(String number) onExists;
  final CaptureMode mode;

  /// Ayarlar > "Kalite uyarıları" anahtarı (varsayılan: açık).
  final bool showWarnings;

  const PhotoConfirmDialog({
    super.key,
    required this.initial,
    required this.process,
    required this.className,
    required this.onExists,
    required this.mode,
    this.showWarnings = true,
    this.suggestedNumber,
  });

  @override
  State<PhotoConfirmDialog> createState() => _PhotoConfirmDialogState();
}

class _PhotoConfirmDialogState extends State<PhotoConfirmDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  late ProcessedPhoto _photo;
  bool _enhanced = false;
  bool _enhancing = false;

  String? _error;
  bool _overwriteWarning = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.initial;
    _controller = TextEditingController(text: widget.suggestedNumber ?? '');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleEnhance(bool value) async {
    if (_enhancing) return;
    setState(() => _enhancing = true);
    try {
      final next = await widget.process(value);
      if (!mounted) return;
      setState(() {
        _photo = next;
        _enhanced = value;
        _enhancing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _enhancing = false);
      AppSnackbar.error(context, 'İyileştirme başarısız: $e');
    }
  }

  Future<void> _checkDuplicate(String value) async {
    final number = value.trim();
    if (number.isEmpty) {
      setState(() {
        _overwriteWarning = false;
        _error = null;
      });
      return;
    }
    setState(() => _checking = true);
    try {
      final exists = await widget.onExists(number);
      if (!mounted) return;
      setState(() {
        _overwriteWarning = exists;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  void _submit() {
    final number = _controller.text.trim();
    if (number.isEmpty) {
      setState(() => _error = 'Okul numarası girin.');
      return;
    }
    if (!RegExp(r'^\d{1,12}$').hasMatch(number)) {
      setState(() => _error = 'Yalnızca rakam kullanın.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop<(String, ProcessedPhoto)>((number, _photo));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final analysis = _photo.analysis;
    final dark = analysis.brightness < 78;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fotoğrafı Kaydet',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${widget.className} · ${_photo.width}×'
                            '${_photo.height} px · '
                            '${_photo.sizeInKb.toStringAsFixed(0)} KB · '
                            'kalite %${_photo.quality}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Vazgeç',
                    ),
                  ],
                ),
              ),

              // Önizleme
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _photo.width / _photo.height,
                          child: Image.memory(
                            _photo.bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                    if (_enhancing)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),

              // Kalite denetimi (Ayarlar'dan kapatılabilir)
              if (analysis.hasWarnings && widget.showWarnings)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dark
                          ? scheme.errorContainer
                          : scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in analysis.warnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: dark
                                      ? scheme.onErrorContainer
                                      : scheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    w,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: dark
                                          ? scheme.onErrorContainer
                                          : scheme.onTertiaryContainer,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Otomatik iyileştirme anahtarı
              SwitchListTile(
                value: _enhanced,
                onChanged: _enhancing ? null : _toggleEnhance,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                title: const Text(
                  'Parlaklık & Kontrast İyileştir',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  'Karanlık yüzü ve arka planı otomatik aydınlatır',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                secondary: Icon(
                  Icons.auto_fix_high_rounded,
                  color: _enhanced ? scheme.primary : scheme.outline,
                ),
              ),

              // Okul numarası
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 12,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Okul Numarası',
                    hintText: 'örn. 1042',
                    errorText: _error,
                    counterText: '',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    suffixIcon: _checking
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    if (_error != null) setState(() => _error = null);
                    _checkDuplicate(value);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),

              if (_overwriteWarning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 19, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bu numarada kayıtlı fotoğraf var. Kaydederseniz '
                            'üzerine yazılacak.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onTertiaryContainer,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.refresh_rounded, size: 19),
                        label: const Text('Yeniden Çek'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _enhancing ? null : _submit,
                        icon: const Icon(Icons.save_rounded, size: 19),
                        label: Text(
                          _overwriteWarning ? 'Üzerine Yaz' : 'Kaydet',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
