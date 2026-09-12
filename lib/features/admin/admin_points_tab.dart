import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../points/points_models.dart';

/// Admin: puan oranları, Sil Süpür günü/ağırlıklar, katalog (eSIM dahil).
class AdminPointsTab extends StatefulWidget {
  const AdminPointsTab({super.key});

  @override
  State<AdminPointsTab> createState() => _AdminPointsTabState();
}

class _AdminPointsTabState extends State<AdminPointsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _fn = FirebaseFunctions.instanceFor(region: 'europe-west1');

  bool _loading = true;
  String? _error;
  PointsConfig _config = const PointsConfig();
  double? _esimBalanceUsd;
  List<PointsCatalogItem> _catalog = [];
  List<Map<String, dynamic>> _esimPackages = [];

  final _tlCtrl = TextEditingController();
  final _postCtrl = TextEditingController();
  final _reelCtrl = TextEditingController();
  final _storyCtrl = TextEditingController();
  final _likeCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  final _repostCtrl = TextEditingController();
  final _spinCtrl = TextEditingController();
  final _hourCtrl = TextEditingController();
  final _notifyTitleCtrl = TextEditingController();
  final _notifyBodyCtrl = TextEditingController();
  final _accessCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _userPtsUid = TextEditingController();
  final _userPtsDelta = TextEditingController();
  final _usdCtrl = TextEditingController();
  final _marginCtrl = TextEditingController();

  int _weekday = 3;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _tlCtrl.dispose();
    _postCtrl.dispose();
    _reelCtrl.dispose();
    _storyCtrl.dispose();
    _likeCtrl.dispose();
    _commentCtrl.dispose();
    _repostCtrl.dispose();
    _spinCtrl.dispose();
    _hourCtrl.dispose();
    _notifyTitleCtrl.dispose();
    _notifyBodyCtrl.dispose();
    _accessCtrl.dispose();
    _secretCtrl.dispose();
    _userPtsUid.dispose();
    _userPtsDelta.dispose();
    _usdCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  void _fillControllers(PointsConfig c) {
    _tlCtrl.text = c.tlPerPoint.toString();
    _postCtrl.text = '${c.earn.post}';
    _reelCtrl.text = '${c.earn.reel}';
    _storyCtrl.text = '${c.earn.story}';
    _likeCtrl.text = '${c.earn.likeReceived}';
    _commentCtrl.text = '${c.earn.commentReceived}';
    _repostCtrl.text = '${c.earn.repostReceived}';
    _spinCtrl.text = '${c.silSupur.freeSpinsPerWeek}';
    _hourCtrl.text = '${c.silSupur.hour}';
    _notifyTitleCtrl.text = c.silSupur.notifyTitle;
    _notifyBodyCtrl.text = c.silSupur.notifyBody;
    _weekday = c.silSupur.weekday;
    _usdCtrl.text = c.usdTryRate.toString();
    _marginCtrl.text = c.defaultMarginPercent.toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfgRes = await _fn.httpsCallable('adminGetPointsConfig').call();
      final data = Map<String, dynamic>.from(cfgRes.data as Map? ?? {});
      final cfg = PointsConfig.fromMap(
        Map<String, dynamic>.from((data['config'] as Map?) ?? {}),
      );
      final cat = await PointsService.listCatalog(admin: true);
      if (!mounted) return;
      _fillControllers(cfg);
      setState(() {
        _config = cfg;
        _esimBalanceUsd = data['esimBalanceUsd'] == null
            ? null
            : (num.tryParse('${data['esimBalanceUsd']}') ?? 0).toDouble();
        _catalog = cat;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    final next = PointsConfig(
      enabled: _config.enabled,
      tlPerPoint: double.tryParse(_tlCtrl.text.trim()) ?? _config.tlPerPoint,
      usdTryRate: double.tryParse(_usdCtrl.text.trim()) ?? _config.usdTryRate,
      defaultMarginPercent:
          double.tryParse(_marginCtrl.text.trim()) ?? _config.defaultMarginPercent,
      earn: PointsEarnRates(
        post: int.tryParse(_postCtrl.text.trim()) ?? _config.earn.post,
        reel: int.tryParse(_reelCtrl.text.trim()) ?? _config.earn.reel,
        story: int.tryParse(_storyCtrl.text.trim()) ?? _config.earn.story,
        likeReceived: int.tryParse(_likeCtrl.text.trim()) ?? _config.earn.likeReceived,
        commentReceived:
            int.tryParse(_commentCtrl.text.trim()) ?? _config.earn.commentReceived,
        repostReceived:
            int.tryParse(_repostCtrl.text.trim()) ?? _config.earn.repostReceived,
      ),
      silSupur: SilSupurConfig(
        enabled: _config.silSupur.enabled,
        weekday: _weekday,
        hour: int.tryParse(_hourCtrl.text.trim()) ?? _config.silSupur.hour,
        minute: _config.silSupur.minute,
        freeSpinsPerWeek:
            int.tryParse(_spinCtrl.text.trim()) ?? _config.silSupur.freeSpinsPerWeek,
        segments: _config.silSupur.segments,
        notifyTitle: _notifyTitleCtrl.text.trim(),
        notifyBody: _notifyBodyCtrl.text.trim(),
      ),
    );
    try {
      await _fn.httpsCallable('adminSavePointsConfig').call({'config': next.toMap()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ayarlar kaydedildi')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _seed() async {
    try {
      await _fn.httpsCallable('adminSeedDefaultCatalog').call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Varsayılan eSIM katalogu yüklendi')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _loadEsimPackages({String location = 'TR'}) async {
    try {
      final res = await _fn.httpsCallable('adminListEsimPackages').call({
        'locationCode': location,
      });
      final items = (res.data as Map?)?['items'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _esimPackages = items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editItem([PointsCatalogItem? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final points = TextEditingController(text: '${existing?.pointsCost ?? 100}');
    final cash = TextEditingController(
      text: existing?.cashPriceTl == null ? '' : '${existing!.cashPriceTl}',
    );
    final loc = TextEditingController(text: existing?.locationLabel ?? '');
    final locCodes = TextEditingController(text: existing?.locationCodes ?? '');
    final code = TextEditingController(text: existing?.packageCode ?? '');
    final slug = TextEditingController(text: existing?.slug ?? '');
    final weight = TextEditingController(text: '${existing?.silSupurWeight ?? 0}');
    final costUsd = TextEditingController(
      text: existing?.costUsd == null ? '' : '${existing!.costUsd}',
    );
    final margin = TextEditingController(
      text: '${existing?.marginPercent ?? _config.defaultMarginPercent}',
    );
    var type = existing?.type ?? 'esim';
    var active = existing?.active ?? true;
    var sil = existing?.silSupurEligible ?? false;

    void recalcKp(void Function(void Function()) setLocal) {
      final usd = double.tryParse(costUsd.text.trim().replaceAll(',', '.'));
      final m = double.tryParse(margin.text.trim().replaceAll(',', '.'));
      if (usd == null || usd <= 0) return;
      final kp = _config.kpFromUsd(usd, marginPercent: m);
      final sale = _config.saleTryFromUsd(usd, marginPercent: m);
      points.text = '$kp';
      cash.text = sale.toStringAsFixed(2);
      setLocal(() {});
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Ürün ekle' : 'Ürün düzenle'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'esim', child: Text('eSIM')),
                      DropdownMenuItem(value: 'gift', child: Text('Hediye')),
                    ],
                    onChanged: (v) => setLocal(() => type = v ?? 'esim'),
                    decoration: const InputDecoration(labelText: 'Tür'),
                  ),
                  TextField(controller: title, decoration: const InputDecoration(labelText: 'Başlık')),
                  TextField(controller: desc, decoration: const InputDecoration(labelText: 'Açıklama'), maxLines: 2),
                  if (type == 'esim') ...[
                    TextField(
                      controller: costUsd,
                      decoration: const InputDecoration(
                        labelText: 'Tedarikçi maliyet (USD)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => recalcKp(setLocal),
                    ),
                    TextField(
                      controller: margin,
                      decoration: InputDecoration(
                        labelText: 'Kar marjı %',
                        helperText:
                            'Satış ₺ = USD × ${_config.usdTryRate.toStringAsFixed(1)} × (1+marj). KP otomatik.',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => recalcKp(setLocal),
                    ),
                  ],
                  TextField(
                    controller: points,
                    decoration: const InputDecoration(
                      labelText: 'KP maliyeti (Kampüsteyim Puan)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: cash,
                    decoration: const InputDecoration(
                      labelText: 'Nakit fiyat (₺, isteğe bağlı)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(controller: loc, decoration: const InputDecoration(labelText: 'Lokasyon etiketi')),
                  TextField(
                    controller: locCodes,
                    decoration: const InputDecoration(
                      labelText: 'Ülke kodları (mail / detay)',
                      hintText: 'TR veya AT,BE,DE,...TR',
                    ),
                  ),
                  if (type == 'esim') ...[
                    TextField(controller: code, decoration: const InputDecoration(labelText: 'packageCode')),
                    TextField(controller: slug, decoration: const InputDecoration(labelText: 'slug')),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif (markette görünsün)'),
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sil Süpür çarkına koy'),
                    subtitle: const Text('Açıksa bu eSIM / hediye haftalık çarkta çıkabilir'),
                    value: sil,
                    onChanged: (v) => setLocal(() {
                      sil = v;
                      if (v && (int.tryParse(weight.text) ?? 0) <= 0) {
                        weight.text = '5';
                      }
                    }),
                  ),
                  if (sil)
                    TextField(
                      controller: weight,
                      decoration: const InputDecoration(
                        labelText: 'Sil Süpür çıkma ağırlığı',
                        helperText: 'Yüksek = daha sık çıkar',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _fn.httpsCallable('upsertPointsCatalogItem').call({
        if (existing != null) 'id': existing.id,
        'type': type,
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'pointsCost': int.tryParse(points.text.trim()) ?? 0,
        'cashPriceTl': cash.text.trim().isEmpty
            ? null
            : double.tryParse(cash.text.trim().replaceAll(',', '.')),
        'costUsd': costUsd.text.trim().isEmpty
            ? null
            : double.tryParse(costUsd.text.trim().replaceAll(',', '.')),
        'marginPercent': double.tryParse(margin.text.trim().replaceAll(',', '.')),
        'locationLabel': loc.text.trim(),
        'locationCodes': locCodes.text.trim(),
        'active': active,
        'silSupurEligible': sil,
        'silSupurWeight': int.tryParse(weight.text.trim()) ?? 0,
        'packageCode': code.text.trim(),
        'slug': slug.text.trim(),
        'esim': {
          'packageCode': code.text.trim(),
          'slug': slug.text.trim(),
        },
        'sort': existing?.sort ?? (_catalog.length + 1) * 10,
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Yenile')),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_esimBalanceUsd != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'eSIM Access bakiye: \$${_esimBalanceUsd!.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Puan & Sil Süpür'),
            Tab(text: 'Katalog'),
            Tab(text: 'eSIM API paketleri'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _settingsPane(),
              _catalogPane(),
              _apiPane(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsPane() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Puan sistemi açık'),
          subtitle: const Text(
            'Öğrenciler ancak Market → durum da açıksa görür. Market kapalıysa KP / Sil Süpür / eSIM gizlenir.',
          ),
          value: _config.enabled,
          onChanged: (v) => setState(() => _config = PointsConfig(
                enabled: v,
                tlPerPoint: _config.tlPerPoint,
                usdTryRate: _config.usdTryRate,
                defaultMarginPercent: _config.defaultMarginPercent,
                earn: _config.earn,
                silSupur: _config.silSupur,
              )),
        ),
        TextField(
          controller: _tlCtrl,
          decoration: const InputDecoration(
            labelText: '1 KP kaç ₺? (Kampüsteyim Puan)',
            helperText: 'Market kartlarında ≈ ₺ olarak görünür',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        TextField(
          controller: _usdCtrl,
          decoration: const InputDecoration(
            labelText: 'USD → ₺ kuru (eSIM maliyet hesabı)',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        TextField(
          controller: _marginCtrl,
          decoration: const InputDecoration(
            labelText: 'Varsayılan kar marjı %',
            helperText: 'API’den ürün eklerken KP bu marjla hesaplanır',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        const Text('Etkileşim puanları', style: TextStyle(fontWeight: FontWeight.w800)),
        _num('Post', _postCtrl),
        _num('Reels', _reelCtrl),
        _num('Hikâye', _storyCtrl),
        _num('Beğeni alma', _likeCtrl),
        _num('Yorum alma', _commentCtrl),
        _num('Repost alma', _repostCtrl),
        const Divider(height: 28),
        SwitchListTile(
          title: const Text('Sil Süpür açık'),
          value: _config.silSupur.enabled,
          onChanged: (v) => setState(() {
            _config = PointsConfig(
              enabled: _config.enabled,
              tlPerPoint: _config.tlPerPoint,
              usdTryRate: _config.usdTryRate,
              defaultMarginPercent: _config.defaultMarginPercent,
              earn: _config.earn,
              silSupur: SilSupurConfig(
                enabled: v,
                weekday: _config.silSupur.weekday,
                hour: _config.silSupur.hour,
                minute: _config.silSupur.minute,
                freeSpinsPerWeek: _config.silSupur.freeSpinsPerWeek,
                segments: _config.silSupur.segments,
                notifyTitle: _config.silSupur.notifyTitle,
                notifyBody: _config.silSupur.notifyBody,
              ),
            );
          }),
        ),
        DropdownButtonFormField<int>(
          value: _weekday,
          decoration: const InputDecoration(labelText: 'Sil Süpür günü'),
          items: [
            for (var i = 0; i < 7; i++)
              DropdownMenuItem(value: i, child: Text(SilSupurConfig.weekdayLabels[i])),
          ],
          onChanged: (v) => setState(() => _weekday = v ?? 3),
        ),
        _num('Bildirim saati (0-23, İstanbul)', _hourCtrl),
        _num('Haftalık ücretsiz çevirme', _spinCtrl),
        TextField(controller: _notifyTitleCtrl, decoration: const InputDecoration(labelText: 'Bildirim başlığı')),
        TextField(controller: _notifyBodyCtrl, decoration: const InputDecoration(labelText: 'Bildirim metni'), maxLines: 2),
        const SizedBox(height: 16),
        const Text('eSIM Access anahtarları', style: TextStyle(fontWeight: FontWeight.w800)),
        TextField(
          controller: _accessCtrl,
          decoration: const InputDecoration(labelText: 'AccessCode'),
          obscureText: true,
        ),
        TextField(
          controller: _secretCtrl,
          decoration: const InputDecoration(labelText: 'SecretKey'),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              await _fn.httpsCallable('adminSetEsimSecrets').call({
                'accessCode': _accessCtrl.text.trim(),
                'secretKey': _secretCtrl.text.trim(),
              });
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('eSIM anahtarları kaydedildi')),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
            }
          },
          child: const Text('Anahtarları kaydet'),
        ),
        const Divider(height: 28),
        const Text('Kullanıcı puanı (negatif de olabilir)', style: TextStyle(fontWeight: FontWeight.w800)),
        TextField(controller: _userPtsUid, decoration: const InputDecoration(labelText: 'Kullanıcı uid')),
        TextField(
          controller: _userPtsDelta,
          decoration: const InputDecoration(labelText: 'Delta (örn. 50 veya -20)'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              await _fn.httpsCallable('adminAdjustPoints').call({
                'uid': _userPtsUid.text.trim(),
                'delta': int.tryParse(_userPtsDelta.text.trim()) ?? 0,
                'note': 'admin_panel',
              });
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Puan güncellendi')),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
            }
          },
          child: const Text('Puan uygula'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Çarkta “Tekrar dene / puan” dilimleri varsayılan ayardadır. '
          'Katalogda Sil Süpür ağırlığı > 0 olan eSIM ve hediyeler çarka eklenir.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saveConfig, child: const Text('Kaydet')),
      ],
    );
  }

  Widget _catalogPane() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilledButton.tonal(onPressed: _seed, child: const Text('Varsayılan eSIM’leri yükle')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _editItem(), child: const Text('Ürün ekle')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _catalog.length,
            itemBuilder: (_, i) {
              final it = _catalog[i];
              return ListTile(
                leading: Icon(it.isEsim ? Icons.sim_card : Icons.card_giftcard),
                title: Text(it.title),
                subtitle: Text(
                  '${it.pointsCost} KP'
                  '${it.costUsd != null ? ' · maliyet \$${it.costUsd!.toStringAsFixed(2)}' : ''}'
                  '${it.marginPercent != null ? ' · marj %${it.marginPercent!.toStringAsFixed(0)}' : ''}'
                  '${it.locationLabel != null ? ' · ${it.locationLabel}' : ''}'
                  '${it.silSupurEligible ? ' · Sil Süpür w=${it.silSupurWeight}' : ''}'
                  '${it.packageCode != null ? '\n${it.packageCode}' : ''}',
                ),
                isThreeLine: it.packageCode != null,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editItem(it),
                ),
                onLongPress: () async {
                  final del = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Silinsin mi?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
                      ],
                    ),
                  );
                  if (del != true) return;
                  await _fn.httpsCallable('deletePointsCatalogItem').call({'id': it.id});
                  await _load();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _apiPane() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _loadEsimPackages(location: 'ALL'),
                child: const Text('TR ucuz + EU-30'),
              ),
              FilledButton.tonal(
                onPressed: () => _loadEsimPackages(location: 'TR'),
                child: const Text('Sadece TR'),
              ),
              FilledButton.tonal(
                onPressed: () => _loadEsimPackages(location: 'EU30'),
                child: const Text('EU-30 (TR dahil)'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _esimPackages.length,
            itemBuilder: (_, i) {
              final p = _esimPackages[i];
              return ListTile(
                title: Text('${p['name']}'),
                subtitle: Text(
                  '${p['packageCode']} · ${p['slug']}\n'
                  '\$${(p['priceUsd'] as num?)?.toStringAsFixed(2)} · '
                  '${(p['volumeGb'] as num?)?.toStringAsFixed(2)}GB · ${p['duration']}g\n'
                  '${p['location']}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    final usd = (p['priceUsd'] as num?)?.toDouble() ?? 0;
                    final locRaw = '${p['location'] ?? ''}';
                    final kp = usd > 0 ? _config.kpFromUsd(usd) : 100;
                    _editItem(
                      PointsCatalogItem(
                        id: '',
                        type: 'esim',
                        title: '${p['name']}',
                        pointsCost: kp,
                        cashPriceTl: usd > 0
                            ? _config.saleTryFromUsd(usd)
                            : null,
                        costUsd: usd > 0 ? usd : null,
                        marginPercent: _config.defaultMarginPercent,
                        locationLabel: locRaw == 'TR'
                            ? 'Türkiye'
                            : 'Avrupa + Türkiye (EU-30)',
                        locationCodes: locRaw,
                        packageCode: '${p['packageCode']}',
                        slug: '${p['slug']}',
                        silSupurEligible: false,
                        silSupurWeight: 0,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _num(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
        ),
      );
}
