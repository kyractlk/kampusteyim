import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final event = feed.eventById(eventId);
    if (event == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => AppNav.back(context, fallback: '/events'),
          ),
          title: const Text('Etkinlik'),
        ),
        body: const Center(child: Text('Etkinlik bulunamadı')),
      );
    }
    final applied = user != null && event.hasActiveApplication(user.id);
    final blocked = event.applyBlockedReason(
      user: user,
      follows: (cid) => auth.follows(cid),
    );
    final canApply = blocked.isEmpty;
    final date =
        DateFormat('d MMMM yyyy · HH:mm', 'tr').format(event.startsAt);
    final deadlineLabel = event.applicationDeadline == null
        ? null
        : DateFormat('d MMMM yyyy · HH:mm', 'tr')
            .format(event.applicationDeadline!);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => AppNav.back(context, fallback: '/events'),
        ),
        title: const Text('Etkinlik'),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            onPressed: () => AppShare.shareLink(
              context: context,
              url: AppShare.event(event.id),
              subject: event.title,
              preview: '${event.title}\n$date',
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (event.imageUrl != null)
            GestureDetector(
              onTap: () => openMediaViewer(
                context,
                urls: [event.imageUrl!],
                isVideo: const [false],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SafeNetworkImage(
                    url: event.imageUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            event.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (event.communityName != null) ...[
            const SizedBox(height: 10),
            AffiliationBadge(
              orgName: event.communityName!,
              logoUrl: event.communityLogoUrl,
              orgId: event.communityId,
              verifiedGold: true,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            date,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (event.location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              event.location,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Kimler: ${event.audienceLabel}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (deadlineLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              'Son başvuru: $deadlineLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Text(event.description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(
            'Kadro: ${event.approvedCount}/${event.capacity}'
            '${event.pendingCount > 0 ? ' · ${event.pendingCount} bekleyen' : ''}'
            '${event.isRosterFull ? ' · Kadro doldu' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: !canApply
                ? null
                : () async {
                    if (!AuthGate.requireAuth(
                      context,
                      message: 'Başvuru için giriş yapmalısın.',
                    )) {
                      return;
                    }
                    final a = context.read<AuthProvider>();
                    final err = await feed.applyToEvent(
                      event.id,
                      applicant: a.user,
                      follows: (cid) => a.follows(cid),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(err ?? 'Başvurun alındı.'),
                      ),
                    );
                  },
            child: Text(
              applied ? 'Başvuruldu' : (blocked.isEmpty ? 'Başvur' : blocked),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.go('/events'),
            child: const Text('Tüm etkinlikler'),
          ),
        ],
      ),
    );
  }
}
