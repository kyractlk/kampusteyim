import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';

/// Instagram tarzı gelen takip istekleri — kabul / sil.
class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final ids = List<String>.from(auth.user?.incomingFollowRequests ?? const []);
    for (final id in ids) {
      await auth.ensureUserLoaded(id);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _accept(AppUser requester) async {
    if (_busy.contains(requester.id)) return;
    setState(() => _busy.add(requester.id));
    final auth = context.read<AuthProvider>();
    final me = auth.user;
    final ok = await auth.acceptFollowRequest(requester.id);
    if (!mounted) return;
    if (ok && me != null) {
      context.read<NotificationProvider>().pushSocial(
            toUserId: requester.id,
            title: 'İstek kabul edildi',
            body: '${me.fullName} takip isteğini kabul etti',
            emoji: '✨',
            type: 'follow_accepted',
            actorId: me.id,
            targetId: me.id,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${requester.fullName} artık seni takip ediyor')),
      );
    }
    setState(() => _busy.remove(requester.id));
  }

  Future<void> _reject(AppUser requester) async {
    if (_busy.contains(requester.id)) return;
    setState(() => _busy.add(requester.id));
    await context.read<AuthProvider>().rejectFollowRequest(requester.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İstek silindi')),
    );
    setState(() => _busy.remove(requester.id));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pendingIds = auth.user?.incomingFollowRequests ?? const <String>[];
    final users = <AppUser>[];
    for (final id in pendingIds) {
      final u = auth.findUser(id);
      if (u != null) {
        users.add(u);
      } else {
        users.add(
          AppUser(
            id: id,
            email: '',
            studentNo: '',
            firstName: 'Kullanıcı',
            lastName: '',
            phone: '',
            city: '',
            university: '',
            username: id,
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gelen istekler')),
      body: _loading && users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : users.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Bekleyen takip isteği yok.',
                      style: TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = users[i];
                    final busy = _busy.contains(u.id);
                    final handle = MentionUtils.displayHandle(
                      u.handle,
                      fallback: u.fullName,
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          UserAvatar(
                            name: u.fullName,
                            photoUrl: u.communityLogoUrl ?? u.photoUrl,
                            radius: 26,
                            isCommunity: u.isCommunity,
                            onTap: () => context.push('/user/${u.id}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => context.push('/user/${u.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    handle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
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
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Seni takip etmek istiyor',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (busy)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else ...[
                            FilledButton(
                              onPressed: () => _accept(u),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 34),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Kabul'),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () => _reject(u),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 34),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Sil'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// Profil / listelerde ortak takip butonu metni.
String followActionLabel(
  AuthProvider auth,
  AppUser target, {
  bool compact = false,
}) {
  final me = auth.user;
  if (me == null || auth.idsFor(target.id).contains(me.id)) return '';
  if (auth.follows(target.id)) {
    return compact ? 'Takip' : 'Takip ediliyor';
  }
  if (auth.hasOutgoingFollowRequest(target.id)) {
    return compact ? 'İstek' : 'İstek gönderildi';
  }
  if (auth.isFollowedBy(target.id)) {
    return compact ? 'Geri takip' : 'Sen de onu takip et';
  }
  if (target.isPrivateAccount) {
    return compact ? 'İstek' : 'İstek gönder';
  }
  return 'Takip et';
}
