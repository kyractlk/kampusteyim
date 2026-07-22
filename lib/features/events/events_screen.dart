import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/safe_network_image.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final events = context.watch<FeedProvider>().events;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Etkinlikler')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: events.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final event = events[index];
          final applied =
              user != null && event.hasActiveApplication(user.id);
          final blocked = event.applyBlockedReason(
            user: user,
            follows: (cid) => auth.follows(cid),
          );
          final canApply = blocked.isEmpty;
          final date =
              DateFormat('d MMMM yyyy · HH:mm', 'tr').format(event.startsAt);
          final deadlineLabel = event.applicationDeadline == null
              ? null
              : DateFormat('d MMM · HH:mm', 'tr')
                  .format(event.applicationDeadline!);

          return Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => AppNav.openEvent(context, event.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.imageUrl != null)
                    GestureDetector(
                      onTap: () => openMediaViewer(
                        context,
                        urls: [event.imageUrl!],
                        isVideo: const [false],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        child: AspectRatio(
                          aspectRatio: 16 / 7,
                          child: SafeNetworkImage(
                            url: event.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.surfaceMuted,
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
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Paylaş',
                            onPressed: () => AppShare.shareLink(
                              context: context,
                              url: AppShare.event(event.id),
                              subject: event.title,
                              preview: event.title,
                            ),
                            icon: const Icon(
                              Icons.ios_share_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                        if (event.communityName != null) ...[
                          const SizedBox(height: 6),
                          AffiliationBadge(
                            orgName: event.communityName!,
                            logoUrl: event.communityLogoUrl,
                            orgId: event.communityId,
                            compact: true,
                            verifiedGold: true,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          date,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${event.audienceLabel}'
                          '${deadlineLabel != null ? ' · Son başvuru: $deadlineLabel' : ''}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        Text(event.description),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 16,
                              color: AppColors.cyan,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.location,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                              ),
                            ),
                            Text(
                              '${event.approvedCount}/${event.capacity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: event.capacity == 0
                                ? 0
                                : (event.approvedCount / event.capacity)
                                    .clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: AppColors.surfaceMuted,
                            color: event.isRosterFull
                                ? AppColors.crimson
                                : AppColors.lime,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: !canApply
                                ? null
                                : () async {
                                    if (!AuthGate.requireAuth(
                                      context,
                                      message:
                                          'Etkinliğe başvurmak için giriş yapmalısın.',
                                    )) {
                                      return;
                                    }
                                    final auth = context.read<AuthProvider>();
                                    final err = await context
                                        .read<FeedProvider>()
                                        .applyToEvent(
                                          event.id,
                                          applicant: auth.user,
                                          follows: (cid) => auth.follows(cid),
                                        );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          err ??
                                              '${event.title} başvurusu alındı.',
                                        ),
                                      ),
                                    );
                                  },
                            child: Text(
                              applied
                                  ? 'Başvuruldu'
                                  : (blocked.isEmpty ? 'Başvur' : blocked),
                            ),
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
              .fadeIn(delay: (60 * index).ms)
              .scale(
                begin: const Offset(0.98, 0.98),
                curve: Curves.easeOutCubic,
              );
        },
      ),
    );
  }
}
