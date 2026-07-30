import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/ad_image_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../data/mock/mock_data.dart';
import '../commerce/commerce_service.dart';

/// Ortak reklam formu — firma / topluluk
class AdCampaignFormSheet extends StatefulWidget {
  const AdCampaignFormSheet({
    super.key,
    required this.ownerType,
    this.events = const [],
    this.jobs = const [],
    this.allowEventLink = true,
  });

  final String ownerType; // company | community
  final List<({String id, String title})> events;
  final List<({String id, String title})> jobs;

  /// Organizatör olmayan firmalarda etkinlik bağlantısı gizlenir.
  final bool allowEventLink;

  static Future<bool?> open(
    BuildContext context, {
    required String ownerType,
    List<({String id, String title})> events = const [],
    List<({String id, String title})> jobs = const [],
    bool allowEventLink = true,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AdCampaignFormSheet(
        ownerType: ownerType,
        events: events,
        jobs: jobs,
        allowEventLink: allowEventLink,
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
  final _emailHeadline = TextEditingController();
  final _emailBody = TextEditingController();
  final _ctaLabel = TextEditingController(text: 'Detayları Gör');
  final _linkUrl = TextEditingController();

  final _placements = <String>{'feed'};
  final _cities = <String>{};
  final _unis = <String>{};
  var _adKind = 'standard';
  var _linkType = 'none';
  String? _linkEventId;
  String? _linkJobId;
  bool _busy = false;
  bool _uploading = false;
  String _uploadStage = '';
  double _uploadProgress = 0;
  Map<String, String> _imageVariants = {};

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
      _emailHeadline,
      _emailBody,
      _ctaLabel,
      _linkUrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickUploadImage() async {
    setState(() {
      _uploading = true;
      _uploadStage = 'seçim';
      _uploadProgress = 0;
    });
    try {
      final result = await AdImageUpload.pickAndUpload(
        onProgress: (stage, p) {
          if (!mounted) return;
          setState(() {
            _uploadStage = stage;
            _uploadProgress = p;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _imageUrl.text = result.imageUrl;
        _imageVariants = Map<String, String>.from(result.variants);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Görsel yüklendi · feed / reels / hikâye boyutları hazır'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      if (!msg.contains('Görsel seçilmedi')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yükleme: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = 0;
          _uploadStage = '';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_imageUrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce reklam görseli yükleyin')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      var linkType = _linkType;
      if (!widget.allowEventLink && linkType == 'event') {
        linkType = 'none';
      }
      await CommerceService.submitAd({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'imageUrl': _imageUrl.text.trim(),
        'imageVariants': _imageVariants,
        'adKind': _adKind,
        'placements': _placements.toList(),
        'targetCities': _cities.toList(),
        'targetUniversities': _unis.toList(),
        'linkType': linkType,
        'linkEventId': _linkEventId,
        'linkJobId': _linkJobId,
        'linkUrl': _linkUrl.text.trim(),
        'scheduleStart': _start.text.trim(),
        'scheduleEnd': _end.text.trim(),
        'preferredHours': _hours.text.trim(),
        'pushTitle': _pushTitle.text.trim(),
        'pushBody': _pushBody.text.trim(),
        'emailSubject': _emailSubject.text.trim(),
        'emailHeadline': _emailHeadline.text.trim(),
        'emailBody': _emailBody.text.trim(),
        'ctaLabel': _ctaLabel.text.trim(),
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
            const SizedBox(height: 10),
            const Text(
              'Reklam görseli',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Galeriden yükleyin. Sistem feed (16:9), reels (4:5) ve '
              'hikâye (9:16) boyutlarını otomatik üretir.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            if (_imageUrl.text.trim().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SafeNetworkImage(
                    url: _imageUrl.text.trim(),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (_uploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _uploadProgress.clamp(0.05, 1)),
              const SizedBox(height: 4),
              Text(
                _uploadStage.isEmpty ? 'Yükleniyor…' : _uploadStage,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (_busy || _uploading) ? null : _pickUploadImage,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(
                _imageUrl.text.trim().isEmpty
                    ? 'Görsel yükle'
                    : 'Görseli değiştir',
              ),
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
              items: [
                const DropdownMenuItem(value: 'none', child: Text('Bağlantı yok')),
                if (widget.allowEventLink)
                  const DropdownMenuItem(value: 'event', child: Text('Etkinlik')),
                const DropdownMenuItem(value: 'job', child: Text('İş / staj')),
                if (widget.ownerType == 'community')
                  const DropdownMenuItem(
                    value: 'sponsor',
                    child: Text('Sponsor'),
                  ),
                const DropdownMenuItem(value: 'url', child: Text('URL')),
              ],
              onChanged: (v) => setState(() => _linkType = v ?? 'none'),
              decoration: const InputDecoration(labelText: 'Öne çıkar'),
            ),
            if (widget.allowEventLink &&
                _linkType == 'event' &&
                widget.events.isNotEmpty)
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
            if (_placements.contains('email')) ...[
              TextField(
                controller: _emailSubject,
                decoration: const InputDecoration(labelText: 'E-posta konu'),
              ),
              TextField(
                controller: _emailHeadline,
                decoration: const InputDecoration(labelText: 'E-posta başlığı'),
              ),
              TextField(
                controller: _emailBody,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'E-posta reklam metni',
                  helperText:
                      'Kurumsal HTML şablona yerleştirilir; uygulama linki eklenmez.',
                ),
              ),
              TextField(
                controller: _ctaLabel,
                decoration: const InputDecoration(
                  labelText: 'Buton metni',
                  hintText: 'İncele / Başvur / Satın Al',
                ),
              ),
            ],
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
