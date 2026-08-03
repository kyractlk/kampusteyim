import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../admin/admin_user_search_field.dart';
import '../payments/admin_payments_panel.dart';
import 'plus_config.dart';
import 'plus_provider.dart';

/// Admin · Kampüsteyim Plus yönetimi
class AdminPlusTab extends StatefulWidget {
  const AdminPlusTab({super.key});

  @override
  State<AdminPlusTab> createState() => _AdminPlusTabState();
}

class _AdminPlusTabState extends State<AdminPlusTab> {
  final _trialDays = TextEditingController(text: '60');
  final _freeCv = TextEditingController(text: '2');
  final _freePosts = TextEditingController(text: '30');
  final _freeStories = TextEditingController(text: '20');
  final _freeFiles = TextEditingController(text: '0');
  final _plusCv = TextEditingController(text: '20');
  final _plusPosts = TextEditingController(text: '0');
  final _plusStories = TextEditingController(text: '0');
  final _plusFiles = TextEditingController(text: '15');
  final _pricing = TextEditingController();
  final _discount = TextEditingController();
  final _grantUser = TextEditingController();
  final _grantDays = TextEditingController(text: '60');

  PlusFeatures _features = const PlusFeatures();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  @override
  void dispose() {
    for (final c in [
      _trialDays,
      _freeCv,
      _freePosts,
      _freeStories,
      _freeFiles,
      _plusCv,
      _plusPosts,
      _plusStories,
      _plusFiles,
      _pricing,
      _discount,
      _grantUser,
      _grantDays,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate() {
    final cfg = context.read<PlusProvider>().config;
    _apply(cfg);
    setState(() => _loading = false);
  }

  void _apply(PlusConfig cfg) {
    _trialDays.text = '${cfg.trialDays}';
    _features = cfg.features;
    _freeCv.text = '${cfg.rateLimitsFree.cvAiDaily}';
    _freePosts.text = '${cfg.rateLimitsFree.postsDaily}';
    _freeStories.text = '${cfg.rateLimitsFree.storiesDaily}';
    _freeFiles.text = '${cfg.rateLimitsFree.filePostsDaily}';
    _plusCv.text = '${cfg.rateLimitsPlus.cvAiDaily}';
    _plusPosts.text = '${cfg.rateLimitsPlus.postsDaily}';
    _plusStories.text = '${cfg.rateLimitsPlus.storiesDaily}';
    _plusFiles.text = '${cfg.rateLimitsPlus.filePostsDaily}';
    _pricing.text = cfg.pricingNote;
    _discount.text = cfg.discountNote;
  }

  int _n(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  Future<void> _save() async {
    setState(() => _saving = true);
    final cfg = PlusConfig(
      trialDays: _n(_trialDays, 60).clamp(1, 365),
      features: _features,
      rateLimitsFree: PlusRateLimits(
        cvAiDaily: _n(_freeCv, 2),
        postsDaily: _n(_freePosts, 30),
        storiesDaily: _n(_freeStories, 20),
        filePostsDaily: _n(_freeFiles, 0),
      ),
      rateLimitsPlus: PlusRateLimits(
        cvAiDaily: _n(_plusCv, 20),
        postsDaily: _n(_plusPosts, 0),
        storiesDaily: _n(_plusStories, 0),
        filePostsDaily: _n(_plusFiles, 15),
      ),
      pricingNote: _pricing.text.trim(),
      discountNote: _discount.text.trim(),
    );
    final err = await context.read<PlusProvider>().saveConfig(cfg);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err == null ? 'Plus ayarları kaydedildi' : 'Hata: $err'),
      ),
    );
  }

  Future<void> _grant() async {
    final id = _grantUser.text.trim();
    if (id.isEmpty) return;
    final days = _n(_grantDays, 60).clamp(1, 730);
    final err = await context.read<PlusProvider>().adminGrantPlus(
          userId: id,
          days: days,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Plus atandı ($days gün)')),
    );
  }

  Future<void> _revoke() async {
    final id = _grantUser.text.trim();
    if (id.isEmpty) return;
    final err =
        await context.read<PlusProvider>().adminRevokePlus(userId: id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Plus kaldırıldı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<PlusProvider>();
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'KampüsteyimPlus',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ücretsiz deneme, özellik bayrakları ve rate limit. '
          'Kart / Shopier / IBAN ödemesi aşağıda yapılandırılır.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            color: AppColors.surfaceMuted,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Market vitrini',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              SelectableText(
                'https://app.kampusteyim.app/market',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Web satış + uygulama ödemeleri aynı API. Aylık tutar ödeme panelinden güncellenir.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _trialDays,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Ücretsiz deneme (gün)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Özellikler', style: TextStyle(fontWeight: FontWeight.w800)),
        SwitchListTile(
          title: const Text('Dosya paylaşımı'),
          value: _features.filePosts,
          onChanged: (v) =>
              setState(() => _features = _features.copyWith(filePosts: v)),
        ),
        SwitchListTile(
          title: const Text('CV tema / renk'),
          value: _features.cvTheme,
          onChanged: (v) =>
              setState(() => _features = _features.copyWith(cvTheme: v)),
        ),
        SwitchListTile(
          title: const Text('CV tüm diller'),
          value: _features.cvAllLanguages,
          onChanged: (v) => setState(
            () => _features = _features.copyWith(cvAllLanguages: v),
          ),
        ),
        SwitchListTile(
          title: const Text('Yüksek CV kotası'),
          value: _features.higherCvQuota,
          onChanged: (v) => setState(
            () => _features = _features.copyWith(higherCvQuota: v),
          ),
        ),
        SwitchListTile(
          title: const Text('Yeşil tick'),
          value: _features.greenBadge,
          onChanged: (v) =>
              setState(() => _features = _features.copyWith(greenBadge: v)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Rate limit — ücretsiz (0 = sınırsız)',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'CV-AI sunucuda uygulanır. Post / hikâye / dosya alanları yer tutucu.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        _numRow('CV-AI / gün', _freeCv),
        _numRow('Gönderi / gün*', _freePosts),
        _numRow('Hikâye / gün*', _freeStories),
        _numRow('Dosya post / gün*', _freeFiles),
        const SizedBox(height: 12),
        const Text(
          'Rate limit — Plus',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _numRow('CV-AI / gün', _plusCv),
        _numRow('Gönderi / gün*', _plusPosts),
        _numRow('Hikâye / gün*', _plusStories),
        _numRow('Dosya post / gün*', _plusFiles),
        const SizedBox(height: 16),
        TextField(
          controller: _pricing,
          decoration: const InputDecoration(
            labelText: 'Fiyat notu (görünen metin)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _discount,
          decoration: const InputDecoration(
            labelText: 'İndirim notu / push metni',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Plus ayarlarını kaydet'),
        ),
        const Divider(height: 36),
        const Text(
          'Bekleyen Plus IBAN ödemeleri',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const AdminPlusPaymentReviewsPanel(),
        const Divider(height: 36),
        const AdminPaymentsPanel(),
        const Divider(height: 36),
        const Text(
          'Kullanıcıya Plus ata / kaldır',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        AdminUserSearchField(
          controller: _grantUser,
          labelText: 'Kullanici ara (ad / e-posta / @handle / uid)',
          hintText: 'Ornek: Ali Veli veya ali@mail.com',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _grantDays,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Gün (ata)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _grant,
                child: const Text('Plus ata'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _revoke,
                child: const Text('Kaldır'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Hızlı ata: kullanıcılar sekmesinden uid kopyala. '
          'Hediye/transfer kapalı.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }

  Widget _numRow(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
