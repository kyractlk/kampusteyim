import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'stories_provider.dart';
import 'story_models.dart';

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.userId});

  final String userId;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _index = 0;
  Timer? _timer;
  double _progress = 0;
  String? _boundStoryKey;
  bool _started = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(Story story) {
    _timer?.cancel();
    if (story.items.isEmpty) return;
    final safe = _index.clamp(0, story.items.length - 1);
    _index = safe;
    _progress = 0;
    final item = story.items[safe];
    final totalMs = item.mediaType == MediaType.video ? 15000 : 5000;
    const tick = 50;
    var elapsed = 0;
    _timer = Timer.periodic(const Duration(milliseconds: tick), (t) {
      elapsed += tick;
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _progress = (elapsed / totalMs).clamp(0.0, 1.0));
      if (elapsed >= totalMs) {
        t.cancel();
        _next(story);
      }
    });
  }

  void _next(Story story) {
    if (_index < story.items.length - 1) {
      setState(() => _index++);
      _startTimer(story);
    } else if (mounted) {
      context.pop();
    }
  }

  void _prev(Story story) {
    if (_index > 0) {
      setState(() => _index--);
      _startTimer(story);
    } else {
      _startTimer(story);
    }
  }

  Future<void> _report(StoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hikâyeyi şikayet et'),
        content: const Text(
          'Bu hikâye uygunsuz veya spam olarak işaretlensin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
            child: const Text('Şikayet et'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<StoriesProvider>().reportStory(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Şikayet alındı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final stories = context.watch<StoriesProvider>();
    final me = auth.user;
    final story = stories.storyForUser(widget.userId);

    if (me == null || me.isSpectatorMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                me?.isSpectatorMode == true
                    ? 'İzleyici modunda hikâye görüntülenemez.'
                    : 'Giriş gerekli',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.pop(),
                child:
                    const Text('Kapat', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (story == null || story.items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Aktif hikâye yok',
                style: TextStyle(color: Colors.white),
              ),
              TextButton(
                onPressed: () => context.pop(),
                child:
                    const Text('Kapat', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final key =
        '${story.authorId}:${story.items.map((e) => e.id).join(',')}';
    if (!_started || _boundStoryKey != key) {
      _boundStoryKey = key;
      _started = true;
      if (_index >= story.items.length) _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startTimer(story);
      });
    }

    final safeIndex = _index.clamp(0, story.items.length - 1);
    final item = story.items[safeIndex];
    final liked = item.isLikedBy(me.id);
    final isOwner = item.authorId == me.id;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTapUp: (d) {
                  final w = MediaQuery.sizeOf(context).width;
                  if (d.localPosition.dx < w * 0.35) {
                    _prev(story);
                  } else {
                    _next(story);
                  }
                },
                onLongPressStart: (_) => _timer?.cancel(),
                onLongPressEnd: (_) => _startTimer(story),
                child: item.mediaType == MediaType.video
                    ? const Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white70,
                          size: 64,
                        ),
                      )
                    : SafeNetworkImage(
                        url: item.mediaUrl,
                        fit: BoxFit.contain,
                      ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Column(
                children: [
                  Row(
                    children: List.generate(story.items.length, (i) {
                      final filled = i < safeIndex
                          ? 1.0
                          : (i == safeIndex ? _progress : 0.0);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: filled,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${story.authorName}  ${story.authorHandle}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 20,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context
                        .read<StoriesProvider>()
                        .likeStory(item.id, me.id),
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? AppColors.crimson : Colors.white,
                    ),
                  ),
                  Text(
                    '${item.likedBy.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  if (isOwner)
                    IconButton(
                      tooltip: 'Sil',
                      onPressed: () async {
                        final stories = context.read<StoriesProvider>();
                        await stories.deleteStory(item.id);
                        if (!mounted) return;
                        final remaining = stories.storyForUser(widget.userId);
                        if (!mounted) return;
                        if (remaining == null || remaining.items.isEmpty) {
                          if (context.mounted) context.pop();
                        } else {
                          setState(() {
                            _index = 0;
                            _boundStoryKey = null;
                            _started = false;
                          });
                        }
                      },
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white),
                    ),
                  IconButton(
                    tooltip: 'Şikayet et',
                    onPressed: () => _report(item),
                    icon: const Icon(Icons.flag_outlined, color: Colors.white),
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
