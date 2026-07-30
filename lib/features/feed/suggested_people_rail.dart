import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/campus_affinity.dart';
import '../auth/data/auth_provider.dart';

/// Instagram tarzı yatay "Onerilenler" rayı.
class SuggestedPeopleRail extends StatelessWidget {
  const SuggestedPeopleRail({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final me = auth.user;
    if (me == null) return const SizedBox.shrink();

    final items = PeopleSuggestions.build(
      auth: auth,
      dismissed: auth.dismissedSuggestions,
      limit: 20,
    );
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Önerilenler',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/search'),
                child: Text(
                  'Tümünü gör',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              return _SuggestCard(item: item);
            },
          ),
        ),
      ],
    );
  }
}

class _SuggestCard extends StatelessWidget {
  const _SuggestCard({required this.item});
  final SuggestedPerson item;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final u = item.user;
    final pending = auth.hasOutgoingFollowRequest(u.id);
    final following = auth.follows(u.id);

    return SizedBox(
      width: 148,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Stack(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/user/${u.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                      backgroundImage: (u.photoUrl != null &&
                              u.photoUrl!.trim().isNotEmpty)
                          ? NetworkImage(u.photoUrl!)
                          : null,
                      child: (u.photoUrl == null || u.photoUrl!.trim().isEmpty)
                          ? Text(
                              u.initials,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      u.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.reason ??
                          (u.isPrivateAccount ? 'Gizli hesap' : u.handle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: following
                            ? null
                            : () async {
                                await auth.toggleFollow(u.id);
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(
                          following
                              ? 'Takip'
                              : pending
                                  ? 'İstek'
                                  : u.isPrivateAccount
                                      ? 'İstek'
                                      : 'Takip et',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                tooltip: 'Kapat',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => auth.dismissSuggestion(u.id),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
