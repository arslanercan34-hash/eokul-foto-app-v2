import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/zip_share_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/class_card.dart';
import 'about_screen.dart';
import 'camera_screen.dart';
import 'class_detail_screen.dart';
import 'help_screen.dart';
import 'settings_screen.dart';

/// Ekran 1 — Sınıf yönetimi (Drawer + kurumsal kimlik + footer).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService.instance;
  final ZipShareService _zip = ZipShareService.instance;

  List<ClassFolder> _classes = const <ClassFolder>[];
  bool _loading = true;
  String? _error;
  bool _sharingSchool = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final classes = await _storage.loadClasses();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Sınıflar yüklenemedi: $e';
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Eylemler
  // ---------------------------------------------------------------------------

  Future<void> _addClass() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddClassDialog(),
    );
    if (name == null || !mounted) return;

    final created = await _storage.createClass(name);
    if (!mounted) return;

    if (!created) {
      AppSnackbar.warning(context, 'Bu isimde bir sınıf zaten var.');
      return;
    }

    await _load();
    if (!mounted) return;

    final folder = await _storage.loadClass(name);
    if (folder == null || !mounted) return;
    AppSnackbar.success(context, '${folder.name} sınıfı oluşturuldu.');
  }

  Future<void> _deleteClass(ClassFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${folder.name} sınıfını sil'),
        content: Text(
          folder.photoCount == 0
              ? 'Bu sınıf klasörü silinecek.'
              : 'Bu sınıftaki ${folder.photoCount} fotoğraf da kalıcı '
                  'olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _storage.deleteClass(folder.name);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    AppSnackbar.success(context, '${folder.name} silindi.');
  }

  Future<void> _shareClass(ClassFolder folder) async {
    if (folder.photoCount == 0) {
      AppSnackbar.warning(context, 'Bu sınıfta henüz fotoğraf yok.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    _showBusy('ZIP arşivi hazırlanıyor…');
    try {
      final result = await _zip.shareClass(folder,
          sharePositionOrigin: _origin());
      if (!mounted) return;
      _hideBusy();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${result.photoCount} fotoğraf hazır '
            '(${result.sizeInMb.toStringAsFixed(1)} MB).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.error(context, 'ZIP oluşturulamadı: $e');
    }
  }

  /// Tüm okulu tek ZIP'e — `SinifAdi/OkulNo.jpg` hiyerarşisiyle.
  Future<void> _shareWholeSchool() async {
    if (_sharingSchool) return;
    final withPhotos =
        _classes.where((c) => c.photoCount > 0).toList(growable: false);
    if (withPhotos.isEmpty) {
      AppSnackbar.warning(context, 'Henüz hiç fotoğraf çekilmemiş.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharingSchool = true);
    _showBusy('Okul arşivi hazırlanıyor…');
    try {
      final result = await _zip.shareWholeSchool(
        withPhotos,
        sharePositionOrigin: _origin(),
      );
      if (!mounted) return;
      _hideBusy();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Tüm okul hazır: ${result.photoCount} fotoğraf, '
            '${withPhotos.length} sınıf '
            '(${result.sizeInMb.toStringAsFixed(1)} MB).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.error(context, 'ZIP oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() => _sharingSchool = false);
    }
  }

  Future<void> _renameClass(ClassFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sınıf Adını Değiştir'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Yeni sınıf adı',
            hintText: '5-A',
            prefixIcon: Icon(Icons.class_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Değiştir'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || !mounted) return;
    if (newName == folder.name) return;

    final ok = await _storage.renameClass(folder.name, newName);
    if (!mounted) return;
    if (!ok) {
      AppSnackbar.warning(context, 'Bu isimde bir sınıf zaten var.');
      return;
    }

    await _load();
    if (!mounted) return;
    AppSnackbar.success(context, 'Sınıf adı "$newName" olarak güncellendi.');
  }

  Future<void> _openClass(ClassFolder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassDetailScreen(className: folder.name),
      ),
    );
    await _load();
  }

  Future<void> _openCamera(ClassFolder folder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(className: folder.name),
      ),
    );
    await _load();
  }

  Future<void> _navigate(Widget screen) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    await _load();
  }

  Rect? _origin() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _showBusy(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BusyDialog(message: message),
    );
  }

  void _hideBusy() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPhotos = _classes.fold<int>(0, (sum, c) => sum + c.photoCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('e-Okul Vesikalık'),
        actions: [
          IconButton(
            tooltip: 'Tüm Okulu ZIP Paylaş',
            onPressed:
                _sharingSchool || totalPhotos == 0 ? null : _shareWholeSchool,
            icon: _sharingSchool
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.drive_folder_upload_rounded),
          ),
          IconButton(
            tooltip: 'Yenile',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _buildDrawer(theme),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme, totalPhotos),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClass,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni Sınıf Ekle'),
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    final scheme = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Kurumsal kimlik
            DrawerHeader(
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'e-Okul & Biyometrik\nVesikalık Pro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Ercan ARSLAN\nBilişim Teknolojileri Öğretmeni',
                            style: TextStyle(
                              color: Color(0xFF1A3A72),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _tile(
                    icon: Icons.school_rounded,
                    label: 'Sınıflar (Ana Ekran)',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  _tile(
                    icon: Icons.folder_zip_rounded,
                    label: 'Tüm Okulu Tek ZIP Olarak Paylaş',
                    subtitle: 'SınıfAdı/OkulNo.jpg klasör yapısıyla',
                    onTap: () {
                      Navigator.of(context).pop();
                      _shareWholeSchool();
                    },
                  ),
                  const Divider(indent: 14, endIndent: 14),
                  _tile(
                    icon: Icons.tune_rounded,
                    label: 'Çekim Modu & Çözünürlük Ayarları',
                    onTap: () => _navigate(const SettingsScreen()),
                  ),
                  _tile(
                    icon: Icons.menu_book_rounded,
                    label: 'Yardım & Biyometrik / e-Okul Kuralları',
                    subtitle: 'Sekmeli rehber',
                    onTap: () => _navigate(const HelpScreen()),
                  ),
                  _tile(
                    icon: Icons.info_rounded,
                    label: 'Hakkında',
                    onTap: () => _navigate(const AboutScreen()),
                  ),
                ],
              ),
            ),

            // Kurumsal bilgi bandı (footer)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Text(
                'Geliştirici: Ercan ARSLAN\nBilişim Teknolojileri Öğretmeni',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontSize: 14.5)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      onTap: onTap,
    );
  }

  Widget _buildBody(ThemeData theme, int totalPhotos) {
    if (_loading && _classes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline_rounded,
              size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      children: [
        if (_classes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Row(
              children: [
                _StatChip(
                  icon: Icons.school_rounded,
                  label: '${_classes.length} sınıf',
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.photo_camera_rounded,
                  label: '$totalPhotos fotoğraf',
                ),
              ],
            ),
          ),
        if (_classes.isEmpty) _buildEmpty(theme),
        for (final folder in _classes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClassCard(
              folder: folder,
              onTap: () => _openClass(folder),
              onCapture: () => _openCamera(folder),
              onShare: () => _shareClass(folder),
              onDelete: () => _deleteClass(folder),
              onRename: () => _renameClass(folder),
            ),
          ),

        // Alt bilgi bandı (footer)
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 110),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_rounded,
                    size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Geliştirici: Ercan ARSLAN — Bilişim Teknolojileri '
                    'Öğretmeni',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_2_rounded,
              size: 46,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Henüz sınıf eklenmedi',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            'Sağ alttaki “Yeni Sınıf Ekle” düğmesine dokunup sınıfınızı '
            'oluşturun (örn. 5-A). Ardından sınıfın içinden öğrencilerin '
            'vesikalık fotoğraflarını çekebilirsiniz.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yeni sınıf adı soran diyalog.
class _AddClassDialog extends StatefulWidget {
  const _AddClassDialog();

  @override
  State<_AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<_AddClassDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  static final RegExp _pattern =
      RegExp(r'^[0-9]{1,2}\s*[-/ ]?\s*[A-Za-zÇĞİÖŞÜçğıöşü]{1,3}$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Sınıf adı boş olamaz.');
      return;
    }
    if (!_pattern.hasMatch(raw)) {
      setState(() => _error = 'Örnek biçim: 5-A, 8/B, 12 A');
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Yeni Sınıf Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sınıf adını girin. Bu ad, cihazdaki klasör adı olarak da '
            'kullanılacak.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Sınıf adı',
              hintText: '5-A',
              errorText: _error,
              prefixIcon: const Icon(Icons.class_rounded),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Oluştur')),
      ],
    );
  }
}

/// İşlem sürerken gösterilen modal.
class _BusyDialog extends StatelessWidget {
  final String message;

  const _BusyDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
