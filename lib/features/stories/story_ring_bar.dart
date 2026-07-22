import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/social_widgets.dart';
import '../auth/data/auth_provider.dart';
import 'stories_provider.dart';
import 'story_compose_sheet.dart';

class StoryRingBar extends StatelessWidget {
  const StoryRingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final stories = context.watch<StoriesProvider>();
    final me = auth.user;
    if (me == null) return const SizedBox.shrink();
    if (me.isSpectatorMode) return const SizedBox.shrink();

    final rings = stories.storyRings();
    final hasOwn = rings.any((r) => r.authorId == me.id);

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: rings.length + (hasOwn ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (!hasOwn && index == 0) {
            return _AddStoryRing(
              name: me.fullName,
              photoUrl: me.photoUrl,
              onTap: () => showStoryComposeSheet(context),
            );
          }
          final ring = rings[hasOwn ? index : index - 1];
          final isSelf = ring.authorId == me.id;
          return _StoryRingTile(
            name: isSelf ? 'Hikâyen' : ring.authorName.split(' ').first,
            photoUrl: ring.authorPhotoUrl,
            isSelf: isSelf,
            onTap: () => context.push('/stories/view/${ring.authorId}'),
            onAdd: isSelf ? () => showStoryComposeSheet(context) : null,
          );
        },
      ),
    );
  }
}

class _AddStoryRing extends StatelessWidget {
  const _AddStoryRing({
    required this.name,
    required this.photoUrl,
    required this.onTap,
  });

  final String name;
  final String? photoUrl;
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 2),
                  ),
                  child: UserAvatar(name: name, photoUrl: photoUrl, radius: 28),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.cyan,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Hikâye ekle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
    this.onAdd,
  });

  final String name;
  final String? photoUrl;
  final bool isSelf;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onAdd,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.cyan, AppColors.crimson, AppColors.gold],
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
                if (isSelf && onAdd != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.cyan,
                          shape: BoxShape.circle,
                        ),
                        child:
                            const Icon(Icons.add, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
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
