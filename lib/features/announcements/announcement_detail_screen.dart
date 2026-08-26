import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../core/widgets/social_widgets.dart';
import '../feed/feed_provider.dart';

class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.announcementId});

  final String announcementId;

  @override
  Widget build(BuildContext context) {
    final item = context.watch<FeedProvider>().announcementById(announcementId);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => AppNav.back(context, fallback: '/announcements'),
          ),
          title: const Text('Duyuru'),
        ),
        body: const Center(child: Text('Duyuru bulunamadı')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => AppNav.back(context, fallback: '/announcements'),
        ),
        title: const Text('Duyuru'),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            onPressed: () => AppShare.shareLink(
              context: context,
              url: AppShare.announcement(item.id),
              subject: item.title,
              preview: item.title,
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (item.imageUrl != null) ...[
            GestureDetector(
              onTap: () => openMediaViewer(
                context,
                urls: [item.imageUrl!],
                isVideo: const [false],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SafeNetworkImage(
                    url: item.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.surfaceMuted,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_outlined),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (item.isPinned)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.push_pin_rounded,
                    size: 14,
                    color: AppColors.crimson.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sabitlenmiş',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.crimson.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            item.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
          ),
          if (item.communityName != null) ...[
            const SizedBox(height: 12),
            AffiliationBadge(
              orgName: item.communityName!,
              logoUrl: item.communityLogoUrl,
              orgId: item.communityId,
              verifiedGold: true,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${DateFormat('d MMMM yyyy · HH:mm', 'tr').format(item.createdAt)}'
            ' · ${item.audienceLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: HashtagText(
              text: item.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                  ),
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => context.go('/announcements'),
            child: const Text('Tüm duyurular'),
          ),
        ],
      ),
    );
  }
}
