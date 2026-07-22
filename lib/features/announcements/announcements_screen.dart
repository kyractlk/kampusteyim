import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/safe_network_image.dart';
import '../feed/feed_provider.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<FeedProvider>().announcements;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Duyurular'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Misafir okuyabilir',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final audienceLabel = switch (item.audience) {
            'members' => 'Üyelere',
            'followers' => 'Takipçilere',
            _ => 'Tüm kampüs',
          };
          final audienceColor = switch (item.audience) {
            'members' => AppColors.gold,
            'followers' => AppColors.cyan,
            _ => AppColors.lime,
          };

          return Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: item.isPinned
                    ? AppColors.crimson.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => AppNav.openAnnouncement(context, item.id),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.imageUrl != null)
                  GestureDetector(
                    onTap: () => openMediaViewer(
                      context,
                      urls: [item.imageUrl!],
                      isVideo: const [false],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                      child: AspectRatio(
                        aspectRatio: 16 / 7,
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (item.isPinned) ...[
                            const Icon(Icons.push_pin_rounded,
                                size: 16, color: AppColors.crimson),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: audienceColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              audienceLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Paylaş',
                            onPressed: () => AppShare.shareLink(
                              context: context,
                              url: AppShare.announcement(item.id),
                              subject: item.title,
                              preview: item.title,
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                          ),
                          Text(
                            DateFormat('d MMM', 'tr').format(item.createdAt),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (item.communityName != null) ...[
                        AffiliationBadge(
                          orgName: item.communityName!,
                          logoUrl: item.communityLogoUrl,
                          orgId: item.communityId,
                          compact: true,
                          verifiedGold: true,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        item.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          )
              .animate()
              .fadeIn(delay: (50 * index).ms)
              .slideX(begin: 0.04, curve: Curves.easeOutCubic);
        },
      ),
    );
  }
}
