import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../ads/ad_campaign_form.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';

/// Topluluk hesabi yonetim paneli: duyuru, etkinlik, basvuru onayi, logo, reklam, kadro.
class CommunityPortalScreen extends StatefulWidget {
  const CommunityPortalScreen({super.key});

  @override
  State<CommunityPortalScreen> createState() => _CommunityPortalScreenState();
}

class _CommunityPortalScreenState extends State<CommunityPortalScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final me = auth.user;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Topluluk paneli')),
        body: const Center(child: Text('Giris gerekli')),
      );
    }
    final staffCommunity = me.panelAccess &&
        me.panelOrgType == 'community' &&
        (me.panelOrgId ?? '').isNotEmpty;
    if (!me.isCommunity && !staffCommunity) {
      return Scaffold(
        appBar: AppBar(title: const Text('Topluluk paneli')),
        body: const Center(
          child: Text('Bu panel yalnizca topluluk hesaplari / kadro icindir.'),
        ),
      );
    }
    final effectiveOrgId = me.isCommunity ? me.id : (me.panelOrgId ?? me.id);

    if (me.isCommunity && !me.communityCanPublish) {
      return Scaffold(
        appBar: AppBar(title: const Text('Topluluk paneli')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MtIcon(MtIcons.community, size: 48, color: AppColors.gold),
              const SizedBox(height: 12),
              const Text(
                'Logo yuklemeden duyuru, etkinlik veya paylasim yapamazsin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  auth.updateProfile(
                    communityLogoUrl: 'assets/logos/ays_circle.png',
                    photoUrl: null,
                  );
                  auth.upsertUser(
                    me.copyWith(
                      communityLogoUrl: 'assets/logos/ays_circle.png',
                      photoUrl: 'assets/logos/ays_circle.png',
                    ),
                  );
                },
                child: const Text('Varsayilan MT logosunu ata'),
              ),
            ],
          ),
        ),
      );
    }

    final pages = [
      _CommunityEventsTab(me: me),
      _CommunityAnnouncementsTab(me: me),
      _CommunityApplicationsTab(me: me),
      _CommunityAdsTab(orgId: effectiveOrgId, me: me),
      _CommunityStaffTab(orgId: effectiveOrgId),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            const VerifiedBadge(gold: true, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(me.fullName, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            label: 'Etkinlik',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            label: 'Duyuru',
          ),
          NavigationDestination(
            icon: Icon(Icons.how_to_reg_outlined),
            label: 'Basvuru',
          ),
          NavigationDestination(
            icon: Icon(Icons.ads_click_outlined),
            label: 'Reklam',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_add_outlined),
            label: 'Kadro',
          ),
        ],
      ),
    );
  }
}

class _CommunityEventsTab extends StatefulWidget {
  const _CommunityEventsTab({required this.me});
  final AppUser me;

  @override
  State<_CommunityEventsTab> createState() => _CommunityEventsTabState();
}

