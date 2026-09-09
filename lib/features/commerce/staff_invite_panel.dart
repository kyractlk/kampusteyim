import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/panel_chrome.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'org_invite_service.dart';

/// Firma / topluluk kadro daveti — arama, izinler, bekleyen davetler.
class StaffInvitePanel extends StatefulWidget {
  const StaffInvitePanel({
    super.key,
    required this.orgId,
    required this.orgType,
  });

  final String orgId;
  final String orgType; // company | community

  @override
  State<StaffInvitePanel> createState() => _StaffInvitePanelState();
}

class _StaffInvitePanelState extends State<StaffInvitePanel> {
  final _query = TextEditingController();
  bool _panel = true;
  bool _badge = true;
  bool _busy = false;
  bool _loadingList = true;
  bool _searchingRemote = false;
  List<Map<String, dynamic>> _invites = const [];
  List<Map<String, dynamic>> _staff = const [];
  /// Org’a bağlı / affiliate kişisel hesaplar (ters linked dahil).
  final Map<String, AppUser> _related = {};
  /// Son uzak arama sonuçları.
  final Map<String, AppUser> _remoteHits = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refreshRoster();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapDirectory());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _bootstrapDirectory() async {
    final auth = context.read<AuthProvider>();
    try {
      await auth.syncDirectoryFromFirestore();
    } catch (_) {}
    final org = await auth.ensureUserLoaded(widget.orgId, forceRemote: true);
    final me = auth.user;
    final seedIds = <String>{
      ...?org?.linkedAccountIds,
      ...?me?.linkedAccountIds,
    };
    for (final id in seedIds) {
      final u = await auth.ensureUserLoaded(id);
      if (u != null && _isInviteCandidate(u)) {
        _related[u.id] = u;
      }
    }
    // Ters bağ: linkedAccountIds array-contains orgId
    await _loadRelatedFromFirestore(auth);
    if (mounted) setState(() {});
  }

  Future<void> _loadRelatedFromFirestore(AuthProvider auth) async {
    final fs = FirebaseFirestore.instance.collection('users');
    try {
      final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        fs
            .where('linkedAccountIds', arrayContains: widget.orgId)
            .limit(40)
            .get(),
        fs.where('panelOrgId', isEqualTo: widget.orgId).limit(40).get(),
      ];
      if (widget.orgType == 'company') {
        queries.add(
          fs
              .where('affiliatedCompanyId', isEqualTo: widget.orgId)
              .limit(40)
              .get(),
        );
      }
      final snaps = await Future.wait(queries);
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final u = await auth.ensureUserLoaded(doc.id);
          if (u != null && _isInviteCandidate(u)) {
            _related[u.id] = u;
          }
        }
      }
    } catch (e) {
      debugPrint('[staff] related load: $e');
    }
  }

  bool _isInviteCandidate(AppUser u) {
    if (u.id == widget.orgId) return false;
    // Yalnız org hesaplarını ele — admin / öğrenci / kişisel kalır.
    if (u.isCommunity || u.role == UserRole.community) return false;
    if (u.isCompany || u.role == UserRole.company) return false;
    return true;
  }

  Future<void> _refreshRoster() async {
    setState(() => _loadingList = true);
    try {
      final data = await OrgInviteService.listForOrg(widget.orgId);
      if (!mounted) return;
      setState(() {
        _invites = (data['invites'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _staff = (data['staff'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _invite(AppUser u) async {
    setState(() => _busy = true);
    try {
      await OrgInviteService.invite(
        orgId: widget.orgId,
        orgType: widget.orgType,
        inviteeUid: u.id,
        grantPanelAccess: _panel,
        grantBlueBadge: _badge,
      );
      _query.clear();
      _remoteHits.clear();
      await _refreshRoster();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${u.fullName} davet edildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke({String? memberUid, String? inviteId}) async {
    setState(() => _busy = true);
    try {
      await OrgInviteService.revoke(
        orgId: widget.orgId,
        memberUid: memberUid,
        inviteId: inviteId,
      );
      await _refreshRoster();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onQueryChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    final q = _query.text.trim();
    if (q.length < 2) {
      _remoteHits.clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_remoteSearch(q));
    });
  }

  Future<void> _remoteSearch(String raw) async {
    final q = raw.trim();
    if (q.length < 2 || !mounted) return;
    setState(() => _searchingRemote = true);
    final auth = context.read<AuthProvider>();
    final fs = FirebaseFirestore.instance.collection('users');
    final bare = q.replaceFirst(RegExp(r'^@'), '').toLowerCase();
    try {
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        fs.where('username', isEqualTo: bare).limit(8).get(),
        fs.where('email', isEqualTo: q.toLowerCase()).limit(8).get(),
        fs.where('email', isEqualTo: q).limit(8).get(),
      ];
      // Tam ad / ad — eşitlik + lowercase varyant
      if (q.length >= 3) {
        futures.add(fs.where('firstName', isEqualTo: q).limit(8).get());
        final titled = bare.isEmpty
            ? q
            : '${bare[0].toUpperCase()}${bare.substring(1)}';
        futures.add(fs.where('firstName', isEqualTo: titled).limit(8).get());
        futures.add(fs.where('fullName', isEqualTo: q).limit(8).get());
      }
      final snaps = await Future.wait(futures);
      final found = <String, AppUser>{};
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final u = await auth.ensureUserLoaded(doc.id, forceRemote: true);
          if (u != null && _isInviteCandidate(u)) {
            found[u.id] = u;
            _related[u.id] = u;
          }
        }
      }
      if (!mounted || _query.text.trim() != raw.trim()) return;
      setState(() {
        _remoteHits
          ..clear()
          ..addAll(found);
      });
    } catch (e) {
      debugPrint('[staff] remote search: $e');
    } finally {
      if (mounted) setState(() => _searchingRemote = false);
    }
  }

  List<AppUser> _searchHits(AuthProvider auth) {
    final q = _query.text.trim();
    final qLower = q.toLowerCase();
    final bare = qLower.replaceFirst(RegExp(r'^@'), '');
    final seen = <String>{};
    final out = <AppUser>[];

    void consider(AppUser u) {
      if (!_isInviteCandidate(u)) return;
      if (!seen.add(u.id)) return;
      out.add(u);
    }

    bool matches(AppUser u) {
      if (q.isEmpty) return true;
      final uname = (u.username ?? '').toLowerCase();
      final blob =
          '${u.fullName} ${u.email} ${u.handle} $uname ${u.firstName} ${u.lastName}'
              .toLowerCase();
      return blob.contains(qLower) ||
          uname == bare ||
          (q.length >= 2 && u.email.toLowerCase().startsWith(qLower));
    }

    // Bağlı / affiliate hesaplar — boş aramada da öneri olarak göster.
    for (final u in _related.values) {
      if (matches(u)) consider(u);
    }
    if (q.isEmpty) return out.take(20).toList();

    for (final u in _remoteHits.values) {
      if (matches(u)) consider(u);
    }
    for (final u in auth.directory) {
      if (matches(u)) consider(u);
    }
    for (final u in auth.searchUsers(q)) {
      consider(u);
    }

    return out.take(20).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final q = _query.text.trim();
    final hits = _searchHits(auth);
    final pending =
        _invites.where((e) => '${e['status']}' == 'pending').toList();
    final orgLabel = widget.orgType == 'company' ? 'firma' : 'topluluk';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelCard(
          color: AppColors.navy.withValues(alpha: 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yönetim kadrosu',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kullanıcıyı arayın, yetki seçin ve davet gönderin. '
                'Davetliye e-posta ile onay bağlantısı iletilir.',
                style: TextStyle(
                  height: 1.4,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PanelSectionLabel(
                'Yetkiler',
                subtitle: 'Davet edilen kişiye verilecek erişim',
              ),
              PanelToggleCard(
                selected: _panel,
                icon: Icons.dashboard_customize_outlined,
                label: 'Panele erişim',
                onChanged: (v) => setState(() => _panel = v),
              ),
              const SizedBox(height: 8),
              PanelToggleCard(
                selected: _badge,
                icon: Icons.verified_outlined,
                label: 'Mavi tick',
                onChanged: (v) => setState(() => _badge = v),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _query,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  labelText: 'Kullanıcı ara',
                  hintText: 'Ad, e-posta veya @kullanıcı',
                  prefixIcon: const Icon(Icons.person_search_outlined),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _debounce?.cancel();
                            _query.clear();
                            _remoteHits.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              if (_busy || _searchingRemote) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 3),
              ],
              if (hits.isEmpty && q.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Bağlı hesaplar yükleniyor veya henüz yok. Ad / @kullanıcı ara.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              if (hits.isEmpty && q.length >= 2 && !_searchingRemote)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Eşleşen kişisel hesap yok. @kullanıcı adı veya e-posta deneyin.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              if (hits.isNotEmpty && q.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 2),
                  child: Text(
                    'Bağlı hesaplar',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ...hits.map(
                (u) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _PersonTile(
                    name: u.fullName,
                    subtitle: u.email,
                    photoUrl: u.photoUrl,
                    trailing: FilledButton(
                      onPressed: _busy ? null : () => _invite(u),
                      child: const Text('Davet et'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: PanelSectionLabel(
                      'Kadro',
                      subtitle: 'Aktif üyeler ve bekleyen davetler',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: _loadingList ? null : _refreshRoster,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              if (_loadingList)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              if (!_loadingList && _staff.isEmpty && pending.isEmpty)
                Text(
                  'Henüz $orgLabel kadrosunda kimse yok.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ..._staff.map(
                (s) => _PersonTile(
                  name: '${s['name'] ?? s['email'] ?? s['uid']}',
                  subtitle: '${s['email'] ?? ''}'.trim().isEmpty
                      ? 'Aktif kadro'
                      : '${s['email']}',
                  photoUrl: '${s['photoUrl'] ?? ''}',
                  trailing: IconButton(
                    tooltip: 'Çıkar',
                    onPressed: _busy
                        ? null
                        : () => _revoke(memberUid: '${s['uid']}'),
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ),
              ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Bekleyen davetler',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 6),
                ...pending.map(
                  (inv) => _PersonTile(
                    name: '${inv['inviteeName'] ?? inv['inviteeEmail']}',
                    subtitle: 'Mail gönderildi · yanıt bekleniyor',
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _revoke(inviteId: '${inv['id']}'),
                      child: const Text('İptal'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.name,
    required this.subtitle,
    required this.trailing,
    this.photoUrl,
  });

  final String name;
  final String subtitle;
  final Widget trailing;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 42,
            height: 42,
            child: url.isEmpty
                ? ColoredBox(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    child: Center(
                      child: Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                  )
                : SafeNetworkImage(
                    url: url,
                    fit: BoxFit.cover,
                    width: 42,
                    height: 42,
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (subtitle.trim().isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}
