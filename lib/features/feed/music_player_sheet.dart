import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../study/music_link_meta.dart';

/// Spotify / Apple Music resmi embed oynatıcı.
Future<void> openMusicPlayer(
  BuildContext context, {
  required MusicLinkMeta meta,
}) async {
  final embed = embedUrlForMusic(meta);
  if (kIsWeb || embed == null) {
    final uri = Uri.tryParse(meta.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _MusicPlayerSheet(meta: meta, embedUrl: embed),
  );
}

String? embedUrlForMusic(MusicLinkMeta meta) {
  final url = meta.url.trim();
  if (meta.provider == 'spotify' || url.contains('open.spotify.com')) {
    // open.spotify.com/track/ID → open.spotify.com/embed/track/ID
    final m = RegExp(
      r'open\.spotify\.com/(intl-[a-z]{2}/)?(track|album|playlist|episode)/([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(url);
    if (m == null) return null;
    final kind = m.group(2)!;
    final id = m.group(3)!;
    return 'https://open.spotify.com/embed/$kind/$id?utm_source=generator&theme=0';
  }
  if (meta.provider == 'apple' || url.contains('music.apple.com')) {
    // music.apple.com/... → embed.music.apple.com/...
    final u = Uri.tryParse(url);
    if (u == null) return null;
    return Uri(
      scheme: 'https',
      host: 'embed.music.apple.com',
      path: u.path,
      query: u.query.isEmpty ? null : u.query,
    ).toString();
  }
  return null;
}

class _MusicPlayerSheet extends StatefulWidget {
  const _MusicPlayerSheet({required this.meta, required this.embedUrl});

  final MusicLinkMeta meta;
  final String embedUrl;

  @override
  State<_MusicPlayerSheet> createState() => _MusicPlayerSheetState();
}

class _MusicPlayerSheetState extends State<_MusicPlayerSheet> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    final isApple = widget.meta.provider == 'apple';
    final h = MediaQuery.sizeOf(context).height * 0.42;
    return SizedBox(
      height: h.clamp(280.0, 380.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.meta.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        isApple ? 'Apple Music' : 'Spotify',
                        style: TextStyle(
                          color: isApple
                              ? const Color(0xFFFA233B)
                              : const Color(0xFF1DB954),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(widget.meta.url);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: const Text('Uygulamada aç'),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.navy),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
