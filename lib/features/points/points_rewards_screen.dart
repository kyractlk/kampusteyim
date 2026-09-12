import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import 'esim_quick_install.dart';
import 'points_models.dart';

class PointsRewardsScreen extends StatefulWidget {
  const PointsRewardsScreen({super.key});

  @override
  State<PointsRewardsScreen> createState() => _PointsRewardsScreenState();
}

class _PointsRewardsScreenState extends State<PointsRewardsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<UserReward> _all = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await PointsService.listRewards();
      if (!mounted) return;
      setState(() {
        _all = items;
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

  @override
  Widget build(BuildContext context) {
    final esims = _all.where((e) => e.isEsim).toList();
    final gifts = _all.where((e) => e.isGift).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kazandıklarım'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'eSIMlerim (${esims.length})'),
            Tab(text: 'Diğer hediyeler (${gifts.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      child: esims.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 80),
                                Center(child: Text('Henüz eSIM yok')),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: esims.length,
                              itemBuilder: (_, i) => _EsimTile(
                                reward: esims[i],
                                onChanged: _load,
                              ),
                            ),
                    ),
                    RefreshIndicator(
                      onRefresh: _load,
                      child: gifts.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 80),
                                Center(child: Text('Henüz hediye yok')),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: gifts.length,
                              itemBuilder: (_, i) {
                                final g = gifts[i];
                                return Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(color: AppColors.border),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(Icons.card_giftcard),
                                    title: Text(g.title),
                                    subtitle: Text('${g.paidLabel} · ${g.status}'),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _EsimTile extends StatefulWidget {
  const _EsimTile({required this.reward, required this.onChanged});

  final UserReward reward;
  final Future<void> Function() onChanged;

  @override
  State<_EsimTile> createState() => _EsimTileState();
}

class _EsimTileState extends State<_EsimTile> {
  bool _open = false;
  bool _busy = false;
  late UserReward _r;

  @override
  void initState() {
    super.initState();
    _r = widget.reward;
  }

  @override
  void didUpdateWidget(covariant _EsimTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reward.id != widget.reward.id ||
        oldWidget.reward.status != widget.reward.status ||
        oldWidget.reward.ac != widget.reward.ac) {
      _r = widget.reward;
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final updated = await PointsService.refreshEsim(_r.id);
      if (!mounted) return;
      setState(() {
        _r = updated;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String get _statusLabel {
    final s = _r.status.toLowerCase();
    if (s == 'ready') return 'Kuruluma hazır';
    if (s == 'active' || s == 'in_use') return 'Aktif';
    if (s == 'expired') return 'Süresi doldu';
    if (s == 'pending') return 'Hazırlanıyor';
    return _r.status;
  }

  Future<void> _quickInstall({required bool apple}) async {
    final ok = apple
        ? await EsimQuickInstall.launchApple(_r.ac)
        : await EsimQuickInstall.launchAndroid(_r.ac);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apple
                ? 'iPhone kurulumu açılamadı. QR veya kurulum kodunu dene.'
                : 'Android kurulumu açılamadı. QR veya kurulum kodunu dene.',
          ),
        ),
      );
    }
  }

  Future<void> _copyLpa() async {
    final lpa = EsimQuickInstall.normalize(_r.ac);
    if (lpa == null) return;
    await Clipboard.setData(ClipboardData(text: lpa));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kurulum kodu kopyalandı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAc = EsimQuickInstall.normalize(_r.ac) != null;
    final onIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final onAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ExpansionTile(
        initiallyExpanded: _open,
        onExpansionChanged: (v) => setState(() => _open = v),
        leading: CircleAvatar(
          backgroundColor: AppColors.navy,
          child: Icon(
            _r.esimStatus == 'IN_USE' ? Icons.signal_cellular_alt : Icons.sim_card,
            color: AppColors.cyan,
            size: 20,
          ),
        ),
        title: Text(_r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_r.paidLabel} · $_statusLabel'),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _kv('Kalan data',
                    '${_r.remainGb.toStringAsFixed(2)} / ${_r.totalGb.toStringAsFixed(2)} GB'),
                _kv('Süre', '${_r.totalDuration ?? '-'} gün'),
                _kv('Aktivasyon', _r.activateTime ?? 'Henüz aktif değil'),
                _kv('Bitiş', _r.expiredTime ?? '—'),
                if ((_r.locationCodes ?? '').isNotEmpty)
                  _kv('Ülkeler', _r.locationCodes!),
                if (hasAc) ...[
                  const SizedBox(height: 14),
                  _InstallPanel(
                    lpa: _r.ac!,
                    onIos: onIos,
                    onAndroid: onAndroid,
                    onApple: () => _quickInstall(apple: true),
                    onAndroidInstall: () => _quickInstall(apple: false),
                    onCopy: _copyLpa,
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Kullanımı yenile'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                k,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _InstallPanel extends StatelessWidget {
  const _InstallPanel({
    required this.lpa,
    required this.onIos,
    required this.onAndroid,
    required this.onApple,
    required this.onAndroidInstall,
    required this.onCopy,
  });

  final String lpa;
  final bool onIos;
  final bool onAndroid;
  final VoidCallback onApple;
  final VoidCallback onAndroidInstall;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1F3A), Color(0xFF163356)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kurulum',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'QR’ı tara veya tek dokunuşla kur',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: lpa,
                version: QrVersions.auto,
                size: 188,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.navy,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.navy,
                ),
                embeddedImage: const AssetImage(AppAssets.kampusIcon),
                embeddedImageStyle: const QrEmbeddedImageStyle(
                  size: Size(34, 34),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Hızlı kurulum',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFBAE6FD),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PlatformInstallButton(
                  label: 'iPhone',
                  icon: Icons.phone_iphone,
                  primary: onIos || (!onIos && !onAndroid),
                  onPressed: onApple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PlatformInstallButton(
                  label: 'Android',
                  icon: Icons.android,
                  primary: onAndroid,
                  onPressed: onAndroidInstall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onCopy,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Kurulum kodunu kopyala'),
          ),
          const SizedBox(height: 10),
          Text(
            'LPA nedir? eSIM’i telefona yüklemek için kullanılan gizli kurulum kodudur. '
            'Kopyalayıp Ayarlar → eSIM Ekle ile de girebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kurulumdan sonra uluslararası dolaşımı / data roaming’i aç.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cyan.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformInstallButton extends StatelessWidget {
  const _PlatformInstallButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: AppColors.navy,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
