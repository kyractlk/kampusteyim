import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../maintenance/maintenance_provider.dart';
import '../moderation/moderation_models.dart';
import '../notifications/notification_provider.dart';
import 'admin_content_tabs.dart';
import 'admin_feedback_tab.dart';
import 'admin_legal_tab.dart';
import 'admin_maintenance_tab.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';
import 'admin_registrations_tab.dart';
import 'admin_study_rooms_tab.dart';

class _AdminTab {
  const _AdminTab({
    required this.label,
    required this.icon,
    required this.builder,
    required this.required,
  });

  final String label;
  final Widget icon;
  final Widget Function() builder;
  final List<AdminPermission> required;
}

/// Ana admin paneli — RBAC ile sekme ve aksiyon kilidi.
class AdminPortalScreen extends StatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  State<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends State<AdminPortalScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final admin = context.read<AdminProvider>();
      await auth.syncDirectoryFromFirestore();
      await admin.loadReportsFromFirestore();
      admin.resyncSystemRoles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final admin = context.watch<AdminProvider>();
    final me = auth.user;

    if (me == null) {
      return const _AdminGateLogin();
    }
    if (!me.canAccessAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MtIcon(MtIcons.admin, size: 48, color: AppColors.navy),
                const SizedBox(height: 12),
                const Text(
                  'Bu hesap admin / personel yetkisine sahip değil.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await auth.signOut();
                    if (context.mounted) setState(() {});
                  },
                  child: const Text('Çıkış yap'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final myRole = admin.roleById(me.staffRoleId);
    final tabs = <_AdminTab>[
      if (admin.can(me, AdminPermission.manageUsers))
        _AdminTab(
          label: 'Kullanıcılar',
          icon: const MtIcon(MtIcons.follow, size: 22),
          required: const [AdminPermission.manageUsers],
          builder: () => AdminUsersTab(
            auth: auth,
            admin: admin,
            me: me,
            onUserAction: _handleUserAction,
          ),
        ),
      if (admin.can(me, AdminPermission.manageUsers))
        _AdminTab(
          label: 'Kayıtlar',
          icon: const Icon(Icons.how_to_reg_outlined),
          required: const [AdminPermission.manageUsers],
          builder: () => const AdminRegistrationsTab(),
        ),
      if (admin.can(me, AdminPermission.reviewReports))
        _AdminTab(
          label: 'Şikayetler',
          icon: const MtIcon(MtIcons.report, size: 22),
          required: const [AdminPermission.reviewReports],
          builder: () => AdminReportsTab(admin: admin, auth: auth),
        ),
      if (admin.can(me, AdminPermission.viewPosts))
        _AdminTab(
          label: 'Paylaşımlar',
          icon: const MtIcon(MtIcons.comment, size: 22),
          required: const [AdminPermission.viewPosts],
          builder: () => const AdminPostsTab(),
        ),
      if (admin.canAny(me, [
        AdminPermission.createCompany,
        AdminPermission.createCommunity,
      ]))
        _AdminTab(
          label: 'Hesap aç',
          icon: const MtIcon(MtIcons.community, size: 22),
          required: const [
            AdminPermission.createCompany,
            AdminPermission.createCommunity,
          ],
          builder: () => _CreateAccountsTab(auth: auth, admin: admin, me: me),
        ),
      if (admin.can(me, AdminPermission.manageRoles))
        _AdminTab(
          label: 'Roller',
          icon: const MtIcon(MtIcons.admin, size: 22),
          required: const [AdminPermission.manageRoles],
          builder: () => _RolesTab(admin: admin, auth: auth, me: me),
        ),
      if (admin.can(me, AdminPermission.manageAdmins))
        _AdminTab(
          label: 'Adminler',
          icon: const Icon(Icons.badge_outlined, size: 22),
          required: const [AdminPermission.manageAdmins],
          builder: () => _StaffTab(auth: auth, admin: admin, me: me),
        ),
      if (admin.can(me, AdminPermission.sendBroadcast))
        _AdminTab(
          label: 'Push',
          icon: const MtIcon(MtIcons.bell, size: 22),
          required: const [AdminPermission.sendBroadcast],
          builder: () => _BroadcastTab(auth: auth, admin: admin),
        ),
      if (admin.can(me, AdminPermission.manageMaintenance))
        _AdminTab(
          label: 'Bakım',
          icon: const Icon(Icons.construction_outlined, size: 22),
          required: const [AdminPermission.manageMaintenance],
          builder: () => AdminMaintenanceTab(auth: auth, admin: admin),
        ),
      if (admin.can(me, AdminPermission.reviewFeedback))
        _AdminTab(
          label: 'Geri bildirim',
          icon: const Icon(Icons.feedback_outlined, size: 22),
          required: const [AdminPermission.reviewFeedback],
          builder: () => const AdminFeedbackTab(),
        ),
      if (admin.can(me, AdminPermission.reviewStudyRooms))
        _AdminTab(
          label: 'Çalışma odası',
          icon: const Icon(Icons.timer_outlined, size: 22),
          required: const [AdminPermission.reviewStudyRooms],
          builder: () => const AdminStudyRoomsTab(),
        ),
      if (admin.can(me, AdminPermission.manageLegalTexts))
        _AdminTab(
          label: 'KVKK',
          icon: const Icon(Icons.gavel_outlined, size: 22),
          required: const [AdminPermission.manageLegalTexts],
          builder: () => AdminLegalTab(editorName: me.fullName),
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Text('Tanımlı yetkin yok.')),
      );
    }

    final tabIndex = _tab.clamp(0, tabs.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pendingReports =
        admin.reports.where((r) => r.status == ReportStatus.open).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const AppCircleLogo(logo: AppLogo.ays, size: 34, showBorder: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Platform Admin',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    myRole?.name ??
                        (me.isSuperAdmin ? 'Süper Admin · tam yetki' : 'Personel'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${auth.directory.length} kullanıcı · $pendingReports açık şikayet',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          if (admin.status != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    admin.status!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Ana uygulama',
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  backgroundColor: AppColors.surface,
                  selectedIndex: tabIndex,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: AppColors.cyan.withValues(alpha: 0.18),
                  selectedIconTheme:
                      const IconThemeData(color: AppColors.navy),
                  unselectedIconTheme:
                      const IconThemeData(color: AppColors.textSecondary),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    color: AppColors.textSecondary,
                  ),
                  destinations: [
                    for (final t in tabs)
                      NavigationRailDestination(
                        icon: t.icon,
                        label: Text(t.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: tabs[tabIndex].builder()),
              ],
            )
          : tabs[tabIndex].builder(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tabIndex,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final t in tabs)
                  NavigationDestination(icon: t.icon, label: t.label),
              ],
            ),
    );
  }

  Future<void> _handleUserAction(
    BuildContext context,
    AppUser u,
    String v,
  ) async {
    final auth = context.read<AuthProvider>();
    final admin = context.read<AdminProvider>();
    final notif = context.read<NotificationProvider>();
    switch (v) {
      case 'reset':
        await admin.sendPasswordReset(email: u.email);
      case 'gold':
        await admin.setCommunityBadge(auth: auth, userId: u.id, enabled: true);
      case 'ungold':
        await admin.setCommunityBadge(auth: auth, userId: u.id, enabled: false);
      case 'blue':
        final orgs = admin.organizations(auth);
        if (orgs.isEmpty) return;
        final pick = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Kurum seç (ilişki)'),
            children: orgs
                .map(
                  (c) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, c.id),
                    child: Text(
                      '${c.fullName.trim().isEmpty ? c.firstName : c.fullName}'
                      '${c.isCompany ? ' · firma' : c.isCommunity ? ' · topluluk' : ''}',
                    ),
                  ),
                )
                .toList(),
          ),
        );
        if (pick != null) {
          await admin.linkToOrganization(
            auth: auth,
            userId: u.id,
            orgId: pick,
            grantBlueBadge: true,
          );
        }
      case 'gold_affil':
        final orgs = admin.organizations(auth);
        if (orgs.isEmpty) return;
        final pick = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Gold + kurum ilişkisi'),
            children: orgs
                .map(
                  (c) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, c.id),
                    child: Text(
                      c.fullName.trim().isEmpty ? c.firstName : c.fullName,
                    ),
                  ),
                )
                .toList(),
          ),
        );
        if (pick != null) {
          await admin.linkToOrganization(
            auth: auth,
            userId: u.id,
            orgId: pick,
            grantGoldBadge: true,
          );
        }
      case 'unblue':
        await admin.unlinkCommunity(auth: auth, userId: u.id);
      case 'warn':
        await admin.applyRestriction(
          auth: auth,
          notifications: notif,
          userId: u.id,
          type: 'warn',
          reason: 'Admin / Guard: resmi uyarı',
          duration: const Duration(days: 30),
        );
      case 'mute':
        await admin.applyRestriction(
          auth: auth,
          notifications: notif,
          userId: u.id,
          type: 'mute',
          reason: 'Admin / Guard: 24 saat susturma',
          duration: const Duration(hours: 24),
        );
      case 'postban7':
      case 'restrict':
        await admin.applyRestriction(
          auth: auth,
          notifications: notif,
          userId: u.id,
          type: 'postBan',
          reason: 'Admin: 1 hafta paylaşım yasağı',
          duration: const Duration(days: 7),
        );
      case 'fullban':
        await admin.applyRestriction(
          auth: auth,
          notifications: notif,
          userId: u.id,
          type: 'fullBan',
          reason: 'Admin: hesap askıya alındı',
        );
      case 'lift':
        await admin.applyRestriction(
          auth: auth,
          notifications: notif,
          userId: u.id,
          type: 'none',
          reason: '',
        );
      case 'make_admin':
        final roleId = await _pickRole(context, admin);
        if (roleId != null) {
          await admin.assignStaffRole(
            auth: auth,
            userId: u.id,
            roleId: roleId,
          );
        }
      case 'delete_account':
        final confirm1 = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hesabı sil?'),
            content: Text(
              '${u.fullName} (${u.email}) kalıcı olarak silinecek.\n\n'
              'Bu işlem geri alınamaz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Devam'),
              ),
            ],
          ),
        );
        if (confirm1 != true || !context.mounted) return;
        final confirm2 = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Son onay'),
            content: Text('“${u.fullName}” hesabını silmek istediğine emin misin?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.crimson),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hesabı sil'),
              ),
            ],
          ),
        );
        if (confirm2 != true || !context.mounted) return;
        try {
          final callable =
              FirebaseFunctions.instanceFor(region: 'europe-west1')
                  .httpsCallable('adminDeleteAccount');
          await callable.call({'uid': u.id, 'email': u.email});
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${u.fullName} silindi')),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silinemedi: $e')),
          );
        }
      case 'profile':
        if (context.mounted) context.push('/user/${u.id}');
    }
  }
}

