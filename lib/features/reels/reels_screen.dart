import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../ads/ads_provider.dart';
import '../auth/data/auth_provider.dart';
import '../home/home_shell.dart'
    show kGlassNavBarHeight, kReelsBottomNavHeight, shellBottomNavInset;
import '../notifications/notification_provider.dart';
import '../plus/plus_widgets.dart';
import '../profile/follow_requests_screen.dart';
import '../stories/campus_camera_screen.dart';
import 'reel_models.dart';
import 'reels_provider.dart';
import 'reels_video_cache.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

/// Instagram tarzı dikey snap — hızlı flicksnaps, az sürtünme.
class _ReelsPagePhysics extends PageScrollPhysics {
  const _ReelsPagePhysics({super.parent});

  @override
  _ReelsPagePhysics applyTo(ScrollPhysics? ancestor) {
    return _ReelsPagePhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.5,
        stiffness: 420,
        damping: 32,
      );
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _page = PageController();
  int _index = 0;
  bool _refreshing = false;
  bool _didWarm = false;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didWarm) return;
    final reels = context.read<ReelsProvider>();
    final me = context.read<AuthProvider>().user;
    final feed = reels.feedFor(me?.id);
    if (feed.isEmpty) return;
    _didWarm = true;
    unawaited(reels.prefetchAround(feed, _index));
  }

  Future<void> _onRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await context.read<ReelsProvider>().refresh();
      if (mounted) setState(() => _index = 0);
      if (_page.hasClients) {
        await _page.animateToPage(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reels = context.watch<ReelsProvider>();
    final me = auth.user;
    final feed = reels.feedFor(me?.id);
    final tabOn = reels.tabActive;
    final topPad = MediaQuery.paddingOf(context).top;

    final focusId = reels.focusReelId;
    if (focusId != null && feed.isNotEmpty) {
      final i = feed.indexWhere((r) => r.id == focusId);
      if (i >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<ReelsProvider>().takeFocusReelId();
          setState(() => _index = i);
          if (_page.hasClients) {
            _page.jumpToPage(i);
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<ReelsProvider>().takeFocusReelId();
        });
      }
    }

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
            RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: Colors.black87,
              displacement: topPad + 48,
              onRefresh: _onRefresh,
              child: NotificationListener<OverscrollNotification>(
                onNotification: (n) {
                  // İlk reel’de yukarı çek → yenile (Instagram).
                  if (_index == 0 &&
                      n.overscroll < -28 &&
                      n.metrics.axis == Axis.vertical &&
                      !_refreshing) {
                    _onRefresh();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _page,
                  scrollDirection: Axis.vertical,
                  allowImplicitScrolling: true,
                  physics: const _ReelsPagePhysics(),
                  itemCount: feed.length,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    final uid = me?.id;
                    if (uid != null) {
                      context.read<ReelsProvider>().markViewed(feed[i].id, uid);
                    }
                    unawaited(
                      context.read<ReelsProvider>().prefetchAround(feed, i),
                    );
                  },
                  itemBuilder: (context, i) {
                    // Her 6. reel öncesi rastgele reklam (varsa)
                    if (i > 0 && i % 6 == 0) {
                      final ad = context.read<AdsProvider>().pick(
                            context.read<AdsProvider>().reels,
                          );
                      if (ad != null && i == _index) {
                        return ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: AdCard(ad: ad, placement: 'reels'),
                            ),
                          ),
                        );
                      }
                    }
                    return _ReelPage(
                      key: ValueKey(feed[i].id),
                      reel: feed[i],
                      isActive: tabOn && i == _index,
                    );
                  },
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, topPad + 2, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Kampüs Reels',
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        height: 1.1,
                        shadows: [
                          Shadow(blurRadius: 6, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Çek / paylaş',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: () {
                      if (!AuthGate.requireAuth(context)) return;
                      openCampusShareMenu(context);
                    },
                    icon: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
          ),
          if (_refreshing)
            Positioned(
              top: topPad + 36,
              left: 0,
              right: 0,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.cyan,
                  ),
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
    if (already) {
      await auth.toggleFollow(author.id);
      return;
    }
    if (author.isPrivateAccount) {
      if (auth.hasOutgoingFollowRequest(author.id)) {
        await auth.cancelFollowRequest(author.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Takip isteği iptal edildi')),
          );
        }
        return;
      }
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

  void _openComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ReelCommentsSheet(reel: widget.reel),
    );
  }

  Future<void> _editCaption() async {
    final ctrl = TextEditingController(text: widget.reel.caption);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Açıklamayı düzenle',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          cursorColor: AppColors.cyan,
          decoration: InputDecoration(
            hintText: 'Açıklama · @etiket · #hashtag',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (next == null || !mounted) return;
    final me = context.read<AuthProvider>().user;
    if (me == null) return;
    final err = await context.read<ReelsProvider>().updateCaption(
          reelId: widget.reel.id,
          caption: next,
          actorId: me.id,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Açıklama güncellendi'),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reels’i sil'),
        content: const Text(
          'Bu Reels silinsin mi? Profildeki gönderisi de kalkar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final me = context.read<AuthProvider>().user;
    if (me == null) return;
    final err = await context.read<ReelsProvider>().deleteReel(
          reelId: widget.reel.id,
          byUserId: me.id,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Reels silindi')),
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
    final photo = author?.photoUrl ?? reel.authorPhotoUrl;
    // Floating glass bar için ekstra pay (Reels’te cam daha yüksek).
    final glass = LiquidGlass.enabled(context);
    final bottomClear = shellBottomNavInset(context) +
        (glass ? kGlassNavBarHeight + 10 : kReelsBottomNavHeight) +
        22;

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
                : const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.cyan,
                        ),
                      ),
                    ),
                  )
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
                stops: [0, 0.2, 0.5, 1],
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
            left: 12,
            right: 64,
            bottom: bottomClear,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                        radius: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                                  fontSize: 14,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            UserVerificationBadges(user: author, size: 15),
                          ],
                        ),
                      ),
                    ),
                    if (!isSelf && me != null) ...[
                      const SizedBox(width: 8),
                      if (!following)
                        OutlinedButton(
                          style: LiquidGlass.enabled(context)
                              ? liquidOutlinedButtonStyle(
                                  dark: true,
                                  minimumSize: const Size(0, 30),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 0,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                )
                              : OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side:
                                      const BorderSide(color: Colors.white70),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 0),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                          onPressed: () => _toggleFollow(author),
                          child: Text(
                            author == null
                                ? 'Takip et'
                                : followActionLabel(auth, author).isEmpty
                                    ? 'Takip et'
                                    : followActionLabel(auth, author),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                    if (isSelf) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'Reels işlemleri',
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        color: const Color(0xFF1E1E1E),
                        onSelected: (v) {
                          if (v == 'edit') {
                            unawaited(_editCaption());
                          } else if (v == 'delete') {
                            unawaited(_confirmDelete());
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              'Açıklamayı düzenle',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Sil',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (reel.caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ReelCaptionText(caption: reel.caption),
                ],
              ],
            ),
          ),
          Positioned(
            right: 4,
            bottom: bottomClear,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LiquidGlassIconButton(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.redAccent : Colors.white,
                  label: '${reel.likedBy.length}',
                  onTap: me == null
                      ? null
                      : () {
                          final wasLiked = liked;
                          unawaited(() async {
                            await context
                                .read<ReelsProvider>()
                                .toggleLike(reel.id, me.id);
                            if (!wasLiked &&
                                reel.authorId != me.id &&
                                context.mounted) {
                              context.read<NotificationProvider>().pushSocial(
                                    toUserId: reel.authorId,
                                    title: 'Reels beğenisi',
                                    body: '${me.fullName} Reels’ini beğendi',
                                    emoji: 'LIKE',
                                    type: 'reel_like',
                                    actorId: me.id,
                                    targetId: reel.id,
                                  );
                            }
                          }());
                        },
                ),
                const SizedBox(height: 10),
                LiquidGlassIconButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${reel.commentCount}',
                  onTap: () {
                    if (!AuthGate.requireAuth(context)) return;
                    _openComments();
                  },
                ),
                const SizedBox(height: 10),
                LiquidGlassIconButton(
                  icon: _muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
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

/// Açıklama içinde @mention / #hashtag vurgusu.
class _ReelCaptionText extends StatelessWidget {
  const _ReelCaptionText({required this.caption});
  final String caption;

  @override
  Widget build(BuildContext context) {
    final base = const TextStyle(
      color: Colors.white,
      height: 1.3,
      fontSize: 13,
    );
    final accent = TextStyle(
      color: AppColors.cyan,
      height: 1.3,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    final re = RegExp(r'([@#][\wğüşıöçĞÜŞİÖÇ0-9_]+)');
    final spans = <TextSpan>[];
    var start = 0;
    for (final m in re.allMatches(caption)) {
      if (m.start > start) {
        spans.add(TextSpan(text: caption.substring(start, m.start), style: base));
      }
      spans.add(TextSpan(text: m.group(0), style: accent));
      start = m.end;
    }
    if (start < caption.length) {
      spans.add(TextSpan(text: caption.substring(start), style: base));
    }
    return Text.rich(
      TextSpan(children: spans.isEmpty ? [TextSpan(text: caption, style: base)] : spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
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
            type: 'reel_comment',
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
    const bg = Color(0xFF121212);
    const muted = Color(0xFF9AA0A6);
    return Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.58,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Yorumlar',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<ReelComment>>(
                  stream: context
                      .read<ReelsProvider>()
                      .commentsStream(widget.reel.id),
                  builder: (context, snap) {
                    final list = snap.data ?? const [];
                    if (list.isEmpty) {
                      return const Center(
                        child: Text(
                          'Henüz yorum yok — ilkini sen yaz.',
                          style: TextStyle(color: muted),
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
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      UserVerificationBadges(
                                        user: context
                                            .read<AuthProvider>()
                                            .findUser(c.authorId),
                                        size: 13,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.content,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      height: 1.35,
                                    ),
                                  ),
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
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  constraints: const BoxConstraints(maxHeight: 168),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: Colors.white12,
                    ),
                    itemBuilder: (context, i) {
                      final u = _suggestions[i];
                      return ListTile(
                        dense: true,
                        onTap: () => _applyMention(u),
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
                        trailing: u.isCommunity
                            ? const Text(
                                'Topluluk',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              )
                            : null,
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
                          style: const TextStyle(color: Colors.white),
                          cursorColor: AppColors.cyan,
                          decoration: InputDecoration(
                            hintText: 'Yorum yaz… @kullanici',
                            hintStyle: const TextStyle(color: muted),
                            filled: true,
                            fillColor: Colors.white10,
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
      ),
    );
  }
}
