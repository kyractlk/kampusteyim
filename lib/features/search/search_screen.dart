import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import '../feed/feed_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<AuthProvider>().syncDirectoryFromFirestore());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final feed = context.watch<FeedProvider>();
    final q = _ctrl.text.trim();
    final people = auth.searchPeople(q);
    final posts = _searchPosts(feed.posts, q);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Kişi, @handle veya #gönderi ara…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (q.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              onPressed: () {
                _ctrl.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          if (q.isEmpty) ...[
            const _SectionTitle(title: 'Popüler hashtag’ler'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PopularHashtags(
                items: feed.popularHashtags(limit: 5),
                onTap: (tag) {
                  _ctrl.text = '#$tag';
                  _ctrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _ctrl.text.length),
                  );
                  setState(() {});
                },
              ),
            ),
          ],
          _SectionTitle(
            title: q.isEmpty ? 'Kişiler' : 'Kişiler (${people.length})',
          ),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Eşleşen profil yok.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...people.map((u) => _PersonTile(user: u)),
          if (q.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionTitle(title: 'Gönderiler (${posts.length})'),
            if (posts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'Eşleşen gönderi yok.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...posts.map(
                (p) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: PostCard(post: p),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Post> _searchPosts(List<Post> all, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final tag = q.startsWith('#') ? q.substring(1) : q;
    return all.where((p) {
      return p.content.toLowerCase().contains(q) ||
          p.authorName.toLowerCase().contains(q) ||
          p.authorHandle.toLowerCase().contains(q) ||
          p.hashtags.any((h) => h.toLowerCase().contains(tag));
    }).toList();
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
      ),
    );
  }
}

class _PopularHashtags extends StatelessWidget {
  const _PopularHashtags({required this.items, required this.onTap});

  final List<({String tag, int score, int posts})> items;
  final void Function(String tag) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'Henüz yeterli hashtag etkileşimi yok.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  '#${items[i].tag}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${items[i].posts} gönderi · ${items[i].score} etkileşim',
                ),
                trailing: const Icon(Icons.trending_up_rounded,
                    color: AppColors.cyan),
                onTap: () => onTap(items[i].tag),
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final roleLabel = user.isBot
        ? 'AI Bot'
        : user.isCommunity
            ? 'Topluluk'
            : user.isCompany
                ? 'Firma'
                : user.isAdmin
                    ? 'Admin'
                    : user.university;

    return ListTile(
      leading: UserAvatar(
        name: user.fullName,
        photoUrl: user.communityLogoUrl ?? user.photoUrl,
        isCommunity: user.isCommunity,
        radius: 24,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.showGoldBadge) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(gold: true, size: 14),
          ] else if (user.showBlueBadge) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(gold: false, size: 14),
          ],
          if (user.isBot) ...[
            const SizedBox(width: 4),
            const BotBadge(size: 14),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${user.handle} · $roleLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (user.hasAffiliation)
            AffiliationBadge(
              orgName: user.affiliatedCommunityName?.trim() ?? '',
              logoUrl: user.affiliatedOrgLogoUrl,
              orgId: user.affiliatedCommunityId,
              compact: true,
            )
          else if (user.bio.isNotEmpty)
            Text(
              user.bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => AppNav.openUserProfile(context, user),
    );
  }
}
