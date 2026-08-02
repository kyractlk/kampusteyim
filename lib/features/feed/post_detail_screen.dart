import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../admin/admin_permissions.dart';
import '../admin/admin_provider.dart';
import '../auth/data/auth_provider.dart';
import '../moderation/moderation_models.dart';
import '../moderation/report_sheet.dart';
import '../notifications/notification_provider.dart';
import '../plus/plus_widgets.dart';
import 'feed_provider.dart';
import 'feed_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  String? _replyToId;
  String? _replyToName;
  bool _loading = false;
  bool _checkingAccess = true;
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  Future<void> _ensure() async {
    final feed = context.read<FeedProvider>();
    final auth = context.read<AuthProvider>();
    setState(() {
      _loading = feed.postById(widget.postId) == null;
      _checkingAccess = true;
    });
    if (feed.postById(widget.postId) == null) {
      await feed.ensurePostLoaded(widget.postId);
    }
    final post = feed.postById(widget.postId);
    if (post != null) {
      await auth.ensureUserLoaded(post.authorId);
    }
    if (!mounted) return;
    final latest = feed.postById(widget.postId);
    final ok = latest != null && auth.canViewPost(latest);
    setState(() {
      _loading = false;
      _checkingAccess = false;
      _allowed = ok;
    });
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final auth = context.watch<AuthProvider>();
    final post = feed.postById(widget.postId);
    if (_loading || _checkingAccess) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => AppNav.back(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (post == null || !_allowed || !auth.canViewPost(post)) {
      final author = post != null ? auth.findUser(post.authorId) : null;
      final isPrivate = author?.isPrivateAccount == true;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => AppNav.back(context),
          ),
          title: Text(isPrivate ? 'Gizli hesap' : 'Gönderi'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPrivate ? Icons.lock_outline_rounded : Icons.hide_source,
                  size: 44,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 14),
                Text(
                  isPrivate
                      ? 'Bu hesap gizli'
                      : 'Bu içerik bulunamadı',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isPrivate
                      ? 'Gönderiyi ve yorumları görmek için bu hesabı takip etmen ve isteğinin kabul edilmesi gerekir.'
                      : 'Gönderi silinmiş olabilir veya erişimin yok.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (isPrivate && post != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => AppNav.openUser(context, post.authorId),
                    child: const Text('Profile git'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final comments = feed.commentsFor(post.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => AppNav.back(context),
        ),
        title: Text(
          post.authorHandle,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            onPressed: () => AppShare.sharePost(
              context: context,
              id: post.id,
              authorName: post.authorName,
              content: post.content,
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                PostCard(post: post, openPostOnTap: false),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Yorumlar',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${comments.length}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (comments.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'Henüz yorum yok.\nİlk yorumu sen yaz — sohbet burada akar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  ...comments.map(
                    (c) => _CommentTile(
                      comment: c,
                      postAuthorId: post.authorId,
                      onReply: () {
                        if (!AuthGate.requireAuth(
                          context,
                          message: 'Yorum yanıtlamak için giriş yapmalısın.',
                        )) {
                          return;
                        }
                        setState(() {
                          _replyToId = c.id;
                          _replyToName = c.authorName;
                        });
                      },
                      onLike: (id, {parentId}) {
                        if (!AuthGate.requireAuth(
                          context,
                          message: 'Yorum beğenmek için giriş yapmalısın.',
                        )) {
                          return;
                        }
                        final me = auth.user;
                        if (me == null) return;
                        final liked = feed.toggleCommentLike(
                          id,
                          parentId: parentId,
                        );
                        if (liked != null && liked.authorId != me.id) {
                          context.read<NotificationProvider>().pushSocial(
                                toUserId: liked.authorId,
                                title: 'Yeni beğeni',
                                body: '${me.fullName} yorumunu beğendi',
                                emoji: '❤️',
                                type: 'like',
                                actorId: me.id,
                                targetId: post.id,
                              );
                        }
                      },
                      onPin: () {
                        if (!AuthGate.requireAuth(
                          context,
                          message: 'Yorum sabitlemek için giriş yapmalısın.',
                        )) {
                          return;
                        }
                        feed.pinComment(post.id, c.id);
                      },
                      onDelete: (id, {parentId}) async {
                        final me = auth.user;
                        if (me == null) return;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Yorumu sil'),
                            content: const Text('Bu yorum silinsin mi?'),
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
                          await feed.softDeleteComment(
                            id,
                            byUserId: me.id,
                            parentId: parentId,
                          );
                        }
                      },
                      onAuthorTap: (userId) => context.push('/user/$userId'),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_replyToId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Yanıt: $_replyToName',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: AppColors.cyan),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _replyToId = null;
                              _replyToName = null;
                            }),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentCtrl,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: auth.isAuthenticated
                                ? 'Yorum yaz…'
                                : 'Yorum için giriş yap',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onTap: () {
                            if (!AuthGate.requireAuth(
                              context,
                              message: 'Yorum yazmak için giriş yapmalısın.',
                            )) {
                              FocusScope.of(context).unfocus();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {
                          if (!AuthGate.requireAuth(
                            context,
                            message: 'Yorum yazmak için giriş yapmalısın.',
                          )) {
                            return;
                          }
                          final text = _commentCtrl.text;
                          feed.addComment(
                            postId: post.id,
                            author: auth.user!,
                            content: text,
                            parentId: _replyToId,
                          );
                          final me = auth.user!;
                          final notif = context.read<NotificationProvider>();
                          final replyParentId = _replyToId;
                          if (replyParentId != null) {
                            final parent = feed.commentById(replyParentId);
                            if (parent != null && parent.authorId != me.id) {
                              notif.pushSocial(
                                toUserId: parent.authorId,
                                title: 'Yeni yanıt',
                                body: '${me.fullName} yorumuna yanıt verdi',
                                emoji: '💬',
                                type: 'comment',
                                actorId: me.id,
                                targetId: post.id,
                              );
                            }
                            if (post.authorId != me.id &&
                                post.authorId != parent?.authorId) {
                              notif.pushSocial(
                                toUserId: post.authorId,
                                title: 'Yeni yorum',
                                body:
                                    '${me.fullName} gönderine yorum yaptı',
                                emoji: '💬',
                                type: 'comment',
                                actorId: me.id,
                                targetId: post.id,
                              );
                            }
                          } else if (post.authorId != me.id) {
                            notif.pushSocial(
                              toUserId: post.authorId,
                              title: 'Yeni yorum',
                              body: '${me.fullName} gönderine yorum yaptı',
                              emoji: '💬',
                              type: 'comment',
                              actorId: me.id,
                              targetId: post.id,
                            );
                          }
                          _commentCtrl.clear();
                          setState(() {
                            _replyToId = null;
                            _replyToName = null;
                          });
                        },
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.postAuthorId,
    required this.onReply,
    required this.onLike,
    required this.onPin,
    required this.onAuthorTap,
    required this.onDelete,
  });

  final Comment comment;
  final String postAuthorId;
  final VoidCallback onReply;
  final void Function(String id, {String? parentId}) onLike;
  final VoidCallback onPin;
  final void Function(String userId) onAuthorTap;
  final void Function(String commentId, {String? parentId}) onDelete;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('d MMM · HH:mm', 'tr').format(comment.createdAt);
    final me = context.watch<AuthProvider>().user;
    final auth = context.read<AuthProvider>();
    final author = auth.findUser(comment.authorId);
    final canPin = comment.authorId == postAuthorId || me?.id == postAuthorId;
    final isOwn = me != null &&
        (comment.authorId == me.id ||
            auth.idsFor(me.id).contains(comment.authorId));
    final canMod = context.read<AdminProvider>().can(
          me,
          AdminPermission.moderateFeed,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: comment.authorName,
                radius: 16,
                onTap: () => onAuthorTap(comment.authorId),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => onAuthorTap(comment.authorId),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              comment.authorName,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (author != null) ...[
                            const SizedBox(width: 4),
                            UserVerificationBadges(user: author, size: 13),
                          ],
                          if (comment.isPinned) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.push_pin,
                                size: 14, color: AppColors.crimson),
                          ],
                        ],
                      ),
                      Text(
                        '${comment.authorHandle} · $time',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Beğen',
                onPressed: () => onLike(comment.id),
                icon: MtIcon(
                  comment.isLiked ? MtIcons.likeFilled : MtIcons.like,
                  size: 16,
                  color: comment.isLiked
                      ? AppColors.crimson
                      : AppColors.textSecondary,
                ),
              ),
              Text('${comment.likeCount}'),
            ],
          ),
          const SizedBox(height: 8),
          HashtagText(text: comment.content),
          Row(
            children: [
              TextButton(
                onPressed: onReply,
                child: const Text('Yanıtla'),
              ),
              if (canPin)
                TextButton(onPressed: onPin, child: const Text('Sabitle')),
              if (isOwn || canMod)
                TextButton(
                  onPressed: () => onDelete(comment.id),
                  child: const Text('Sil'),
                ),
              IconButton(
                onPressed: () => showReportSheet(
                  context: context,
                  targetType: ReportTargetType.comment,
                  targetId: comment.id,
                  targetOwnerId: comment.authorId,
                ),
                icon: const MtIcon(MtIcons.report, size: 16),
              ),
            ],
          ),
          ...comment.replies.map(
            (r) {
              final replyOwn = me != null &&
                  (r.authorId == me.id ||
                      auth.idsFor(me.id).contains(r.authorId));
              return Container(
              margin: const EdgeInsets.only(left: 12, top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => onAuthorTap(r.authorId),
                    child: Text(
                      r.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  HashtagText(text: r.content),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => onLike(r.id, parentId: comment.id),
                        icon: MtIcon(
                          r.isLiked ? MtIcons.likeFilled : MtIcons.like,
                          size: 14,
                          color: r.isLiked
                              ? AppColors.crimson
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (replyOwn || canMod)
                        TextButton(
                          onPressed: () =>
                              onDelete(r.id, parentId: comment.id),
                          child: const Text('Sil'),
                        ),
                    ],
                  ),
                ],
              ),
            );
            },
          ),
        ],
      ),
    );
  }
}
