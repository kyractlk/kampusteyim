import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../models/models.dart';
import '../reels/reel_models.dart';

enum _ProfileContentKind { posts, text, reels }

/// Instagram tarzı profil içerik sekmeleri: Post grid · Yazılar · Reels.
class ProfileContentTabs extends StatefulWidget {
  const ProfileContentTabs({
    super.key,
    required this.canSee,
    required this.feedPosts,
    required this.reels,
  });

  final bool canSee;
  final List<Post> feedPosts;
  final List<CampusReel> reels;

  @override
  State<ProfileContentTabs> createState() => _ProfileContentTabsState();
}

class _ProfileContentTabsState extends State<ProfileContentTabs> {
  _ProfileContentKind _kind = _ProfileContentKind.posts;

  List<Post> get _mediaPosts {
    final list = widget.feedPosts
        .where((p) => p.media.isNotEmpty && !p.isStudyRoomInvite)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<Post> get _textPosts {
    final list = widget.feedPosts
        .where((p) => p.media.isEmpty && !p.isStudyRoomInvite)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<CampusReel> get _reels {
    final list = List<CampusReel>.from(widget.reels);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void _select(_ProfileContentKind k) {
    if (_kind == k) return;
    setState(() => _kind = k);
  }

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() < 220) return;
    final order = _ProfileContentKind.values;
    final i = order.indexOf(_kind);
    if (v < 0 && i < order.length - 1) {
      _select(order[i + 1]);
    } else if (v > 0 && i > 0) {
      _select(order[i - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canSee) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            const Text(
              'Bu hesap gizli',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Gönderileri görmek için takip isteği gönder ve kabul edilmesini bekle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.95),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(
          kind: _kind,
          onSelect: _select,
          postCount: _mediaPosts.length,
          textCount: _textPosts.length,
          reelCount: _reels.length,
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: _onSwipe,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey(_kind),
              child: switch (_kind) {
                _ProfileContentKind.posts => _MediaGrid(
                    posts: _mediaPosts,
                  ),
                _ProfileContentKind.text => _TextFeed(
                    posts: _textPosts,
                  ),
                _ProfileContentKind.reels => _ReelsGrid(
                    reels: _reels,
                  ),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.kind,
    required this.onSelect,
    required this.postCount,
    required this.textCount,
    required this.reelCount,
  });

  final _ProfileContentKind kind;
  final ValueChanged<_ProfileContentKind> onSelect;
  final int postCount;
  final int textCount;
  final int reelCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.7)),
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          _TabIcon(
            selected: kind == _ProfileContentKind.posts,
            icon: Icons.grid_on_rounded,
            label: 'Post',
            count: postCount,
            onTap: () => onSelect(_ProfileContentKind.posts),
          ),
          _TabIcon(
            selected: kind == _ProfileContentKind.text,
            icon: Icons.notes_rounded,
            label: 'Yazı',
            count: textCount,
            onTap: () => onSelect(_ProfileContentKind.text),
          ),
          _TabIcon(
            selected: kind == _ProfileContentKind.reels,
            icon: Icons.movie_filter_rounded,
            label: 'Reels',
            count: reelCount,
            onTap: () => onSelect(_ProfileContentKind.reels),
          ),
        ],
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.selected,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.navy : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.navy : Colors.transparent,
                width: 1.6,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(
                  '$label · $count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.posts});
  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const _EmptyPane(
        icon: Icons.grid_on_rounded,
        title: 'Henüz post yok',
        subtitle: 'Medyalı gönderiler burada görünür.',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.2,
        crossAxisSpacing: 1.2,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, i) {
        final p = posts[i];
        final media = p.media.first;
        final isVideo = media.type == MediaType.video;
        final multi = p.media.length > 1;
        return InkWell(
          onTap: () => AppNav.openPost(context, p.id),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: AppColors.surfaceMuted,
                child: media.type == MediaType.file
                    ? const Center(
                        child: Icon(Icons.insert_drive_file_rounded, size: 28),
                      )
                    : SafeNetworkImage(
                        url: media.url,
                        fit: BoxFit.cover,
                        cacheWidth: 420,
                      ),
              ),
              if (isVideo)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 20,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              if (multi)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.collections_rounded,
                    color: Colors.white,
                    size: 18,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReelsGrid extends StatelessWidget {
  const _ReelsGrid({required this.reels});
  final List<CampusReel> reels;

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty) {
      return const _EmptyPane(
        icon: Icons.movie_filter_rounded,
        title: 'Henüz Reels yok',
        subtitle: 'Reels paylaşımları burada grid olarak görünür.',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: reels.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.2,
        crossAxisSpacing: 1.2,
        // Instagram reels grid biraz daha dikey.
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, i) {
        final r = reels[i];
        final isVideo = r.mediaType == ReelMediaType.video;
        return InkWell(
          onTap: () {
            AppNav.openReel(context, reelId: r.id);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: SafeNetworkImage(
                  url: r.mediaUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 420,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${r.likedBy.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isVideo)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.movie_rounded,
                    color: Colors.white,
                    size: 16,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TextFeed extends StatelessWidget {
  const _TextFeed({required this.posts});
  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const _EmptyPane(
        icon: Icons.notes_rounded,
        title: 'Henüz yazı yok',
        subtitle: 'Sadece metin gönderileri burada listelenir.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      itemCount: posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = posts[i];
        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.border.withValues(alpha: 0.85)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => AppNav.openPost(context, p.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.content.trim().isEmpty ? '(Boş gönderi)' : p.content,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border_rounded,
                        size: 14,
                        color: AppColors.textSecondary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${p.likeCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                        color: AppColors.textSecondary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${p.replyCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Yazı',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
