import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../points/points_models.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';
import 'admin_user_search_field.dart';

/// Web’de number input step=1 ondalığı engeller; text + filtre kullan.
List<TextInputFormatter> get _silPercentFormatters => [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ];

InputDecoration _silPercentDecoration({
  required String label,
  String? helperText,
  String? suffixText,
  bool isDense = false,
}) =>
    InputDecoration(
      labelText: label,
      helperText: helperText,
      suffixText: suffixText ?? '%',
      isDense: isDense,
      hintText: '0.005',
    );

/// Admin: puan dashboard / sorgula / ayarlar / katalog / eSIM.
class AdminPointsTab extends StatefulWidget {
  const AdminPointsTab({
    super.key,
    this.section = 'dashboard',
    this.showSectionMenu = false,
  });

  /// dashboard | users | settings | catalog | esim
  final String section;
  final bool showSectionMenu;

  @override
  State<AdminPointsTab> createState() => _AdminPointsTabState();
}

class _AdminPointsTabState extends State<AdminPointsTab> {
  late String _section;
  final _fn = FirebaseFunctions.instanceFor(region: 'europe-west1');
  AppUser? _selectedPtsUser;
  int? _selectedPtsBalance;
  List<Map<String, dynamic>> _selectedPtsLedger = [];
  bool _ptsQueryBusy = false;

