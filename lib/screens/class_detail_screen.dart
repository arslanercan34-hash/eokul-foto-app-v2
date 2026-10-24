import 'package:flutter/material.dart';

import '../services/export_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/zip_share_service.dart';
import '../widgets/app_snackbar.dart';
import 'camera_screen.dart';

/// Ekran 2 — Sınıf detayı, galeri ve gelişmiş araçlar.
class ClassDetailScreen extends StatefulWidget {
  final String className;

  const ClassDetailScreen({super.key, required this.className});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final StorageService _storage = StorageService.instance;
  final ZipShareService _zip = ZipShareService.instance;
  final ExportService _export = ExportService.instance;
  final SettingsService _settingsService = SettingsService.instance;

  ClassFolder? _folder;
  bool _loading = true;
  bool _busy = false;

  String _query = '';
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final folder = await _storage.loadClass(widget.className);
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, 'Sınıf yüklenemedi: $e');
    }
  }

  List<StudentPhoto> get _visiblePhotos {
    final all = _folder?.sortedPhotos ?? const <StudentPhoto>[];
    var list = all;
    if (_query.trim().isNotEmpty) {
      list = all
          .where((p) => p.schoolNumber.contains(_query.trim()))
          .toList(growable: false);
    }
    if (!_ascending) {
      list = list.reversed.toList(growable: false);
    }
    return list;
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
      builder: (_) => PopScope(
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
      ),
    );
  }

  void _hideBusy() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  // ---------------------------------------------------------------------------
  // İşlemler
  // ---------------------------------------------------------------------------

  Future<void> _openCamera({String? forNumber}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(
          className: widget.className,
          initialSchoolNumber: forNumber,
        ),
      ),
    );
    await _load();
  }

  Future<void> _shareAll() async {
    final folder = _folder;
    if (folder == null || folder.photos.isEmpty || _busy) return;

    setState(() => _busy = true);
    _showBusy('ZIP arşivi hazırlanıyor…');
    try {
      final result =
          await _zip.shareClass(folder, sharePositionOrigin: _origin());
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.success(
        context,
        '${result.photoCount} fotoğraf ZIP olarak hazırlandı.',
      );
    } catch (e) {
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Biyometrik → e-Okul toplu dönüştürme.
  Future<void> _shareAsEokul() async {
    final folder = _folder;
    if (folder == null || folder.photos.isEmpty || _busy) return;

    setState(() => _busy = true);
    _showBusy('Fotoğraflar e-Okul formatına dönüştürülüyor…');
    try {
      final result = await _zip.shareConvertedEokul(
        folder,
        settings: await _settingsService.load(),
        sharePositionOrigin: _origin(),
      );
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.success(
        context,
        '${result.photoCount} fotoğraf 300×400 / <50 KB olarak hazır.',
      );
    } catch (e) {
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fotoğraflı sınıf listesi (tablo) oluştur + paylaş.
  Future<void> _buildRoster() async {
    final folder = _folder;
    if (folder == null || folder.photos.isEmpty || _busy) return;

    setState(() => _busy = true);
    _showBusy('Sınıf listesi tablosu oluşturuluyor…');
    try {
      final artifact = await _export.buildClassRoster(folder);
      if (!mounted) return;
      _hideBusy();
      await _zip.shareFile(
        artifact.file,
        subject: '${folder.name} — Fotoğraflı Sınıf Listesi',
        text: '${artifact.description} '
            '(${artifact.sizeInKb.toStringAsFixed(0)} KB).',
      );
    } catch (e) {
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.error(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameClass() async {
    final folder = _folder;
    if (folder == null) return;

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

    AppSnackbar.success(context, 'Sınıf adı "$newName" olarak güncellendi.');
    if (!mounted) return;
    // Ekrandaki başlığı yeni adla sürdür.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ClassDetailScreen(className: newName),
      ),
    );
  }

  Future<void> _deletePhoto(StudentPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğrafı sil'),
        content: Text('${photo.schoolNumber} numaralı öğrencinin fotoğrafı '
            'silinecek.'),
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
    await _storage.deletePhoto(widget.className, photo.schoolNumber);
    await _load();
    if (!mounted) return;
    AppSnackbar.success(context, 'Fotoğraf silindi.');
  }

  Future<void> _renameStudent(StudentPhoto photo) async {
    final controller = TextEditingController(text: photo.schoolNumber);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Okul Numarasını Değiştir'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Yeni okul numarası',
            hintText: '1042',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (next == null || next.isEmpty || next == photo.schoolNumber) return;
    if (!RegExp(r'^\d{1,12}$').hasMatch(next)) {
      if (!mounted) return;
      AppSnackbar.warning(context, 'Okul numarası yalnızca rakam olmalı.');
      return;
    }
    if (!mounted) return;

    try {
      await _storage.renameStudent(
        className: widget.className,
        currentNumber: photo.schoolNumber,
        targetNumber: next,
      );
      await _load();
      if (!mounted) return;
      AppSnackbar.success(context, 'Numara $next olarak güncellendi.');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Değiştirilemedi: $e');
    }
  }

  Future<void> _moveStudent(StudentPhoto photo) async {
    final classes = await _storage.loadClasses();
    if (!mounted) return;

    final targets = classes
        .where((c) => c.name != widget.className)
        .toList(growable: false);

    if (targets.isEmpty) {
      AppSnackbar.warning(context, 'Taşınabilecek başka sınıf yok.');
      return;
    }

    final chosen = await showDialog<ClassFolder>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${photo.schoolNumber} → hedef sınıf'),
        children: [
          for (final c in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(c),
              child: Text('${c.name} (${c.photoCount} öğrenci)'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    try {
      await _storage.moveStudent(
        fromClassName: widget.className,
        number: photo.schoolNumber,
        toClassName: chosen.name,
      );
      await _load();
      if (!mounted) return;
      AppSnackbar.success(
        context,
        '${photo.schoolNumber} → ${chosen.name} sınıfına taşındı.',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, 'Taşınamadı: $e');
    }
  }

  Future<void> _buildPrintSheet(StudentPhoto photo) async {
    if (_busy) return;
    setState(() => _busy = true);
    _showBusy('Baskı şablonu oluşturuluyor…');
    try {
      final artifact = await _export.buildPrintSheet(photo);
      if (!mounted) return;
      _hideBusy();
      await _zip.shareFile(
        artifact.file,
        subject: '${photo.schoolNumber} — 10×15 cm Baskı Şablonu',
        text: artifact.description,
      );
    } catch (e) {
      if (!mounted) return;
      _hideBusy();
      AppSnackbar.error(context, 'Şablon oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Arayüz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    final photos = _visiblePhotos;
    final totalCount = folder?.photos.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(folder?.name ?? widget.className),
        actions: [
          IconButton(
            tooltip: 'Sınıfı yeniden adlandır',
            onPressed: _renameClass,
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(
            tooltip: 'Tümünü ZIP Yap ve Paylaş',
            onPressed: totalCount == 0 || _busy ? null : _shareAll,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.folder_zip_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Araçlar',
            icon: const Icon(Icons.more_vert_rounded),
            enabled: totalCount > 0 && !_busy,
            onSelected: (value) {
              switch (value) {
                case 'convert':
                  _shareAsEokul();
                  break;
                case 'roster':
                  _buildRoster();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'convert',
                child: ListTile(
                  leading: Icon(Icons.transform_rounded),
                  title: Text('e-Okul Formatına Dönüştürerek ZIP Paylaş'),
                  subtitle: Text('300×400, <50 KB'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'roster',
                child: ListTile(
                  leading: Icon(Icons.grid_on_rounded),
                  title: Text('Fotoğraflı Sınıf Listesi (Tablo) Oluştur'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : totalCount == 0
              ? _buildEmpty(context)
              : Column(
                  children: [
                    _buildToolbar(context, totalCount),
                    Expanded(child: _buildGrid(context, photos)),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCamera,
        icon: const Icon(Icons.photo_camera_rounded),
        label: const Text('Fotoğraf Çek'),
      ),
    );
  }

  /// Arama + sıralama araç çubuğu.
  Widget _buildToolbar(BuildContext context, int totalCount) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Okul numarasında ara…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () => setState(() => _query = ''),
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _ascending
                    ? 'Artan sıralama (şu an)'
                    : 'Azalan sıralama (şu an)',
                onPressed: () => setState(() => _ascending = !_ascending),
                icon: Icon(
                  _ascending
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _query.trim().isEmpty
                      ? '$totalCount fotoğraf · numaraya göre '
                          '${_ascending ? 'artan' : 'azalan'}'
                      : '${_visiblePhotos.length} sonuç bulundu',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<StudentPhoto> photos) {
    if (photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '"$_query" ile eşleşen öğrenci yok.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.70,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return _PhotoTile(
          photo: photo,
          onTap: () => _showPhotoActions(photo),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_camera_back_rounded,
                size: 42,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Bu sınıfta fotoğraf yok',
              style:
                  theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '“Fotoğraf Çek” ile başlayın. Kamera açık kalır; art arda '
              'çekim yapabilirsiniz.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fotoğraf eylem sayfası: önizleme + tüm araçlar.
  void _showPhotoActions(StudentPhoto photo) {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      photo.file,
                      width: 92,
                      height: 116,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Container(
                        width: 92,
                        height: 116,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_rounded,
                            color: theme.colorScheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Okul No: ${photo.schoolNumber}',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.className} · '
                          '${photo.sizeInKb.toStringAsFixed(0)} KB',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _actionRow(
                theme,
                [
                  _action(
                    context,
                    icon: Icons.refresh_rounded,
                    label: 'Yeniden Çek',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _openCamera(forNumber: photo.schoolNumber);
                    },
                  ),
                  _action(
                    context,
                    icon: Icons.numbers_rounded,
                    label: 'No Değiştir',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _renameStudent(photo);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _actionRow(
                theme,
                [
                  _action(
                    context,
                    icon: Icons.drive_file_move_rounded,
                    label: 'Taşı',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _moveStudent(photo);
                    },
                  ),
                  _action(
                    context,
                    icon: Icons.content_cut_rounded,
                    label: 'Baskı Şablonu\n10×15 · 8\'li',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _buildPrintSheet(photo);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _deletePhoto(photo);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Fotoğrafı Sil'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionRow(ThemeData theme, List<Widget> children) {
    return Row(
      children: [
        Expanded(child: children[0]),
        const SizedBox(width: 10),
        Expanded(child: children[1]),
      ],
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _PhotoTile extends StatelessWidget {
  final StudentPhoto photo;
  final VoidCallback onTap;

  const _PhotoTile({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(14),
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Ink.image(
                image: FileImage(photo.file),
                fit: BoxFit.cover,
                child: const SizedBox.expand(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
              color: scheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      photo.schoolNumber,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${photo.sizeInKb.toStringAsFixed(0)}K',
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
