import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      setState(() => _loading = true);
      await auth.ensureUserLoaded(widget.userId);
      if (mounted) setState(() => _loading = false);
    });
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
      final pending = me.outgoingFollowRequests
          .any((id) => auth.idsFor(target.id).contains(id));
      if (pending) {
        await auth.cancelFollowRequest(target.id);
      } else {
        await auth.requestFollow(target.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Takip isteği gönderildi')),
        );
      }
      return;
    }

    await auth.toggleFollow(target.id);
    if (!mounted) return;
    if (me.id != target.id) {
      context.read<NotificationProvider>().pushSocial(
            toUserId: target.id,
            title: 'Yeni takipçi',
            body: '${me.fullName} seni takip etmeye başladı',
            emoji: 'FOLLOW',
            type: 'follow',
            actorId: me.id,
          );
    }
  }

  String _followLabel(AuthProvider auth, AppUser target) {
    final me = auth.user;
    if (me == null || me.id == target.id) return '';
    if (auth.follows(target.id)) return 'Takipten çık';
    final pending = me.outgoingFollowRequests
        .any((id) => auth.idsFor(target.id).contains(id));
    if (pending) return 'İstek gönderildi';
    if (target.isPrivateAccount) return 'İstek gönder';
    return 'Takip et';
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final u = users[i];
        final me = auth.user;
        final isSelf = me?.id == u.id;
        final label = _followLabel(auth, u);
        return ListTile(
          leading: UserAvatar(
            name: u.fullName,
            photoUrl: u.photoUrl,
            radius: 24,
            onTap: () => context.push('/user/${u.id}'),
          ),
          title: Text(u.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(u.handle),
          trailing: isSelf || label.isEmpty
              ? null
              : OutlinedButton(
                  onPressed: () => _toggleFollow(u),
                  child: Text(label, style: const TextStyle(fontSize: 12)),
                ),
          onTap: () => context.push('/user/${u.id}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.findUser(widget.userId);
    final followers = user == null
        ? const <AppUser>[]
        : _resolve(auth, user.followers);
    final following = user == null
        ? const <AppUser>[]
        : _resolve(auth, user.following);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(user?.handle ?? 'Takip'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.navy,
          indicatorColor: AppColors.cyan,
          tabs: [
            Tab(text: 'Takipçi (${followers.length})'),
            Tab(text: 'Takip (${following.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _list(followers),
          _list(following),
        ],
      ),
    );
  }
}
