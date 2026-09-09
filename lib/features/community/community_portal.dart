import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/breakpoints.dart';
import '../../core/widgets/panel_chrome.dart';
import '../../models/models.dart';
import '../ads/ad_campaign_form.dart';
import '../auth/data/auth_provider.dart';
import '../commerce/staff_invite_panel.dart';
import '../events/event_banner_picker.dart';
import '../feed/feed_provider.dart';

/// Topluluk hesabi yonetim paneli: duyuru, etkinlik, basvuru onayi, logo, reklam, kadro.
class CommunityPortalScreen extends StatefulWidget {
  const CommunityPortalScreen({super.key});

  @override
  State<CommunityPortalScreen> createState() => _CommunityPortalScreenState();
}

class _CommunityPortalScreenState extends State<CommunityPortalScreen> {
  /// null = hosgeldin dashboard; aksi halde acik bolum.
  int? _section;

  static const _titles = [
    'Etkinlik',
    'Duyuru',
    'Basvuru',
    'Reklam',
    'Kadro',
  ];

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
      _CommunityEventsTab(me: me, orgId: effectiveOrgId),
      _CommunityAnnouncementsTab(me: me, orgId: effectiveOrgId),
      _CommunityApplicationsTab(orgId: effectiveOrgId),
      _CommunityAdsTab(orgId: effectiveOrgId, me: me),
      _CommunityStaffTab(orgId: effectiveOrgId),
    ];

    final wide = AppBreakpoints.isWide(context);
    final sectionTitle =
        _section == null ? me.fullName : _titles[_section!];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            const VerifiedBadge(gold: true, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(sectionTitle, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        leading: _section == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _section = null),
              ),
        actions: [
          IconButton(
            tooltip: 'Kapı girişi',
            onPressed: () => context.push('/community/scan'),
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Öğrenci tara',
            onPressed: () => context.push('/community/students'),
            icon: const Icon(Icons.school_outlined),
          ),
          IconButton(
            tooltip: 'Tanıtım kartı',
            onPressed: () => context.push('/tanitimkarti'),
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
          IconButton(
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: _section == null
          ? _CommunityWelcome(
              orgName: me.fullName,
              onSelect: (i) => setState(() => _section = i),
            )
          : wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 280,
                      child: Material(
                        color: AppColors.surface,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (var i = 0; i < _titles.length; i++)
                              ListTile(
                                selected: _section == i,
                                leading: Icon(_iconFor(i)),
                                title: Text(_titles[i]),
                                onTap: () => setState(() => _section = i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: pages[_section!]),
                  ],
                )
              : pages[_section!],
    );
  }

  IconData _iconFor(int i) => switch (i) {
        0 => Icons.event_outlined,
        1 => Icons.campaign_outlined,
        2 => Icons.how_to_reg_outlined,
        3 => Icons.ads_click_outlined,
        _ => Icons.group_add_outlined,
      };
}

class _CommunityWelcome extends StatelessWidget {
  const _CommunityWelcome({
    required this.orgName,
    required this.onSelect,
  });

