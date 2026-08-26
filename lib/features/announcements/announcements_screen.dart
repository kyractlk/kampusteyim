import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../models/models.dart';
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
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                'Misafir okuyabilir',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text(
                'Henüz duyuru yok',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _AnnouncementMinimalCard(item: item, index: index);
              },
            ),
    );
  }
}

class _AnnouncementMinimalCard extends StatelessWidget {
  const _AnnouncementMinimalCard({required this.item, required this.index});

  final Announcement item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final preview = item.body.trim().replaceAll(RegExp(r'\s+'), ' ');
    final date = DateFormat('d MMM', 'tr').format(item.createdAt);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => AppNav.openAnnouncement(context, item.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isPinned
                  ? AppColors.crimson.withValues(alpha: 0.28)
                  : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: SafeNetworkImage(
                      url: item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surfaceMuted,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.campaign_outlined,
                          size: 22,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
              ] else ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.campaign_outlined,
                    size: 18,
                    color: item.isPinned
                        ? AppColors.crimson
                        : AppColors.navy.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item.isPinned) ...[
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 13,
                            color: AppColors.crimson,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (item.communityName != null) ...[
                      const SizedBox(height: 4),
                      AffiliationBadge(
                        orgName: item.communityName!,
                        logoUrl: item.communityLogoUrl,
                        orgId: item.communityId,
                        compact: true,
                        verifiedGold: true,
                      ),
                    ],
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          item.audienceLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy.withValues(alpha: 0.55),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Detay',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.cyan.withValues(alpha: 0.95),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.cyan.withValues(alpha: 0.9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (40 * index).ms, duration: 280.ms)
        .slideY(begin: 0.04, curve: Curves.easeOutCubic);
  }
}
