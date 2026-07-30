import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../data/mock/mock_data.dart';
import '../commerce/commerce_service.dart';

/// Ortak reklam formu — firma / topluluk
class AdCampaignFormSheet extends StatefulWidget {
  const AdCampaignFormSheet({
    super.key,
    required this.ownerType,
    this.events = const [],
    this.jobs = const [],
  });

  final String ownerType; // company | community
  final List<({String id, String title})> events;
  final List<({String id, String title})> jobs;

  static Future<bool?> open(
    BuildContext context, {
    required String ownerType,
    List<({String id, String title})> events = const [],
    List<({String id, String title})> jobs = const [],
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AdCampaignFormSheet(
        ownerType: ownerType,
        events: events,
        jobs: jobs,
      ),
    );
  }

  @override
  State<AdCampaignFormSheet> createState() => _AdCampaignFormSheetState();
}

class _AdCampaignFormSheetState extends State<AdCampaignFormSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _imageUrl = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _hours = TextEditingController();
  final _pushTitle = TextEditingController();
  final _pushBody = TextEditingController();
  final _emailSubject = TextEditingController();
  final _linkUrl = TextEditingController();

  final _placements = <String>{'feed'};
  final _cities = <String>{};
  final _unis = <String>{};
  var _adKind = 'standard';
  var _linkType = 'none';
  String? _linkEventId;
  String? _linkJobId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.ownerType == 'community') {
      _adKind = 'sponsor_promo';
    }
    if (MockData.cities.isNotEmpty) _cities.add(MockData.cities.first);
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _body,
      _imageUrl,
      _start,
      _end,
      _hours,
      _pushTitle,
      _pushBody,
      _emailSubject,
      _linkUrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await CommerceService.submitAd({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'imageUrl': _imageUrl.text.trim(),
        'adKind': _adKind,
        'placements': _placements.toList(),
        'targetCities': _cities.toList(),
        'targetUniversities': _unis.toList(),
        'linkType': _linkType,
        'linkEventId': _linkEventId,
        'linkJobId': _linkJobId,
        'linkUrl': _linkUrl.text.trim(),
        'scheduleStart': _start.text.trim(),
        'scheduleEnd': _end.text.trim(),
        'preferredHours': _hours.text.trim(),
        'pushTitle': _pushTitle.text.trim(),
        'pushBody': _pushBody.text.trim(),
        'emailSubject': _emailSubject.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kinds = widget.ownerType == 'community'
        ? const [
            ('sponsor_promo', 'Sponsor tanıt (ücretsiz)'),
            ('event_promo', 'Ücretsiz etkinlik tanıt'),
            ('sponsor_paid', 'Ücretli sponsor reklamı'),
          ]
        : const [('standard', 'Standart firma reklamı')];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reklam talebi',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _adKind,
              items: [
                for (final k in kinds)
                  DropdownMenuItem(value: k.$1, child: Text(k.$2)),
              ],
              onChanged: (v) => setState(() => _adKind = v ?? _adKind),
              decoration: const InputDecoration(labelText: 'Tür'),
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            TextField(
              controller: _body,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Metin'),
            ),
            TextField(
              controller: _imageUrl,
              decoration: const InputDecoration(labelText: 'Görsel URL'),
            ),
            const SizedBox(height: 8),
            const Text('Mecralar', style: TextStyle(fontWeight: FontWeight.w800)),
            Wrap(
              spacing: 6,
              children: [
                for (final p in ['feed', 'reels', 'stories', 'push', 'email'])
                  FilterChip(
                    label: Text(p),
                    selected: _placements.contains(p),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _placements.add(p);
                      } else {
                        _placements.remove(p);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Hedef iller', style: TextStyle(fontWeight: FontWeight.w800)),
            Wrap(
              spacing: 6,
              children: [
                for (final c in MockData.cities)
                  FilterChip(
                    label: Text(c),
                    selected: _cities.contains(c),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _cities.add(c);
                      } else {
                        _cities.remove(c);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Hedef üniversiteler',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final u in MockData.universities)
                  FilterChip(
                    label: Text(u, overflow: TextOverflow.ellipsis),
                    selected: _unis.contains(u),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _unis.add(u);
                      } else {
                        _unis.remove(u);
                      }
                    }),
                  ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _linkType,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Bağlantı yok')),
                DropdownMenuItem(value: 'event', child: Text('Etkinlik')),
                DropdownMenuItem(value: 'job', child: Text('İş / staj')),
                DropdownMenuItem(value: 'sponsor', child: Text('Sponsor')),
                DropdownMenuItem(value: 'url', child: Text('URL')),
              ],
              onChanged: (v) => setState(() => _linkType = v ?? 'none'),
              decoration: const InputDecoration(labelText: 'Öne çıkar'),
            ),
            if (_linkType == 'event' && widget.events.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _linkEventId ?? widget.events.first.id,
                items: [
                  for (final e in widget.events)
                    DropdownMenuItem(value: e.id, child: Text(e.title)),
                ],
                onChanged: (v) => setState(() => _linkEventId = v),
              ),
            if (_linkType == 'job' && widget.jobs.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _linkJobId ?? widget.jobs.first.id,
                items: [
                  for (final j in widget.jobs)
                    DropdownMenuItem(value: j.id, child: Text(j.title)),
                ],
                onChanged: (v) => setState(() => _linkJobId = v),
              ),
            if (_linkType == 'url' || _linkType == 'sponsor')
              TextField(
                controller: _linkUrl,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
            TextField(
              controller: _start,
              decoration: const InputDecoration(
                labelText: 'Başlangıç ISO',
                hintText: '2026-08-01T10:00:00',
              ),
            ),
            TextField(
              controller: _end,
              decoration: const InputDecoration(labelText: 'Bitiş ISO'),
            ),
            TextField(
              controller: _hours,
              decoration: const InputDecoration(labelText: 'Saat notu'),
            ),
            if (_placements.contains('push')) ...[
              TextField(
                controller: _pushTitle,
                decoration: const InputDecoration(labelText: 'Push başlık'),
              ),
              TextField(
                controller: _pushBody,
                decoration: const InputDecoration(labelText: 'Push metin'),
              ),
            ],
            if (_placements.contains('email'))
              TextField(
                controller: _emailSubject,
                decoration: const InputDecoration(labelText: 'E-posta konu'),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Admin’e gönder'),
            ),
          ],
        ),
      ),
    );
  }
}