Future<String?> _pickRole(BuildContext context, AdminProvider admin) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Rol seç'),
      children: admin.roles
          .where((r) => !r.isSuper)
          .map(
            (r) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${r.permissions.length} yetki · ${r.description}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

// ─── Hesap aç / Roller / Push ───

class _CreateAccountsTab extends StatefulWidget {
  const _CreateAccountsTab({
    required this.auth,
    required this.admin,
    required this.me,
  });
  final AuthProvider auth;
  final AdminProvider admin;
  final AppUser me;

  @override
  State<_CreateAccountsTab> createState() => _CreateAccountsTabState();
}

class _CreateAccountsTabState extends State<_CreateAccountsTab> {
  final _companyName = TextEditingController();
  final _companyEmail = TextEditingController();
  final _companyPass = TextEditingController();
  final _commName = TextEditingController();
  final _commEmail = TextEditingController();
  final _commPass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _companyName.dispose();
    _companyEmail.dispose();
    _companyPass.dispose();
    _commName.dispose();
    _commEmail.dispose();
    _commPass.dispose();
    super.dispose();
  }

  Future<void> _showCreds({
    required String title,
    required String email,
    required String password,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(
          'E-posta: $email\nGeçici şifre: $password\n\n'
          'Bu şifreyi ilgili kişiye güvenli kanaldan ilet. '
          'İlk girişten sonra değiştirilmesini öner.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCompany =
        widget.admin.can(widget.me, AdminPermission.createCompany);
    final canCommunity =
        widget.admin.can(widget.me, AdminPermission.createCommunity);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const AppCircleLogo(logo: AppLogo.ays, size: 56),
        const SizedBox(height: 8),
        Text(
          'Firma ve topluluk hesapları Firebase Auth + profil olarak açılır. '
          'Boş bırakırsan geçici şifre otomatik üretilir.',
          style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.95)),
        ),
        if (canCompany) ...[
          const SizedBox(height: 20),
          Text('Firma hesabı',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _companyName,
            decoration: const InputDecoration(
              labelText: 'Firma adı',
              hintText: 'Örn. AYS Tech',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _companyEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Firma e-posta'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _companyPass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Şifre (opsiyonel)',
              hintText: 'Boş = otomatik',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_companyName.text.trim().isEmpty ||
                        _companyEmail.text.trim().isEmpty) {
                      return;
                    }
                    setState(() => _busy = true);
                    final manual = _companyPass.text.trim();
                    final result = await widget.admin.createManagedAccount(
                      auth: widget.auth,
                      displayName: _companyName.text,
                      email: _companyEmail.text,
                      kind: 'company',
                      password: manual.length >= 6 ? manual : null,
                    );
                    final pass = result.password;
                    setState(() => _busy = false);
                    _companyName.clear();
                    _companyEmail.clear();
                    _companyPass.clear();
                    await _showCreds(
                      title: 'Firma hesabı hazır',
                      email: result.user.email,
                      password: pass,
                    );
                  },
            child: Text(_busy ? 'Oluşturuluyor…' : 'Firma hesabı aç'),
          ),
        ],
        if (canCommunity) ...[
          const Divider(height: 36),
          Text('Topluluk hesabı',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _commName,
            decoration: const InputDecoration(
              labelText: 'Topluluk adı',
              hintText: 'Örn. Mühendislik Topluluğu',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Topluluk e-posta'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commPass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Şifre (opsiyonel)',
              hintText: 'Boş = otomatik',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_commName.text.trim().isEmpty ||
                        _commEmail.text.trim().isEmpty) {
                      return;
                    }
                    setState(() => _busy = true);
                    final manual = _commPass.text.trim();
                    final result = await widget.admin.createManagedAccount(
                      auth: widget.auth,
                      displayName: _commName.text,
                      email: _commEmail.text,
                      kind: 'community',
                      password: manual.length >= 6 ? manual : null,
                    );
                    final pass = result.password;
                    setState(() => _busy = false);
                    _commName.clear();
                    _commEmail.clear();
                    _commPass.clear();
                    await _showCreds(
                      title: 'Topluluk hesabı hazır',
                      email: result.user.email,
                      password: pass,
                    );
                  },
            child: Text(_busy ? 'Oluşturuluyor…' : 'Topluluk hesabı aç'),
          ),
        ],
      ],
    );
  }
}

