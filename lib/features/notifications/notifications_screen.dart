import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'notification_models.dart';
import 'notification_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Set<String> _busy = {};

  String _cleanTitle(String raw) {
    var t = raw.trim();
    // Eski kayıtlar: "LIKE Yeni beğeni" / "FOLLOW Yeni takipçi"
    t = t.replaceFirst(
      RegExp(
        r'^(LIKE|FOLLOW|COMMENT|REPOST|MENTION|JOB|PROMO|ADMIN|ACTIVITY)\s+',
        caseSensitive: false,
      ),
      '',
    );
    return t.isEmpty ? 'Bildirim' : t;
  }

  void _open(
    BuildContext context, {
    required AppNotification n,
  }) {
    context.read<NotificationProvider>().markRead(n.id);
    final type = n.type;
    final targetId = n.targetId;
    final actorId = n.actorId;
    final userRoute = actorId ?? targetId;
    switch (type) {
      case 'follow':
      case 'follow_request':
      case 'follow_accepted':
        if (userRoute != null && userRoute.isNotEmpty) {
          context.push('/user/${Uri.encodeComponent(userRoute)}');
        }
        return;
      case 'mention':
      case 'like':
      case 'comment':
      case 'repost':
      case 'activity':
      case 'promo':
        if (targetId != null && targetId.isNotEmpty) {
          context.push('/post/${Uri.encodeComponent(targetId)}');
        }
        return;
      case 'reel_like':
      case 'reel_comment':
        context.go('/reels');
        return;
      case 'story_like':
        final me = context.read<AuthProvider>().user?.id;
        if (me != null && me.isNotEmpty) {
          context.push('/stories/view/${Uri.encodeComponent(me)}');
        }
        return;
      case 'job':
      case 'application':
        context.push('/jobs');
        return;
      case 'community':
        if (targetId == null || targetId.isEmpty) return;
        if (targetId.startsWith('e_')) {
          context.push('/event/${Uri.encodeComponent(targetId)}');
        } else if (targetId.startsWith('a_')) {
          context.push('/announcement/${Uri.encodeComponent(targetId)}');
        } else {
          context.push('/post/${Uri.encodeComponent(targetId)}');
        }
        return;
      default:
        if (targetId == null || targetId.isEmpty) {
          if (userRoute != null && userRoute.isNotEmpty) {
            context.push('/user/${Uri.encodeComponent(userRoute)}');
          }
          return;
        }
        if (targetId.startsWith('p_') ||
            targetId.startsWith('job_') ||
            targetId.startsWith('ann_') ||
            targetId.contains('post')) {
          context.push('/post/${Uri.encodeComponent(targetId)}');
        } else {
          context.push('/user/${Uri.encodeComponent(targetId)}');
        }
    }
  }

  Future<void> _acceptRequest(AppUser requester) async {
    if (_busy.contains(requester.id)) return;
    setState(() => _busy.add(requester.id));
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    final ok = await auth.acceptFollowRequest(requester.id);
    if (!mounted) return;
    if (ok && me != null) {
      final hub = context.read<NotificationProvider>();
      hub.pushSocial(
        toUserId: requester.id,
        title: 'İstek kabul edildi',
        body: '${me.fullName} takip isteğini kabul etti',
        emoji: '✨',
        type: 'follow_accepted',
        actorId: me.id,
        targetId: me.id,
      );
      // Aynı isteğin bildirim satırını okundu yap.
      for (final n in hub.items) {
        if (n.type == 'follow_request' &&
            (n.actorId == requester.id || n.targetId == requester.id)) {
          hub.markRead(n.id);
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${requester.fullName} kabul edildi')),
      );
    }
    setState(() => _busy.remove(requester.id));
  }

  Future<void> _rejectRequest(AppUser requester) async {
    if (_busy.contains(requester.id)) return;
    setState(() => _busy.add(requester.id));
    await context.read<AuthProvider>().rejectFollowRequest(requester.id);
    if (!mounted) return;
    final hub = context.read<NotificationProvider>();
    for (final n in hub.items) {
      if (n.type == 'follow_request' &&
          (n.actorId == requester.id || n.targetId == requester.id)) {
        hub.markRead(n.id);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Takip isteği silindi')),
    );
    setState(() => _busy.remove(requester.id));
  }

  Future<void> _acceptFromNotification(AppNotification n) async {
    final requesterId = n.actorId ?? n.targetId;
    if (requesterId == null || requesterId.isEmpty) return;
    final auth = context.read<AuthProvider>();
    await auth.ensureUserLoaded(requesterId);
    final u = auth.findUser(requesterId) ??
        AppUser(
          id: requesterId,
          email: '',
          studentNo: '',
          firstName: 'Kullanıcı',
          lastName: '',
          phone: '',
          city: '',
          university: '',
          username: requesterId,
        );
    await _acceptRequest(u);
  }

  Future<void> _rejectFromNotification(AppNotification n) async {
    final requesterId = n.actorId ?? n.targetId;
    if (requesterId == null || requesterId.isEmpty) return;
    final auth = context.read<AuthProvider>();
    await auth.ensureUserLoaded(requesterId);
    final u = auth.findUser(requesterId) ??
        AppUser(
          id: requesterId,
          email: '',
          studentNo: '',
          firstName: 'Kullanıcı',
          lastName: '',
          phone: '',
          city: '',
          university: '',
          username: requesterId,
        );
    await _rejectRequest(u);
  }

  Widget _svgAvatar({
    required String svg,
    required Color color,
    String? photoUrl,
  }) {
    if (photoUrl != null && photoUrl.startsWith('http')) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: color.withValues(alpha: 0.12),
        child: ClipOval(
          child: SafeNetworkImage(
            url: photoUrl,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            placeholder: ColoredBox(
              color: color.withValues(alpha: 0.12),
              child: Center(child: MtIcon(svg, size: 22, color: color)),
            ),
            errorBuilder: (_, _, _) => MtIcon(svg, size: 22, color: color),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.14),
      child: MtIcon(svg, size: 22, color: color),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final ids = auth.user?.incomingFollowRequests ?? const <String>[];
      for (final id in ids) {
        await auth.ensureUserLoaded(id);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<NotificationProvider>();
    final auth = context.watch<AuthProvider>();
    final pendingIds = auth.user?.incomingFollowRequests ?? const <String>[];
    final pendingUsers = <AppUser>[];
    for (final id in pendingIds) {
      final u = auth.findUser(id);
      pendingUsers.add(
        u ??
            AppUser(
              id: id,
              email: '',
              studentNo: '',
              firstName: 'Kullanıcı',
              lastName: '',
              phone: '',
              city: '',
              university: '',
              username: id,
            ),
      );
    }

    // Takip isteği bildirimlerini listedeki duplicate olarak gizle
    // (üstte canlı istek satırları var).
    final pendingIdSet = pendingIds.toSet();
    final items = hub.items.where((n) {
      if (n.type != 'follow_request') return true;
      final a = n.actorId ?? n.targetId;
      if (a == null) return true;
      return !pendingIdSet.any((id) => auth.idsFor(a).contains(id));
    }).toList();

    final empty = items.isEmpty && pendingUsers.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          TextButton(
            onPressed: hub.items.isEmpty ? null : hub.markAllRead,
            child: Text(
              'Tümünü okundu',
              style: TextStyle(
                color: hub.items.any((n) => !n.read)
                    ? AppColors.cyan
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: empty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MtIcon(MtIcons.bell, size: 44, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'Henüz bildirim yok',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              children: [
                if (pendingUsers.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Row(
                      children: [
                        MtIcon(
                          MtIcons.follow,
                          size: 18,
                          color: AppColors.navy,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Takip istekleri (${pendingUsers.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        if (pendingUsers.length > 3)
                          TextButton(
                            onPressed: () => context.push('/follow-requests'),
                            child: const Text('Tümü'),
                          ),
                      ],
                    ),
                  ),
                  ...pendingUsers.take(8).map((u) {
                    final busy = _busy.contains(u.id);
                    return Material(
                      color: const Color(0xFFF3E8FF).withValues(alpha: 0.55),
                      child: InkWell(
                        onTap: () => context.push(
                          '/user/${Uri.encodeComponent(u.id)}',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _svgAvatar(
                                svg: MtIcons.follow,
                                color: const Color(0xFF7C3AED),
                                photoUrl: u.photoUrl,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.fullName.trim().isEmpty
                                          ? '@${u.username}'
                                          : u.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '@${u.username} · takip isteği gönderdi',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        FilledButton(
                                          onPressed: busy
                                              ? null
                                              : () => _acceptRequest(u),
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(0, 34),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                          ),
                                          child: busy
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Text('Kabul'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: busy
                                              ? null
                                              : () => _rejectRequest(u),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(0, 34),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                          ),
                                          child: const Text('Sil'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: AppColors.crimson,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 1),
                  if (items.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Diğer bildirimler',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
                ...items.map((n) {
                  final (svg, color) = MtIcons.forNotificationType(n.type);
                  final isRequest = n.type == 'follow_request';
                  final requesterId = n.actorId ?? n.targetId;
                  final stillPending = isRequest &&
                      requesterId != null &&
                      pendingIds.any(
                        (id) => auth.idsFor(requesterId).contains(id),
                      );
                  final actor = n.actorId != null
                      ? auth.findUser(n.actorId!)
                      : null;

                  return InkWell(
                    onTap: () => _open(context, n: n),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _svgAvatar(
                            svg: svg,
                            color: color,
                            photoUrl: actor?.photoUrl,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _cleanTitle(n.title),
                                  style: TextStyle(
                                    fontWeight: n.read
                                        ? FontWeight.w600
                                        : FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  n.body,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13.5,
                                    height: 1.3,
                                  ),
                                ),
                                if (stillPending) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      FilledButton(
                                        onPressed: () =>
                                            _acceptFromNotification(n),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 34),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                        ),
                                        child: const Text('Kabul'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () =>
                                            _rejectFromNotification(n),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 34),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                        ),
                                        child: const Text('Sil'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (!n.read)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Icon(
                                Icons.circle,
                                size: 10,
                                color: AppColors.crimson,
                              ),
                            )
                          else
                            IconButton(
                              tooltip: 'Okundu',
                              visualDensity: VisualDensity.compact,
                              onPressed: null,
                              icon: MtIcon(
                                MtIcons.check,
                                size: 16,
                                color: Colors.grey.shade400,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
