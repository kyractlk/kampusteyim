import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../plus/plus_widgets.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';

/// Modern kullanıcı yönetimi — Firestore dizin senkronu + durum/doğrulama filtreleri.
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
  String _status = 'all';
  String _verify = 'all';
  String _university = 'all';
  bool _syncing = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshUsers(silent: widget.auth.directory.isNotEmpty));
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _refreshUsers({bool silent = false}) async {
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      final n = await widget.auth.syncDirectoryFromFirestore();
      if (!mounted) return;
      setState(() => _syncing = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$n aktif profil yüklendi · dizinde ${widget.auth.directory.length}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncError = '$e';
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yenileme başarısız: $e')),
        );
      }
    }
  }

  List<String> _universitiesInDirectory(List<AppUser> all) {
    final set = <String>{};
    for (final u in all) {
      final uni = u.university.trim();
      if (uni.isNotEmpty && uni != '—' && uni.toLowerCase() != 'null') {
        set.add(uni);
      }
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  String _shortUni(String uni) {
    return uni
        .replaceAll(' Üniversitesi', '')
        .replaceAll('Universitesi', '')
        .replaceAll('Gaziantep ', 'G.')
        .replaceAll('İslam Bilim Ve Teknoloji', 'İBTÜ')
        .replaceAll('Bilim Ve Teknoloji', 'BTÜ');
  }

  String _statusLabel(AppUser u) {
    if (u.isAccountPending) return 'Onay bekliyor';
    if (u.isAccountRejected) return 'Reddedildi';
    return 'Aktif';
  }

  Color _statusColor(AppUser u) {
    if (u.isAccountPending) return AppColors.warning;
    if (u.isAccountRejected) return AppColors.crimson;
    return AppColors.lime;
  }

  String? _verifyLabel(AppUser u) {
    final t = (u.studentVerificationType ?? '').trim();
    final src = '${u.studentCredential?['source'] ?? ''}';
    if (t == 'edevlet' || src == 'edevlet') return 'e-Devlet';
    if (t == 'deferred') return 'Belge sonra';
    if (t == 'card') return 'Kart';
    if (t == 'document' || (u.studentIdDocUrl ?? '').isNotEmpty) return 'PDF';
    if (u.hasStudentCredential) return 'Doğrulandı';
    if (u.role == UserRole.student) return 'Öğrenci doğrulama yok';
    return null;
  }

  bool _matchesVerify(AppUser u) {
    final t = (u.studentVerificationType ?? '').trim();
    final src = '${u.studentCredential?['source'] ?? ''}';
    switch (_verify) {
      case 'edevlet':
        return t == 'edevlet' || src == 'edevlet';
      case 'document':
        return t == 'document' ||
            ((u.studentIdDocUrl ?? '').isNotEmpty && t != 'edevlet');
      case 'card':
        return t == 'card' ||
            (u.studentIdFrontUrl ?? '').isNotEmpty ||
            (u.studentIdBackUrl ?? '').isNotEmpty;
      case 'deferred':
        return t == 'deferred';
      case 'none':
        return u.role == UserRole.student &&
            t.isEmpty &&
            !u.hasStudentCredential &&
            (u.studentIdDocUrl ?? '').isEmpty;
      default:
        return true;
    }
  }

  List<AppUser> _filtered(List<AppUser> source) {
    final q = _q.text.trim().toLowerCase();
    var users = source.toList();
    if (_role != 'all') {
      users = users.where((u) => u.role.name == _role).toList();
    }
    if (_status != 'all') {
      users = users.where((u) {
        return switch (_status) {
          'pending' => u.isAccountPending,
          'rejected' => u.isAccountRejected,
          'approved' => u.isAccountApproved,
          _ => true,
        };
      }).toList();
    }
    if (_verify != 'all') {
      users = users.where(_matchesVerify).toList();
    }
    if (_university != 'all') {
      users =
          users.where((u) => u.university.trim() == _university).toList();
    }
    if (q.isNotEmpty) {
      users = users.where((u) {
        final handle = u.handle.toLowerCase();
        final uname = (u.username ?? '').toLowerCase();
        return u.fullName.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            handle.contains(q) ||
            uname.contains(q) ||
            u.studentNo.contains(q) ||
            u.university.toLowerCase().contains(q) ||
            u.city.toLowerCase().contains(q) ||
            u.faculty.toLowerCase().contains(q) ||
            u.department.toLowerCase().contains(q);
      }).toList();
    }
    users.sort((a, b) {
      final pa = a.isAccountPending ? 0 : 1;
      final pb = b.isAccountPending ? 0 : 1;
      if (pa != pb) return pa.compareTo(pb);
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return users;
  }

  Widget _chipRow({
    required List<(String, String)> items,
    required String selected,
    required ValueChanged<String> onSelect,
    IconData? leadingIcon,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: leadingIcon != null && i == 0
                    ? Icon(leadingIcon, size: 16)
                    : null,
                label: Text(items[i].$2),
                selected: selected == items[i].$1,
                onSelected: (_) => onSelect(items[i].$1),
                selectedColor: AppColors.cyan.withValues(alpha: 0.18),
                checkmarkColor: AppColors.navy,
                labelStyle: TextStyle(
                  fontWeight: selected == items[i].$1
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.auth.directory.toList();
    final users = _filtered(all);
    final unis = _universitiesInDirectory(all);
    final pendingCount = all.where((u) => u.isAccountPending).length;

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
                        hintText:
                            'İsim, e-posta, @kullanıcı, okul no, üniversite…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: _q.text.isEmpty
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
                    onPressed: _syncing ? null : () => _refreshUsers(),
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
              if (_syncError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Senkron hatası: $_syncError',
                  style: const TextStyle(
                    color: AppColors.crimson,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _chipRow(
                selected: _role,
                onSelect: (v) => setState(() => _role = v),
                items: const [
                  ('all', 'Tümü'),
                  ('student', 'Öğrenci'),
                  ('community', 'Topluluk'),
                  ('company', 'Firma'),
                  ('admin', 'Admin'),
                ],
              ),
              const SizedBox(height: 8),
              _chipRow(
                selected: _status,
                onSelect: (v) => setState(() => _status = v),
                leadingIcon: Icons.verified_user_outlined,
                items: [
                  ('all', 'Durum: tümü'),
                  ('approved', 'Aktif'),
                  (
                    'pending',
                    pendingCount > 0
                        ? 'Onay bekleyen ($pendingCount)'
                        : 'Onay bekleyen'
                  ),
                  ('rejected', 'Reddedilen'),
                ],
              ),
              const SizedBox(height: 8),
              _chipRow(
                selected: _verify,
                onSelect: (v) => setState(() => _verify = v),
                leadingIcon: Icons.badge_outlined,
                items: const [
                  ('all', 'Doğrulama: tümü'),
                  ('edevlet', 'e-Devlet'),
                  ('document', 'PDF belge'),
                  ('card', 'Öğrenci kartı'),
                  ('deferred', 'Sonraya bırakılan'),
                  ('none', 'Doğrulanmamış'),
                ],
              ),
              if (unis.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar:
                              const Icon(Icons.school_outlined, size: 16),
                          label: const Text('Tüm okullar'),
                          selected: _university == 'all',
                          onSelected: (_) =>
                              setState(() => _university = 'all'),
                          selectedColor:
                              AppColors.cyan.withValues(alpha: 0.18),
                        ),
                      ),
                      for (final uni in unis)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(_shortUni(uni)),
                            selected: _university == uni,
                            onSelected: (_) =>
                                setState(() => _university = uni),
                            selectedColor:
                                AppColors.cyan.withValues(alpha: 0.18),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '${users.length} gösteriliyor · ${all.length} dizinde'
                '${_syncing ? ' · yenileniyor…' : ''}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: all.isEmpty && _syncing
              ? const Center(child: CircularProgressIndicator())
              : all.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.people_outline,
                              size: 48,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Henüz kullanıcı yüklenmedi',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Firestore’dan senkronla veya yeni kayıtları bekle.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed:
                                  _syncing ? null : () => _refreshUsers(),
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text('Yenile'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : users.isEmpty
                      ? const Center(
                          child: Text(
                            'Filtreye uyan kullanıcı yok — “Tüm okullar / Durum: tümü” dene',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: users.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final u = users[i];
                            return _UserAdminTile(
                              user: u,
                              staffRoleName: widget.admin
                                  .roleById(u.staffRoleId)
                                  ?.name,
                              statusLabel: _statusLabel(u),
                              statusColor: _statusColor(u),
                              verifyLabel: _verifyLabel(u),
                              onOpenProfile: () =>
                                  AppNav.openUserProfile(context, u),
                              onCredential: () =>
                                  _showUserCredential(context, u),
                              menuItems: _menuFor(u),
                              onMenu: (v) {
                                if (v == 'credential') {
                                  _showUserCredential(context, u);
                                  return;
                                }
                                widget.onUserAction(context, u, v);
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _menuFor(AppUser u) {
    return [
      const PopupMenuItem(value: 'profile', child: Text('Profili aç')),
      const PopupMenuItem(
        value: 'credential',
        child: Text('Öğrenci doğrulama / belge'),
      ),
      if (widget.admin.can(widget.me, AdminPermission.resetPassword))
        const PopupMenuItem(value: 'reset', child: Text('Şifre sıfırla')),
      if (widget.admin.can(widget.me, AdminPermission.manageBadges)) ...[
        PopupMenuItem(
          value: u.isCommunity ? 'ungold' : 'gold',
          child: Text(
            u.isCommunity ? 'Topluluk badge kaldır' : 'Topluluk badge ver',
          ),
        ),
        if (!u.isCommunity) ...[
          const PopupMenuItem(
            value: 'blue',
            child: Text('Kuruma bağla (mavi tick)'),
          ),
          const PopupMenuItem(
            value: 'gold_affil',
            child: Text('Gold tick + kuruma bağla'),
          ),
          const PopupMenuItem(
            value: 'unblue',
            child: Text('Kurum ilişkisini kaldır'),
          ),
        ],
      ],
      if (widget.admin.can(widget.me, AdminPermission.manageAmbassadors) &&
          !u.isCommunity &&
          u.role != UserRole.company)
        PopupMenuItem(
          value: u.isCampusAmbassador ? 'unambassador' : 'ambassador',
          child: Text(
            u.isCampusAmbassador ? 'Elçiliği kaldır' : 'Kampüs elçisi yap',
          ),
        ),
      if (widget.admin.can(widget.me, AdminPermission.manageUsers) &&
          u.role == UserRole.company)
        PopupMenuItem(
          value: u.isEventOrganizer ? 'unorganizer' : 'organizer',
          child: Text(
            u.isEventOrganizer
                ? 'Organizatörlüğü kaldır'
                : 'Etkinlik organizatörü yap',
          ),
        ),
      if (widget.admin.can(widget.me, AdminPermission.managePlus)) ...[
        PopupMenuItem(
          value: 'plus_grant',
          child: Text(
            u.plusActive ? 'Plus süre uzat / yeniden ver' : 'Plus ver',
          ),
        ),
        if (u.plusActive)
          const PopupMenuItem(
            value: 'plus_revoke',
            child: Text('Plus kaldır'),
          ),
      ],
      if (widget.admin.can(widget.me, AdminPermission.restrictUsers)) ...[
        const PopupMenuItem(value: 'warn', child: Text('Uyarı gönder')),
        const PopupMenuItem(value: 'mute', child: Text('24 saat sustur')),
        const PopupMenuItem(
          value: 'postban7',
          child: Text('1 hafta paylaşım yasağı'),
        ),
        const PopupMenuItem(
          value: 'fullban',
          child: Text('Hesabı askıya al'),
        ),
        const PopupMenuItem(
          value: 'lift',
          child: Text('Kısıtlamayı kaldır'),
        ),
      ],
      if (widget.admin.can(widget.me, AdminPermission.manageAdmins) &&
          !u.isCommunity &&
          u.role != UserRole.company)
        const PopupMenuItem(
          value: 'make_admin',
          child: Text('Admin yap / rol ata'),
        ),
      if (widget.admin.can(widget.me, AdminPermission.manageUsers) &&
          !u.isSuperAdmin)
        const PopupMenuItem(
          value: 'delete_account',
          child: Text('Hesabı sil'),
        ),
    ];
  }

  void _showUserCredential(BuildContext context, AppUser u) {
    final c = u.studentCredential ?? const <String, dynamic>{};
    String line(String label, dynamic v) {
      final s = '${v ?? ''}'.trim();
      if (s.isEmpty) return '';
      return '$label: $s';
    }

    final lines = <String>[
      line('Kaynak', c['source'] ?? u.studentVerificationType),
      line('Üniversite', c['university'] ?? u.university),
      line('Fakülte', c['faculty'] ?? u.faculty),
      line('Bölüm', c['department'] ?? u.department),
      line('Durum', c['studentStatus']),
      line('Sınıf', c['grade']),
      line('Bağlı e-posta', c['linkedEmail'] ?? u.email),
      line('Bağlı okul no', c['linkedStudentNo'] ?? u.studentNo),
      line('Doğrulama', c['verifiedAt']),
      line('Barkod (son 4)', c['barkodLast4']),
      if ((u.studentIdDocUrl ?? '').isNotEmpty)
        'Manuel belge URL mevcut (admin incelemesi)',
      if ((u.studentIdFrontUrl ?? '').isNotEmpty) 'Kart ön yüz yüklü',
      if ((u.studentIdBackUrl ?? '').isNotEmpty) 'Kart arka yüz yüklü',
    ].where((e) => e.isNotEmpty).toList();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              u.fullName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              u.email,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Kayıtlı öğrenci doğrulama özeti (eğitim alanları)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (lines.isEmpty)
              const Text('Kayıtlı doğrulama / belge özeti yok.')
            else
              ...lines.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(e, style: const TextStyle(height: 1.35)),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                AppNav.openUserProfile(context, u);
              },
              child: const Text('Profili aç'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserAdminTile extends StatelessWidget {
  const _UserAdminTile({
    required this.user,
    required this.statusLabel,
    required this.statusColor,
    required this.onOpenProfile,
    required this.onCredential,
    required this.menuItems,
    required this.onMenu,
    this.staffRoleName,
    this.verifyLabel,
  });

  final AppUser user;
  final String? staffRoleName;
  final String statusLabel;
  final Color statusColor;
  final String? verifyLabel;
  final VoidCallback onOpenProfile;
  final VoidCallback onCredential;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final uni = user.university.trim();
    final meta = <String>[
      user.role.name,
      ?staffRoleName,
      if (user.handle.isNotEmpty) user.handle,
      if (uni.isNotEmpty && uni != '—') uni,
      if (user.restrictionActive) 'kısıtlı',
      if (user.plusActive) 'Plus',
      if (user.isCampusAmbassador) 'elçi',
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: user.isAccountPending
              ? AppColors.warning.withValues(alpha: 0.55)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenProfile,
        onLongPress: onCredential,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                name: user.fullName,
                photoUrl: user.isCommunity
                    ? (user.communityLogoUrl ?? user.photoUrl)
                    : user.photoUrl,
                isCommunity: user.isCommunity,
                radius: 24,
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
                            user.fullName.trim().isEmpty
                                ? '(İsimsiz)'
                                : user.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        UserVerificationBadges(user: user, size: 14),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniChip(
                          label: statusLabel,
                          color: statusColor,
                        ),
                        if (verifyLabel != null)
                          _MiniChip(
                            label: verifyLabel!,
                            color: verifyLabel == 'e-Devlet'
                                ? AppColors.cyan
                                : AppColors.navySoft,
                          ),
                        if (user.needsUsernameChange)
                          const _MiniChip(
                            label: 'Geçici @ad',
                            color: AppColors.crimson,
                          ),
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: onMenu,
                itemBuilder: (_) => menuItems,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
