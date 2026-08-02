import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import 'follow_requests_screen.dart';

enum FollowListMode { followers, following }

class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.mode,
  });

  final String userId;
  final FollowListMode mode;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.mode == FollowListMode.following ? 1 : 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    setState(() => _loading = true);
    final user = await auth.ensureUserLoaded(widget.userId);
    if (user != null && auth.canViewPrivateContent(user)) {
      final ids = {...user.followers, ...user.following};
      for (final id in ids) {
        await auth.ensureUserLoaded(id);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<AppUser> _resolve(AuthProvider auth, List<String> ids) {
    final out = <AppUser>[];
    for (final id in ids) {
      final u = auth.findUser(id);
      if (u != null) out.add(u);
    }
    return out;
  }

  Future<void> _toggleFollow(AppUser target) async {
    if (!AuthGate.requireAuth(
      context,
      message: 'Takip için giriş yapmalısın.',
    )) {
      return;
    }
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    if (me == null || me.id == target.id) return;

    if (auth.follows(target.id)) {
      await auth.toggleFollow(target.id);
      return;
    }

    if (target.isPrivateAccount && !auth.follows(target.id)) {
      final pending = auth.hasOutgoingFollowRequest(target.id);
      if (pending) {
        await auth.cancelFollowRequest(target.id);
      } else {
        await auth.requestFollow(target.id);
        if (!mounted) return;
        context.read<NotificationProvider>().pushSocial(
              toUserId: target.id,
              title: 'Takip isteği',
              body: '${me.fullName} seni takip etmek istiyor',
              emoji: '✨',
              type: 'follow_request',
              actorId: me.id,
              targetId: me.id,
            );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Takip isteği gönderildi')),
        );
      }
      return;
    }

    await auth.toggleFollow(target.id);
    if (!mounted) return;
    context.read<NotificationProvider>().pushSocial(
          toUserId: target.id,
          title: 'Yeni takipçi',
          body: '${me.fullName} seni takip etmeye başladı',
          emoji: 'FOLLOW',
          type: 'follow',
          actorId: me.id,
          targetId: me.id,
        );
  }

  String _followLabel(AuthProvider auth, AppUser target) {
    return followActionLabel(auth, target);
  }

  Widget _list(List<AppUser> users) {
    final auth = context.watch<AuthProvider>();
    if (_loading && users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (users.isEmpty) {
      return const Center(
        child: Text(
          'Liste boş',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: users.length,
      itemBuilder: (context, i) {
        final u = users[i];
        final me = auth.user;
        final isSelf = me != null && auth.idsFor(u.id).contains(me.id);
        final label = _followLabel(auth, u);
        final following = me != null && auth.follows(u.id);
        final verified = u.showBlueBadge || u.showGoldBadge;
        final handle = MentionUtils.displayHandle(u.handle, fallback: u.fullName);

        return InkWell(
          onTap: () => context.push('/user/${u.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                UserAvatar(
                  name: u.fullName,
                  photoUrl: u.photoUrl,
                  radius: 24,
                  onTap: () => context.push('/user/${u.id}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              handle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 4),
                            VerifiedBadge(gold: u.showGoldBadge, size: 15),
                          ],
                          if (u.isCampusAmbassador) ...[
                            const SizedBox(width: 4),
                            const CampusAmbassadorBadge(size: 15),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        u.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isSelf && label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: following
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.navy,
                              side: const BorderSide(color: AppColors.border),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _toggleFollow(u),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: AppColors.navy,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _toggleFollow(u),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.findUser(widget.userId);
    final canSee = user == null || auth.canViewPrivateContent(user);
    final followers = !canSee || user == null
        ? const <AppUser>[]
        : _resolve(auth, user.followers);
    final following = !canSee || user == null
        ? const <AppUser>[]
        : _resolve(auth, user.following);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          MentionUtils.displayHandle(
            user?.handle ?? '',
            fallback: user?.fullName ?? 'Takip',
          ),
        ),
        bottom: canSee
            ? TabBar(
                controller: _tabs,
                labelColor: AppColors.navy,
                indicatorColor: AppColors.cyan,
                tabs: [
                  Tab(text: 'Takipçi (${followers.length})'),
                  Tab(text: 'Takip (${following.length})'),
                ],
              )
            : null,
      ),
      body: !canSee
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'Bu hesap gizli',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Takipçi ve takip listelerini görmek için önce takip isteğinin kabul edilmesi gerekir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _list(followers),
                _list(following),
              ],
            ),
    );
  }
}
