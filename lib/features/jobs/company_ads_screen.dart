import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage/ad_image_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../ads/ad_campaign_form.dart';
import '../auth/data/auth_provider.dart';
import '../commerce/commerce_service.dart';
import '../payments/payments_service.dart';
import '../jobs/jobs_provider.dart';
import 'company_portal.dart';

/// Firma reklam merkezi: talep, teklif, ödeme ve performans.
class CompanyAdsScreen extends StatefulWidget {
  const CompanyAdsScreen({super.key});

  @override
  State<CompanyAdsScreen> createState() => _CompanyAdsScreenState();
}

class _CompanyAdsScreenState extends State<CompanyAdsScreen> {
  List<Map<String, dynamic>> _ads = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ads = await CommerceService.getMyAds();
      if (mounted) setState(() => _ads = ads);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    if (me == null || !me.isCompany) {
      return const Scaffold(
        body: Center(child: Text('Firma hesabı gerekli')),
      );
    }

    final jobs = context
        .watch<JobsProvider>()
        .companyJobs
        .map((j) => (id: j.id, title: j.title))
        .toList();
    final visible = _ads.where((ad) {
      if (_filter == 'all') return true;
      final status = '${ad['displayStatus'] ?? ad['status'] ?? ''}';
      if (_filter == 'running') {
        return ['active', 'scheduled', 'paused', 'approved'].contains(status);
      }
      if (_filter == 'action') {
        return [
          'quoted',
          'awaiting_payment',
          'paid_review',
          'pending_quote',
          'pending_review',
        ].contains(status);
      }
      return ['completed', 'ended', 'cancelled', 'rejected'].contains(status);
    }).toList();

