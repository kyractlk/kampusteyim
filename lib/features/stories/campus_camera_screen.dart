import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/hashtag_utils.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import '../feed/location_picker_sheet.dart';
import '../reels/reels_provider.dart';
import 'camera_mirror.dart';
import 'stories_provider.dart';
import 'story_overlay.dart';

enum CampusShareMode { story, reels, choose }

/// Kampüs kamera — uygulama içi canlı önizleme (telefon kamerasına yönlendirme yok).
Future<void> openCampusCamera(
  BuildContext context, {
  CampusShareMode mode = CampusShareMode.choose,
}) async {
  if (!AuthGate.requireAuth(
    context,
    message: 'Paylaşmak için giriş yapmalısın.',
  )) {
    return;
  }
  final user = context.read<AuthProvider>().user;
  if (user == null) return;
  if (user.isSpectatorMode) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İzleyici modunda paylaşım yapılamaz.')),
    );
    return;
  }
  if (!user.canUseStories) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Paylaşım şu an kullanılamıyor.')),
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CampusCameraScreen(mode: mode),
    ),
  );
}

/// Hikâye / Reels seçim menüsü (Instagram +).
Future<void> openCampusShareMenu(BuildContext context) async {
  if (!AuthGate.requireAuth(
    context,
    message: 'Paylaşmak için giriş yapmalısın.',
  )) {
    return;
  }
  final choice = await showModalBottomSheet<CampusShareMode>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Text(
              'Ne paylaşmak istersin?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.cyan,
                child: Icon(Icons.auto_awesome, color: Colors.white),
              ),
              title: const Text('Hikâye',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('24 saat kampüste görünür'),
              onTap: () => Navigator.pop(ctx, CampusShareMode.story),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.lime,
                child: Icon(Icons.movie_filter_rounded, color: AppColors.navy),
              ),
              title: const Text('Kampüs Reels',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Dikey klip — Reels akışında'),
              onTap: () => Navigator.pop(ctx, CampusShareMode.reels),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  await openCampusCamera(context, mode: choice);
}

class CampusCameraScreen extends StatefulWidget {
  const CampusCameraScreen({
    super.key,
    this.mode = CampusShareMode.choose,
    @Deprecated('Use mode') bool preferReels = false,
  }) : _legacyPreferReels = preferReels;

  final CampusShareMode mode;
  final bool _legacyPreferReels;

  @override
  State<CampusCameraScreen> createState() => _CampusCameraScreenState();
}

class _CampusCameraScreenState extends State<CampusCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _ready = false;
  bool _recording = false;
  bool _busy = false;
  double _uploadProgress = 0;
  String? _status;
  XFile? _captured;
  bool _isVideo = false;
  final _captionCtrl = TextEditingController();
  final List<StoryOverlay> _storyOverlays = [];

  CampusShareMode get _mode {
    if (widget.mode != CampusShareMode.choose) return widget.mode;
    // ignore: deprecated_member_use_from_same_package
    return widget._legacyPreferReels
        ? CampusShareMode.reels
        : CampusShareMode.choose;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captionCtrl.dispose();
    unawaited(_disposeCam());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(_disposeCam());
    } else if (state == AppLifecycleState.resumed && _captured == null) {
      unawaited(_initCamera());
    }
  }

  Future<void> _disposeCam() async {
    final c = _cam;
    _cam = null;
    _ready = false;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    if (kIsWeb) {
      setState(() => _status = 'Web’de galeri kullan');
      return;
    }
    try {
      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();
      if (!cam.isGranted) {
        if (mounted) {
          setState(() => _status = 'Kamera izni gerekli');
        }
        return;
      }
      if (!mic.isGranted) {
        debugPrint('[camera] mic denied — video sessiz olabilir');
      }
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _status = 'Kamera bulunamadı');
        return;
      }
      // Reels: arka kamera (maks kalite). Hikâye: ön kamera.
      if (_mode == CampusShareMode.reels) {
        final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = back >= 0 ? back : 0;
      } else {
        final front = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
        );
        _cameraIndex = front >= 0 ? front : 0;
      }
      await _openCamera(_cameras[_cameraIndex]);
    } catch (e) {
      debugPrint('[camera] init: $e');
      if (mounted) setState(() => _status = 'Kamera açılamadı');
    }
  }

  Future<void> _openCamera(CameraDescription desc) async {
    const presets = <ResolutionPreset>[
      ResolutionPreset.max,
      ResolutionPreset.ultraHigh,
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
    ];
    Object? lastError;
    for (final preset in presets) {
      await _disposeCam();
      final c = CameraController(
        desc,
        preset,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _cam = c;
      try {
        await c.initialize();
        try {
          await c.setFocusMode(FocusMode.auto);
        } catch (_) {}
        try {
          await c.setExposureMode(ExposureMode.auto);
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _ready = true;
          _status = null;
        });
        debugPrint('[camera] ready preset=$preset');
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[camera] preset $preset failed: $e');
      }
    }
    if (mounted) {
      setState(() => _status = 'Kamera hazır değil');
    }
    debugPrint('[camera] open failed: $lastError');
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording || _busy) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _openCamera(_cameras[_cameraIndex]);
  }

  bool get _isFrontLens {
    final c = _cam;
    if (c == null) return false;
    return c.description.lensDirection == CameraLensDirection.front;
  }

  Future<void> _takePhoto() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _busy || _recording) return;
    final front = _isFrontLens;
    try {
      var file = await c.takePicture();
      // Ön kamera: önizleme aynalı → kaydı da aynala (ters çevirmesin).
      if (front) {
        file = await mirrorImageFileHorizontal(file);
      }
      if (!mounted) return;
      setState(() {
        _captured = file;
        _isVideo = false;
      });
      await _disposeCam();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto çekilemedi: $e')),
      );
    }
  }

  Future<void> _startRecord() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _busy || _recording) return;
    try {
      await c.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt başlatılamadı: $e')),
      );
    }
  }

  Future<void> _stopRecord() async {
    final c = _cam;
    if (c == null || !_recording) return;
    try {
      final file = await c.stopVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _captured = file;
        _isVideo = true;
      });
      await _disposeCam();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt bitirilemedi: $e')),
      );
    }
  }

  Future<void> _fromGallery({required bool video}) async {
    if (_busy || _recording) return;
    try {
      setState(() => _status = 'Galeri…');
      final file = video
          ? await MediaUpload.pickVideo()
          : await MediaUpload.pickImage();
      if (!mounted) return;
      if (file == null) {
        setState(() => _status = null);
        return;
      }
      setState(() {
        _captured = file;
        _isVideo = video;
        _status = null;
      });
      await _disposeCam();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seçilemedi: $e')),
      );
    }
  }

  Future<void> _retake() async {
    setState(() {
      _captured = null;
      _isVideo = false;
      _captionCtrl.clear();
      _storyOverlays.clear();
    });
    await _initCamera();
  }

  Future<void> _addStoryText() async {
    final ctrl = TextEditingController();
    var font = 'bold';
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Yazı ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ctrl, autofocus: true, maxLines: 3),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final f in [
                    ('bold', 'Kalın'),
                    ('serif', 'Serif'),
                    ('handwritten', 'El yazısı'),
                    ('outline', 'Kontur'),
                  ])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: font == f.$1,
                      onSelected: (_) => setLocal(() => font = f.$1),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty) return;
    setState(() {
      _storyOverlays.add(
        StoryOverlay(
          id: 't_${DateTime.now().millisecondsSinceEpoch}',
          type: 'text',
          x: 0.5,
          y: 0.35 + (_storyOverlays.length * 0.08),
          text: text,
          fontStyle: font,
        ),
      );
    });
  }

  Future<void> _addStoryLocation() async {
    final picked = await showLocationPickerSheet(context);
    if (picked == null || !mounted) return;
    final label = '${picked['label'] ?? ''}'.trim();
    if (label.isEmpty) return;
    setState(() {
      _storyOverlays.add(
        StoryOverlay(
          id: 'l_${DateTime.now().millisecondsSinceEpoch}',
          type: 'location',
          x: 0.5,
          y: 0.75,
          locationLabel: label,
          locationLat: (picked['lat'] as num?)?.toDouble(),
          locationLng: (picked['lng'] as num?)?.toDouble(),
          locationMapsUrl: picked['mapsUrl'] as String?,
        ),
      );
    });
  }

  Future<void> _addStoryPostSticker() async {
    final feed = context.read<FeedProvider>();
    final posts = feed.posts.take(20).toList();
    if (posts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eklenecek gönderi yok')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Post>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView.builder(
        itemCount: posts.length,
        itemBuilder: (ctx, i) {
          final p = posts[i];
          return ListTile(
            title: Text(p.authorName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(p.content, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(ctx, p),
          );
        },
      ),
    );
    if (picked == null) return;
    setState(() {
      _storyOverlays.add(
        StoryOverlay(
          id: 'p_${DateTime.now().millisecondsSinceEpoch}',
          type: 'post',
          x: 0.5,
          y: 0.55,
          postId: picked.id,
          postPreview: picked.content,
        ),
      );
    });
  }

  Future<void> _publish({required bool asReel}) async {
    final file = _captured;
    final user = context.read<AuthProvider>().user;
    if (file == null || user == null || _busy) return;
    setState(() {
      _busy = true;
      _uploadProgress = 0;
      _status = asReel ? 'Kampüs Reels yükleniyor…' : 'Hikâye yükleniyor…';
    });
    void onProg(double p) {
      if (!mounted) return;
      setState(() {
        _uploadProgress = p;
        final pct = (p * 100).clamp(0, 100).round();
        _status = asReel
            ? 'Kampüs Reels yükleniyor… %$pct'
            : 'Hikâye yükleniyor… %$pct';
      });
    }

    String? err;
    if (asReel) {
      err = await context.read<ReelsProvider>().createReel(
            author: user,
            file: file,
            isVideo: _isVideo,
            caption: _captionCtrl.text,
            onProgress: onProg,
          );
    } else {
      err = await context.read<StoriesProvider>().createStory(
            author: user,
            file: file,
            isVideo: _isVideo,
            onProgress: onProg,
            overlays: _storyOverlays.map((e) => e.toMap()).toList(),
          );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
      _uploadProgress = 0;
    });
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.lime),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                asReel
                    ? 'Kampüs Reels paylaşıldı'
                    : 'Hikâyen kampüste yayınlandı',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publishByMode() async {
    if (_mode == CampusShareMode.reels) {
      await _publish(asReel: true);
    } else if (_mode == CampusShareMode.story) {
      await _publish(asReel: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _captured != null;
    final title = hasFile
        ? 'Paylaş'
        : (_mode == CampusShareMode.reels
            ? 'Kampüs Reels'
            : (_mode == CampusShareMode.story ? 'Hikâye' : 'Kampüs kamera'));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (hasFile)
            Stack(
              fit: StackFit.expand,
              children: [
                _CapturedPreview(file: _captured!, isVideo: _isVideo),
                if (_mode != CampusShareMode.reels)
                  StoryOverlayLayer(
                    overlays: _storyOverlays,
                    interactive: true,
                    onMove: (id, x, y) {
                      final i = _storyOverlays.indexWhere((e) => e.id == id);
                      if (i < 0) return;
                      setState(() {
                        final o = _storyOverlays[i];
                        _storyOverlays[i] = StoryOverlay(
                          id: o.id,
                          type: o.type,
                          x: x,
                          y: y,
                          scale: o.scale,
                          rotation: o.rotation,
                          text: o.text,
                          fontStyle: o.fontStyle,
                          colorHex: o.colorHex,
                          postId: o.postId,
                          postPreview: o.postPreview,
                          locationLabel: o.locationLabel,
                          locationLat: o.locationLat,
                          locationLng: o.locationLng,
                          locationMapsUrl: o.locationMapsUrl,
                        );
                      });
                    },
                  ),
                if (_mode != CampusShareMode.reels)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: MediaQuery.paddingOf(context).top + 56,
                    child: Row(
                      children: [
                        _StoryToolBtn(
                          icon: Icons.text_fields_rounded,
                          onTap: _addStoryText,
                        ),
                        const SizedBox(width: 8),
                        _StoryToolBtn(
                          icon: Icons.place_outlined,
                          onTap: _addStoryLocation,
                        ),
                        const SizedBox(width: 8),
                        _StoryToolBtn(
                          icon: Icons.sticky_note_2_outlined,
                          onTap: _addStoryPostSticker,
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else if (_ready && _cam != null && _cam!.value.isInitialized)
            _CameraPreviewFill(controller: _cam!)
          else
            ColoredBox(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_status == null)
                      const CircularProgressIndicator(color: AppColors.cyan)
                    else
                      Text(
                        _status!,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    if (kIsWeb || _status != null) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _fromGallery(video: false),
                        child: const Text('Galeriden seç',
                            style: TextStyle(color: AppColors.cyan)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_recording)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, color: Colors.redAccent, size: 12),
                      SizedBox(width: 8),
                      Text(
                        'KAYDEDİLİYOR',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (!hasFile)
                    IconButton(
                      onPressed: _flipCamera,
                      icon: const Icon(Icons.cameraswitch_rounded,
                          color: Colors.white),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          if (hasFile && !_busy)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PublishPanel(
                isVideo: _isVideo,
                mode: _mode,
                captionCtrl: _captionCtrl,
                onRetake: _retake,
                onStory: () => _publish(asReel: false),
                onReels: () => _publish(asReel: true),
                onModePublish: _publishByMode,
              ),
            )
          else if (!hasFile && !_busy)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_status != null && _ready)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _status!,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: 'Galeriden foto',
                            onPressed: () => _fromGallery(video: false),
                            icon: const Icon(Icons.photo_library_outlined,
                                color: Colors.white, size: 30),
                          ),
                          GestureDetector(
                            onTap: _recording ? null : _takePhoto,
                            onLongPressStart: (_) => _startRecord(),
                            onLongPressEnd: (_) => _stopRecord(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: _recording ? 84 : 78,
                              height: _recording ? 84 : 78,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 4),
                                color: _recording
                                    ? Colors.redAccent
                                    : AppColors.cyan.withValues(alpha: 0.4),
                              ),
                              child: Icon(
                                _recording
                                    ? Icons.stop_rounded
                                    : Icons.circle,
                                color: Colors.white,
                                size: _recording ? 36 : 28,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Galeriden video',
                            onPressed: () => _fromGallery(video: true),
                            icon: const Icon(Icons.video_library_outlined,
                                color: Colors.white, size: 30),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _recording
                            ? 'Bırakınca kayıt biter'
                            : 'Dokun: foto · Basılı tut: video',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_busy)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 280),
                builder: (context, fade, child) =>
                    Opacity(opacity: fade, child: child),
                child: ColoredBox(
                  color: const Color(0xE6081424),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.cyan.withValues(alpha: 0.35),
                                  AppColors.navy.withValues(alpha: 0.9),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cyan.withValues(alpha: 0.25),
                                  blurRadius: 28,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(6),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: _uploadProgress),
                              duration: const Duration(milliseconds: 220),
                              builder: (context, value, _) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox.expand(
                                      child: CircularProgressIndicator(
                                        value: value <= 0.02 ? null : value,
                                        strokeWidth: 3.5,
                                        color: AppColors.cyan,
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _mode == CampusShareMode.reels
                                              ? Icons.movie_filter_rounded
                                              : Icons.auto_awesome_rounded,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          value <= 0.02
                                              ? '…'
                                              : '%${(value * 100).round()}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            _status ??
                                (_mode == CampusShareMode.reels
                                    ? 'Kampüs Reels yükleniyor…'
                                    : 'Hikâye yükleniyor…'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kısaca bekle — medyan kampüse aktarılıyor',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: SizedBox(
                              width: 220,
                              child: LinearProgressIndicator(
                                value: _uploadProgress <= 0.02
                                    ? null
                                    : _uploadProgress,
                                minHeight: 5,
                                color: AppColors.lime,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraPreviewFill extends StatelessWidget {
  const _CameraPreviewFill({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    final front =
        controller.description.lensDirection == CameraLensDirection.front;
    Widget preview = size == null
        ? CameraPreview(controller)
        : FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.height,
              height: size.width,
              child: CameraPreview(controller),
            ),
          );
    // Platform ön kamerayı zaten aynalar; ekstra çevirme yok.
    // (Kayıt tarafında foto aynalanır → gördüğün = çekilen.)
    if (!front) return preview;
    return preview;
  }
}

class _CapturedPreview extends StatefulWidget {
  const _CapturedPreview({required this.file, required this.isVideo});
  final XFile file;
  final bool isVideo;

  @override
  State<_CapturedPreview> createState() => _CapturedPreviewState();
}

class _CapturedPreviewState extends State<_CapturedPreview> {
  VideoPlayerController? _vc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo && !kIsWeb) {
      unawaited(_initVideo());
    }
  }

  @override
  void didUpdateWidget(covariant _CapturedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.isVideo != widget.isVideo) {
      unawaited(_disposeVc());
      if (widget.isVideo && !kIsWeb) {
        unawaited(_initVideo());
      }
    }
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.file(File(widget.file.path));
      _vc = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(1);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[camera] preview video: $e');
    }
  }

  Future<void> _disposeVc() async {
    final c = _vc;
    _vc = null;
    _ready = false;
    try {
      await c?.pause();
      await c?.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_disposeVc());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(
            widget.isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
            size: 80,
            color: AppColors.cyan,
          ),
        ),
      );
    }
    if (!widget.isVideo) {
      return Image.file(
        File(widget.file.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
      );
    }
    if (_ready && _vc != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _vc!.value.size.width,
          height: _vc!.value.size.height,
          child: VideoPlayer(_vc!),
        ),
      );
    }
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: AppColors.cyan),
      ),
    );
  }
}