  bool _loading = true;
  String? _error;
  PointsConfig _config = const PointsConfig();
  double? _esimBalanceUsd;
  bool _esimConfigured = false;
  bool _showSecretForm = false;
  bool _usdRefreshing = false;
  List<PointsCatalogItem> _catalog = [];
  List<Map<String, dynamic>> _esimPackages = [];
  bool _esimLoading = false;
  String? _esimError;
  String _esimFilter = 'ALL';
  String _esimQuery = '';
  final _esimSearchCtrl = TextEditingController();
  final Set<String> _selectedCatalogIds = {};
  final Set<String> _selectedPackageCodes = {};
  final _bulkMarginCtrl = TextEditingController();
  final Map<String, TextEditingController> _pkgSilPercentCtrls = {};
  final Map<String, bool> _pkgSilEligible = {};
  bool _bulkBusy = false;
  double _wheelPercentTotal = 0;
  List<Map<String, dynamic>> _wheelSegments = [];
  final List<_WheelSegEdit> _wheelEdits = [];

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
    _section = widget.section;
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminPointsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section && !widget.showSectionMenu) {
      _section = widget.section;
    }
  }

  @override
  void dispose() {
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
    _esimSearchCtrl.dispose();
    _bulkMarginCtrl.dispose();
    for (final c in _pkgSilPercentCtrls.values) {
      c.dispose();
    }
    _pkgSilPercentCtrls.clear();
    _disposeWheelEdits();
    super.dispose();
  }

  void _disposeWheelEdits() {
    for (final e in _wheelEdits) {
      e.dispose();
    }
    _wheelEdits.clear();
  }

  void _rebuildWheelEdits(PointsConfig cfg, List<PointsCatalogItem> cat) {
    _disposeWheelEdits();
    final base = cfg.silSupur.segments.isNotEmpty
        ? cfg.silSupur.segments
        : const [
            SilSupurSegment(id: 'miss', label: 'Tekrar dene', weight: 40, type: 'none'),
            SilSupurSegment(
              id: 'pts30',
              label: '+30 puan',
              weight: 22,
              type: 'points',
              points: 30,
            ),
            SilSupurSegment(
              id: 'pts80',
              label: '+80 puan',
              weight: 14,
              type: 'points',
              points: 80,
            ),
            SilSupurSegment(
              id: 'pts150',
              label: '+150 puan',
              weight: 8,
              type: 'points',
              points: 150,
            ),
          ];
    for (final s in base) {
      _wheelEdits.add(
        _WheelSegEdit.base(
          id: s.id.isNotEmpty ? s.id : 'seg_${DateTime.now().microsecondsSinceEpoch}',
          label: s.label,
          percent: s.weight.toDouble(),
          type: s.type,
          points: s.points ?? 0,
        ),
      );
    }
    for (final it in cat.where((e) => e.silSupurEligible && e.active)) {
      final pct = (it.silSupurPercent > 0 ? it.silSupurPercent : it.silSupurWeight)
          .toDouble();
      _wheelEdits.add(
        _WheelSegEdit.catalog(
          catalogId: it.id,
          label: it.title,
          percent: pct,
          type: it.type,
        ),
      );
    }
  }

  double get _editWheelPercentTotal {
    var t = 0.0;
    for (final e in _wheelEdits) {
      t += parseSilPercent(e.percentCtrl.text.trim());
    }
    return t;
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
    if (_bulkMarginCtrl.text.trim().isEmpty) {
      _bulkMarginCtrl.text = c.defaultMarginPercent.toString();
    }
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
      final wheel = data['silSupurWheel'] is Map
          ? Map<String, dynamic>.from(data['silSupurWheel'] as Map)
          : <String, dynamic>{};
      final wheelSegs = (wheel['segments'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final cat = await PointsService.listCatalog(admin: true);
      if (!mounted) return;
      _fillControllers(cfg);
      setState(() {
        _config = cfg;
        _esimBalanceUsd = data['esimBalanceUsd'] == null
            ? null
            : (num.tryParse('${data['esimBalanceUsd']}') ?? 0).toDouble();
        _esimConfigured = data['esimConfigured'] == true || _esimBalanceUsd != null;
        _catalog = cat;
        _selectedCatalogIds.removeWhere((id) => !cat.any((c) => c.id == id));
        _wheelPercentTotal =
            (num.tryParse('${wheel['percentTotal']}') ?? 0).toDouble();
        _wheelSegments = wheelSegs;
        _rebuildWheelEdits(cfg, cat);
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
    final parsedUsd =
        double.tryParse(_usdCtrl.text.trim().replaceAll(',', '.')) ??
            _config.usdTryRate;
    final rateChanged = (parsedUsd - _config.usdTryRate).abs() > 0.0001;
    final baseSegs = <SilSupurSegment>[];
    for (final e in _wheelEdits.where((x) => !x.isCatalog)) {
      final pct = parseSilPercent(e.percentCtrl.text.trim());
      final pts = int.tryParse(e.pointsCtrl.text.trim()) ?? 0;
      final type = e.type;
      baseSegs.add(
        SilSupurSegment(
          id: e.id,
          label: e.labelCtrl.text.trim().isEmpty ? e.id : e.labelCtrl.text.trim(),
          weight: pct,
          type: type,
          points: type == 'points' ? pts : null,
          title: e.labelCtrl.text.trim().isEmpty ? null : e.labelCtrl.text.trim(),
        ),
      );
    }
    final next = _config.copyWith(
      enabled: _config.enabled,
      tlPerPoint: double.tryParse(_tlCtrl.text.trim().replaceAll(',', '.')) ??
          _config.tlPerPoint,
      usdTryRate: parsedUsd,
      usdTrySource: rateChanged ? 'manual' : _config.usdTrySource,
      usdTryUpdatedAt:
          rateChanged ? DateTime.now().toUtc().toIso8601String() : _config.usdTryUpdatedAt,
      usdTryAuto: _config.usdTryAuto,
      defaultMarginPercent:
          double.tryParse(_marginCtrl.text.trim().replaceAll(',', '.')) ??
              _config.defaultMarginPercent,
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
        segments: baseSegs,
        notifyTitle: _notifyTitleCtrl.text.trim(),
        notifyBody: _notifyBodyCtrl.text.trim(),
      ),
    );
    try {
      await _fn.httpsCallable('adminSavePointsConfig').call({'config': next.toMap()});
      // Katalog dilim yüzdelerini de kaydet
      for (final e in _wheelEdits.where((x) => x.isCatalog)) {
        PointsCatalogItem? it;
        for (final c in _catalog) {
          if (c.id == e.catalogId) {
            it = c;
            break;
          }
        }
        if (it == null) continue;
        final pct = parseSilPercent(e.percentCtrl.text.trim());
        await _fn.httpsCallable('upsertPointsCatalogItem').call({
          'id': it.id,
          'type': it.type,
          'title': it.title,
          'description': it.description,
          'imageUrl': it.imageUrl,
          'pointsCost': it.pointsCost,
          'cashPriceTl': it.cashPriceTl,
          'costUsd': it.costUsd,
          'marginPercent': it.marginPercent,
          'locationLabel': it.locationLabel,
          'locationCodes': it.locationCodes,
          'active': it.active,
          'silSupurEligible': pct > 0,
          'silSupurWeight': pct,
          'silSupurPercent': pct,
          'packageCode': it.packageCode,
          'slug': it.slug,
          'sort': it.sort,
          'stock': it.stock,
          'esim': it.type == 'esim'
              ? {'packageCode': it.packageCode, 'slug': it.slug}
              : null,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ayarlar ve çark kaydedildi')),
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

  Future<void> _refreshUsdFromTcmb() async {
    setState(() => _usdRefreshing = true);
    try {
      final res = await _fn.httpsCallable('adminRefreshUsdTryRate').call();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final rate = (num.tryParse('${data['usdTryRate']}') ?? 0).toDouble();
      if (!mounted) return;
      if (rate > 0) {
        _usdCtrl.text = rate.toStringAsFixed(4);
        setState(() {
          _config = _config.copyWith(
            usdTryRate: rate,
            usdTrySource: '${data['usdTrySource'] ?? 'tcmb'}',
            usdTryUpdatedAt: data['usdTryUpdatedAt']?.toString(),
          );
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rate > 0
                ? 'TCMB kuru güncellendi: ${rate.toStringAsFixed(4)} ₺'
                : 'Kur güncellendi',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _usdRefreshing = false);
    }
  }

  bool get _canManageEsimSecrets {
    final admin = context.read<AdminProvider>();
    final me = context.read<AuthProvider>().user;
    if (me == null) return false;
    if (me.isSuperAdmin) return true;
    return admin.can(me, AdminPermission.manageEsimSecrets);
  }

  Future<void> _saveEsimSecrets() async {
    try {
      await _fn.httpsCallable('adminSetEsimSecrets').call({
        'accessCode': _accessCtrl.text.trim(),
        'secretKey': _secretCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('eSIM anahtarları kaydedildi')),
      );
      _accessCtrl.clear();
      _secretCtrl.clear();
      setState(() => _showSecretForm = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _loadEsimPackages({String location = 'ALL'}) async {
    setState(() {
      _esimLoading = true;
      _esimError = null;
      _esimFilter = location;
    });
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
        _selectedPackageCodes
            .removeWhere((c) => !_esimPackages.any((p) => '${p['packageCode']}' == c));
        _esimConfigured = true;
        _esimLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() {
        _esimLoading = false;
        _esimError = msg;
        if (msg.contains('kimlik') || msg.contains('anahtar') || msg.contains('failed-precondition')) {
          _esimConfigured = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  List<Map<String, dynamic>> get _filteredEsimPackages {
    final q = _esimQuery.trim().toLowerCase();
    if (q.isEmpty) return _esimPackages;
    return _esimPackages.where((p) {
      final blob =
          '${p['name']} ${p['slug']} ${p['packageCode']} ${p['location']}'
              .toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  void _addPackageToCatalog(Map<String, dynamic> p) {
    final usd = (p['priceUsd'] as num?)?.toDouble() ?? 0;
    final locRaw = '${p['location'] ?? ''}';
    final kp = usd > 0 ? _config.kpFromUsd(usd) : 100;
    _editItem(
      PointsCatalogItem(
        id: '',
        type: 'esim',
        title: '${p['name']}',
        pointsCost: kp,
        cashPriceTl: usd > 0 ? _config.saleTryFromUsd(usd) : null,
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
  }

  Future<bool> _confirm(String title, {String? body}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Onayla')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteCatalogSelection({required bool all}) async {
    if (!all && _selectedCatalogIds.isEmpty) return;
    final ok = await _confirm(
      all ? 'Tüm katalog silinsin mi?' : '${_selectedCatalogIds.length} ürün silinsin mi?',
      body: 'Bu işlem geri alınamaz.',
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await _fn.httpsCallable('deletePointsCatalogItems').call(
        all ? {'all': true} : {'ids': _selectedCatalogIds.toList()},
      );
      _selectedCatalogIds.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(all ? 'Katalog temizlendi' : 'Seçilenler silindi')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  TextEditingController _silPercentCtrlFor(String code) {
    return _pkgSilPercentCtrls.putIfAbsent(
      code,
      () => TextEditingController(text: '0'),
    );
  }

  void _togglePackageSelected(String code, bool selected) {
    setState(() {
      if (selected) {
        _selectedPackageCodes.add(code);
        _silPercentCtrlFor(code);
        _pkgSilEligible.putIfAbsent(code, () => false);
      } else {
        _selectedPackageCodes.remove(code);
        _pkgSilEligible.remove(code);
        final c = _pkgSilPercentCtrls.remove(code);
        c?.dispose();
      }
    });
  }

  double get _selectedSilPercentSum {
    var sum = 0.0;
    for (final code in _selectedPackageCodes) {
      if (_pkgSilEligible[code] != true) continue;
      sum += parseSilPercent(
        _pkgSilPercentCtrls[code]?.text.trim() ?? '0',
      );
    }
    return sum;
  }

  Future<void> _bulkAddSelectedPackages() async {
    final codes = _selectedPackageCodes.toSet();
    final packs = _esimPackages
        .where((p) => codes.contains('${p['packageCode']}'))
        .toList();
    if (packs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce paket seç')),
      );
      return;
    }
    final margin = double.tryParse(
          _bulkMarginCtrl.text.trim().replaceAll(',', '.'),
        ) ??
        _config.defaultMarginPercent;
    final silSum = _selectedSilPercentSum;
    final ok = await _confirm(
      '${packs.length} paket markete eklensin mi?',
      body:
          'Marj %${margin.toStringAsFixed(0)}\n'
          'Seçilen Sil Süpür payı toplamı: %${formatSilPercent(silSum)}\n'
          'Mevcut çark toplamı: %${formatSilPercent(_wheelPercentTotal)} '
          '(oranlar normalize edilir)',
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      final res = await _fn.httpsCallable('adminBulkUpsertPointsCatalog').call({
        'marginPercent': margin,
        'items': packs.map((p) {
          final code = '${p['packageCode']}';
          final pct = parseSilPercent(
            _pkgSilPercentCtrls[code]?.text.trim() ?? '0',
          );
          final eligible = _pkgSilEligible[code] == true && pct > 0;
          return {
            'packageCode': p['packageCode'],
            'slug': p['slug'],
            'name': p['name'],
            'priceUsd': p['priceUsd'],
            'location': p['location'],
            'duration': p['duration'],
            'volumeGb': p['volumeGb'],
            'silSupurEligible': eligible,
            'silSupurPercent': eligible ? pct : 0,
          };
        }).toList(),
      });
      final n = (res.data as Map?)?['upserted'] ?? packs.length;
      for (final c in _pkgSilPercentCtrls.values) {
        c.dispose();
      }
      _pkgSilPercentCtrls.clear();
      _pkgSilEligible.clear();
      _selectedPackageCodes.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$n ürün eklendi / güncellendi'),
          action: SnackBarAction(
            label: 'Katalog',
            onPressed: () => setState(() => _section = 'catalog'),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
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
    final weight = TextEditingController(
      text: formatSilPercent(existing?.silSupurPercent ?? existing?.silSupurWeight ?? 0),
    );
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
                      if (v &&
                          (double.tryParse(weight.text.replaceAll(',', '.')) ?? 0) <=
                              0) {
                        weight.text = '5';
                      }
                    }),
                  ),
                  if (sil)
                    TextField(
                      controller: weight,
                      decoration: _silPercentDecoration(
                        label: 'Sil Süpür çıkma %',
                        helperText:
                            'Ondalık serbest: 5 veya 0.005 — dilimler normalize edilir.',
                      ),
                      keyboardType: TextInputType.text,
                      inputFormatters: _silPercentFormatters,
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
        'silSupurWeight': parseSilPercent(weight.text.trim()),
        'silSupurPercent': parseSilPercent(weight.text.trim()),
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
        if (widget.showSectionMenu)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in const [
                    ('dashboard', 'Dashboard', Icons.dashboard_customize_outlined),
                    ('users', 'Puan sorgula', Icons.manage_search_outlined),
                    ('settings', 'Ayarlar', Icons.tune_outlined),
                    ('catalog', 'Katalog', Icons.inventory_2_outlined),
                    ('esim', 'eSIM API', Icons.sim_card_outlined),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(s.$3, size: 18),
                        label: Text(s.$2),
                        selected: _section == s.$1,
                        onSelected: (_) => setState(() => _section = s.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(child: _sectionBody()),
      ],
    );
  }

  Widget _sectionBody() {
    switch (_section) {
      case 'users':
        return _usersPane();
      case 'settings':
        return _settingsPane();
      case 'catalog':
        return _catalogPane();
      case 'esim':
        return _apiPane();
      case 'dashboard':
      default:
        return _dashboardPane();
    }
  }

  Widget _dashboardPane() {
    final live = _config.enabled;
    final silDay = const [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ][_weekday.clamp(1, 7)];
    final silOn = _catalog.where((e) => e.silSupurEligible).length;
    final esimCount = _catalog.where((e) => e.type == 'esim').length;
    final giftCount = _catalog.where((e) => e.type == 'gift').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B1F3A), Color(0xFF164E7A), Color(0xFF0EA5E9)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B1F3A).withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      live ? 'Sistem canlı' : 'Sistem kapalı',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Yenile',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Kampüsteyim Puan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '1 KP ≈ ${_config.tlPerPoint.toStringAsFixed(2)} ₺'
                '${_esimBalanceUsd != null ? ' · eSIM \$${_esimBalanceUsd!.toStringAsFixed(2)}' : ''}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _dashPill('Katalog', '${_catalog.length}'),
                  _dashPill('Sil Süpür', '$silOn'),
                  _dashPill('eSIM ürün', '$esimCount'),
                  _dashPill('Hediye', '$giftCount'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final cards = [
              _dashCard(
                icon: Icons.casino_outlined,
                title: 'Sil Süpür',
                body: '$silDay · saat ${_hourCtrl.text.trim().isEmpty ? _config.silSupur.hour : _hourCtrl.text} · ${_spinCtrl.text} çevirme/hafta',
                accent: const Color(0xFF0EA5E9),
              ),
              _dashCard(
                icon: Icons.currency_exchange,
                title: 'USD / TRY',
                body: _config.usdTryRate > 0
                    ? '${_config.usdTryRate.toStringAsFixed(4)} · ${_config.usdTrySource}'
                    : 'Kur henüz yok',
                accent: const Color(0xFF22C55E),
              ),
              _dashCard(
                icon: Icons.donut_large_outlined,
                title: 'Çark payı',
                body: _wheelSegments.isEmpty
                    ? 'Dilimler boş'
                    : 'Toplam %${formatSilPercent(_wheelPercentTotal)} · ${_wheelSegments.length} dilim',
                accent: const Color(0xFFF59E0B),
              ),
              _dashCard(
                icon: Icons.sim_card_outlined,
                title: 'eSIM Access',
                body: _esimConfigured
                    ? (_esimBalanceUsd != null
                        ? 'Bağlı · \$${_esimBalanceUsd!.toStringAsFixed(2)}'
                        : 'Anahtarlar bağlı')
                    : 'Anahtar bekleniyor',
                accent: _esimConfigured ? const Color(0xFF22C55E) : AppColors.crimson,
              ),
            ];
            if (wide) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final w in cards)
                    SizedBox(width: (c.maxWidth - 12) / 2, child: w),
                ],
              );
            }
            return Column(
              children: [
                for (final w in cards) ...[w, const SizedBox(height: 12)],
              ],
            );
          },
        ),
        if (_wheelSegments.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Çark özeti',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final s in _wheelSegments.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text('${s['label']}')),
                        Text(
                          '~${s['chance']}%',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Hızlı geçiş',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _section = 'users'),
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('Puan sorgula'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _section = 'catalog'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Katalog'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _section = 'esim'),
              icon: const Icon(Icons.sim_card_outlined),
              label: const Text('eSIM API'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _section = 'settings'),
              icon: const Icon(Icons.tune_outlined),
              label: const Text('Ayarlar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dashPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashCard({
    required IconData icon,
    required String title,
    required String body,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUserPoints(AppUser user) async {
    setState(() {
      _selectedPtsUser = user;
      _ptsQueryBusy = true;
      _userPtsUid.text = user.id;
      _selectedPtsBalance = null;
      _selectedPtsLedger = [];
    });
    try {
      final balSnap =
          await FirebaseFirestore.instance.doc('user_points/${user.id}').get();
      final bal = balSnap.exists
          ? (balSnap.data()?['balance'] as num?)?.toInt() ?? 0
          : 0;
      final ledSnap = await FirebaseFirestore.instance
          .collection('points_ledger')
          .where('uid', isEqualTo: user.id)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get()
          .catchError((_) => FirebaseFirestore.instance
              .collection('points_ledger')
              .where('uid', isEqualTo: user.id)
              .limit(20)
              .get());
      final rows = ledSnap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      if (!mounted) return;
      setState(() {
        _selectedPtsBalance = bal;
        _selectedPtsLedger = rows;
        _ptsQueryBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ptsQueryBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _usersPane() {
    final u = _selectedPtsUser;
    final name = u == null
        ? null
        : (u.fullName.trim().isNotEmpty
            ? u.fullName
            : (u.firstName.trim().isNotEmpty ? u.firstName : u.username));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Puan sorgula',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kullanıcıyı ara, bakiyeyi gör, delta uygula. Kullanıcılar sekmesindeki ⋮ menüden de açılır.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        AdminUserSearchField(
          controller: _userPtsUid,
          labelText: 'Öğrenci / kullanıcı ara',
          onSelected: _loadUserPoints,
        ),
        const SizedBox(height: 12),
        if (_ptsQueryBusy) const LinearProgressIndicator(minHeight: 2),
        if (u != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF0B1F3A), Color(0xFF12355C)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        u.email.isNotEmpty ? u.email : u.id,
                        style: const TextStyle(
                          color: Color(0xFFA8C5E2),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Bakiye',
                      style: TextStyle(color: Color(0xFFA8C5E2), fontSize: 11),
                    ),
                    Text(
                      '${_selectedPtsBalance ?? '—'} KP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _userPtsDelta,
            decoration: const InputDecoration(
              labelText: 'Delta (örn. 50 veya -20)',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _ptsQueryBusy
                ? null
                : () async {
                    try {
                      final res = await _fn.httpsCallable('adminAdjustPoints').call({
                        'uid': u.id,
                        'delta': int.tryParse(_userPtsDelta.text.trim()) ?? 0,
                        'note': 'admin_points_query',
                      });
                      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
                      final next = (data['balance'] as num?)?.toInt();
                      if (!mounted) return;
                      setState(() {
                        if (next != null) _selectedPtsBalance = next;
                      });
                      _userPtsDelta.clear();
                      await _loadUserPoints(u);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Güncellendi · $next KP')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
            child: const Text('Puan uygula'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Son hareketler',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_selectedPtsLedger.isEmpty)
            const Text(
              'Kayıt yok',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            for (final row in _selectedPtsLedger)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${row['reason'] ?? '—'}'),
                subtitle: Text('${row['id'] ?? ''}'),
                trailing: Text(
                  () {
                    final d = (row['delta'] as num?)?.toInt() ?? 0;
                    final after = (row['balanceAfter'] as num?)?.toInt();
                    final sign = d > 0 ? '+' : '';
                    return '$sign$d → ${after ?? '—'}';
                  }(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        ],
      ],
    );
  }

  Widget _settingsPane() {
    final src = _config.usdTrySource;
    final srcLabel = src == 'tcmb' || src == 'tcmb_auto'
        ? 'TCMB ForexSelling'
        : (src == 'manual' ? 'Manuel' : src);
    final updated = _config.usdTryUpdatedAt;
    String updatedLabel = 'henüz çekilmedi';
    if (updated != null && updated.isNotEmpty) {
      final dt = DateTime.tryParse(updated)?.toLocal();
      updatedLabel = dt != null
          ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : updated;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Puan sistemi açık'),
          subtitle: const Text(
            'Öğrenciler ancak Market → durum da açıksa görür. Market kapalıysa KP / Sil Süpür / eSIM gizlenir.',
          ),
          value: _config.enabled,
          onChanged: (v) => setState(() => _config = _config.copyWith(enabled: v)),
        ),
        TextField(
          controller: _tlCtrl,
          decoration: const InputDecoration(
            labelText: '1 KP kaç ₺? (Kampüsteyim Puan)',
            helperText: 'Market kartlarında ≈ ₺ olarak görünür',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.currency_exchange, color: AppColors.navy),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'USD → ₺ kuru',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Text(
                    _config.usdTryRate.toStringAsFixed(4),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppColors.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Kaynak: $srcLabel · $updatedLabel',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('TCMB’den günlük otomatik'),
                subtitle: const Text('Hafta içi 16:05 (İstanbul) ForexSelling'),
                value: _config.usdTryAuto,
                onChanged: (v) => setState(() => _config = _config.copyWith(usdTryAuto: v)),
              ),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _usdRefreshing ? null : _refreshUsdFromTcmb,
                    icon: _usdRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('Şimdi TCMB çek'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _usdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Manuel kur',
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
            _config = _config.copyWith(
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
        const SizedBox(height: 12),
        _wheelEditor(),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _esimConfigured ? Icons.verified_outlined : Icons.key_off_outlined,
            color: _esimConfigured ? AppColors.lime : AppColors.crimson,
          ),
          title: Text(
            _esimConfigured
                ? 'eSIM Access anahtarları bağlı'
                : 'eSIM Access anahtarı yok',
          ),
          subtitle: Text(
            _esimConfigured
                ? (_esimBalanceUsd != null
                    ? 'Bakiye \$${_esimBalanceUsd!.toStringAsFixed(2)} · değiştirmek için eSIM API sekmesi'
                    : 'Değiştirmek için eSIM API sekmesi / yetkili rol')
                : 'Rol: Puan & eSIM + (isteğe bağlı) eSIM Access anahtarları',
          ),
          trailing: TextButton(
            onPressed: () => setState(() => _section = 'esim'),
            child: const Text('Aç'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Çark dilimlerini yukarıdan düzenle; katalog hediye/eSIM payları da buradan değişir. '
          'Yüzdeler toplanır, gerçek çıkma oranı normalize edilir. '
          'Personel için “Puan & eSIM” rolünü Adminler / Roller’den ata.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saveConfig, child: const Text('Kaydet')),
      ],
    );
  }

  Widget _wheelEditor() {
    final total = _editWheelPercentTotal;
    final denom = total <= 0 ? 1.0 : total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sil Süpür çarkı · pay toplamı %${formatSilPercent(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _wheelEdits.add(
                      _WheelSegEdit.base(
                        id: 'seg_${DateTime.now().millisecondsSinceEpoch}',
                        label: 'Yeni dilim',
                        percent: 5,
                        type: 'points',
                        points: 50,
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Dilim ekle'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Temel dilimler (Tekrar dene / puan) burada. Katalog ürünleri de listelenir. '
            'Çıkma % ondalıklı olabilir (örn. 0.005). Kaydet ile uygula.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _wheelEdits.length; i++) ...[
            _wheelEditRow(_wheelEdits[i], denom),
            if (i < _wheelEdits.length - 1) const Divider(height: 18),
          ],
          if (_wheelEdits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Dilim yok. “Dilim ekle” veya katalogda Sil Süpür % ver.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wheelEditRow(_WheelSegEdit e, double denom) {
    final pct = parseSilPercent(e.percentCtrl.text.trim());
    final chance = denom <= 0 ? 0.0 : (pct / denom) * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                e.isCatalog ? 'Katalog · ${e.type}' : 'Temel dilim',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: e.isCatalog ? AppColors.cyan : AppColors.navy,
                ),
              ),
            ),
            Text(
              '~${formatSilPercent(chance)}%',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            if (!e.isCatalog)
              IconButton(
                tooltip: 'Sil',
                onPressed: () => setState(() {
                  e.dispose();
                  _wheelEdits.remove(e);
                }),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            if (e.isCatalog)
              TextButton(
                onPressed: () {
                  PointsCatalogItem? it;
                  for (final c in _catalog) {
                    if (c.id == e.catalogId) {
                      it = c;
                      break;
                    }
                  }
                  if (it != null) {
                    setState(() => _section = 'catalog');
                    _editItem(it);
                  }
                },
                child: const Text('Ürün'),
              ),
          ],
        ),
        TextField(
          controller: e.labelCtrl,
          readOnly: e.isCatalog,
          decoration: const InputDecoration(
            labelText: 'Etiket',
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: e.percentCtrl,
                decoration: _silPercentDecoration(
                  label: 'Çıkma %',
                  helperText: 'Ondalık OK · örn. 0.005',
                  isDense: true,
                ),
                keyboardType: TextInputType.text,
                inputFormatters: _silPercentFormatters,
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (!e.isCatalog) ...[
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: e.type,
                  decoration: const InputDecoration(
                    labelText: 'Tür',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('Tekrar dene')),
                    DropdownMenuItem(value: 'points', child: Text('Puan')),
                  ],
                  onChanged: (v) => setState(() => e.type = v ?? 'none'),
                ),
              ),
            ],
          ],
        ),
        if (!e.isCatalog && e.type == 'points') ...[
          const SizedBox(height: 6),
          TextField(
            controller: e.pointsCtrl,
            decoration: const InputDecoration(
              labelText: 'Verilecek KP',
              isDense: true,
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
  }

  Widget _catalogPane() {
    final allSelected =
        _catalog.isNotEmpty && _selectedCatalogIds.length == _catalog.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: _bulkBusy ? null : _seed,
                child: const Text('Varsayılan eSIM’leri yükle'),
              ),
              FilledButton(
                onPressed: _bulkBusy ? null : () => _editItem(),
                child: const Text('Ürün ekle'),
              ),
              FilterChip(
                label: Text(allSelected ? 'Seçimi kaldır' : 'Tümünü seç'),
                selected: allSelected,
                onSelected: _catalog.isEmpty
                    ? null
                    : (_) => setState(() {
                          if (allSelected) {
                            _selectedCatalogIds.clear();
                          } else {
                            _selectedCatalogIds
                              ..clear()
                              ..addAll(_catalog.map((e) => e.id));
                          }
                        }),
              ),
              if (_selectedCatalogIds.isNotEmpty)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(foregroundColor: AppColors.crimson),
                  onPressed: _bulkBusy
                      ? null
                      : () => _deleteCatalogSelection(all: false),
                  child: Text('Seçilenleri sil (${_selectedCatalogIds.length})'),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.crimson),
                onPressed: _bulkBusy || _catalog.isEmpty
                    ? null
                    : () => _deleteCatalogSelection(all: true),
                child: const Text('Tüm katalogu sil'),
              ),
            ],
          ),
        ),
        if (_bulkBusy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _catalog.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Katalog boş. API paketlerinden seçip toplu ekleyebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _catalog.length,
                  itemBuilder: (_, i) {
                    final it = _catalog[i];
                    final selected = _selectedCatalogIds.contains(it.id);
                    return CheckboxListTile(
                      value: selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedCatalogIds.add(it.id);
                        } else {
                          _selectedCatalogIds.remove(it.id);
                        }
                      }),
                      secondary: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editItem(it),
                      ),
                      title: Text(it.title),
                      subtitle: Text(
                        '${it.pointsCost} KP'
                        '${it.costUsd != null ? ' · maliyet \$${it.costUsd!.toStringAsFixed(2)}' : ''}'
                        '${it.marginPercent != null ? ' · marj %${it.marginPercent!.toStringAsFixed(0)}' : ''}'
                        '${it.locationLabel != null ? ' · ${it.locationLabel}' : ''}'
                        '${it.silSupurEligible ? ' · Sil Süpür %${formatSilPercent(it.silSupurPercent)}' : ''}'
                        '${it.packageCode != null ? '\n${it.packageCode}' : ''}',
                      ),
                      isThreeLine: it.packageCode != null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _apiPane() {
    final filtered = _filteredEsimPackages;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.navy,
                AppColors.navy.withValues(alpha: 0.88),
                const Color(0xFF0B3A4A),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.sim_card_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'eSIM Access',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          _esimConfigured
                              ? 'Canlı katalog · TR ucuz + EU-30 (TR dahil)'
                              : 'Önce AccessCode / SecretKey kaydet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: (_esimConfigured ? AppColors.lime : AppColors.crimson)
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _esimConfigured ? AppColors.lime : AppColors.crimson,
                      ),
                    ),
                    child: Text(
                      _esimBalanceUsd != null
                          ? '\$${_esimBalanceUsd!.toStringAsFixed(2)}'
                          : (_esimConfigured ? 'Bağlı' : 'Anahtar yok'),
                      style: TextStyle(
                        color: _esimConfigured ? AppColors.lime : Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_esimConfigured && !_showSecretForm) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.lime.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.lime.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, color: AppColors.lime),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Anahtarlar sistemde kayıtlı — tekrar girilmez.'
                          '${_esimBalanceUsd != null ? ' Bakiye \$${_esimBalanceUsd!.toStringAsFixed(2)}' : ''}',
                          style: const TextStyle(color: Colors.white, height: 1.35),
                        ),
                      ),
                      if (_canManageEsimSecrets)
                        TextButton(
                          onPressed: () => setState(() => _showSecretForm = true),
                          child: const Text('Değiştir', style: TextStyle(color: Colors.white70)),
                        ),
                    ],
                  ),
                ),
              ] else if (_canManageEsimSecrets) ...[
                if (_esimConfigured)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _showSecretForm = false),
                      child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                TextField(
                  controller: _accessCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'AccessCode',
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _secretCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'SecretKey',
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lime,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: _saveEsimSecrets,
                  child: const Text('Anahtarları kaydet'),
                ),
              ] else ...[
                Text(
                  _esimConfigured
                      ? 'Anahtarlar bağlı. Değiştirmek için “eSIM Access anahtarları” yetkisi gerekir.'
                      : 'Anahtar yok. Süper admin veya eSIM Access yetkili rol kaydedebilir.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.35),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Bakiyeyi yenile', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Katalog çek',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('TR + EU-30', 'ALL', Icons.public),
            _filterChip('Sadece TR', 'TR', Icons.flag_outlined),
            _filterChip('EU-30', 'EU30', Icons.travel_explore),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _esimSearchCtrl,
          onChanged: (v) => setState(() => _esimQuery = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'İsim, slug veya packageCode ara…',
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),
        if (_esimLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_esimError != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.crimson.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.crimson.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paketler yüklenemedi',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(_esimError!, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: () => _loadEsimPackages(location: _esimFilter),
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          )
        else if (_esimPackages.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Henüz paket çekilmedi. Yukarıdaki filtrelerden birini seç — '
              'TR ucuz paketler + TR içeren EU-30 listelenir. '
              'Markete eklerken marj ve Sil Süpür seçenekleri açılır.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          )
        else ...[
          Text(
            '${filtered.length} paket'
            '${_esimQuery.isNotEmpty ? ' · “$_esimQuery”' : ''}'
            ' · kur ${_config.usdTryRate.toStringAsFixed(1)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    FilterChip(
                      label: Text(
                        _selectedPackageCodes.length == filtered.length &&
                                filtered.isNotEmpty
                            ? 'Seçimi kaldır'
                            : 'Görünenleri seç',
                      ),
                      selected: filtered.isNotEmpty &&
                          filtered.every(
                            (p) => _selectedPackageCodes
                                .contains('${p['packageCode']}'),
                          ),
                      onSelected: filtered.isEmpty
                          ? null
                          : (_) {
                              final allOn = filtered.every(
                                (p) => _selectedPackageCodes
                                    .contains('${p['packageCode']}'),
                              );
                              for (final p in filtered) {
                                _togglePackageSelected(
                                  '${p['packageCode']}',
                                  !allOn,
                                );
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedPackageCodes.length} seçili',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bulkMarginCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Toplu kar marjı %',
                    isDense: true,
                    helperText:
                        'Sil Süpür % her paketin kartından ayrı girilir',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sil Süpür seçili pay: %${formatSilPercent(_selectedSilPercentSum)}'
                  ' · mevcut çark: %${formatSilPercent(_wheelPercentTotal)}'
                  ' (oranlar normalize)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _selectedSilPercentSum > 100
                        ? AppColors.crimson
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_wheelSegments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final s in _wheelSegments.take(8))
                        _miniTag(
                          '${s['label']}: %${formatSilPercent(num.tryParse('${s['percent']}') ?? 0)}'
                          ' (~${formatSilPercent(num.tryParse('${s['chance']}') ?? 0)}%)',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _bulkBusy || _selectedPackageCodes.isEmpty
                      ? null
                      : _bulkAddSelectedPackages,
                  icon: _bulkBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check),
                  label: Text(
                    'Seçilenleri markete ekle (${_selectedPackageCodes.length})',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final p in filtered) _esimPackageCard(p),
        ],
      ],
    );
  }

  Widget _filterChip(String label, String code, IconData icon) {
    final selected = _esimFilter == code && (_esimPackages.isNotEmpty || _esimLoading);
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: _esimLoading ? null : (_) => _loadEsimPackages(location: code),
      selectedColor: AppColors.cyan.withValues(alpha: 0.18),
      checkmarkColor: AppColors.navy,
    );
  }

  Widget _esimPackageCard(Map<String, dynamic> p) {
    final usd = (p['priceUsd'] as num?)?.toDouble() ?? 0;
    final gb = (p['volumeGb'] as num?)?.toDouble() ?? 0;
    final days = p['duration'];
    final loc = '${p['location'] ?? ''}';
    final code = '${p['packageCode']}';
    final isTrOnly = loc == 'TR';
    final margin = double.tryParse(
          _bulkMarginCtrl.text.trim().replaceAll(',', '.'),
        ) ??
        _config.defaultMarginPercent;
    final kp = usd > 0 ? _config.kpFromUsd(usd, marginPercent: margin) : 0;
    final sale =
        usd > 0 ? _config.saleTryFromUsd(usd, marginPercent: margin) : 0.0;
    final selected = _selectedPackageCodes.contains(code);
    final silOn = _pkgSilEligible[code] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.cyan : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => _togglePackageSelected(code, v == true),
              ),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (isTrOnly ? AppColors.cyan : AppColors.gold)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isTrOnly ? 'TR' : 'EU',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isTrOnly ? AppColors.cyan : AppColors.gold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$code · ${p['slug']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _miniTag('\$${usd.toStringAsFixed(2)}'),
                        _miniTag('${gb.toStringAsFixed(gb >= 10 ? 0 : 2)} GB'),
                        _miniTag('$days gün'),
                        if (kp > 0) _miniTag('$kp KP', accent: true),
                        if (sale > 0) _miniTag('≈ ${sale.toStringAsFixed(0)} ₺'),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tek tek düzenleyerek ekle',
                onPressed: () => _addPackageToCatalog(p),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (selected) ...[
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
              title: const Text('Sil Süpür’de görünsün'),
              value: silOn,
              onChanged: (v) => setState(() {
                _pkgSilEligible[code] = v;
                if (v) {
                  final c = _silPercentCtrlFor(code);
                  if ((double.tryParse(c.text.replaceAll(',', '.')) ?? 0) <= 0) {
                    c.text = '5';
                  }
                }
              }),
            ),
            if (silOn)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: TextField(
                  controller: _silPercentCtrlFor(code),
                  decoration: _silPercentDecoration(
                    label: 'Bu paketin çıkma %',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.text,
                  inputFormatters: _silPercentFormatters,
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _miniTag(String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.cyan.withValues(alpha: 0.14)
            : AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accent ? AppColors.cyan : AppColors.textSecondary,
        ),
      ),
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

class _WheelSegEdit {
  _WheelSegEdit._({
    required this.id,
    required this.isCatalog,
    this.catalogId,
    required this.type,
    required this.labelCtrl,
    required this.percentCtrl,
    required this.pointsCtrl,
  });

  factory _WheelSegEdit.base({
    required String id,
    required String label,
    required double percent,
    required String type,
    required int points,
  }) =>
      _WheelSegEdit._(
        id: id,
        isCatalog: false,
        type: type,
        labelCtrl: TextEditingController(text: label),
        percentCtrl: TextEditingController(text: formatSilPercent(percent)),
        pointsCtrl: TextEditingController(text: '$points'),
      );

  factory _WheelSegEdit.catalog({
    required String catalogId,
    required String label,
    required double percent,
    required String type,
  }) =>
      _WheelSegEdit._(
        id: 'cat_$catalogId',
        isCatalog: true,
        catalogId: catalogId,
        type: type,
        labelCtrl: TextEditingController(text: label),
        percentCtrl: TextEditingController(text: formatSilPercent(percent)),
        pointsCtrl: TextEditingController(text: '0'),
      );

  final String id;
  final bool isCatalog;
  final String? catalogId;
  String type;
  final TextEditingController labelCtrl;
  final TextEditingController percentCtrl;
  final TextEditingController pointsCtrl;

  void dispose() {
    labelCtrl.dispose();
    percentCtrl.dispose();
    pointsCtrl.dispose();
  }
}
