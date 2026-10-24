import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../widgets/app_snackbar.dart';

/// Çekim Modu & Çözünürlük Ayarları.
///
/// Burada yapılan seçimler kamera ekranındaki hızlı geçiş çubuğuyla da
/// senkrondır (aynı `SettingsService` üzerinden).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _service = SettingsService.instance;
  AppSettings _settings = const AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _service.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  Future<void> _update(AppSettings next) async {
    setState(() => _settings = next);
    await _service.save(next);
    if (!mounted) return;
    AppSnackbar.success(context, 'Ayarlar kaydedildi.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Çekim Modu & Çözünürlük')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _section(theme, 'Aktif Çekim Modu',
              'Kamera ekranındaki hızlı çubukla da değişebilir.'),
          _modeCard(theme, CaptureMode.eokul,
              icon: Icons.school_rounded,
              detail: '3:4 dikey oran · dosya boyutu kesinlikle '
                  '<${_settings.eokulMaxKb} KB · MEB e-Okul yüklemeye '
                  'doğrudan uygun.'),
          _modeCard(theme, CaptureMode.biometric,
              icon: Icons.face_retouching_natural_rounded,
              detail: '5:6 (50×60 mm) ICAO oranı · %95 JPEG kalitesi · '
                  'boyut sınırı YOK · pasaport, kimlik, sınav başvurusu.'),
          _modeCard(theme, CaptureMode.badge,
              icon: Icons.badge_rounded,
              detail: '3:4 · 600×800 px · altına sınıf + okul numarası '
                  'koyu bantla işlenir (yaka kartı / okul kimliği).'),

          _section(theme, 'e-Okul Çözünürlüğü',
              'MEB e-Okul’a yüklenecek vesikalıklar için çözünürlük.'),
          SegmentedButton<EokulResolution>(
            segments: EokulResolution.values
                .map((r) => ButtonSegment(value: r, label: Text(r.label)))
                .toList(),
            selected: {_settings.eokulResolution},
            onSelectionChanged: (s) =>
                _update(_settings.copyWith(eokulResolution: s.first)),
          ),

          _section(theme, 'e-Okul Dosya Boyutu Sınırı',
              'JPEG kalitesi, en yüksek olacak şekilde otomatik ayarlanır; '
              'dosya bu sınırın altına sıkıştırılır.'),
          Row(
            children: [
              const Icon(Icons.data_usage_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _settings.eokulMaxKb.toDouble(),
                  min: 15,
                  max: 50,
                  divisions: 7,
                  label: '${_settings.eokulMaxKb} KB',
                  onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(eokulMaxKb: v.round()),
                  ),
                  onChangeEnd: (v) => _update(
                    _settings.copyWith(eokulMaxKb: v.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${_settings.eokulMaxKb} KB',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Text(
            'Önerilen: 40–49 KB (yüksek kalite) veya 20–30 KB (sıkı arşiv). '
            'Alt sınır 20 KB’tır; bu, e-Okul’un reddedebileceği çok küçük '
            'dosyaları engeller.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),

          _section(theme, 'Biyometrik Çözünürlük',
              'ICAO / kimlik / pasaport / sınav başvurusu fotoğrafları.'),
          SegmentedButton<BiometricResolution>(
            segments: BiometricResolution.values
                .map((r) => ButtonSegment(value: r, label: Text(r.label)))
                .toList(),
            selected: {_settings.biometricResolution},
            onSelectionChanged: (s) => _update(
              _settings.copyWith(biometricResolution: s.first),
            ),
          ),
          SwitchListTile(
            value: _settings.biometricTag,
            onChanged: (v) => _update(_settings.copyWith(biometricTag: v)),
            title: const Text('Biyometrik dosyalara "BIO" rozeti',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Örn. 1042_BIO.jpg — klasörde ayrışmayı kolaylaştırır.'),
          ),

          _section(theme, 'Çekim Yardımcıları', null),
          ListTile(
            title: const Text('Geri Sayım Süresi',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Deklanşöre bastıktan sonra otomatik çekim'),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('Kapalı')),
                ButtonSegment(value: 3, label: Text('3 sn')),
              ],
              selected: {_settings.timerSeconds},
              onSelectionChanged: (s) =>
                  _update(_settings.copyWith(timerSeconds: s.first)),
            ),
          ),
          SwitchListTile(
            value: _settings.suggestEnhance,
            onChanged: (v) => _update(_settings.copyWith(suggestEnhance: v)),
            title: const Text('Kalite uyarıları',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Karanlık fotoğraf ve biyometrik arka plan denetimi'),
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _update(const AppSettings()),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Varsayılana Dön'),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeCard(
    ThemeData theme,
    CaptureMode mode, {
    required IconData icon,
    required String detail,
  }) {
    final selected = _settings.mode == mode;
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _update(_settings.copyWith(mode: mode)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 26,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            mode.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle_rounded,
                              size: 20, color: scheme.primary),
                      ],
                    ),
                    Text(
                      mode.subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
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
