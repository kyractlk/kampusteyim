import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../admin/admin_provider.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import 'moderation_models.dart';

Future<void> showReportSheet({
  required BuildContext context,
  required ReportTargetType targetType,
  required String targetId,
  String? targetOwnerId,
  String? snapshotTitle,
  String? snapshotBody,
  String? snapshotAuthor,
  String? snapshotUrl,
}) async {
  if (!AuthGate.requireAuth(
    context,
    message: 'Şikayet etmek için giriş yapmalısın.',
  )) {
    return;
  }

  final reasons = switch (targetType) {
    ReportTargetType.post => [
        'Spam',
        'Nefret / taciz',
        'Yanıltıcı bilgi',
        'Uygunsuz içerik',
        'Diğer',
      ],
    ReportTargetType.comment => [
        'Taciz',
        'Spam',
        'Nefret söylemi',
        'Diğer',
      ],
    ReportTargetType.account => [
        'Kimlik sahteciliği',
        'Taciz',
        'Spam hesap',
        'Diğer',
      ],
  };

  String? selected = reasons.first;
  final details = TextEditingController();

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    MtIcon(MtIcons.report, size: 22, color: AppColors.crimson),
                    SizedBox(width: 8),
                    Text(
                      'Şikayet et',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...reasons.map(
                  (r) => ListTile(
                    dense: true,
                    title: Text(r),
                    leading: Icon(
                      selected == r
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected == r ? AppColors.navy : null,
                    ),
                    onTap: () => setLocal(() => selected = r),
                  ),
                ),
                TextField(
                  controller: details,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Detay (opsiyonel)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Gönder'),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  if (ok != true || !context.mounted) {
    details.dispose();
    return;
  }

  final auth = context.read<AuthProvider>();
  final feed = context.read<FeedProvider>();
  final me = auth.user!;

  var title = snapshotTitle ?? '';
  var body = snapshotBody ?? '';
  var author = snapshotAuthor ?? '';
  var url = snapshotUrl ?? '';
  var ownerId = targetOwnerId;

  if (targetType == ReportTargetType.post) {
    final post = feed.postByIdIncludingDeleted(targetId);
    if (post != null) {
      body = body.isEmpty ? post.content : body;
      author = author.isEmpty ? post.authorName : author;
      ownerId ??= post.authorId;
      url = url.isEmpty ? AppShare.post(post.id) : url;
      title = title.isEmpty ? 'Gönderi' : title;
    } else {
      url = url.isEmpty ? AppShare.post(targetId) : url;
    }
  } else if (targetType == ReportTargetType.account) {
    final u = auth.findUser(targetId);
    if (u != null) {
      author = author.isEmpty ? u.fullName : author;
      body = body.isEmpty ? (u.bio.isEmpty ? u.email : u.bio) : body;
      ownerId ??= u.id;
      url = url.isEmpty ? AppShare.userOf(u) : url;
      title = title.isEmpty ? 'Profil' : title;
    } else {
      url = url.isEmpty ? AppShare.user(targetId) : url;
    }
  }

  await context.read<AdminProvider>().fileReport(
        ContentReport(
          id: 'rep_${const Uuid().v4().substring(0, 8)}',
          targetType: targetType,
          targetId: targetId,
          targetOwnerId: ownerId,
          reporterId: me.id,
          reason: selected ?? 'Diğer',
          details: details.text.trim(),
          createdAt: DateTime.now(),
          snapshotTitle: title,
          snapshotBody: body,
          snapshotAuthor: author,
          snapshotUrl: url,
          reporterEmail: me.email,
          reporterName: me.fullName,
        ),
      );
  details.dispose();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Şikayetin alındı. Admin inceleyecek.')),
    );
  }
}
