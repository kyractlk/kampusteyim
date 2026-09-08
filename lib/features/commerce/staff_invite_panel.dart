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
  List<Map<String, dynamic>> _invites = const [];
  List<Map<String, dynamic>> _staff = const [];

  @override
  void initState() {
    super.initState();
    _refreshRoster();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
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
      await _refreshRoster();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${u.fullName} davet edildi. Mailindeki bağlantı uygulamayı açar.',
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final q = _query.text.trim();
    final hits = q.isEmpty
        ? <AppUser>[]
        : auth
            .searchUsers(q)
            .where((u) => !u.isCommunity && !u.isCompany && u.id != widget.orgId)
            .take(12)
            .toList();
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
              Text(
                'Kişiyi ara, yetkisini seç ve davet et. Davetliye e-posta gider; '
                'bağlantıya basınca Android veya iOS uygulaması açılır, '
                'kabul/red içeride yapılır.',
                style: const TextStyle(
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    avatar: Icon(
                      Icons.dashboard_customize_outlined,
                      size: 16,
                      color: _panel ? Colors.white : AppColors.navy,
                    ),
                    label: const Text('Panele erişim'),
                    selected: _panel,
                    onSelected: (v) => setState(() => _panel = v),
                  ),
                  FilterChip(
                    avatar: Icon(
                      Icons.verified_outlined,
                      size: 16,
                      color: _badge ? Colors.white : AppColors.navy,
                    ),
                    label: const Text('Mavi tick'),
                    selected: _badge,
                    onSelected: (v) => setState(() => _badge = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Kullanıcı ara',
                  hintText: 'Ad, e-posta veya @kullanıcı',
                  prefixIcon: const Icon(Icons.person_search_outlined),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 3),
              ],
              if (hits.isEmpty && q.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Eşleşen öğrenci hesabı yok.',
                    style: TextStyle(color: AppColors.textSecondary),
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
    this.photoUrl,
    this.trailing,
  });

  final String name;
  final String subtitle;
  final String? photoUrl;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final url = (photoUrl ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 42,
              height: 42,
              child: url.isNotEmpty
                  ? SafeNetworkImage(
                      url: url,
                      fit: BoxFit.cover,
                      width: 42,
                      height: 42,
                    )
                  : const ColoredBox(
                      color: Color(0xFFE8EEF5),
                      child: Icon(Icons.person_outline, size: 22),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (subtitle.isNotEmpty)
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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