class _PublishPanel extends StatefulWidget {
  const _PublishPanel({
    required this.isVideo,
    required this.mode,
    required this.captionCtrl,
    required this.onRetake,
    required this.onStory,
    required this.onReels,
    required this.onModePublish,
  });

  final bool isVideo;
  final CampusShareMode mode;
  final TextEditingController captionCtrl;
  final VoidCallback onRetake;
  final VoidCallback onStory;
  final VoidCallback onReels;
  final VoidCallback onModePublish;

  @override
  State<_PublishPanel> createState() => _PublishPanelState();
}

class _PublishPanelState extends State<_PublishPanel> {
  final _focus = FocusNode();
  String? _mentionQuery;
  List<AppUser> _mentionHits = const [];

  bool get _showCaption =>
      widget.mode == CampusShareMode.reels ||
      widget.mode == CampusShareMode.choose;

  @override
  void initState() {
    super.initState();
    widget.captionCtrl.addListener(_onCaptionChanged);
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.captionCtrl.removeListener(_onCaptionChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onCaptionChanged() {
    if (!mounted || !_showCaption) return;
    final auth = context.read<AuthProvider>();
    final cursor = widget.captionCtrl.selection.baseOffset;
    final q = MentionUtils.activeQuery(
      widget.captionCtrl.text,
      cursor < 0 ? widget.captionCtrl.text.length : cursor,
    );
    if (q == null) {
      if (_mentionQuery != null) {
        setState(() {
          _mentionQuery = null;
          _mentionHits = const [];
        });
      } else {
        setState(() {});
      }
      return;
    }
    final hits = MentionUtils.suggestions(
      directory: auth.directory,
      query: q,
      excludeUserId: auth.user?.id,
    );
    setState(() {
      _mentionQuery = q;
      _mentionHits = hits;
    });
  }

  void _pickMention(AppUser u) {
    final cursor = widget.captionCtrl.selection.baseOffset;
    final next = MentionUtils.applyMention(
      text: widget.captionCtrl.text,
      cursor: cursor < 0 ? widget.captionCtrl.text.length : cursor,
      user: u,
    );
    widget.captionCtrl.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.cursor),
    );
    setState(() {
      _mentionQuery = null;
      _mentionHits = const [];
    });
  }