  final String orgName;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            PanelWelcomeHeader(
              title: 'Hoş geldiniz',
              subtitle: '$orgName yönetim paneli',
            ),
            const SizedBox(height: 12),
            PanelNavTile(
              accent: true,
              icon: Icons.qr_code_scanner_rounded,
              title: 'Kapı girişi',
              subtitle: 'Bilet QR doğrula',
              onTap: () => context.push('/community/scan'),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.event_outlined,
              title: 'Etkinlik',
              subtitle: 'Oluştur · yönet',
              onTap: () => onSelect(0),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.campaign_outlined,
              title: 'Duyuru',
              subtitle: 'Takipçilere duyuru yayınla',
              onTap: () => onSelect(1),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.how_to_reg_outlined,
              title: 'Başvuru',
              subtitle: 'Üyelik başvurularını onayla',
              onTap: () => onSelect(2),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.ads_click_outlined,
              title: 'Reklam',
              subtitle: 'Kampanya talebi oluştur',
              onTap: () => onSelect(3),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.group_add_outlined,
              title: 'Yönetim kadrosu',
              subtitle: 'Davet · yetki',
              onTap: () => onSelect(4),
            ),
            const SizedBox(height: 10),
            PanelNavTile(
              icon: Icons.school_outlined,
              title: 'Öğrenci tara',
              subtitle: 'Kampüs öğrencilerini filtrele',
              onTap: () => context.push('/community/students'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityEventsTab extends StatefulWidget {
  const _CommunityEventsTab({required this.me, required this.orgId});
  final AppUser me;
  final String orgId;

  @override
  State<_CommunityEventsTab> createState() => _CommunityEventsTabState();
}

class _CommunityEventsTabState extends State<_CommunityEventsTab> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _loc = TextEditingController();
  final _cap = TextEditingController(text: '40');
  final _rules = TextEditingController();
  /// -1 = hicbir adim acik degil
  int _step = -1;
  String _audience = 'followers';
  DateTime _startsAt = DateTime.now().add(const Duration(days: 7));
  DateTime _deadline = DateTime.now().add(const Duration(days: 5));
  String _bannerUrl = '';
  bool _bannerBusy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _loc.dispose();
    _cap.dispose();
    _rules.dispose();
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
        feed.events.where((e) => e.communityId == widget.orgId).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => context.push('/community/scan'),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Kapı girişi · bilet okut'),
        ),
        const SizedBox(height: 14),
        _StepCard(
          step: 1,
          title: 'Temel bilgiler',
          expanded: _step == 0,
          onToggle: () => setState(() => _step = _step == 0 ? -1 : 0),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _loc,
                decoration: const InputDecoration(
                  labelText: 'Konum',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              EventBannerPreview(
                url: _bannerUrl,
                uploading: _bannerBusy,
                onPick: () async {
                  setState(() => _bannerBusy = true);
                  final url = await pickEventBanner(context);
                  if (!mounted) return;
                  setState(() {
                    _bannerBusy = false;
                    if (url != null && url.isNotEmpty) _bannerUrl = url;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StepCard(
          step: 2,
          title: 'Kimler · kontenjan · tarih',
          expanded: _step == 1,
          onToggle: () => setState(() => _step = _step == 1 ? -1 : 1),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _audience,
                decoration: const InputDecoration(
                  labelText: 'Kimler katılabilir?',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'followers', child: Text('Takipçiler')),
                  DropdownMenuItem(value: 'campus', child: Text('Tüm kampüs')),
                  DropdownMenuItem(
                    value: 'students',
                    child: Text('Sadece öğrenciler'),
                  ),
                  DropdownMenuItem(
                    value: 'members',
                    child: Text('Topluluk üyeleri'),
                  ),
                ],
                onChanged: (v) => setState(() => _audience = v ?? 'followers'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cap,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kontenjan (kadro)',
                  border: OutlineInputBorder(),
                ),
              ),
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
                title: const Text('Son başvuru saati'),
                subtitle: Text(_fmt(_deadline)),
                trailing: const Icon(Icons.timer_outlined),
                onTap: () async {
                  final picked = await _pickDateTime(_deadline);
                  if (picked != null) setState(() => _deadline = picked);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StepCard(
          step: 3,
          title: 'Kurallar (opsiyonel)',
          expanded: _step == 2,
          onToggle: () => setState(() => _step = _step == 2 ? -1 : 2),
          child: TextField(
            controller: _rules,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Kapıda / etkinlikte uyulacak kurallar',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () async {
            final cap = int.tryParse(_cap.text) ?? 40;
            if (_title.text.trim().isEmpty) return;
            if (!_deadline.isBefore(_startsAt)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Son başvuru saati, etkinlik tarihinden önce olmalı.',
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
                    _loc.text.trim().isEmpty ? 'Kampüs' : _loc.text.trim(),
                startsAt: _startsAt,
                capacity: cap,
                audience: _audience,
                applicationDeadline: _deadline,
                applicationsOpen: true,
                communityId: widget.orgId,
                communityName: widget.me.fullName,
                communityLogoUrl: widget.me.communityLogoUrl,
                organizerCompanyId: widget.orgId,
                organizerCompanyName: widget.me.fullName,
                rules: _rules.text.trim(),
                imageUrl: _bannerUrl.isNotEmpty
                    ? _bannerUrl
                    : widget.me.communityLogoUrl,
              ),
              notifyAudience: true,
            );
            _title.clear();
            _desc.clear();
            _rules.clear();
            _bannerUrl = '';
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Etkinlik yayınlandı')),
            );
          },
          child: const Text('Etkinlik yayınla'),
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
  const _CommunityAnnouncementsTab({required this.me, required this.orgId});
  final AppUser me;
  final String orgId;

  @override
  State<_CommunityAnnouncementsTab> createState() =>
      _CommunityAnnouncementsTabState();
}

class _CommunityAnnouncementsTabState extends State<_CommunityAnnouncementsTab> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'followers';
  bool _formOpen = false;

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
        _StepCard(
          step: 1,
          title: 'Yeni duyuru',
          expanded: _formOpen,
          onToggle: () => setState(() => _formOpen = !_formOpen),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Başlık',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Duyuru metni',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _audience,
                decoration: const InputDecoration(
                  labelText: 'Hedef kitle',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'followers',
                    child: Text('Takipçiler (push + e-posta)'),
                  ),
                  DropdownMenuItem(value: 'members', child: Text('Üyeler')),
                  DropdownMenuItem(value: 'campus', child: Text('Kampüs geneli')),
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
                    communityId: widget.orgId,
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
                            ? 'Duyuru yayınlandı — takipçilere bildirim gönderiliyor'
                            : 'Duyuru yayınlandı',
                      ),
                    ),
                  );
                },
                child: const Text('Duyuru yayınla'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommunityApplicationsTab extends StatelessWidget {
  const _CommunityApplicationsTab({required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final events = feed.events.where((e) => e.communityId == orgId).toList();
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
                      communityAdminId: orgId,
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
          'Sponsor tanıtın: ücretsiz etkinlik veya ücretli sponsor reklamı. '
          'İl / üniversite seçimi zorunludur; yayın için yönetim ekibimiz inceler.',
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

class _CommunityStaffTab extends StatelessWidget {
  const _CommunityStaffTab({required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        StaffInvitePanel(orgId: orgId, orgType: 'community'),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final int step;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: expanded ? AppColors.navy : AppColors.border,
          width: expanded ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.navy,
              child: Text(
                '$step',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            trailing: Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }
}
