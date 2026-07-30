import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/social_widgets.dart';
import '../ads/ads_provider.dart';
import '../auth/data/auth_provider.dart';
import 'campus_camera_screen.dart';
import 'stories_provider.dart';

class StoryRingBar extends StatelessWidget {
  const StoryRingBar({super.key});

  Future<void> _onSelfTap(BuildContext context, {required bool hasOwn}) async {
    if (hasOwn) {
      final me = context.read<AuthProvider>().user;
      if (me != null) {
        await context.push('/stories/view/${me.id}');
      }
      return;
    }
    await openCampusShareMenu(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final stories = context.watch<StoriesProvider>();
    final ads = context.watch<AdsProvider>();
    final me = auth.user;
    if (me == null) return const SizedBox.shrink();
    if (me.isSpectatorMode) return const SizedBox.shrink();

    final rings = stories.storyRings();
    final storyAd = ads.pick(ads.stories);
    final extra = storyAd == null ? 0 : 1;

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: rings.length + 1 + extra,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateShareRing(
              onTap: () => openCampusShareMenu(context),
            );
          }
          if (storyAd != null && index == 1) {
            return _AdStoryRing(
              ad: storyAd,
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: AdCard(ad: storyAd, placement: 'stories'),
                  ),
                );
              },
            );
          }
          final ring = rings[index - 1 - extra];
          final isSelf = ring.authorId == me.id;
          return _StoryRingTile(
            name: isSelf ? 'Hikâyen' : ring.authorName.split(' ').first,
            photoUrl: ring.authorPhotoUrl,
            isSelf: isSelf,
            onTap: () {
              if (isSelf) {
                _onSelfTap(context, hasOwn: true);
              } else {
                context.push('/stories/view/${ring.authorId}');
              }
            },
          );
        },
      ),
    );
  }
}

/// Instagram tarzı geniş + — hikâye / reels menüsü.
class _CreateShareRing extends StatelessWidget {
  const _CreateShareRing({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.border, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded,
                  size: 34, color: AppColors.cyan),
            ),
            const SizedBox(height: 6),
            const Text(
              'Paylaş',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryRingTile extends StatelessWidget {
  const _StoryRingTile({
    required this.name,
    required this.photoUrl,
    required this.isSelf,
    required this.onTap,
  });

  final String name;
  final String? photoUrl;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isSelf
                    ? const LinearGradient(
                        colors: [
                          AppColors.cyan,
                          AppColors.crimson,
                          AppColors.gold,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [
                          AppColors.cyan,
                          AppColors.crimson,
                          AppColors.gold,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(
                  name: name,
                  photoUrl: photoUrl,
                  radius: 26,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdStoryRing extends StatelessWidget {
  const _AdStoryRing({required this.ad, required this.onTap});
  final Map<String, dynamic> ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        '${ad['ownerName'] ?? ad['companyName'] ?? 'Sponsor'}'.trim();
    final photo = '${ad['ownerPhotoUrl'] ?? ''}'.trim();
    final short = name.split(' ').first;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.navy, width: 2.5),
              ),
              child: UserAvatar(
                name: name,
                photoUrl: photo.startsWith('http') ? photo : null,
                radius: 28,
                isCommunity: ad['isCommunity'] == true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              short.isEmpty ? 'Sponsor' : short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