    return CompanyPortalShell(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reklamlarım'),
          actions: [
            IconButton(
              tooltip: 'Yenile',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final ok = await AdCampaignFormSheet.open(
              context,
              ownerType: 'company',
              allowEventLink: me.isEventOrganizer,
              jobs: jobs,
            );
            if (ok == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reklam talebi gönderildi')),
              );
              await _load();
            }
          },
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('Yeni reklam'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Akış, Reels, Hikâye, Push veya e-posta için reklam talebi '
                'oluşturun. Görseli yükleyin; sistem feed (16:9), reels (4:5) '
                've hikâye (9:16) boyutlarını kendisi üretir. Admin onayından '
                'sonra yayınlanır.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip('all', 'Tümü (${_ads.length})'),
                _filterChip('running', 'Yayında'),
                _filterChip('action', 'İşlem bekleyen'),
                _filterChip('archive', 'Arşiv'),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _ErrorCard(message: _error!, retry: _load)
            else if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    'Bu bölümde kampanya yok.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              for (final ad in visible)
                _CampaignCard(
                  data: ad,
                  onChanged: _load,
                  onOpen: () => _openDetails(ad),
                ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Future<void> _openDetails(Map<String, dynamic> ad) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CampaignDetailSheet(data: ad, onChanged: _load),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.data,
    required this.onChanged,
    required this.onOpen,
  });
  final Map<String, dynamic> data;
  final Future<void> Function() onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final image = '${data['imageUrl'] ?? ''}';
    final placements = (data['placements'] as List? ?? const []).join(', ');
    final status = '${data['displayStatus'] ?? data['status'] ?? ''}';
    final metrics = Map<String, dynamic>.from(data['metrics'] as Map? ?? {});
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 92,
                    height: 70,
                    child: SafeNetworkImage(url: image, fit: BoxFit.cover),
                  ),
                )
              else
                const SizedBox(
                  width: 92,
                  height: 70,
                  child: ColoredBox(
                    color: AppColors.background,
                    child: Icon(Icons.campaign_outlined),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${data['title'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _StatusPill(status: status),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      placements.isEmpty ? 'Mecra seçilmedi' : placements,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      children: [
                        _MetricMini(
                          label: 'Erişim',
                          value: '${metrics['reach'] ?? 0}',
                        ),
                        _MetricMini(
                          label: 'Gösterim',
                          value: '${metrics['impressions'] ?? 0}',
                        ),
                        _MetricMini(
                          label: 'Tıklama',
                          value: '${metrics['clicks'] ?? 0}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampaignDetailSheet extends StatefulWidget {
  const _CampaignDetailSheet({
    required this.data,
    required this.onChanged,
  });
  final Map<String, dynamic> data;
  final Future<void> Function() onChanged;

  @override
  State<_CampaignDetailSheet> createState() => _CampaignDetailSheetState();
}

class _CampaignDetailSheetState extends State<_CampaignDetailSheet> {
  bool _busy = false;

  Map<String, dynamic> get ad => widget.data;
  String get status => '${ad['displayStatus'] ?? ad['status'] ?? ''}';

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = Map<String, dynamic>.from(ad['metrics'] as Map? ?? {});
    final byPlacement =
        Map<String, dynamic>.from(ad['metricsByPlacement'] as Map? ?? {});
    final locations =
        Map<String, dynamic>.from(ad['deliveryLocations'] as Map? ?? {});
    final history = ad['statusHistory'] as List? ?? const [];
    final image = '${ad['imageUrl'] ?? ''}';

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${ad['title'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _StatusPill(status: status),
              ],
            ),
            const SizedBox(height: 12),
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SafeNetworkImage(url: image, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 16),
            _sectionTitle('Performans'),
            Row(
              children: [
                Expanded(
                  child: _MetricBox(
                    label: 'Erişim',
                    value: '${metrics['reach'] ?? 0}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricBox(
                    label: 'Gösterim',
                    value: '${metrics['impressions'] ?? 0}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricBox(
                    label: 'Tıklama',
                    value: '${metrics['clicks'] ?? 0}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricBox(
                    label: 'E-posta',
                    value: '${metrics['emailSent'] ?? ad['reachMailCount'] ?? 0}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricBox(
                    label: 'Açılma',
                    value: '${metrics['emailOpened'] ?? 0}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricBox(
                    label: 'Push',
                    value: '${metrics['pushSent'] ?? ad['reachPushCount'] ?? 0}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('Yayın detayları'),
            _info('Mecralar', (ad['placements'] as List? ?? const []).join(', ')),
            _info('Hedef iller', (ad['targetCities'] as List? ?? const []).join(', ')),
            _info(
              'Hedef üniversiteler',
              (ad['targetUniversities'] as List? ?? const []).join(', '),
            ),
            _info('Başlangıç', '${ad['scheduleStart'] ?? '—'}'),
            _info('Bitiş', '${ad['scheduleEnd'] ?? '—'}'),
            _info('Bağlantı', '${ad['linkUrl'] ?? '—'}'),
            if (byPlacement.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle('Mecra bazında sonuçlar'),
              for (final entry in byPlacement.entries)
                _breakdownRow(entry.key, entry.value),
            ],
            if (locations.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle('Gösterildiği yerler'),
              for (final entry in locations.entries.take(12))
                _breakdownRow(entry.key.replaceAll('_', ' '), entry.value),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle('Kampanya geçmişi'),
              for (final raw in history.reversed.take(12))
                Builder(
                  builder: (_) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(_statusLabel('${item['status'] ?? ''}')),
                      subtitle: Text('${item['at'] ?? ''}'),
                    );
                  },
                ),
            ],
            if (status == 'quoted') ...[
              const SizedBox(height: 18),
              _sectionTitle('Fiyat teklifi'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(ad['quotedAmount'] as num?)?.toStringAsFixed(2) ?? '0'} TL',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                    ),
                    if ('${ad['quoteNote'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${ad['quoteNote']}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Teklifi kabul edince IBAN ve ödeme kodu açılır. '
                      'Havale sonrası “Ödemeyi yaptım” ile bildirirsiniz; '
                      'admin onaylayınca reklam yayına girer.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await CommerceService.acceptAdQuote('${ad['id']}');
                          }),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Teklifi kabul et'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await CommerceService.declineAdQuote('${ad['id']}');
                          }),
                  icon: const Icon(Icons.close),
                  label: const Text('Teklifi reddet'),
                ),
              ),
            ],
            if (status == 'awaiting_payment') ...[
              const SizedBox(height: 18),
              _sectionTitle('Ödeme bilgileri'),
              const Text(
                'Aşağıdaki IBAN’a teklif tutarını yatırın. Açıklamaya yalnızca '
                'ödeme kodunu yazın.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              AdIbanPaymentCard(
                amount: (ad['quotedAmount'] as num?)?.toDouble() ?? 0,
                iban: '${ad['payoutIban'] ?? ''}',
                holder: '${ad['payoutIbanHolder'] ?? ''}',
                bank: '${ad['payoutBank'] ?? ''}',
                code: '${ad['ibanReference'] ?? ''}',
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          final messenger = ScaffoldMessenger.of(context);
                          _run(() async {
                            final message = await PaymentsService.confirmIban(
                              '${ad['paymentOrderId']}',
                            );
                            messenger.showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                          });
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Ödemeyi yaptım'),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (![
                  'awaiting_payment',
                  'paid_review',
                  'completed',
                  'cancelled',
                ].contains(status))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Düzenle'),
                  ),
                if (![
                  'awaiting_payment',
                  'paid_review',
                  'completed',
                  'cancelled',
                ].contains(status))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _replaceCreative,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Görseli değiştir'),
                  ),
                if (!['awaiting_payment', 'paid_review'].contains(status))
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      ['active', 'scheduled', 'paused', 'approved'].contains(status)
                          ? 'Kampanyayı durdur'
                          : 'Sil',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final title = TextEditingController(text: '${ad['title'] ?? ''}');
    final body = TextEditingController(text: '${ad['body'] ?? ''}');
    final url = TextEditingController(text: '${ad['linkUrl'] ?? ''}');
    final emailHeadline =
        TextEditingController(text: '${ad['emailHeadline'] ?? ad['title'] ?? ''}');
    final emailBody =
        TextEditingController(text: '${ad['emailBody'] ?? ad['body'] ?? ''}');
    final cta = TextEditingController(text: '${ad['ctaLabel'] ?? 'Detayları Gör'}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kampanyayı düzenle'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Başlık'),
                ),
                TextField(
                  controller: body,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reklam metni'),
                ),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'Firma / kampanya bağlantısı',
                  ),
                ),
                TextField(
                  controller: emailHeadline,
                  decoration: const InputDecoration(
                    labelText: 'E-posta başlığı',
                  ),
                ),
                TextField(
                  controller: emailBody,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'E-posta içeriği',
                  ),
                ),
                TextField(
                  controller: cta,
                  decoration: const InputDecoration(labelText: 'Buton metni'),
                ),
                if (['active', 'scheduled', 'paused', 'approved'].contains(status))
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Aktif kampanyada hedef ve mecra değişmez; içerik ve '
                      'bağlantı güncellenebilir.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        await CommerceService.updateAd('${ad['id']}', {
          'title': title.text.trim(),
          'body': body.text.trim(),
          'linkUrl': url.text.trim(),
          'emailHeadline': emailHeadline.text.trim(),
          'emailBody': emailBody.text.trim(),
          'ctaLabel': cta.text.trim(),
        });
      });
    }
    title.dispose();
    body.dispose();
    url.dispose();
    emailHeadline.dispose();
    emailBody.dispose();
    cta.dispose();
  }

  Future<void> _replaceCreative() async {
    setState(() => _busy = true);
    try {
      final uploaded = await AdImageUpload.pickAndUpload(
        onProgress: (stage, progress) {
          if (!mounted || progress < 1) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yeni görsel boyutları hazırlandı')),
          );
        },
      );
      await CommerceService.updateAd('${ad['id']}', {
        'imageUrl': uploaded.imageUrl,
        'imageVariants': uploaded.variants,
      });
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted && !'$e'.contains('Görsel seçilmedi')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Görsel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final active =
        ['active', 'scheduled', 'paused', 'approved'].contains(status);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(active ? 'Kampanyayı durdur?' : 'Reklamı sil?'),
        content: Text(
          active
              ? 'Yayın hemen durur. Geçmiş performans verileri korunur.'
              : 'Bu reklam kuyruğundan kalıcı olarak silinir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(active ? 'Durdur' : 'Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => CommerceService.deleteAd('${ad['id']}'));
    }
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      );

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            Expanded(child: Text(value.isEmpty ? '—' : value)),
          ],
        ),
      );

  Widget _breakdownRow(String label, dynamic raw) {
    final data = Map<String, dynamic>.from(raw as Map? ?? {});
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(
        '${data['reach'] ?? 0} erişim · '
        '${data['impressions'] ?? 0} gösterim · '
        '${data['clicks'] ?? 0} tıklama',
      ),
    );
  }
}

class _MetricMini extends StatelessWidget {
  const _MetricMini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text(
        '$label $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      );
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' || 'approved' => Colors.green,
      'quoted' || 'awaiting_payment' => Colors.orange,
      'rejected' || 'cancelled' => Colors.red,
      'paused' => Colors.blueGrey,
      _ => AppColors.navy,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'pending_quote' => 'Teklif bekliyor',
      'pending_review' || 'pending' => 'İncelemede',
      'quoted' => 'Teklif geldi',
      'quote_declined' => 'Teklif reddedildi',
      'awaiting_payment' => 'Ödeme bekliyor',
      'paid_review' => 'Ödeme inceleniyor',
      'active' || 'approved' => 'Yayında',
      'scheduled' => 'Planlandı',
      'paused' => 'Duraklatıldı',
      'completed' || 'ended' => 'Tamamlandı',
      'rejected' => 'Reddedildi',
      'cancelled' => 'İptal edildi',
      _ => status,
    };

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Reklamlar alınamadı'),
          subtitle: Text(message),
          trailing: IconButton(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
}