class _CommunityEventsTabState extends State<_CommunityEventsTab> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  final _cap = TextEditingController(text: '40');
  String _audience = 'followers';
  DateTime _startsAt = DateTime.now().add(const Duration(days: 7));
  DateTime _deadline = DateTime.now().add(const Duration(days: 5));

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _loc.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('tr'),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _fmt(DateTime d) => DateFormat('d MMM yyyy - HH:mm', 'tr').format(d);

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final mine =
        feed.events.where((e) => e.communityId == widget.me.id).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Yeni etkinlik', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Baslik'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _desc,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Aciklama'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _loc,
          decoration: const InputDecoration(labelText: 'Konum'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cap,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Kontenjan (kadro)'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _audience,
          decoration: const InputDecoration(labelText: 'Kimler katilabilir?'),
          items: const [
            DropdownMenuItem(value: 'followers', child: Text('Takipciler')),
            DropdownMenuItem(value: 'campus', child: Text('Tum kampus')),
            DropdownMenuItem(value: 'students', child: Text('Sadece ogrenciler')),
            DropdownMenuItem(
              value: 'members',
              child: Text('Topluluk uyeleri'),
            ),
          ],
          onChanged: (v) => setState(() => _audience = v ?? 'followers'),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Etkinlik tarihi'),
          subtitle: Text(_fmt(_startsAt)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final picked = await _pickDateTime(_startsAt);
            if (picked != null) setState(() => _startsAt = picked);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Son basvuru saati'),
          subtitle: Text(_fmt(_deadline)),
          trailing: const Icon(Icons.timer_outlined),
          onTap: () async {
            final picked = await _pickDateTime(_deadline);
            if (picked != null) setState(() => _deadline = picked);
          },
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            final cap = int.tryParse(_cap.text) ?? 40;
            if (_title.text.trim().isEmpty) return;
            if (!_deadline.isBefore(_startsAt)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Son basvuru saati, etkinlik tarihinden once olmali.',
                  ),
                ),
              );
              return;
            }
            await feed.addEvent(
              CampusEvent(
                id: 'e_${const Uuid().v4().substring(0, 8)}',
                title: _title.text.trim(),
                description: _desc.text.trim(),
                location:
                    _loc.text.trim().isEmpty ? 'Kampus' : _loc.text.trim(),
                startsAt: _startsAt,
                capacity: cap,
                audience: _audience,
                applicationDeadline: _deadline,
                applicationsOpen: true,
                communityId: widget.me.id,
                communityName: widget.me.fullName,
                communityLogoUrl: widget.me.communityLogoUrl,
                imageUrl:
                    'https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/900/420',
              ),
              notifyAudience: true,
            );
            _title.clear();
            _desc.clear();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Etkinlik yayinlandi')),
            );
          },
          child: const Text('Etkinlik yayinla'),
        ),
        const Divider(height: 32),
        Text(
          'Etkinliklerim (${mine.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...mine.map(
          (e) => ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Text(e.title),
            subtitle: Text(
              '${DateFormat('d MMM yyyy', 'tr').format(e.startsAt)} - '
              '${e.approvedCount}/${e.capacity} kadro - '
              '${e.pendingCount} bekleyen'
              '${e.isRosterFull ? ' - Kadro doldu' : ''}'
              '${!e.applicationsOpen || e.isDeadlinePassed ? ' - Basvuru kapali' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openManageSheet(context, e),
          ),
        ),
      ],
    );
  }

  Future<void> _openManageSheet(BuildContext context, CampusEvent event) async {
    final feed = context.read<FeedProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                event.title,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kadro: ${event.approvedCount}/${event.capacity} - '
                'Bekleyen: ${event.pendingCount}\n'
                'Kimler: ${event.audienceLabel}\n'
                'Son basvuru: ${event.applicationDeadline == null ? '-' : _fmt(event.applicationDeadline!)}'
                '${event.isRosterFull ? '\nDurum: Kadro doldu' : ''}'
                '${!event.applicationsOpen || event.isDeadlinePassed ? '\nDurum: Basvurular kapandi' : ''}',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final base = event.applicationDeadline ?? DateTime.now();
                  final picked = await _pickDateTime(
                    base.isBefore(DateTime.now())
                        ? DateTime.now().add(const Duration(days: 2))
                        : base.add(const Duration(days: 2)),
                  );
                  if (picked == null) return;
                  await feed.extendEventDeadline(
                    eventId: event.id,
                    newDeadline: picked,
                    communityAdminId: widget.me.id,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Son basvuru ${_fmt(picked)} olarak uzatildi. '
                        'Topluluk adminine bildirildi.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.update),
                label: const Text('Son basvuru saatini uzat / yeniden ac'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Kapat'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CommunityAnnouncementsTab extends StatefulWidget {
  const _CommunityAnnouncementsTab({required this.me});
  final AppUser me;

  @override
  State<_CommunityAnnouncementsTab> createState() =>
      _CommunityAnnouncementsTabState();
}

class _CommunityAnnouncementsTabState extends State<_CommunityAnnouncementsTab> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'followers';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Baslik'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _body,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Duyuru metni'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _audience,
          decoration: const InputDecoration(labelText: 'Hedef kitle'),
          items: const [
            DropdownMenuItem(
              value: 'followers',
              child: Text('Takipciler (push + e-posta)'),
            ),
            DropdownMenuItem(value: 'members', child: Text('Uyeler')),
            DropdownMenuItem(value: 'campus', child: Text('Kampus geneli')),
          ],
          onChanged: (v) => setState(() => _audience = v ?? 'followers'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
              return;
            }
            final ann = Announcement(
              id: 'a_${const Uuid().v4().substring(0, 8)}',
              title: _title.text.trim(),
              body: _body.text.trim(),
              createdAt: DateTime.now(),
              audience: _audience,
              communityId: widget.me.id,
              communityName: widget.me.fullName,
              communityLogoUrl: widget.me.communityLogoUrl,
            );
            await feed.publishAnnouncement(ann);
            _title.clear();
            _body.clear();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _audience == 'followers'
                      ? 'Duyuru yayinlandi - takipcilere bildirim gonderiliyor'
                      : 'Duyuru yayinlandi',
                ),
              ),
            );
          },
          child: const Text('Duyuru yayinla'),
        ),
      ],
    );
  }
}

class _CommunityApplicationsTab extends StatelessWidget {
  const _CommunityApplicationsTab({required this.me});
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final events = feed.events.where((e) => e.communityId == me.id).toList();
    final rows = <(CampusEvent, EventApplication)>[];
    for (final e in events) {
      for (final a in e.applications) {
        if (a.status == EventApplicationStatus.pending ||
            a.status == EventApplicationStatus.approved) {
          rows.add((e, a));
        }
      }
    }
    rows.sort((a, b) {
      final ap = a.$2.status == EventApplicationStatus.pending ? 0 : 1;
      final bp = b.$2.status == EventApplicationStatus.pending ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return b.$2.createdAt.compareTo(a.$2.createdAt);
    });

