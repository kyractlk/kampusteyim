import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import '../moderation/moderation_models.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';

/// Filtre + arama ile kullanıcı yönetimi.
class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({
    super.key,
    required this.auth,
    required this.admin,
    required this.me,
    required this.onUserAction,
  });

  final AuthProvider auth;
  final AdminProvider admin;
  final AppUser me;
  final Future<void> Function(BuildContext context, AppUser u, String action)
      onUserAction;

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final _q = TextEditingController();
  String _role = 'all';
  bool _syncing = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _refreshUsers() async {
    setState(() => _syncing = true);
    final n = await widget.auth.syncDirectoryFromFirestore();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$n kullanıcı Firestore’dan yüklendi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    var users = widget.auth.directory.toList();
    if (_role != 'all') {
      users = users.where((u) => u.role.name == _role).toList();
    }
    if (q.isNotEmpty) {
      users = users.where((u) {
        return u.fullName.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.handle.toLowerCase().contains(q) ||
            u.studentNo.contains(q);
      }).toList();
    }
    users.sort((a, b) => a.fullName.compareTo(b.fullName));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _q,
                      decoration: InputDecoration(
                        hintText: 'İsim, e-posta, @handle ara…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: q.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _q.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Firestore’dan yenile',
                    onPressed: _syncing ? null : _refreshUsers,
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in [
                      ('all', 'Tümü'),
                      ('student', 'Öğrenci'),
                      ('community', 'Topluluk'),
                      ('company', 'Firma'),
                      ('admin', 'Admin'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(e.$2),
                          selected: _role == e.$1,
                          onSelected: (_) => setState(() => _role = e.$1),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${users.length} / ${widget.auth.directory.length} profil',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final u = users[i];
              final staffRole = widget.admin.roleById(u.staffRoleId);
              return Material(
                color: AppColors.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  leading: UserAvatar(
                    name: u.fullName,
                    photoUrl: u.communityLogoUrl ?? u.photoUrl,
                    isCommunity: u.isCommunity,
                    radius: 24,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          u.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (u.showGoldBadge) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(gold: true, size: 15),
                      ] else if (u.showBlueBadge) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(gold: false, size: 15),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${u.email}\n${u.role.name}'
                    '${staffRole != null ? ' · ${staffRole.name}' : ''}'
                    '${u.restrictionActive ? ' · kısıtlı' : ''}',
                  ),
                  isThreeLine: true,
                  onTap: () => AppNav.openUserProfile(context, u),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) =>
                        widget.onUserAction(context, u, v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'profile', child: Text('Profili aç')),
                      if (widget.admin
                          .can(widget.me, AdminPermission.resetPassword))
                        const PopupMenuItem(
                            value: 'reset', child: Text('Şifre sıfırla')),
                      if (widget.admin
                          .can(widget.me, AdminPermission.manageBadges)) ...[
                        PopupMenuItem(
                          value: u.isCommunity ? 'ungold' : 'gold',
                          child: Text(u.isCommunity
                              ? 'Topluluk badge kaldır'
                              : 'Topluluk badge ver'),
                        ),
                        if (!u.isCommunity) ...[
                          const PopupMenuItem(
                              value: 'blue',
                              child: Text('Kuruma bağla (mavi tick)')),
                          const PopupMenuItem(
                              value: 'gold_affil',
                              child: Text('Gold tick + kuruma bağla')),
                          const PopupMenuItem(
                              value: 'unblue',
                              child: Text('Kurum ilişkisini kaldır')),
                        ],
                      ],
                      if (widget.admin
                          .can(widget.me, AdminPermission.restrictUsers)) ...[
                        const PopupMenuItem(
                            value: 'warn', child: Text('Uyarı gönder')),
                        const PopupMenuItem(
                            value: 'mute',
                            child: Text('24 saat sustur')),
                        const PopupMenuItem(
                            value: 'postban7',
                            child: Text('1 hafta paylaşım yasağı')),
                        const PopupMenuItem(
                            value: 'fullban',
                            child: Text('Hesabı askıya al')),
                        const PopupMenuItem(
                            value: 'lift',
                            child: Text('Kısıtlamayı kaldır')),
                      ],
                      if (widget.admin
                              .can(widget.me, AdminPermission.manageAdmins) &&
                          !u.isCommunity &&
                          u.role != UserRole.company)
                        const PopupMenuItem(
                            value: 'make_admin',
                            child: Text('Admin yap / rol ata')),
                      if (widget.admin
                              .can(widget.me, AdminPermission.manageUsers) &&
                          !u.isSuperAdmin)
                        const PopupMenuItem(
                          value: 'delete_account',
                          child: Text('Hesabı sil'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({
    super.key,
    required this.admin,
    required this.auth,
  });

  final AdminProvider admin;
  final AuthProvider auth;

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  String _status = 'open';
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _statusLabel(ReportStatus s) => switch (s) {
        ReportStatus.open => 'Açık',
        ReportStatus.reviewing => 'İncelemede',
        ReportStatus.resolved => 'Çözüldü',
        ReportStatus.dismissed => 'Red',
      };

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    var list = List<ContentReport>.from(widget.admin.reports);
    if (_status != 'all') {
      list = list.where((r) => r.status.name == _status).toList();
    }
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        return r.reason.toLowerCase().contains(q) ||
            r.details.toLowerCase().contains(q) ||
            r.snapshotBody.toLowerCase().contains(q) ||
            r.snapshotAuthor.toLowerCase().contains(q) ||
            r.targetId.toLowerCase().contains(q);
      }).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _q,
                decoration: const InputDecoration(
                  hintText: 'Şikayet / içerik ara…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('filter_$_status'),
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Durum filtresi',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Açık')),
                  DropdownMenuItem(
                      value: 'reviewing', child: Text('İncelemede')),
                  DropdownMenuItem(value: 'resolved', child: Text('Çözüldü')),
                  DropdownMenuItem(value: 'dismissed', child: Text('Red')),
                  DropdownMenuItem(value: 'all', child: Text('Tümü')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _status = v);
                },
              ),
              const SizedBox(height: 6),
              Text(
                '${list.length} şikayet · tek tek açıp inceleyin',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Şikayet yok'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    ExpansionPanelList.radio(
                      key: ValueKey('reports_panel_$_status'),
                      elevation: 0,
                      expandedHeaderPadding: EdgeInsets.zero,
                      children: [
                        for (final r in list)
                          ExpansionPanelRadio(
                            value: r.id,
                            canTapOnHeader: true,
                            backgroundColor: AppColors.surface,
                            headerBuilder: (context, isExpanded) {
                              final deleted = r.targetType ==
                                      ReportTargetType.post &&
                                  feed
                                          .postByIdIncludingDeleted(r.targetId)
                                          ?.isDeleted ==
                                      true;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: Icon(
                                  Icons.report_outlined,
                                  color: r.status == ReportStatus.open
                                      ? AppColors.crimson
                                      : AppColors.textSecondary,
                                ),
                                title: Text(
                                  r.reason,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${r.targetType.name.toUpperCase()} · ${_statusLabel(r.status)}'
                                  '${deleted ? ' · SİLİNMİŞ' : ''}'
                                  ' · ${DateFormat('d MMM HH:mm', 'tr').format(r.createdAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Hızlı işlem',
                                  onSelected: (v) =>
                                      _quickAction(context, feed, r, v),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'review',
                                        child: Text('İncelemeye al')),
                                    PopupMenuItem(
                                        value: 'resolve',
                                        child: Text('Çözüldü')),
                                    PopupMenuItem(
                                        value: 'dismiss',
                                        child: Text('Reddet')),
                                  ],
                                ),
                              );
                            },
                            body: _ReportDetailBody(
                              report: r,
                              auth: widget.auth,
                              admin: widget.admin,
                              feed: feed,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _quickAction(
    BuildContext context,
    FeedProvider feed,
    ContentReport r,
    String v,
  ) async {
    switch (v) {
      case 'review':
        widget.admin.resolveReport(r.id, ReportStatus.reviewing);
      case 'resolve':
        widget.admin.resolveReport(r.id, ReportStatus.resolved);
      case 'dismiss':
        widget.admin.resolveReport(r.id, ReportStatus.dismissed);
    }
  }
}