  void _insertToken(String token) {
    final t = widget.captionCtrl.text;
    final cursor = widget.captionCtrl.selection.baseOffset;
    final at = cursor < 0 ? t.length : cursor;
    final before = t.substring(0, at);
    final after = t.substring(at);
    final needsSpace = before.isNotEmpty && !before.endsWith(' ');
    final insert = '${needsSpace ? ' ' : ''}$token';
    final next = '$before$insert$after';
    final newCursor = before.length + insert.length;
    widget.captionCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.mode != CampusShareMode.choose;
    final uniqueTags = HashtagUtils.uniqueCount(widget.captionCtrl.text);
    final showMentions = _mentionQuery != null && _mentionHits.isNotEmpty;

    return Material(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showCaption) ...[
                TextField(
                  controller: widget.captionCtrl,
                  focusNode: _focus,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  minLines: 2,
                  cursorColor: AppColors.cyan,
                  onTapOutside: (_) {
                    _focus.unfocus();
                    setState(() {
                      _mentionQuery = null;
                      _mentionHits = const [];
                    });
                  },
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () {
                    _focus.unfocus();
                    setState(() {
                      _mentionQuery = null;
                      _mentionHits = const [];
                    });
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Açıklama · @kullanıcı / @topluluk · #hashtag',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_focus.hasFocus)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _focus.unfocus();
                        setState(() {
                          _mentionQuery = null;
                          _mentionHits = const [];
                        });
                      },
                      child: const Text(
                        'Klavye kapat',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                if (showMentions)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _mentionHits.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: Colors.white12,
                      ),
                      itemBuilder: (context, i) {
                        final u = _mentionHits[i];
                        return ListTile(
                          dense: true,
                          onTap: () => _pickMention(u),
                          leading: UserAvatar(
                            name: u.fullName,
                            photoUrl: u.communityLogoUrl ?? u.photoUrl,
                            isCommunity: u.isCommunity,
                            radius: 16,
                          ),
                          title: Text(
                            u.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            MentionUtils.displayHandle(u.handle),
                            style: TextStyle(
                              color: u.isCommunity
                                  ? AppColors.lime
                                  : AppColors.cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Text(
                            u.isCommunity
                                ? 'Topluluk'
                                : (u.isCompany ? 'Firma' : 'Kullanıcı'),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _CaptionQuickChip(
                      label: '@ etiket',
                      onTap: () => _insertToken('@'),
                    ),
                    const SizedBox(width: 8),
                    _CaptionQuickChip(
                      label: '# hashtag',
                      onTap: () => _insertToken('#'),
                    ),
                    const Spacer(),
                    if (uniqueTags > 0)
                      Text(
                        '$uniqueTags hashtag',
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (fixed)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.mode == CampusShareMode.reels
                        ? AppColors.lime
                        : AppColors.cyan,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: widget.onModePublish,
                  child: Text(
                    widget.mode == CampusShareMode.reels
                        ? 'Kampüs Reels olarak paylaş'
                        : 'Hikâye olarak paylaş',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              else ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: widget.onStory,
                  child: const Text(
                    'Hikâye olarak paylaş',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lime,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: widget.onReels,
                  child: Text(
                    widget.isVideo
                        ? 'Kampüs Reels olarak paylaş'
                        : 'Kampüs Reels’e koy',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
              TextButton(
                onPressed: widget.onRetake,
                child: const Text(
                  'Yeniden çek',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptionQuickChip extends StatelessWidget {
  const _CaptionQuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryToolBtn extends StatelessWidget {
  const _StoryToolBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}