    if (rows.isEmpty) {
      return const Center(child: Text('Basvuru yok'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final (event, app) = rows[i];
        final pending = app.status == EventApplicationStatus.pending;
        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ListTile(
            title: Text(app.userName),
            subtitle: Text(
              '${event.title}\n'
              '${pending ? 'Bekliyor' : 'Onayli'} - '
              '${event.approvedCount}/${event.capacity} kadro'
              '${event.isRosterFull ? ' - Kadro doldu' : ''}',
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pending) ...[
                  IconButton(
                    tooltip: 'Onayla',
                    onPressed: () => feed.reviewEventApplication(
                      eventId: event.id,
                      applicationId: app.id,
                      approve: true,
                    ),
                    icon: const Icon(Icons.check_circle, color: AppColors.lime),
                  ),
                  IconButton(
                    tooltip: 'Reddet (slot acilir)',
                    onPressed: () => feed.reviewEventApplication(
                      eventId: event.id,
                      applicationId: app.id,
                      approve: false,
                    ),
                    icon: const Icon(Icons.cancel, color: AppColors.crimson),
                  ),
                ],
                IconButton(
                  tooltip: 'Basvuruyu sil',
                  onPressed: () async {
                    await feed.deleteEventApplication(
                      eventId: event.id,
                      applicationId: app.id,
                      communityAdminId: me.id,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Basvuru silindi - kontenjan acildi - admin bilgilendirildi',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommunityAdsTab extends StatelessWidget {
  const _CommunityAdsTab({required this.orgId, required this.me});
  final String orgId;
  final AppUser me;

  @override
  Widget build(BuildContext context) {
    final events = context
        .watch<FeedProvider>()
        .events
        .where((e) => e.communityId == orgId)
        .map((e) => (id: e.id, title: e.title))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Sponsor tanit, ucretsiz etkinlik veya ucretli sponsor reklami. '
          'Il / universite secimi zorunlu; admin onaylar.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            final ok = await AdCampaignFormSheet.open(
              context,
              ownerType: 'community',
              events: events,
            );
            if (ok == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reklam talebi gonderildi')),
              );
            }
          },
          icon: const Icon(Icons.campaign),
          label: const Text('Yeni reklam / sponsor'),
        ),
        const SizedBox(height: 16),
        StreamBuilder(
          stream: FirebaseFirestore.instance
              .collection('ad_campaigns')
              .where('ownerId', isEqualTo: orgId)
              .limit(40)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Text('Henuz reklam talebi yok.');
            }
            return Column(
              children: [
                for (final d in docs) ...[
                  Card(
                    child: ListTile(
                      title: Text('${d.data()['title']}'),
                      subtitle: Text(
                        '${d.data()['status']} - ${d.data()['adKind']}',
                      ),
                    ),
                  ),
                  if (d.data()['status'] == 'awaiting_payment')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AdIbanPaymentCard(
                        amount:
                            (d.data()['quotedAmount'] as num?)?.toDouble() ?? 0,
                        iban: '${d.data()['payoutIban'] ?? ''}',
                        holder: '${d.data()['payoutIbanHolder'] ?? ''}',
                        bank: '${d.data()['payoutBank'] ?? ''}',
                        code: '${d.data()['ibanReference'] ?? ''}',
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CommunityStaffTab extends StatefulWidget {
  const _CommunityStaffTab({required this.orgId});
  final String orgId;

  @override
  State<_CommunityStaffTab> createState() => _CommunityStaffTabState();
}

class _CommunityStaffTabState extends State<_CommunityStaffTab> {
  final _query = TextEditingController();
  bool _panel = true;
  bool _badge = true;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _invite(AppUser u) async {
    setState(() => _busy = true);
    try {
      await OrgInviteService.invite(
        orgId: widget.orgId,
        orgType: 'community',
        inviteeUid: u.id,
        grantPanelAccess: _panel,
        grantBlueBadge: _badge,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${u.fullName} davet edildi')),
      );
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
            .where((u) => !u.isCommunity && !u.isCompany)
            .take(20)
            .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Yonetim kadrosu davet et: panel erisimi ve/veya mavi tick.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        SwitchListTile(
          title: const Text('Panele erisim'),
          value: _panel,
          onChanged: (v) => setState(() => _panel = v),
        ),
        SwitchListTile(
          title: const Text('Mavi tick'),
          value: _badge,
          onChanged: (v) => setState(() => _badge = v),
        ),
        TextField(
          controller: _query,
          decoration: const InputDecoration(
            labelText: 'Kullanici ara',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_busy) const LinearProgressIndicator(),
        ...hits.map(
          (u) => ListTile(
            title: Text(u.fullName),
            subtitle: Text(u.email),
            trailing: FilledButton(
              onPressed: _busy ? null : () => _invite(u),
              child: const Text('Davet'),
            ),
          ),
        ),
      ],
    );
  }
}
