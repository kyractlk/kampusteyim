import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/storage/ad_image_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/panel_chrome.dart';
import '../../core/widgets/safe_network_image.dart';
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
  var _adKind = 'standard';
  var _linkType = 'none';
  String? _linkEventId;
  String? _linkJobId;
  DateTime? _startAt;
  DateTime? _endAt;
  TimeOfDay? _hourFrom;
  TimeOfDay? _hourTo;
  bool _busy = false;
  bool _uploading = false;
  String _uploadStage = '';
  double _uploadProgress = 0;
  Map<String, String> _imageVariants = {};
  int _step = 0;

  static const _stepLabels = ['İçerik', 'Hedef', 'Bağlantı', 'Gönder'];

  static const _placementLabels = {
    'feed': 'Akış',
    'reels': 'Reels',
    'stories': 'Hikâye',
    'push': 'Push',
    'email': 'E-posta',
  };

  @override
  void initState() {
    super.initState();
    if (widget.ownerType == 'community') {
      _adKind = 'sponsor_promo';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _body,
      _imageUrl,
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

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Seçilmedi';
    return DateFormat('d MMM yyyy · HH:mm', 'tr').format(d);
  }

  String _fmtTime(TimeOfDay? t) {
    if (t == null) return '—';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
    if (_cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir hedef il seçin')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      var linkType = _linkType;
      if (!widget.allowEventLink && linkType == 'event') {
        linkType = 'none';
      }
      final eventId = linkType == 'event'
          ? (_linkEventId ??
              (widget.events.isNotEmpty ? widget.events.first.id : null))
          : _linkEventId;
      final jobId = linkType == 'job'
          ? (_linkJobId ??
              (widget.jobs.isNotEmpty ? widget.jobs.first.id : null))
          : _linkJobId;
      var linkUrl = _linkUrl.text.trim();
      if (linkType == 'event' && (eventId ?? '').isNotEmpty) {
        linkUrl =
            'https://app.kampusteyim.app/event/${Uri.encodeComponent(eventId!)}';
      } else if (linkType == 'job' && (jobId ?? '').isNotEmpty) {
        final postId =
            jobId!.startsWith('job_') ? jobId : 'job_$jobId';
        linkUrl =
            'https://app.kampusteyim.app/post/${Uri.encodeComponent(postId)}';
      }
      final hours = _hours.text.trim().isNotEmpty
          ? _hours.text.trim()
          : (_hourFrom != null && _hourTo != null)
              ? '${_fmtTime(_hourFrom)}–${_fmtTime(_hourTo)}'
              : '';
      await CommerceService.submitAd({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'imageUrl': _imageUrl.text.trim(),
        'imageVariants': _imageVariants,
        'adKind': _adKind,
        'placements': _placements.toList(),
        'targetCities': _cities.toList(),
        'targetUniversities': const <String>[],
        'linkType': linkType,
        'linkEventId': eventId,
        'linkJobId': jobId,
        'linkUrl': linkUrl,
        'scheduleStart': _startAt?.toUtc().toIso8601String() ?? '',
        'scheduleEnd': _endAt?.toUtc().toIso8601String() ?? '',
        'preferredHours': hours,
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

  bool _canGoNext() {
    switch (_step) {
      case 0:
        if (_title.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Başlık gerekli')),
          );
          return false;
        }
        if (_imageUrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Önce reklam görseli yükleyin')),
          );
          return false;
        }
        return true;
      case 1:
        if (_placements.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('En az bir mecra seçin')),
          );
          return false;
        }
        if (_cities.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('En az bir hedef il seçin')),
          );
          return false;
        }
        return true;
      default:
        return true;
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
        4,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
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
            const SizedBox(height: 4),
            const Text(
              'Yayın il bazlıdır. Üniversite seçimi yoktur.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            PanelStepBar(labels: _stepLabels, step: _step),
            const SizedBox(height: 16),
            if (_step == 0) ...[
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PanelSectionLabel('İçerik'),
                    DropdownButtonFormField<String>(
                      initialValue: _adKind,
                      items: [
                        for (final k in kinds)
                          DropdownMenuItem(value: k.$1, child: Text(k.$2)),
                      ],
                      onChanged: (v) => setState(() => _adKind = v ?? _adKind),
                      decoration: const InputDecoration(labelText: 'Tür'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Başlık'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _body,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Metin'),
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
                      'Görsel',
                      subtitle:
                          'Feed (16:9), reels (4:5) ve hikâye (9:16) otomatik üretilir.',
                    ),
                    if (_imageUrl.text.trim().isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: SafeNetworkImage(
                            url: _imageUrl.text.trim(),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_uploading) ...[
                      LinearProgressIndicator(
                        value: _uploadProgress.clamp(0.05, 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _uploadStage.isEmpty ? 'Yükleniyor…' : _uploadStage,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: (_busy || _uploading) ? null : _pickUploadImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _imageUrl.text.trim().isEmpty
                            ? 'Görsel yükle'
                            : 'Görseli değiştir',
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_step == 1) ...[
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PanelSectionLabel('Mecralar'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _placementLabels.keys)
                          FilterChip(
                            label: Text(_placementLabels[p]!),
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
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PanelSectionLabel(
                      'Hedef iller',
                      subtitle:
                          'Reklam seçilen illerdeki kullanıcılara gösterilir.',
                    ),
                    CityTargetPicker(
                      selected: _cities,
                      onChanged: (v) => setState(() {
                        _cities
                          ..clear()
                          ..addAll(v);
                      }),
                    ),
                  ],
                ),
              ),
            ] else if (_step == 2) ...[
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PanelSectionLabel('Bağlantı'),
                    DropdownButtonFormField<String>(
                      initialValue: _linkType,
                      items: [
                        const DropdownMenuItem(
                          value: 'none',
                          child: Text('Bağlantı yok'),
                        ),
                        if (widget.allowEventLink)
                          const DropdownMenuItem(
                            value: 'event',
                            child: Text('Etkinlik'),
                          ),
                        const DropdownMenuItem(
                          value: 'job',
                          child: Text('İş / staj'),
                        ),
                        if (widget.ownerType == 'community')
                          const DropdownMenuItem(
                            value: 'sponsor',
                            child: Text('Sponsor'),
                          ),
                        const DropdownMenuItem(value: 'url', child: Text('URL')),
                      ],
                      onChanged: (v) => setState(() {
                        _linkType = v ?? 'none';
                        if (_linkType == 'job' &&
                            _linkJobId == null &&
                            widget.jobs.isNotEmpty) {
                          _linkJobId = widget.jobs.first.id;
                        }
                        if (_linkType == 'event' &&
                            _linkEventId == null &&
                            widget.events.isNotEmpty) {
                          _linkEventId = widget.events.first.id;
                        }
                      }),
                      decoration: const InputDecoration(labelText: 'Öne çıkar'),
                    ),
                    if (widget.allowEventLink &&
                        _linkType == 'event' &&
                        widget.events.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _linkEventId ?? widget.events.first.id,
                        items: [
                          for (final e in widget.events)
                            DropdownMenuItem(value: e.id, child: Text(e.title)),
                        ],
                        onChanged: (v) => setState(() => _linkEventId = v),
                        decoration: const InputDecoration(labelText: 'Etkinlik'),
                      ),
                    ],
                    if (_linkType == 'job' && widget.jobs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _linkJobId ?? widget.jobs.first.id,
                        items: [
                          for (final j in widget.jobs)
                            DropdownMenuItem(value: j.id, child: Text(j.title)),
                        ],
                        onChanged: (v) => setState(() => _linkJobId = v),
                        decoration: const InputDecoration(labelText: 'İlan'),
                      ),
                    ],
                    if (_linkType == 'url' || _linkType == 'sponsor') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _linkUrl,
                        decoration: const InputDecoration(labelText: 'URL'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PanelSectionLabel('Yayın takvimi'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_circle_outline),
                      title: const Text('Başlangıç'),
                      subtitle: Text(_fmtDate(_startAt)),
                      trailing: _startAt == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'Temizle',
                              onPressed: () => setState(() => _startAt = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      onTap: () async {
                        final d = await pickPanelDateTime(
                          context,
                          initial: _startAt,
                        );
                        if (d != null) setState(() => _startAt = d);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.stop_circle_outlined),
                      title: const Text('Bitiş'),
                      subtitle: Text(_fmtDate(_endAt)),
                      trailing: _endAt == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'Temizle',
                              onPressed: () => setState(() => _endAt = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      onTap: () async {
                        final d = await pickPanelDateTime(
                          context,
                          initial: _endAt ?? _startAt,
                          firstDate: _startAt,
                        );
                        if (d != null) setState(() => _endAt = d);
                      },
                    ),
                    const Divider(height: 8),
                    const SizedBox(height: 4),
                    const Text(
                      'Tercih edilen saat aralığı',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _hourFrom ?? TimeOfDay.now(),
                              );
                              if (t != null) setState(() => _hourFrom = t);
                            },
                            child: Text('Başlangıç: ${_fmtTime(_hourFrom)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _hourTo ?? TimeOfDay.now(),
                              );
                              if (t != null) setState(() => _hourTo = t);
                            },
                            child: Text('Bitiş: ${_fmtTime(_hourTo)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hours,
                      decoration: const InputDecoration(
                        labelText: 'Saat notu (opsiyonel)',
                        hintText: 'Örn. akşam yayınlansın',
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (_placements.contains('push'))
                PanelCard(
                  child: Column(
                    children: [
                      const PanelSectionLabel('Push bildirimi'),
                      TextField(
                        controller: _pushTitle,
                        decoration:
                            const InputDecoration(labelText: 'Push başlık'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pushBody,
                        decoration:
                            const InputDecoration(labelText: 'Push metin'),
                      ),
                    ],
                  ),
                ),
              if (_placements.contains('push') && _placements.contains('email'))
                const SizedBox(height: 12),
              if (_placements.contains('email'))
                PanelCard(
                  child: Column(
                    children: [
                      const PanelSectionLabel('E-posta reklamı'),
                      TextField(
                        controller: _emailSubject,
                        decoration: const InputDecoration(labelText: 'Konu'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _emailHeadline,
                        decoration: const InputDecoration(labelText: 'Başlık'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _emailBody,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Metin'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ctaLabel,
                        decoration: const InputDecoration(
                          labelText: 'Buton metni',
                          hintText: 'İncele / Başvur / Satın Al',
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_placements.contains('push') &&
                  !_placements.contains('email'))
                PanelCard(
                  child: Text(
                    '${_title.text.trim().isEmpty ? 'Reklam' : _title.text.trim()}\n'
                    '${_cities.length} il · ${_placements.length} mecra',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Yönetime gönder'),
              ),
            ],
            const SizedBox(height: 16),
            if (_step < _stepLabels.length - 1)
              Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step -= 1),
                      child: const Text('Geri'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (!_canGoNext()) return;
                      setState(() => _step += 1);
                    },
                    child: const Text('İleri'),
                  ),
                ],
              )
            else if (_step > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () => setState(() => _step -= 1),
                  child: const Text('Geri'),
                ),
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
    return PanelCard(
      color: AppColors.navy.withValues(alpha: 0.06),
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
            'Açıklamaya yalnızca kodu yazın. Ödeme sonrası yönetim ekibimiz inceler.',
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
