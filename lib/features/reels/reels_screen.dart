import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import '../stories/campus_camera_screen.dart';
import 'reel_models.dart';
import 'reels_provider.dart';
import 'reels_video_cache.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _page = PageController();
  int _index = 0;

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
    final tabOn = reels.tabActive;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
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
                        mode: CampusShareMode.reels,
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
                setState(() => _index = i);
                final uid = me?.id;
                if (uid == null) return;
                context.read<ReelsProvider>().markViewed(feed[i].id, uid);
                // Sonraki 2–3 reel’i ısıt.
                final slice = feed.skip(i).take(4).toList();
                ReelsVideoCache.instance.prefetch(slice, count: 4);
              },
              itemBuilder: (context, i) => _ReelPage(
                key: ValueKey(feed[i].id),
                reel: feed[i],
                isActive: tabOn && i == _index,
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'Kampüs Reels',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      shadows: [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Çek / paylaş',
                    onPressed: () {
                      if (!AuthGate.requireAuth(context)) return;
                      openCampusShareMenu(context);
                    },
                    icon: const Icon(Icons.camera_alt_rounded,
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
  const _ReelPage({super.key, required this.reel, required this.isActive});
  final CampusReel reel;
  final bool isActive;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _vc;
  bool _ready = false;
  bool _paused = false;
  bool _muted = false;
  bool _showPauseIcon = false;
  bool _ownedLocally = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncPlayback();
    }
    if (oldWidget.reel.id != widget.reel.id) {
      _detachVc();
      _paused = false;
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    if (widget.reel.mediaType != ReelMediaType.video) return;
    final cached = await ReelsVideoCache.instance.obtain(
      reelId: widget.reel.id,
      url: widget.reel.mediaUrl,
    );
    if (!mounted) return;
    if (cached != null) {
      _vc = cached;
      _ownedLocally = false;
      setState(() => _ready = true);
      _syncPlayback();
      return;
    }
    // Cache başarısızsa yerel fallback.
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.reel.mediaUrl));
      _vc = c;
      _ownedLocally = true;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);
      if (!mounted) return;
      setState(() => _ready = true);
      _syncPlayback();
    } catch (e) {
      debugPrint('[reels] video: $e');
    }
  }

  void _syncPlayback() {
    final c = _vc;
    if (c == null || !_ready) return;
    if (widget.isActive && !_paused) {
      c.setVolume(_muted ? 0 : 1);
      c.play();
    } else {
      c.pause();
    }
  }

  void _togglePause() {
    if (widget.reel.mediaType != ReelMediaType.video) return;
    setState(() {
      _paused = !_paused;
      _showPauseIcon = true;
    });
    _syncPlayback();
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showPauseIcon = false);
    });
  }

  void _toggleMute() {
    final c = _vc;
    setState(() => _muted = !_muted);
    c?.setVolume(_muted ? 0 : 1);
  }

  void _detachVc() {
    final c = _vc;
    _vc = null;
    _ready = false;
    if (_ownedLocally && c != null) {
      try {
        c.pause();
        c.dispose();
      } catch (_) {}
    } else {
      // Paylaşımlı cache — sadece pause.
      try {
        c?.pause();
      } catch (_) {}
    }
    _ownedLocally = false;
  }

  @override
  void dispose() {
    _detachVc();
    super.dispose();
  }

  Future<void> _toggleFollow(AppUser? author) async {
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    if (me == null || author == null) return;
    if (me.id == author.id) return;
    final already = auth.follows(author.id);
    if (author.isPrivateAccount && !already) {
      await auth.requestFollow(author.id);
      if (!mounted) return;
      context.read<NotificationProvider>().pushSocial(
            toUserId: author.id,
            title: 'Takip isteği',
            body: '${me.fullName} seni takip etmek istiyor',
            emoji: '✨',
            type: 'follow_request',
            actorId: me.id,
            targetId: me.id,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takip isteği gönderildi')),
      );
      return;
    }
    await auth.toggleFollow(author.id);
    if (!mounted) return;
    if (!already) {
      context.read<NotificationProvider>().pushSocial(
            toUserId: author.id,
            title: 'Yeni takipçi',
            body: '${me.fullName} seni takip etmeye başladı',
            emoji: 'FOLLOW',
            type: 'follow',
            actorId: me.id,
            targetId: me.id,
          );
    }
  }

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ReelCommentsSheet(reel: widget.reel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final auth = context.watch<AuthProvider>();
    final me = auth.user;
    final author = auth.findUser(reel.authorId);
    final liked = me != null && reel.likedByUser(me.id);
    final following = me != null && auth.follows(reel.authorId);
    final isSelf = me != null && auth.idsFor(reel.authorId).contains(me.id);
    final verified = reel.authorVerified ||
        (author?.showBlueBadge == true) ||
        (author?.showGoldBadge == true);
    final photo = author?.photoUrl ?? reel.authorPhotoUrl;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePause,
      child: Stack(
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
            SafeNetworkImage(url: reel.mediaUrl, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black26,
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black87,
                ],
                stops: [0, 0.2, 0.55, 1],
              ),
            ),
          ),
          if (_showPauseIcon)
            Center(
              child: Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: Colors.white.withValues(alpha: 0.85),
                size: 72,
              ),
            ),
          Positioned(
            left: 14,
            right: 72,
            bottom: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push(
                        '/user/${Uri.encodeComponent(reel.authorId)}',
                      ),
                      child: UserAvatar(
                        name: reel.authorName,
                        photoUrl: photo,
                        radius: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => context.push(
                          '/user/${Uri.encodeComponent(reel.authorId)}',
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                reel.displayHandle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (verified) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 16,
                                color: author?.showGoldBadge == true
                                    ? AppColors.gold
                                    : const Color(0xFF1DA1F2),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!isSelf && me != null) ...[
                      const SizedBox(width: 10),
                      if (!following)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _toggleFollow(author),
                          child: Text(
                            author?.isPrivateAccount == true
                                ? 'İstek'
                                : 'Takip et',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        Text(
                          'Takip',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ],
                ),
                if (reel.caption.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    reel.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 8,
            bottom: 96,
            child: Column(
              children: [
                _SideBtn(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.redAccent : Colors.white,
                  label: '${reel.likedBy.length}',
                  onTap: me == null
                      ? null
                      : () => context
                          .read<ReelsProvider>()
                          .toggleLike(reel.id, me.id),
                ),
                const SizedBox(height: 14),
                _SideBtn(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${reel.commentCount}',
                  onTap: () {
                    if (!AuthGate.requireAuth(context)) return;
                    _openComments();
                  },
                ),
                const SizedBox(height: 14),
                _SideBtn(
                  icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  label: _muted ? 'Sessiz' : 'Ses',
                  onTap: reel.mediaType == ReelMediaType.video
                      ? _toggleMute
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideBtn extends StatelessWidget {
  const _SideBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: color, size: 30),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _ReelCommentsSheet extends StatefulWidget {
  const _ReelCommentsSheet({required this.reel});
  final CampusReel reel;

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<AppUser> _suggestions = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final cursor = _ctrl.selection.baseOffset;
    final q = MentionUtils.activeQuery(text, cursor < 0 ? text.length : cursor);
    final auth = context.read<AuthProvider>();
    if (q == null) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() {
      _suggestions = MentionUtils.suggestions(
        directory: auth.directory,
        query: q,
        excludeUserId: auth.user?.id,
      );
    });
  }

  void _applyMention(AppUser u) {
    final cursor = _ctrl.selection.baseOffset;
    final r = MentionUtils.applyMention(
      text: _ctrl.text,
      cursor: cursor < 0 ? _ctrl.text.length : cursor,
      user: u,
    );
    _ctrl.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
    setState(() => _suggestions = const []);
  }

  Future<void> _send() async {
    final me = context.read<AuthProvider>().user;
    if (me == null) return;
    final err = await context.read<ReelsProvider>().addComment(
          reelId: widget.reel.id,
          author: me,
          content: _ctrl.text,
        );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    if (widget.reel.authorId != me.id) {
      context.read<NotificationProvider>().pushSocial(
            toUserId: widget.reel.authorId,
            title: 'Yeni yorum',
            body: '${me.fullName} Reels’ine yorum yaptı',
            emoji: '💬',
            type: 'comment',
            actorId: me.id,
            targetId: widget.reel.id,
          );
    }
    _ctrl.clear();
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Yorumlar',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ReelComment>>(
                stream:
                    context.read<ReelsProvider>().commentsStream(widget.reel.id),
                builder: (context, snap) {
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return const Center(
                      child: Text(
                        'Henüz yorum yok — ilkini sen yaz.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => context.push(
                              '/user/${Uri.encodeComponent(c.authorId)}',
                            ),
                            child: UserAvatar(
                              name: c.authorName,
                              photoUrl: c.authorPhotoUrl,
                              radius: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      c.displayHandle,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (c.authorVerified) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.verified,
                                          size: 14, color: Color(0xFF1DA1F2)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(c.content),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_suggestions.isNotEmpty)
              SizedBox(
                height: 56,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) {
                    final u = _suggestions[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: UserAvatar(
                          name: u.fullName,
                          photoUrl: u.photoUrl,
                          radius: 12,
                        ),
                        label: Text(MentionUtils.displayHandle(u.handle)),
                        onPressed: () => _applyMention(u),
                      ),
                    );
                  },
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        onChanged: _onChanged,
                        decoration: InputDecoration(
                          hintText: 'Yorum yaz… @kullanici',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded,
                          color: AppColors.cyan),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
