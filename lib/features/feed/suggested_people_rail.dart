import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/storage/media_disk_cache.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/campus_affinity.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/social_widgets.dart';
import '../../core/widgets/web_safe_image.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import '../profile/follow_requests_screen.dart';
import '../reels/reels_provider.dart';

/// Instagram tarzı yatay "Önerilenler" rayı — kompakt + etkileşim algoritması.
class SuggestedPeopleRail extends StatefulWidget {
  const SuggestedPeopleRail({super.key});

  @override
  State<SuggestedPeopleRail> createState() => _SuggestedPeopleRailState();
}

class _SuggestedPeopleRailState extends State<SuggestedPeopleRail> {
  List<SuggestedPerson> _items = const [];
  String _fingerprint = '';
  int _shuffleSeed = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  void _rebuildIfNeeded({bool forceShuffle = false}) {
    final auth = context.read<AuthProvider>();
    final feed = context.read<FeedProvider>();
    final reels = context.read<ReelsProvider>();
    final me = auth.user;
    if (me == null) {
      if (_items.isNotEmpty) {
        setState(() {
          _items = const [];
          _fingerprint = '';
        });
      }
      return;
    }

    final likedPostN = feed.posts.where((p) => p.isLiked).length;
    final likedReelN =
        reels.items.where((r) => r.likedByUser(me.id)).length;
    final fp =
        '${me.id}|${me.following.length}|${auth.dismissedSuggestions.length}|'
        '${auth.directory.length}|${me.outgoingFollowRequests.length}|'
        '$likedPostN|$likedReelN|${feed.posts.length}|${reels.items.length}';
    if (fp == _fingerprint && _items.isNotEmpty && !forceShuffle) return;

    if (fp != _fingerprint || _shuffleSeed == 0) {
      _shuffleSeed = DateTime.now().microsecondsSinceEpoch;
    }

    final signals = EngagementSignals.fromContent(
      auth: auth,
      viewerId: me.id,
      posts: feed.posts,
      reels: reels.items,
    );

    final authorTags = <String, List<String>>{};
    void addTags(String authorId, Iterable<String> tags) {
      if (tags.isEmpty) return;
      final list = authorTags.putIfAbsent(authorId, () => <String>[]);
      for (final t in tags) {
        final n = t.trim().toLowerCase();
        if (n.isNotEmpty && !list.contains(n)) list.add(n);
      }
    }

    for (final p in feed.posts) {
      addTags(p.authorId, p.hashtags);
    }
    for (final r in reels.items) {
      addTags(r.authorId, r.hashtags);
    }

    final next = PeopleSuggestions.build(
      auth: auth,
      dismissed: auth.dismissedSuggestions,
      limit: 20,
      signals: signals,
      authorTags: authorTags,
      shuffleSeed: _shuffleSeed,
    );
    _fingerprint = fp;
    _items = next;
    _prefetchPhotos(next);
    if (mounted) setState(() {});
  }

  void _prefetchPhotos(List<SuggestedPerson> items) {
    if (kIsWeb) return;
    final urls = items
        .map((e) => e.user.photoUrl?.trim() ?? '')
        .where((u) => u.startsWith('http'))
        .toList(growable: false);
    if (urls.isEmpty) return;
    MediaDiskCache.instance.prefetchAll(urls, concurrency: 6, front: true);
    for (final url in urls.take(12)) {
      unawaited(
        precacheImage(webSafeImageProvider(url), context).catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    context.watch<FeedProvider>();
    context.watch<ReelsProvider>();
    _rebuildIfNeeded();

    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Önerilenler',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  _shuffleSeed = DateTime.now().microsecondsSinceEpoch;
                  _rebuildIfNeeded(forceShuffle: true);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  'Karıştır',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy.withValues(alpha: 0.7),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/search'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  'Tümünü gör',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
        ClipRect(
          child: SizedBox(
            height: 156,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              scrollDirection: Axis.horizontal,
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                return _SuggestCard(item: _items[i]);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
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
    final label = followActionLabel(auth, u);
    final liquid = LiquidGlass.enabled(context);
    final radius = liquid ? 16.0 : 12.0;

    final content = Material(
      color: liquid ? Colors.transparent : AppColors.surface,
      shape: liquid
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: const BorderSide(color: AppColors.border),
            ),
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: () => context.push('/user/${u.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
              child: Column(
                children: [
                  UserAvatar(
                    name: u.fullName,
                    photoUrl: u.communityLogoUrl ?? u.photoUrl,
                    radius: 24,
                    isCommunity: u.isCommunity,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    u.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.reason ??
                        (u.isPrivateAccount ? 'Gizli hesap' : u.handle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
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
                      style: liquid
                          ? liquidFilledButtonStyle(
                              dark: false,
                              minimumSize: const Size.fromHeight(30),
                            )
                          : FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      child: Text(
                        following
                            ? 'Takip'
                            : pending
                                ? 'İstek'
                                : (label.isNotEmpty ? label : 'Takip et'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Kapat',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => auth.dismissSuggestion(u.id),
              icon: Icon(
                Icons.close,
                size: 16,
                color: liquid
                    ? AppColors.textSecondary.withValues(alpha: 0.85)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: 118,
      child: liquid
          ? LiquidGlass(
              borderRadius: radius,
              blur: 14,
              intensity: 0.85,
              borderOpacity: 0.55,
              child: content,
            )
          : content,
    );
  }
}
