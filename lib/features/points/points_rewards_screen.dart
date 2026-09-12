import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
        oldWidget.reward.status != widget.reward.status) {
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

  @override
  Widget build(BuildContext context) {
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
        subtitle: Text(
          '${_r.paidLabel} · ${_r.status}'
          '${_r.esimStatus != null ? ' · ${_r.esimStatus}' : ''}',
        ),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _kv('Kalan data', '${_r.remainGb.toStringAsFixed(2)} / ${_r.totalGb.toStringAsFixed(2)} GB'),
                _kv('Süre', '${_r.totalDuration ?? '-'} gün'),
                _kv('ICCID', _r.iccid ?? '—'),
                _kv('SM-DP', _r.smdpStatus ?? '—'),
                _kv('Aktivasyon', _r.activateTime ?? 'Henüz aktif değil'),
                _kv('Bitiş', _r.expiredTime ?? '—'),
                if ((_r.locationCodes ?? '').isNotEmpty)
                  _kv('Ülkeler', _r.locationCodes!),
                if ((_r.ac ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await EsimQuickInstall.launch(_r.ac);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Quick Install açılamadı. QR veya LPA ile kur.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.sim_card_download_outlined),
                    label: const Text('Quick Install (iPhone / Android)'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Kurulum (LPA)', style: TextStyle(fontWeight: FontWeight.w700)),
                  SelectableText(_r.ac!, style: const TextStyle(fontSize: 12)),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _r.ac!));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('LPA kopyalandı')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('LPA kopyala'),
                  ),
                ],
                if ((_r.qrCodeUrl ?? '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(_r.qrCodeUrl!)),
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('QR aç'),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Kurulum: Ayarlar → Mobil servis / eSIM → QR veya aktivasyon kodu ile ekle. '
                  'Veri için uluslararası dolaşımı aç.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
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
              child: Text(k, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
