import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/safe_network_image.dart';
import '../auth/data/auth_provider.dart';
import '../stories/campus_camera_screen.dart';
import 'reel_models.dart';
import 'reels_provider.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _page = PageController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reels = context.watch<ReelsProvider>();
    final me = auth.user;
    final feed = reels.feedFor(me?.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (reels.isLoading && feed.isEmpty)
            const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          else if (feed.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.movie_filter_outlined,
                        size: 56, color: Colors.white54),
                    const SizedBox(height: 12),
                    const Text(
                      'Henüz Kampüs Reels yok.\nİlk klip senin olsun!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => openCampusCamera(
                        context,
                        preferReels: true,
                      ),
                      child: const Text('Reels çek'),
                    ),
                  ],
                ),
              ),
            )
          else
            PageView.builder(
              controller: _page,
              scrollDirection: Axis.vertical,
              itemCount: feed.length,
              onPageChanged: (i) {
                final uid = me?.id;
                if (uid == null) return;
                context.read<ReelsProvider>().markViewed(feed[i].id, uid);
              },
              itemBuilder: (context, i) => _ReelPage(reel: feed[i]),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'Kampüs Reels',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      if (!AuthGate.requireAuth(context)) return;
                      openCampusCamera(context, preferReels: true);
                    },
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({required this.reel});
  final CampusReel reel;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _vc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    if (widget.reel.mediaType != ReelMediaType.video) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.reel.mediaUrl));
    _vc = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[reels] video: $e');
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final me = context.watch<AuthProvider>().user;
    final liked = me != null && reel.likedByUser(me.id);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (reel.mediaType == ReelMediaType.video)
          _ready && _vc != null
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _vc!.value.size.width,
                    height: _vc!.value.size.height,
                    child: VideoPlayer(_vc!),
                  ),
                )
              : const ColoredBox(color: Colors.black)
        else
          SafeNetworkImage(
            url: reel.mediaUrl,
            fit: BoxFit.cover,
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 72,
          bottom: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${reel.authorHandle.isEmpty ? reel.authorName : reel.authorHandle}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (reel.caption.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  reel.caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 10,
          bottom: 40,
          child: Column(
            children: [
              IconButton(
                onPressed: me == null
                    ? null
                    : () => context
                        .read<ReelsProvider>()
                        .toggleLike(reel.id, me.id),
                icon: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.redAccent : Colors.white,
                  size: 32,
                ),
              ),
              Text(
                '${reel.likedBy.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
