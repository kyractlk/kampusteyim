import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import 'notification_models.dart';
import 'notification_provider.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  void _open(
    BuildContext context, {
    required String? type,
    String? targetId,
    String? actorId,
  }) {
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
        if (targetId == null || targetId.isEmpty) return;
        if (targetId.startsWith('p_') ||
            targetId.startsWith('job_') ||
            targetId.startsWith('ann_') ||
            targetId.contains('post')) {
          context.push('/post/${Uri.encodeComponent(targetId)}');
        }
    }
  }

  Future<void> _acceptRequest(BuildContext context, AppNotification n) async {
    final requesterId = n.actorId ?? n.targetId;
    if (requesterId == null || requesterId.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    final ok = await auth.acceptFollowRequest(requesterId);
    if (!context.mounted || !ok || me == null) return;
    context.read<NotificationProvider>().pushSocial(
      toUserId: requesterId,
      title: 'İstek kabul edildi',
      body: '${me.fullName} takip isteğini kabul etti',
      emoji: '✨',
      type: 'follow_accepted',
      actorId: me.id,
      targetId: me.id,
    );
    hubMarkRead(context, n.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Takip isteği kabul edildi')));
  }

  Future<void> _rejectRequest(BuildContext context, AppNotification n) async {
    final requesterId = n.actorId ?? n.targetId;
    if (requesterId == null || requesterId.isEmpty) return;
    await context.read<AuthProvider>().rejectFollowRequest(requesterId);
    if (!context.mounted) return;
    hubMarkRead(context, n.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Takip isteği reddedildi')));
  }

  void hubMarkRead(BuildContext context, String id) {
    context.read<NotificationProvider>().markRead(id);
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<NotificationProvider>();
    final auth = context.watch<AuthProvider>();
    final pendingIds = auth.user?.incomingFollowRequests ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          TextButton(
            onPressed: hub.markAllRead,
            child: const Text('Tümünü okundu'),
          ),
        ],
      ),
      body: hub.items.isEmpty && pendingIds.isEmpty
          ? const Center(child: Text('Henüz bildirim yok'))
          : ListView.separated(
              itemCount: hub.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = hub.items[i];
                final isRequest = n.type == 'follow_request';
                final requesterId = n.actorId ?? n.targetId;
                final stillPending =
                    isRequest &&
                    requesterId != null &&
                    pendingIds.any(
                      (id) => auth.idsFor(requesterId).contains(id),
                    );

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                    child: Text(n.emoji, style: const TextStyle(fontSize: 20)),
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.read ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.body),
                      if (stillPending) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: () => _acceptRequest(context, n),
                              child: const Text('Kabul'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () => _rejectRequest(context, n),
                              child: const Text('Reddet'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  isThreeLine: stillPending,
                  trailing: n.read
                      ? null
                      : const Icon(
                          Icons.circle,
                          size: 10,
                          color: AppColors.crimson,
                        ),
                  onTap: () => _open(
                    context,
                    type: n.type,
                    targetId: n.targetId,
                    actorId: n.actorId,
                  ),
                );
              },
            ),
    );
  }
}