// ─── Roller ───

class _RolesTab extends StatelessWidget {
  const _RolesTab({
    required this.admin,
    required this.auth,
    required this.me,
  });
  final AdminProvider admin;
  final AuthProvider auth;
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final catalogCount = AdminPermission.values.length;
    final groups = AdminPermission.byGroup;
    final roles = admin.roles;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Roller & yetkiler',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (admin.rolesLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$catalogCount izin · ${groups.length} grup · ${roles.length} rol\n'
          'Bakım erişimi, akış moderasyonu ve hesap açma yetkileri rollerden yönetilir. '
          'Değişiklikler Firestore’a kaydedilir.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in groups.entries)
              Chip(
                label: Text('${e.key} (${e.value.length})'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              admin.resyncSystemRoles();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(admin.status ?? 'Roller senkronlandı')),
              );
            },
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Sistem rollerini güncelle'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _openEditor(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Yeni rol'),
        ),
        const SizedBox(height: 16),
        ...admin.roles.map((role) {
          final perms = role.isSuper
              ? AdminPermission.values.toSet()
              : role.permissions;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: role.isSuper
                      ? AppColors.gold.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: ExpansionTile(
                initiallyExpanded: false,
                title: Text(
                  role.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${perms.length}/$catalogCount izin'
                  '${role.isSystem ? ' · sistem' : ''}'
                  '${role.isSuper ? ' · süper' : ''}\n${role.description}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final entry in groups.entries) ...[
                    Builder(
                      builder: (_) {
                        final inGroup =
                            entry.value.where(perms.contains).toList();
                        if (inGroup.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final p in inGroup)
                                    Chip(
                                      label: Text(
                                        p.label,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  Row(
                    children: [
                      if (!role.isSuper)
                        TextButton(
                          onPressed: () =>
                              _openEditor(context, existing: role),
                          child: const Text('İzinleri düzenle'),
                        ),
                      if (!role.isSystem && !role.isSuper)
                        TextButton(
                          onPressed: () {
                            admin.deleteRole(role.id, auth);
                          },
                          child: const Text(
                            'Sil',
                            style: TextStyle(color: AppColors.crimson),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {StaffRole? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final selected = <AdminPermission>{
      ...(existing?.permissions ?? {}),
    };

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        existing == null ? 'Yeni rol' : 'Rol izinlerini düzenle',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Rol adı'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Açıklama'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'İzinler',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setLocal(
                              () => selected.addAll(AdminPermission.values),
                            ),
                            child: const Text('Tümü'),
                          ),
                          TextButton(
                            onPressed: () => setLocal(selected.clear),
                            child: const Text('Temizle'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final entry
                                in AdminPermission.byGroup.entries) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        style: const TextStyle(
                                          color: AppColors.cyan,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => setLocal(
                                        () => selected.addAll(entry.value),
                                      ),
                                      child: const Text('Grup'),
                                    ),
                                  ],
                                ),
                              ),
                              ...entry.value.map(
                                (p) => CheckboxListTile(
                                  dense: true,
                                  value: selected.contains(p),
                                  title: Text(p.label),
                                  subtitle: Text(
                                    p.key,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onChanged: (v) {
                                    setLocal(() {
                                      if (v == true) {
                                        selected.add(p);
                                      } else {
                                        selected.remove(p);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${selected.length} izin seçili',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Vazgeç'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              if (nameCtrl.text.trim().isEmpty ||
                                  selected.isEmpty) {
                                return;
                              }
                              Navigator.pop(ctx, true);
                            },
                            child: const Text('Kaydet'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (saved == true) {
      if (existing == null) {
        admin.createRole(
          name: nameCtrl.text,
          description: descCtrl.text,
          permissions: selected,
        );
      } else {
        admin.updateRole(
          roleId: existing.id,
          name: nameCtrl.text,
          description: descCtrl.text,
          permissions: selected,
        );
      }
    }
    nameCtrl.dispose();
    descCtrl.dispose();
  }
}

// ─── Adminler ───

class _StaffTab extends StatefulWidget {
  const _StaffTab({
    required this.auth,
    required this.admin,
    required this.me,
  });
  final AuthProvider auth;
  final AdminProvider admin;
  final AppUser me;

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  String? _roleId;

  @override
  void initState() {
    super.initState();
    final list = widget.admin.roles.where((r) => !r.isSuper).toList();
    _roleId = list.isEmpty ? null : list.first.id;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.admin.staffMembers(widget.auth);
    final assignable =
        widget.admin.roles.where((r) => !r.isSuper).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Yeni admin ekle',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _first,
          decoration: const InputDecoration(labelText: 'Ad'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _last,
          decoration: const InputDecoration(labelText: 'Soyad'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'E-posta'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _roleId,
          decoration: const InputDecoration(labelText: 'Rol'),
          items: assignable
              .map(
                (r) => DropdownMenuItem(
                  value: r.id,
                  child: Text('${r.name} (${r.permissions.length} yetki)'),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _roleId = v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            if (_first.text.trim().isEmpty ||
                _email.text.trim().isEmpty ||
                _roleId == null) {
              return;
            }
            await widget.admin.createAdminAccount(
              auth: widget.auth,
              firstName: _first.text,
              lastName: _last.text,
              email: _email.text,
              roleId: _roleId!,
            );
            _first.clear();
            _last.clear();
            _email.clear();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.admin.status ?? 'Oluşturuldu')),
              );
            }
          },
          icon: const MtIcon(MtIcons.admin, size: 18, color: Colors.white),
          label: const Text('Admin oluştur ve rol ata'),
        ),
        const Divider(height: 36),
        Text(
          'Mevcut adminler (${staff.length})',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...staff.map((u) {
          final role = widget.admin.roleById(u.staffRoleId);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(u.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${u.email}\n${role?.name ?? 'rol yok'}'
                '${u.isSuperAdmin ? ' · süper' : ''}',
              ),
              isThreeLine: true,
              trailing: u.isSuperAdmin
                  ? const Chip(label: Text('Süper'))
                  : PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'revoke') {
                          await widget.admin.revokeStaffAccess(
                            auth: widget.auth,
                            userId: u.id,
                          );
                        } else if (v == 'role') {
                          final id = await _pickRole(context, widget.admin);
                          if (id != null) {
                            await widget.admin.assignStaffRole(
                              auth: widget.auth,
                              userId: u.id,
                              roleId: id,
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'role', child: Text('Rol değiştir')),
                        PopupMenuItem(
                            value: 'revoke', child: Text('Adminliği kaldır')),
                      ],
                    ),
            ),
          );
        }),
      ],
    );
  }
}

// ─── Push yayın ───

class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab({required this.auth, required this.admin});
  final AuthProvider auth;
  final AdminProvider admin;

  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _userQ = TextEditingController();
  bool _toAll = true;
  bool _alsoMail = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _userQ.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final q = _userQ.text.trim().toLowerCase();
    var users = widget.auth.directory.toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (q.isNotEmpty) {
      users = users
          .where((u) =>
              u.fullName.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              u.handle.toLowerCase().contains(q))
          .toList();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Push bildirimi gönder',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Seçili kullanıcılara veya herkese. Toplam dizinde ${widget.auth.directory.length} üye.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Başlık'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _body,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Mesaj'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Tüm kullanıcılara gönder'),
          subtitle: Text('Firestore’daki tüm üyeler (${widget.auth.directory.length})'),
          value: _toAll,
          onChanged: (v) => setState(() => _toAll = v),
        ),
        SwitchListTile(
          title: const Text('Ayrıca e-posta gönder'),
          subtitle: const Text('Firestore’da email kaydı olanlara'),
          value: _alsoMail,
          onChanged: (v) => setState(() => _alsoMail = v),
        ),
        if (!_toAll) ...[
          const Divider(),
          Text(
            'Alıcıları seç (${_selected.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _userQ,
            decoration: const InputDecoration(
              hintText: 'İsim veya e-posta ara…',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ...users.map(
            (u) => CheckboxListTile(
              dense: true,
              value: _selected.contains(u.id),
              title: Text(u.fullName),
              subtitle: Text(u.email, style: const TextStyle(fontSize: 12)),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(u.id);
                  } else {
                    _selected.remove(u.id);
                  }
                });
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: admin.busy
              ? null
              : () async {
                  if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Başlık ve mesaj gerekli')),
                    );
                    return;
                  }
                  if (!_toAll && _selected.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('En az bir kullanıcı seç')),
                    );
                    return;
                  }
                  final result = await widget.admin.broadcastPush(
                    auth: widget.auth,
                    notifications: context.read<NotificationProvider>(),
                    title: _title.text,
                    body: _body.text,
                    toAll: _toAll,
                    selectedUserIds: _selected,
                    alsoMail: _alsoMail,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.delivered > 0
                              ? '${result.targeted} hedef · ${result.delivered} cihaz FCM'
                              : '${result.targeted} hedef · 0 cihaz — token yok. Telefonda uygulamayı aç, giriş yap, bildirim iznini ver.',
                        ),
                      ),
                    );
                  }
                },
          icon: const MtIcon(MtIcons.bell, size: 18, color: Colors.white),
          label: Text(admin.busy ? 'Gönderiliyor…' : 'Push gönder'),
        ),
        if (admin.status != null) ...[
          const SizedBox(height: 8),
          Text(admin.status!, style: const TextStyle(color: AppColors.cyan)),
        ],
      ],
    );
  }
}

