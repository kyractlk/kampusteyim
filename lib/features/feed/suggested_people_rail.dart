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
import '../auth/data/auth_provider.dart';

/// Instagram tarzı yatay "Önerilenler" rayı — fotoğraflar disk cache + prefetch.
class SuggestedPeopleRail extends StatefulWidget {
  const SuggestedPeopleRail({super.key});

  @override
  State<SuggestedPeopleRail> createState() => _SuggestedPeopleRailState();
}

class _SuggestedPeopleRailState extends State<SuggestedPeopleRail> {
  List<SuggestedPerson> _items = const [];
  String _fingerprint = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  void _rebuildIfNeeded() {
    final auth = context.read<AuthProvider>();
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

    // Dizin / takip / dismiss değişince yeniden hesapla.
    final fp =
        '${me.id}|${me.following.length}|${auth.dismissedSuggestions.length}|'
        '${auth.directory.length}|${me.outgoingFollowRequests.length}';
    if (fp == _fingerprint && _items.isNotEmpty) return;

    final next = PeopleSuggestions.build(
      auth: auth,
      dismissed: auth.dismissedSuggestions,
      limit: 20,
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
    // Image cache'e de erken bas.
    for (final url in urls.take(12)) {
      unawaited(precacheImage(NetworkImage(url), context).catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Takip durumu güncellensin diye auth'u dinle; liste fingerprint ile korunur.
    context.watch<AuthProvider>();
    _rebuildIfNeeded();

    if (_items.isEmpty) return const SizedBox.shrink();

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
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final item = _items[i];
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
    final liquid = LiquidGlass.enabled(context);
    final radius = liquid ? 20.0 : 14.0;

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
              padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
              child: Column(
                children: [
                  UserAvatar(
                    name: u.fullName,
                    photoUrl: u.communityLogoUrl ?? u.photoUrl,
                    radius: 34,
                    isCommunity: u.isCommunity,
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
                      style: liquid
                          ? liquidFilledButtonStyle(
                              dark: false,
                              minimumSize: const Size.fromHeight(34),
                            )
                          : FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
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
              icon: Icon(
                Icons.close,
                size: 18,
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
      width: 148,
      child: liquid
          ? LiquidGlass(
              borderRadius: radius,
              blur: 24,
              intensity: 1.1,
              borderOpacity: 0.7,
              child: content,
            )
          : content,
    );
  }
}
