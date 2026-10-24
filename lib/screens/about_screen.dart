import 'package:flutter/material.dart';

/// Hakkında / Künye ekranı.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// Uygulama sürümü — pubspec.yaml `version:` ile senkron tutulur.
  static const String appVersion = '3.0.0';

  static const String developer = 'Ercan ARSLAN';
  static const String developerTitle = 'Bilişim Teknolojileri Öğretmeni';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Hakkında')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
        children: [
          // Logo
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: Colors.white, size: 48),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'e-Okul & Biyometrik\nVesikalık Pro',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sürüm $appVersion',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 28),

          // Özellikler
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Özellikler',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _feature(Icons.school_rounded,
                      'e-Okul Modu: 3:4, 300×400 px, kesin <50 KB JPEG'),
                  _feature(Icons.face_retouching_natural_rounded,
                      'Biyometrik Mod: ICAO 5:6, %95 kalite, animasyonlu '
                      'hedefleme'),
                  _feature(Icons.badge_rounded,
                      'Yaka Kartı: sınıf + okul numarası işlemeli 600×800'),
                  _feature(Icons.light_mode_rounded,
                      'Akıllı ışık/arka plan analizi + tek dokunuş '
                      'iyileştirme'),
                  _feature(Icons.camera_rounded,
                      'Flaş / fener, ön-arka, pozlama, 3 sn geri sayım'),
                  _feature(Icons.folder_zip_rounded,
                      'Sınıf ve okul geneli ZIP — klasör yapısıyla'),
                  _feature(Icons.grid_on_rounded,
                      'Fotoğraflı sınıf listesi ve 10×15 cm baskı şablonu'),
                  _feature(Icons.transform_rounded,
                      'Biyometrikten e-Okul’a toplu dönüştürücü'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Künye
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                Text(
                  'Hazırlayan',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  developer,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  developerTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 10),
                Text(
                  'Okul ortamı için geliştirilmiş vesikalık arşivleme '
                  'sistemi — MEB e-Okul ve biyometrik standartlarla uyumlu.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}