/// Bakım sırasında da çalışan güvenli personel giriş formu.
class _AdminGateLogin extends StatefulWidget {
  const _AdminGateLogin();

  @override
  State<_AdminGateLogin> createState() => _AdminGateLoginState();
}

class _AdminGateLoginState extends State<_AdminGateLogin> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Giriş başarısız')),
      );
      return;
    }
    final user = auth.user;
    if (user == null || !user.canAccessAdmin) {
      await auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hesap admin yetkisine sahip değil.'),
        ),
      );
      return;
    }
    final maint = context.read<MaintenanceProvider>();
    final admin = context.read<AdminProvider>();
    if (maint.blocksApp && !admin.canAccessDuringMaintenance(user)) {
      await auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bakımda erişim için “Bakım sırasında eriş” yetkisi gerekli.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().isBusy;
    final maint = context.watch<MaintenanceProvider>().blocksApp;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personel girişi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (maint) {
              context.go('/home');
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MtIcon(MtIcons.admin, size: 48, color: AppColors.navy),
                  const SizedBox(height: 12),
                  Text(
                    maint
                        ? 'Bakım modu · yalnızca yetkili personel'
                        : 'Admin paneline giriş',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Yetkisiz hesaplar reddedilir. Oturum Firebase Auth ile doğrulanır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.95),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Personel e-posta',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) {
                      final e = (v ?? '').trim();
                      if (e.isEmpty) return 'E-posta gerekli';
                      if (!e.contains('@')) return 'Geçersiz e-posta';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').length < 6) return 'Şifre en az 6 karakter';
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.navy,
                    ),
                    child: Text(busy ? 'Doğrulanıyor…' : 'Giriş yap'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
