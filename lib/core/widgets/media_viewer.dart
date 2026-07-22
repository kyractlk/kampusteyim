import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import 'safe_network_image.dart';

/// Tam ekran foto / video görüntüleyici + indir.
Future<void> openMediaViewer(
  BuildContext context, {
  required List<String> urls,
  required List<bool> isVideo,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => MediaViewerPage(
        urls: urls,
        isVideo: isVideo,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class MediaViewerPage extends StatefulWidget {
  const MediaViewerPage({
    super.key,
    required this.urls,
    required this.isVideo,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final List<bool> isVideo;
  final int initialIndex;

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late final PageController _page;
  late int _index;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final url = widget.urls[_index];
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('İndirme başarısız (${res.statusCode})');
        }
        final ext = widget.isVideo[_index]
            ? 'mp4'
            : (url.contains('.png') ? 'png' : 'jpg');
        final mime = widget.isVideo[_index]
            ? 'video/mp4'
            : (ext == 'png' ? 'image/png' : 'image/jpeg');
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                res.bodyBytes,
                mimeType: mime,
                name: 'mt_media.$ext',
              ),
            ],
            text: 'KampüsteyimAPP medya',
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medya hazır · paylaş / kaydet')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.urls.length}'),
        actions: [
          IconButton(
            tooltip: 'İndir / paylaş',
            onPressed: _busy ? null : _download,
            icon: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final url = widget.urls[i];
          if (widget.isVideo[i]) {
            return _VideoPane(url: url);
          }
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: SafeNetworkImage(
                url: url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.white70, size: 48),
                    SizedBox(height: 8),
                    Text('Görsel yüklenemedi',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VideoPane extends StatefulWidget {
  const _VideoPane({required this.url});
  final String url;

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  VideoPlayerController? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 8),
            const Text('Video oynatılamadı',
                style: TextStyle(color: Colors.white70)),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(widget.url),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Tarayıcıda aç'),
            ),
          ],
        ),
      );
    }
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
        setState(() {});
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              if (!c.value.isPlaying)
                const Icon(Icons.play_circle_fill_rounded,
                    color: Colors.white, size: 64),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppColors.cyan,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
