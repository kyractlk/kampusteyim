import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/breakpoints.dart';
import '../../core/utils/hashtag_utils.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../admin/admin_permissions.dart';
import '../admin/admin_provider.dart';
import '../auth/data/auth_provider.dart';
import '../home/home_shell.dart';
import '../moderation/moderation_models.dart';
import '../moderation/report_sheet.dart';
import '../notifications/notification_provider.dart';
import '../stories/story_ring_bar.dart';
import '../study/study_models.dart';
import 'feed_provider.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final allPosts = context.watch<FeedProvider>().posts;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final posts = user == null
        ? allPosts
        : allPosts
            .where(
              (p) =>
                  !user.blocks(p.authorId) &&
                  !(auth.findUser(p.authorId)?.blocks(user.id) ?? false),
            )
            .toList();
    final restricted = user != null && !user.canPost;
    final spectator = user?.isSpectatorMode == true;
    final needsLogo =
        user != null && user.isCommunity && !user.communityCanPublish;
    final wide = AppBreakpoints.isWide(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        // Mobil: yumuşak gradient · PC: düz yüzey (Twitter merkez kolon)
        gradient: wide
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFE8F4F8), AppColors.background],
              ),
        color: wide ? AppColors.surface : null,
      ),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface.withValues(alpha: 0.94),
            // PC'de marka solda; merkezde sadece "Akış"
            title: wide
                ? const Text(
                    'Akış',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  )
                : const MtTitle(),
            actions: const [FeedAppBarActions()],
          ),
          if (user != null && user.restrictionActive)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.crimson.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.crimson.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const MtIcon(MtIcons.ban,
                        size: 22, color: AppColors.crimson),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        user.isFullyBanned
                            ? 'Hesabın askıda: ${user.restrictionReason}'
                            : 'Paylaşım yasağın var: ${user.restrictionReason}'
                                '${user.restrictionUntil != null ? '\nBitiş: ${user.restrictionUntil!.toLocal()}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (user != null)
            const SliverToBoxAdapter(child: StoryRingBar()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _ComposerCard(
                enabled: auth.isAuthenticated && !restricted && !needsLogo,
                lockMessage: needsLogo
                    ? 'Topluluk logosu yüklemeden paylaşım yapamazsın.'
                    : spectator
                        ? 'İzleyici modunda paylaşım yapılamaz. Gizlilik ayarlarından kapatabilirsin.'
                        : restricted
                            ? 'Paylaşım yasağın nedeniyle gönderi atamazsın.'
                            : 'Paylaşım yapmak için giriş yapmalısın.',
                onTapLocked: () {
                  if (!auth.isAuthenticated) {
                    AuthGate.requireAuth(
                      context,
                      message: 'Paylaşım yapmak için giriş yapmalısın.',
                    );
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        needsLogo
                            ? 'Önce topluluk logosunu yükle (Topluluk paneli).'
                            : spectator
                                ? 'İzleyici modu açık: yalnızca içerik okuyabilirsin.'
                                : 'Paylaşım yasağın aktif.',
                      ),
                    ),
                  );
                },
                onSubmit: (text, media) async {
                  final u = auth.user!;
                  if (!u.canPost || !u.communityCanPublish) {
                    return 'Paylaşım yapılamıyor';
                  }
                  final result = await context.read<FeedProvider>().addPost(
                        authorId: u.id,
                        authorName: u.fullName,
                        authorHandle: u.handle,
                        content: text,
                        media: media,
                        isCommunity: u.isCommunity,
                        directory: auth.directory,
                      );
                  if (!context.mounted) return result;
                  if (result != null) {
                    final msg = result.startsWith('WARN:')
                        ? result.substring(5)
                        : result;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  }
                  return result;
                },
              ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList.separated(
              itemCount: posts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return PostCard(post: posts[index])
                    .animate()
                    .fadeIn(delay: (40 * index).ms)
                    .slideY(begin: 0.04);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerCard extends StatefulWidget {
  const _ComposerCard({
    required this.onSubmit,
    required this.enabled,
    required this.onTapLocked,
    required this.lockMessage,
  });

  final Future<String?> Function(String text, List<MediaItem> media) onSubmit;
  final bool enabled;
  final VoidCallback onTapLocked;
  final String lockMessage;

  @override
  State<_ComposerCard> createState() => _ComposerCardState();
}

class _ComposerCardState extends State<_ComposerCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  XFile? _imageFile;
  XFile? _videoFile;
  bool _busy = false;
  String? _mentionQuery;
  List<AppUser> _mentionHits = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onComposeChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onComposeChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onComposeChanged() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final cursor = _controller.selection.baseOffset;
    final q = MentionUtils.activeQuery(_controller.text, cursor);
    if (q == null) {
      if (_mentionQuery != null) {
        setState(() {
          _mentionQuery = null;
          _mentionHits = const [];
        });
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
    final cursor = _controller.selection.baseOffset;
    final next = MentionUtils.applyMention(
      text: _controller.text,
      cursor: cursor < 0 ? _controller.text.length : cursor,
      user: u,
    );
    _controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.cursor),
    );
    setState(() {
      _mentionQuery = null;
      _mentionHits = const [];
    });
  }

  Future<void> _pickImage() async {
    if (!widget.enabled) {
      widget.onTapLocked();
      return;
    }
    final f = await MediaUpload.pickImage();
    if (f != null) setState(() => _imageFile = f);
  }

  Future<void> _pickVideo() async {
    if (!widget.enabled) {
      widget.onTapLocked();
      return;
    }
    final f = await MediaUpload.pickVideo();
    if (f != null) setState(() => _videoFile = f);
  }

  Future<void> _publish() async {
    if (!widget.enabled) {
      widget.onTapLocked();
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty && _imageFile == null && _videoFile == null) return;
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final media = <MediaItem>[];
      final authUid = fa.FirebaseAuth.instance.currentUser?.uid ?? user.id;
      if (_imageFile != null) {
        final url = await MediaUpload.uploadXFile(
          file: _imageFile!,
          folder: 'posts/$authUid',
          firstName: user.firstName,
          lastName: user.lastName,
          studentNo: user.studentNo,
          isVideo: false,
        );
        media.add(MediaItem(url: url, type: MediaType.image));
      }
      if (_videoFile != null) {
        final url = await MediaUpload.uploadXFile(
          file: _videoFile!,
          folder: 'posts/$authUid',
          firstName: user.firstName,
          lastName: user.lastName,
          studentNo: user.studentNo,
          isVideo: true,
        );
        media.add(MediaItem(url: url, type: MediaType.video));
      }
      final result = await widget.onSubmit(text, media);
      final blocked = result != null && !result.startsWith('WARN:');
      if (!blocked) {
        _controller.clear();
        setState(() {
          _imageFile = null;
          _videoFile = null;
          _mentionQuery = null;
          _mentionHits = const [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uniqueTags = HashtagUtils.uniqueCount(_controller.text);
    final showMentions = _mentionQuery != null && _mentionHits.isNotEmpty;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.enabled ? null : widget.onTapLocked,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: widget.enabled && !_busy,
                maxLines: 3,
                minLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.enabled
                      ? 'Kampüste neler oluyor? @etiket · #hashtag'
                      : widget.lockMessage,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (showMentions)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _mentionHits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final u = _mentionHits[i];
                      return ListTile(
                        dense: true,
                        leading: UserAvatar(
                          name: u.fullName,
                          photoUrl: u.communityLogoUrl ?? u.photoUrl,
                          isCommunity: u.isCommunity,
                          radius: 18,
                        ),
                        title: Text(
                          u.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(u.handle),
                        onTap: () => _pickMention(u),
                      );
                    },
                  ),
                ),
              if (_imageFile != null || _videoFile != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (_imageFile != null)
                        Chip(
                          label: const Text('Foto seçildi · max 75MB'),
                          onDeleted: () => setState(() => _imageFile = null),
                        ),
                      if (_videoFile != null)
                        Chip(
                          label: const Text('Video · max 45sn / 75MB'),
                          onDeleted: () => setState(() => _videoFile = null),
                        ),
                    ],
                  ),
                ),
              if (uniqueTags > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$uniqueTags benzersiz hashtag',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Fotoğraf (max 75 MB)',
                    onPressed: _busy ? null : _pickImage,
                    icon: Icon(
                      Icons.image_outlined,
                      color: _imageFile != null
                          ? AppColors.cyan
                          : AppColors.textSecondary,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Video (max 45 sn)',
                    onPressed: _busy ? null : _pickVideo,
                    icon: Icon(
                      Icons.videocam_outlined,
                      color: _videoFile != null
                          ? AppColors.lime
                          : AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy ? null : _publish,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Paylaş'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.openPostOnTap = true,
  });

  final Post post;
  /// Detay sayfasında false — tekrar push spam’ini önler.
  final bool openPostOnTap;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final feed = context.read<FeedProvider>();
    final author = auth.findUser(post.authorId);
    final time = DateFormat('d MMM · HH:mm', 'tr').format(post.createdAt);
    final gold = author?.showGoldBadge == true || post.isCommunity;
    final blue = author?.showBlueBadge == true;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: post.isStudyRoomInvite
              ? AppColors.cyan.withValues(alpha: 0.65)
              : post.isCommunity
                  ? AppColors.cyan.withValues(alpha: 0.45)
                  : AppColors.border,
          width: post.isStudyRoomInvite ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: openPostOnTap && !post.isStudyRoomInvite
            ? () => AppNav.openPost(context, post.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.repostedFromName != null) ...[
                Row(
                  children: [
                    const MtIcon(MtIcons.repost,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${post.authorName} yeniden paylaştı',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  UserAvatar(
                    name: post.authorName,
                    photoUrl: author?.communityLogoUrl ?? author?.photoUrl,
                    isCommunity: post.isCommunity,
                    onTap: () {
                      if (author != null) {
                        AppNav.openUserProfile(context, author);
                      } else {
                        AppNav.openUser(context, post.authorId);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (author != null) {
                          AppNav.openUserProfile(context, author);
                        } else {
                          AppNav.openUser(context, post.authorId);
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  post.authorName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (gold) ...[
                                const SizedBox(width: 4),
                                const VerifiedBadge(gold: true, size: 15),
                              ] else if (blue) ...[
                                const SizedBox(width: 4),
                                const VerifiedBadge(gold: false, size: 15),
                              ],
                              if (author?.isBot == true) ...[
                                const SizedBox(width: 4),
                                const BotBadge(size: 15),
                              ],
                            ],
                          ),
                          Text(
                            '${post.authorHandle} · $time'
                            '${author != null && author.affiliatedCommunityName != null && !author.hasAffiliation ? ' · ${author.affiliatedCommunityName}' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          if (author != null &&
                              author.hasAffiliation &&
                              (author.affiliatedCommunityName?.trim().isNotEmpty ??
                                  false))
                            AffiliationBadge(
                              orgName: author.affiliatedCommunityName!.trim(),
                              logoUrl: author.affiliatedOrgLogoUrl ??
                                  (author.affiliatedCommunityId != null
                                      ? auth
                                          .findUser(author.affiliatedCommunityId!)
                                          ?.communityLogoUrl
                                      : null),
                              orgId: author.affiliatedCommunityId,
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Diğer',
                    icon: const Icon(Icons.more_horiz_rounded,
                        size: 20, color: AppColors.textSecondary),
                    onSelected: (v) async {
                      final me = auth.user;
                      if (v == 'share') {
                        await AppShare.sharePost(
                          context: context,
                          id: post.id,
                          authorName: post.authorName,
                          content: post.content,
                        );
                        return;
                      }
                      if (v == 'report') {
                        await showReportSheet(
                          context: context,
                          targetType: ReportTargetType.post,
                          targetId: post.id,
                          targetOwnerId: post.authorId,
                        );
                        return;
                      }
                      if (v == 'delete') {
                        if (me == null) return;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Gönderiyi sil'),
                            content: const Text(
                              'Bu gönderi silinsin mi? (Twitter tarzı — akıştan kalkar.)',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Vazgeç'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Sil'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await feed.softDeletePost(post.id, byUserId: me.id);
                        }
                        return;
                      }
                      if (v == 'mute' || v == 'postban') {
                        if (me == null) return;
                        final admin = context.read<AdminProvider>();
                        await admin.applyRestriction(
                          auth: auth,
                          userId: post.authorId,
                          type: v == 'mute' ? 'mute' : 'postBan',
                          reason: v == 'mute'
                              ? 'Akış moderasyonu · susturma'
                              : 'Akış moderasyonu · paylaşım yasağı',
                          duration: v == 'mute'
                              ? const Duration(hours: 24)
                              : const Duration(days: 7),
                          notifications: context.read<NotificationProvider>(),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v == 'mute'
                                    ? 'Kullanıcı 24 saat susturuldu'
                                    : '7 günlük paylaşım yasağı uygulandı',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (ctx) {
                      final me = auth.user;
                      final admin = ctx.read<AdminProvider>();
                      final isOwn = me != null &&
                          (post.authorId == me.id ||
                              auth.idsFor(me.id).contains(post.authorId) ||
                              auth.idsFor(post.authorId).contains(me.id));
                      final canMod = admin.can(me, AdminPermission.moderateFeed) ||
                          admin.can(me, AdminPermission.restrictUsers);
                      return [
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('Paylaş'),
                        ),
                        if (!isOwn)
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('Şikayet et'),
                          ),
                        if (isOwn || canMod)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Gönderiyi sil'),
                          ),
                        if (canMod && !isOwn) ...[
                          const PopupMenuItem(
                            value: 'mute',
                            child: Text('Kullanıcıyı sustur (24s)'),
                          ),
                          const PopupMenuItem(
                            value: 'postban',
                            child: Text('Paylaşım yasağı (7 gün)'),
                          ),
                        ],
                      ];
                    },
                  ),
                ],
              ),
              if (post.isStudyRoomInvite) ...[
                const SizedBox(height: 12),
                _StudyRoomInvitePanel(post: post),
              ] else ...[
                if (post.content.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  HashtagText(text: post.content),
                ],
                if (post.media.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MediaCarousel(
                    urls: post.media.map((m) => m.url).toList(),
                    types: post.media
                        .map((m) => m.type == MediaType.video)
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _Action(
                    svg: post.isLiked ? MtIcons.likeFilled : MtIcons.like,
                    label: '${post.likeCount}',
                    active: post.isLiked,
                    color: AppColors.crimson,
                    onTap: () {
                      if (!AuthGate.requireAuth(
                        context,
                        message: 'Beğenmek için giriş yapmalısın.',
                      )) {
                        return;
                      }
                      final wasLiked = post.isLiked;
                      feed.toggleLike(post.id);
                      if (!wasLiked && post.authorId != auth.user!.id) {
                        context.read<NotificationProvider>().pushSocial(
                              toUserId: post.authorId,
                              title: 'Yeni beğeni',
                              body: '${auth.user!.fullName} gönderini beğendi',
                              emoji: 'LIKE',
                              type: 'like',
                              actorId: auth.user!.id,
                              targetId: post.id,
                            );
                      }
                    },
                  ),
                  _Action(
                    svg: MtIcons.comment,
                    label: '${post.replyCount}',
                    onTap: () => AppNav.openPost(context, post.id),
                  ),
                  _Action(
                    svg: MtIcons.repost,
                    label: '${post.repostCount}',
                    active: post.isReposted,
                    color: AppColors.lime,
                    onTap: () {
                      if (!AuthGate.requireAuth(
                        context,
                        message: 'Repost için giriş yapmalısın.',
                      )) {
                        return;
                      }
                      final was = post.isReposted;
                      feed.toggleRepost(postId: post.id, user: auth.user!);
                      if (!was && post.authorId != auth.user!.id) {
                        context.read<NotificationProvider>().pushSocial(
                              toUserId: post.authorId,
                              title: 'Yeniden paylaşım',
                              body:
                                  '${auth.user!.fullName} gönderini repostladı',
                              emoji: 'RP',
                              type: 'repost',
                              actorId: auth.user!.id,
                              targetId: post.id,
                            );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Çalışma odası duyurusu — ayrı layout + büyük Katıl butonu.
class _StudyRoomInvitePanel extends StatefulWidget {
  const _StudyRoomInvitePanel({required this.post});

  final Post post;

  @override
  State<_StudyRoomInvitePanel> createState() => _StudyRoomInvitePanelState();
}

class _StudyRoomInvitePanelState extends State<_StudyRoomInvitePanel> {
  bool _joining = false;

  Future<void> _join() async {
    if (!AuthGate.requireAuth(
      context,
      message: 'Odaya katılmak için giriş yapmalısın.',
    )) {
      return;
    }
    setState(() => _joining = true);
    try {
      var roomId = widget.post.studyRoomId?.trim();
      if (roomId == null || roomId.isEmpty) {
        final code = widget.post.studyRoomCode;
        if (code == null || code.isEmpty) {
          throw StateError('Oda bağlantısı bulunamadı');
        }
        final room = await StudyRoomService.findByCode(code);
        if (room == null) throw StateError('Oda bulunamadı veya kapandı');
        roomId = room.id;
      }
      if (!mounted) return;
      context.push('/study/$roomId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final title = (post.studyTitle?.trim().isNotEmpty == true)
        ? post.studyTitle!.trim()
        : 'Odak seansı';
    final minutes = post.studyMinutes ?? 25;
    final code = post.studyRoomCode?.toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1F3A), Color(0xFF12355C)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: AppColors.cyan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Hadi bana katıl',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (code != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$minutes dakikalık ortak odak — birlikte çalışalım',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.navy,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _joining ? null : _join,
            child: _joining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.handshake_outlined, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Hadi, katıl',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.svg,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final String svg;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = active ? (color ?? AppColors.cyan) : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            MtIcon(svg, size: 18, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
