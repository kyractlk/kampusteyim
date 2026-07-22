import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import 'notification_provider.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  void _open(BuildContext context, String? type, String? targetId) {
    if (targetId == null || targetId.isEmpty) return;
    switch (type) {
      case 'mention':
      case 'like':
      case 'comment':
      case 'repost':
      case 'activity':
        context.push('/post/${Uri.encodeComponent(targetId)}');
      case 'follow':
        context.push('/user/${Uri.encodeComponent(targetId)}');
      case 'job':
      case 'application':
        context.push('/jobs');
      case 'community':
        if (targetId.startsWith('e_') || targetId.startsWith('a_')) {
          // etkinlik / duyuru id
          if (targetId.startsWith('e_')) {
            context.push('/event/${Uri.encodeComponent(targetId)}');
          } else {
            context.push('/announcement/${Uri.encodeComponent(targetId)}');
          }
        } else {
          context.push('/post/${Uri.encodeComponent(targetId)}');
        }
      default:
        if (targetId.startsWith('p_') ||
            targetId.startsWith('job_') ||
            targetId.startsWith('ann_') ||
            targetId.contains('post')) {
          context.push('/post/${Uri.encodeComponent(targetId)}');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<NotificationProvider>();
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
      body: hub.items.isEmpty
          ? const Center(child: Text('Henüz bildirim yok'))
          : ListView.separated(
              itemCount: hub.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = hub.items[i];
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
                  subtitle: Text(n.body),
                  trailing: n.read
                      ? null
                      : const Icon(Icons.circle,
                          size: 10, color: AppColors.crimson),
                  onTap: () => _open(context, n.type, n.targetId),
                );
              },
            ),
    );
  }
}
