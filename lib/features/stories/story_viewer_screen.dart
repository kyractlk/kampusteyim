import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/media_disk_cache.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../core/widgets/social_widgets.dart';
import '../../core/widgets/web_safe_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import '../plus/plus_widgets.dart';
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
  int _elapsedMs = 0;
  int _totalMs = 5000;
  String? _boundStoryKey;
  bool _started = false;
  String? _recordedViewId;

  bool _mediaReady = false;
  bool _holdPaused = false;
  bool _waitingMedia = false;
  VideoPlayerController? _video;
  String? _videoForItemId;

  @override
  void dispose() {
    _timer?.cancel();
    _disposeVideo();
    super.dispose();
  }

  void _disposeVideo() {
    final v = _video;
    _video = null;
    _videoForItemId = null;
    try {
      v?.pause();
      v?.dispose();
    } catch (_) {}
  }

  void _armItem(Story story) {
    _timer?.cancel();
    if (story.items.isEmpty) return;
    final safe = _index.clamp(0, story.items.length - 1);
    _index = safe;
    _progress = 0;
    _elapsedMs = 0;
    _mediaReady = false;
    _waitingMedia = true;
    _holdPaused = false;
    final item = story.items[safe];
    _totalMs = item.mediaType == MediaType.video ? 15000 : 5000;
    unawaited(_prepareMedia(item, story));
    _ensureTicker(story);
    setState(() {});
  }

  Future<void> _prepareMedia(StoryItem item, Story story) async {
    final itemId = item.id;
    if (item.mediaType == MediaType.video) {
      await _prepareVideo(item);
      if (!mounted || story.items[_index.clamp(0, story.items.length - 1)].id != itemId) {
        return;
      }
      _onMediaReady(story);
      return;
    }
    // Görsel: native disk; web CDN stream
    File? file;
    if (!kIsWeb) {
      try {
        file = await MediaDiskCache.instance.ensure(item.mediaUrl);
      } catch (_) {}
    }
    if (!mounted || story.items[_index.clamp(0, story.items.length - 1)].id != itemId) {
      return;
    }
    try {
      final provider = (!kIsWeb && file != null)
          ? FileImage(file) as ImageProvider
          : webSafeImageProvider(item.mediaUrl);
      await precacheImage(provider, context);
    } catch (_) {}
    if (!mounted || story.items[_index.clamp(0, story.items.length - 1)].id != itemId) {
      return;
    }
    _onMediaReady(story);
  }

  Future<void> _prepareVideo(StoryItem item) async {
    if (_videoForItemId == item.id && _video?.value.isInitialized == true) {
      return;
    }
    _disposeVideo();
    try {
      File? file;
      if (!kIsWeb) {
        file = await MediaDiskCache.instance.ensure(item.mediaUrl);
      }
      VideoPlayerController c;
      if (file != null) {
        c = VideoPlayerController.file(file);
      } else {
        c = VideoPlayerController.networkUrl(Uri.parse(item.mediaUrl));
      }
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _video = c;
      _videoForItemId = item.id;
      final dur = c.value.duration.inMilliseconds;
      if (dur > 500) {
        _totalMs = dur.clamp(3000, 30000);
      }
      if (!_holdPaused) {
        await c.play();
      }
    } catch (e) {
      debugPrint('[story] video: $e');
    }
  }

  void _onMediaReady(Story story) {
    if (!mounted) return;
    setState(() {
      _mediaReady = true;
      _waitingMedia = false;
    });
    _ensureTicker(story);
    final v = _video;
    if (v != null && !_holdPaused && v.value.isInitialized) {
      unawaited(v.play());
    }
    // Sonraki item’ı ısıt (Instagram).
    unawaited(_prefetchAdjacent(story));
  }

  Future<void> _prefetchAdjacent(Story story) async {
    final next = _index + 1;
    if (next >= story.items.length) return;
    final item = story.items[next];
    if (item.mediaUrl.isEmpty) return;
    try {
      if (item.mediaType == MediaType.video) {
        if (kIsWeb) {
          final c = VideoPlayerController.networkUrl(Uri.parse(item.mediaUrl));
          await c.initialize();
          await c.dispose();
        } else {
          await MediaDiskCache.instance.ensure(item.mediaUrl, highPriority: true);
        }
      } else {
        if (!kIsWeb) {
          await MediaDiskCache.instance.ensure(item.mediaUrl, highPriority: true);
        } else if (mounted) {
          await precacheImage(webSafeImageProvider(item.mediaUrl), context);
        }
      }
    } catch (_) {}
  }

  void _ensureTicker(Story story) {
    _timer?.cancel();
    const tick = 50;
    _timer = Timer.periodic(const Duration(milliseconds: tick), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      // Instagram: yüklenene / basılı tutmaya kadar süre durur.
      if (!_mediaReady || _holdPaused || _waitingMedia) return;
      _elapsedMs += tick;
      setState(() => _progress = (_elapsedMs / _totalMs).clamp(0.0, 1.0));
      if (_elapsedMs >= _totalMs) {
        t.cancel();
        _next(story);
      }
    });
  }

  void _next(Story story) {
    _disposeVideo();
    if (_index < story.items.length - 1) {
      setState(() => _index++);
      _armItem(story);
    } else if (mounted) {
      context.pop();
    }
  }

  void _prev(Story story) {
    _disposeVideo();
    if (_index > 0) {
      setState(() => _index--);
    }
    _armItem(story);
  }

  void _recordViewIfNeeded(StoryItem item, String meId) {
    if (item.authorId == meId) return;
    if (_recordedViewId == item.id) return;
    _recordedViewId = item.id;
    unawaited(context.read<StoriesProvider>().recordView(item.id, meId));
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

  Future<void> _toggleLike(StoryItem item, AppUser me) async {
    final wasLiked = item.isLikedBy(me.id);
    await context.read<StoriesProvider>().likeStory(item.id, me.id);
    if (!mounted || wasLiked || item.authorId == me.id) return;
    context.read<NotificationProvider>().pushSocial(
          toUserId: item.authorId,
          title: 'Hikâyen beğenildi',
          body: '${me.fullName} hikâyeni beğendi',
          emoji: '❤️',
          type: 'like',
          actorId: me.id,
          targetId: item.id,
        );
  }

  Future<void> _openViewers(StoryItem item) async {
    _holdPaused = true;
    _video?.pause();
    final auth = context.read<AuthProvider>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final viewers = item.viewedBy;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Görenler · ${viewers.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (viewers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Henüz kimse görmedi'),
                  )
                else
                  SizedBox(
                    height: 320,
                    child: ListView.separated(
                      itemCount: viewers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = auth.findUser(viewers[i]);
                        final name = u?.fullName ?? viewers[i];
                        return ListTile(
                          leading: UserAvatar(
                            name: name,
                            photoUrl: u?.photoUrl,
                            radius: 18,
                          ),
                          title: Text(name),
                          subtitle: Text(u?.handle ?? ''),
                          trailing: item.likedBy.contains(viewers[i])
                              ? const Icon(Icons.favorite, color: AppColors.crimson, size: 18)
                              : null,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    _holdPaused = false;
    if (_mediaReady) {
      unawaited(_video?.play() ?? Future.value());
    }
  }

  @override
  Widget build(BuildContext context) {
    final stories = context.watch<StoriesProvider>();
    final auth = context.watch<AuthProvider>();
    final me = auth.user;
    if (me == null) {
      return const Scaffold(body: Center(child: Text('Giriş gerekli')));
    }
    final story = stories.storyForUser(widget.userId);
    if (story == null || !story.hasItems) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Aktif hikâye yok', style: TextStyle(color: Colors.white)),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Kapat', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final key = '${story.authorId}:${story.items.map((e) => e.id).join(',')}';
    if (!_started || _boundStoryKey != key) {
      final firstOpen = !_started;
      _boundStoryKey = key;
      _started = true;
      if (firstOpen) {
        // Instagram: ilk görülmemiş item’den başla.
        final myIds = auth.idsFor(me.id);
        final unseen = story.items.indexWhere(
          (it) => !it.viewedBy.any(myIds.contains) && it.authorId != me.id,
        );
        _index = unseen >= 0 ? unseen : 0;
      }
      if (_index >= story.items.length) _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _armItem(story);
      });
    }

    final safeIndex = _index.clamp(0, story.items.length - 1);
    final item = story.items[safeIndex];
    final liked = item.isLikedBy(me.id);
    final isOwner = item.authorId == me.id;
    _recordViewIfNeeded(item, me.id);

    Widget media;
    if (item.mediaType == MediaType.video) {
      if (_video != null &&
          _videoForItemId == item.id &&
          _video!.value.isInitialized) {
        media = FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _video!.value.size.width,
            height: _video!.value.size.height,
            child: VideoPlayer(_video!),
          ),
        );
      } else {
        media = const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5),
          ),
        );
      }
    } else {
      media = SafeNetworkImage(
        url: item.mediaUrl,
        fit: BoxFit.contain,
        placeholder: const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: Colors.white70,
              strokeWidth: 2.5,
            ),
          ),
        ),
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 48,
        ),
      );
    }

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
                onLongPressStart: (_) {
                  _holdPaused = true;
                  _video?.pause();
                },
                onLongPressEnd: (_) {
                  _holdPaused = false;
                  if (_mediaReady) unawaited(_video?.play() ?? Future.value());
                },
                child: media,
              ),
            ),
            if (_waitingMedia && !_mediaReady)
              const Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Yükleniyor…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
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
                        child: Row(
                          children: [
                            Flexible(
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
                            const SizedBox(width: 6),
                            UserVerificationBadges(
                              user: auth.findUser(story.authorId),
                              size: 15,
                            ),
                          ],
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
                  if (isOwner)
                    InkWell(
                      onTap: () => _openViewers(item),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.visibility_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${item.viewedBy.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (item.likedBy.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.favorite,
                                color: AppColors.crimson,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${item.likedBy.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else ...[
                    IconButton(
                      onPressed: () => _toggleLike(item, me),
                      icon: Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? AppColors.crimson : Colors.white,
                      ),
                    ),
                    Text(
                      '${item.likedBy.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                  const Spacer(),
                  if (isOwner)
                    IconButton(
                      onPressed: () async {
                        await context.read<StoriesProvider>().deleteStory(item.id);
                        if (mounted) context.pop();
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.white70),
                    )
                  else
                    IconButton(
                      onPressed: () => _report(item),
                      icon: const Icon(Icons.flag_outlined, color: Colors.white70),
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