class _ReportDetailBody extends StatelessWidget {
  const _ReportDetailBody({
    required this.report,
    required this.auth,
    required this.admin,
    required this.feed,
  });

  final ContentReport report;
  final AuthProvider auth;
  final AdminProvider admin;
  final FeedProvider feed;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final post = r.targetType == ReportTargetType.post
        ? feed.postByIdIncludingDeleted(r.targetId)
        : null;
    final owner = r.targetOwnerId != null
        ? auth.findUser(r.targetOwnerId!)
        : null;
    final deleted = post?.isDeleted == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.details.isNotEmpty)
            Text(r.details, style: const TextStyle(height: 1.4)),
          if (r.aiSummary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.aiActed
                        ? 'AI aksiyon aldı · ${r.aiDecision}'
                        : 'AI admin’e bıraktı · ${r.aiDecision}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(r.aiSummary),
                  if (r.aiAdminNote.isNotEmpty)
                    Text(
                      'Not: ${r.aiAdminNote}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: deleted
                  ? Border.all(
                      color: AppColors.crimson.withValues(alpha: 0.35),
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.snapshotAuthor.isNotEmpty
                      ? r.snapshotAuthor
                      : (owner?.fullName ?? 'Hedef'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  r.snapshotBody.isNotEmpty
                      ? r.snapshotBody
                      : (post?.content ?? '(anlık görüntü yok)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('status_${r.id}_${r.status.name}'),
            initialValue: r.status.name,
            decoration: const InputDecoration(
              labelText: 'Durum',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'open', child: Text('Açık')),
              DropdownMenuItem(value: 'reviewing', child: Text('İncelemede')),
              DropdownMenuItem(value: 'resolved', child: Text('Çözüldü')),
              DropdownMenuItem(value: 'dismissed', child: Text('Red')),
            ],
            onChanged: (v) {
              if (v == null) return;
              final next = ReportStatus.values.firstWhere(
                (e) => e.name == v,
                orElse: () => r.status,
              );
              admin.resolveReport(r.id, next);
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (r.targetType == ReportTargetType.post)
                OutlinedButton.icon(
                  onPressed: () async {
                    await feed.ensurePostLoaded(r.targetId);
                    if (!context.mounted) return;
                    context.push('/post/${r.targetId}');
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Postu aç'),
                ),
              if (owner != null || r.targetOwnerId != null)
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/user/${owner?.id ?? r.targetOwnerId}',
                  ),
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('Profil'),
                ),
              if (r.snapshotUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: r.snapshotUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link kopyalandı')),
                    );
                  },
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Link'),
                ),
              if (post != null && !post.isDeleted)
                OutlinedButton.icon(
                  onPressed: () => feed.softDeletePost(
                    post.id,
                    byUserId: auth.user?.id ?? 'admin',
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Postu sil'),
                ),
              if (post != null && post.isDeleted)
                OutlinedButton.icon(
                  onPressed: () => feed.restorePost(post.id),
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Geri al'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminPostsTab extends StatefulWidget {
  const AdminPostsTab({super.key});

  @override
  State<AdminPostsTab> createState() => _AdminPostsTabState();
}

class _AdminPostsTabState extends State<AdminPostsTab> {
  final _q = TextEditingController();
  bool _showDeleted = true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final auth = context.watch<AuthProvider>();
    var posts = feed.allPostsAdmin;
    if (!_showDeleted) {
      posts = posts.where((p) => !p.isDeleted).toList();
    }
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      posts = posts.where((p) {
        return p.content.toLowerCase().contains(q) ||
            p.authorName.toLowerCase().contains(q) ||
            p.id.toLowerCase().contains(q) ||
            p.hashtags.any((h) => h.toLowerCase().contains(q));
      }).toList();
    }

    final width = MediaQuery.sizeOf(context).width;
    final maxCard = width >= 1100 ? 720.0 : double.infinity;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _q,
                decoration: const InputDecoration(
                  hintText: 'Gönderi / yazar / #etiket ara…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Silinmişleri göster'),
                value: _showDeleted,
                onChanged: (v) => setState(() => _showDeleted = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: posts.isEmpty
              ? const Center(child: Text('Paylaşım yok'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final p = posts[i];
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxCard),
                        child: _AdminPostCard(
                          post: p,
                          feed: feed,
                          auth: auth,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AdminPostCard extends StatelessWidget {
  const _AdminPostCard({
    required this.post,
    required this.feed,
    required this.auth,
  });

  final Post post;
  final FeedProvider feed;
  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    final p = post;
    final images = p.media.where((m) => m.type == MediaType.image).toList();
    final videos = p.media.where((m) => m.type == MediaType.video).toList();

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: p.isDeleted
              ? AppColors.crimson.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/post/${p.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    name: p.authorName,
                    isCommunity: p.isCommunity,
                    radius: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.authorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (p.isDeleted) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'SİLİNDİ',
                                style: TextStyle(
                                  color: AppColors.crimson,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          DateFormat('d MMM yyyy · HH:mm', 'tr')
                              .format(p.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'open':
                          context.push('/post/${p.id}');
                        case 'copy':
                          await Clipboard.setData(
                            ClipboardData(text: p.permalink),
                          );
                        case 'share':
                          await AppShare.sharePost(
                            context: context,
                            id: p.id,
                            authorName: p.authorName,
                            content: p.content,
                          );
                        case 'soft':
                          await feed.softDeletePost(
                            p.id,
                            byUserId: auth.user?.id ?? 'admin',
                          );
                        case 'restore':
                          await feed.restorePost(p.id);
                        case 'hard':
                          await feed.hardDeletePost(p.id);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('Aç')),
                      const PopupMenuItem(
                          value: 'copy', child: Text('Link kopyala')),
                      const PopupMenuItem(
                          value: 'share', child: Text('Paylaş')),
                      if (!p.isDeleted)
                        const PopupMenuItem(
                            value: 'soft', child: Text('Soft sil')),
                      if (p.isDeleted)
                        const PopupMenuItem(
                            value: 'restore', child: Text('Geri al')),
                      const PopupMenuItem(
                          value: 'hard', child: Text('Kalıcı sil')),
                    ],
                  ),
                ],
              ),
            ),
            if (p.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  p.content,
                  style: const TextStyle(height: 1.45, fontSize: 14.5),
                ),
              ),
            if (images.isNotEmpty)
              _AdminMediaGrid(urls: images.map((e) => e.url).toList()),
            if (videos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < videos.length; i++)
                      Chip(
                        avatar: const Icon(Icons.videocam_outlined, size: 16),
                        label: Text(
                          videos.length == 1 ? 'Video' : 'Video ${i + 1}',
                          style: TextStyle(
                            color: AppColors.navy.withValues(alpha: 0.8),
                          ),
                        ),
                        side: const BorderSide(color: AppColors.border),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                '${p.likeCount} beğeni · ${p.replyCount} yorum · ${p.permalink}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMediaGrid extends StatelessWidget {
  const _AdminMediaGrid({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (urls.length == 1) {
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: SafeNetworkImage(url: urls.first, fit: BoxFit.cover),
      );
    }
    final show = urls.take(4).toList();
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (var i = 0; i < show.length; i++)
            Stack(
              fit: StackFit.expand,
              children: [
                SafeNetworkImage(url: show[i], fit: BoxFit.cover),
                if (i == 3 && urls.length > 4)
                  ColoredBox(
                    color: Colors.black45,
                    child: Center(
                      child: Text(
                        '+${urls.length - 4}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

