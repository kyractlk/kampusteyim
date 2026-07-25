import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import '../reels/reels_provider.dart';
import 'stories_provider.dart';

/// Kampüs kamera — anlık foto / basılı video / galeri; Hikâye veya Reels paylaş.
Future<void> openCampusCamera(
  BuildContext context, {
  bool preferReels = false,
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
      builder: (_) => CampusCameraScreen(preferReels: preferReels),
    ),
  );
}

class CampusCameraScreen extends StatefulWidget {
  const CampusCameraScreen({super.key, this.preferReels = false});

  final bool preferReels;

  @override
  State<CampusCameraScreen> createState() => _CampusCameraScreenState();
}

class _CampusCameraScreenState extends State<CampusCameraScreen> {
  XFile? _file;
  bool _isVideo = false;
  bool _busy = false;
  String? _status;

  Future<void> _snapPhoto() async {
    if (_busy) return;
    try {
      setState(() => _status = 'Kamera açılıyor…');
      final file = await MediaUpload.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      if (file == null) {
        setState(() => _status = null);
        return;
      }
      setState(() {
        _file = file;
        _isVideo = false;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto çekilemedi: $e')),
      );
    }
  }

  Future<void> _recordVideo() async {
    if (_busy) return;
    try {
      setState(() => _status = 'Video kaydı…');
      final file = await MediaUpload.pickVideo(source: ImageSource.camera);
      if (!mounted) return;
      if (file == null) {
        setState(() => _status = null);
        return;
      }
      setState(() {
        _file = file;
        _isVideo = true;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Video çekilemedi: $e')),
      );
    }
  }

  Future<void> _fromGallery({required bool video}) async {
    if (_busy) return;
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
        _file = file;
        _isVideo = video;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seçilemedi: $e')),
      );
    }
  }

  Future<void> _publish({required bool asReel}) async {
    final file = _file;
    final user = context.read<AuthProvider>().user;
    if (file == null || user == null || _busy) return;
    setState(() {
      _busy = true;
      _status = asReel ? 'Kampüs Reels yükleniyor…' : 'Hikâye yükleniyor…';
    });
    String? err;
    if (asReel) {
      err = await context.read<ReelsProvider>().createReel(
            author: user,
            file: file,
            isVideo: _isVideo,
          );
    } else {
      err = await context.read<StoriesProvider>().createStory(
            author: user,
            file: file,
            isVideo: _isVideo,
          );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
    });
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          asReel ? 'Kampüs Reels paylaşıldı' : 'Hikâyen kampüste yayınlandı',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _file != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          hasFile ? 'Paylaş' : 'Kampüs kamera',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: hasFile
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isVideo
                                ? Icons.videocam_rounded
                                : Icons.photo_rounded,
                            size: 72,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isVideo
                                ? 'Video hazır — nasıl paylaşmak istersin?'
                                : 'Fotoğraf hazır — nasıl paylaşmak istersin?',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.camera_alt_outlined,
                            size: 64,
                            color: Colors.white54,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _status ??
                                'Dokun: foto · Basılı tut / video · Galeri',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
              ),
            ),
            if (_busy || _status != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.cyan,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _status ?? 'Yükleniyor…',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            if (hasFile && !_busy) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: AppColors.navy,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => _publish(asReel: false),
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
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => _publish(asReel: true),
                      child: Text(
                        _isVideo
                            ? 'Kampüs Reels olarak paylaş'
                            : 'Kampüs Reels’e de koy',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _file = null;
                        _isVideo = false;
                      }),
                      child: const Text(
                        'Yeniden çek',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!_busy) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Galeriden foto',
                      onPressed: () => _fromGallery(video: false),
                      icon: const Icon(Icons.photo_library_outlined,
                          color: Colors.white, size: 28),
                    ),
                    GestureDetector(
                      onTap: _snapPhoto,
                      onLongPress: _recordVideo,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: AppColors.cyan.withValues(alpha: 0.35),
                        ),
                        child: const Icon(Icons.circle,
                            color: Colors.white, size: 28),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Galeriden video',
                      onPressed: () => _fromGallery(video: true),
                      icon: const Icon(Icons.video_library_outlined,
                          color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Orta düğme: dokun = foto · basılı tut = video',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