/// IBAN ödeme kartı (reklam teklifi)
class AdIbanPaymentCard extends StatelessWidget {
  const AdIbanPaymentCard({
    super.key,
    required this.amount,
    required this.iban,
    required this.holder,
    required this.code,
    this.bank = '',
  });

  final double amount;
  final String iban;
  final String holder;
  final String code;
  final String bank;

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label kopyalandı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reklam ödemesi',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _row(context, 'Tutar', '${amount.toStringAsFixed(2)} TL'),
          _row(context, 'IBAN', iban),
          _row(context, 'Alıcı', holder),
          if (bank.isNotEmpty) _row(context, 'Banka', bank),
          _row(context, 'Açıklama kodu', code, emphasize: true),
          const SizedBox(height: 6),
          const Text(
            'Açıklamaya yalnızca kodu yaz. Ödeme sonrası admin onaylar.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: emphasize ? AppColors.navy : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _copy(context, label, value),
            icon: const Icon(Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}

class OrgInviteService {
  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<void> invite({
    required String orgId,
    required String orgType,
    required String inviteeUid,
    required bool grantPanelAccess,
    required bool grantBlueBadge,
  }) async {
    await _fn.httpsCallable('inviteOrgMember').call({
      'orgId': orgId,
      'orgType': orgType,
      'inviteeUid': inviteeUid,
      'grantPanelAccess': grantPanelAccess,
      'grantBlueBadge': grantBlueBadge,
    });
  }

  static Future<Map<String, dynamic>> getInvite(String id) async {
    final res = await _fn.httpsCallable('getOrgInvite').call({'inviteId': id});
    return Map<String, dynamic>.from(
      (res.data as Map?)?['invite'] as Map? ?? {},
    );
  }

  static Future<void> respond({
    required String inviteId,
    required bool accept,
  }) async {
    await _fn.httpsCallable('respondOrgInvite').call({
      'inviteId': inviteId,
      'accept': accept,
    });
  }

  static Future<void> revoke({
    required String orgId,
    String? memberUid,
    String? inviteId,
    bool removeBadge = true,
  }) async {
    await _fn.httpsCallable('revokeOrgMember').call({
      'orgId': orgId,
      if (memberUid != null) 'memberUid': memberUid,
      if (inviteId != null) 'inviteId': inviteId,
      'removeBadge': removeBadge,
    });
  }
}
