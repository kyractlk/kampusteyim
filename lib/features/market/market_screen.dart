import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/liquid_glass.dart';
import '../auth/data/auth_provider.dart';
import '../payments/payment_checkout_sheet.dart';
import '../payments/payments_service.dart';

/// Uygulama içi Market — merch, Plus, kodlarım.
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  PaymentsPublicConfig? _cfg;
  List<Map<String, dynamic>> _myCodes = [];
  String? _error;
  bool _loading = true;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
      final cfg = await PaymentsService.getPublic();
      var mine = <Map<String, dynamic>>[];
      try {
        if (context.read<AuthProvider>().isAuthenticated) {
          mine = await PaymentsService.myCampaigns();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _myCodes = mine;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _buyPlus({String? code, int? months}) async {
    if (!AuthGate.requireAuth(context)) return;
    await openPaymentCheckout(
      context,
      product: 'plus',
      months: months,
      discountCode: code,
      provider: _cfg?.paytrReady == true ? 'paytr' : null,
    );
    await _load();
  }

  Future<void> _openMerch(Map<String, dynamic> item) async {
    if (!AuthGate.requireAuth(context)) return;
    final sizes = (item['sizes'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    if (sizes.isEmpty) return;
    final nameCtrl = TextEditingController(
      text: context.read<AuthProvider>().user?.fullName ?? '',
    );
    final cityCtrl = TextEditingController(
      text: context.read<AuthProvider>().user?.city ?? '',
    );
    final codeCtrl = TextEditingController();
    var size = sizes.first;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            top: 8,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${item['name']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    '${(item['amount'] as num?)?.toStringAsFixed(0) ?? '—'} TL',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in sizes)
                        ChoiceChip(
                          label: Text(s),
                          selected: size == s,
                          onSelected: (_) => setLocal(() => size = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alıcı adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Şehir',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Kampanya kodu (opsiyonel)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Kart ile güvenle öde'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    await openPaymentCheckout(
      context,
      product: 'merch',
      amount: (item['amount'] as num?)?.toDouble(),
      sku: '${item['sku']}',
      size: size,
      city: cityCtrl.text.trim(),
      shipName: nameCtrl.text.trim(),
      discountCode: codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
      provider: (_cfg?.paytrReady == true && _cfg?.merchPaytrEnabled == true)
          ? 'paytr'
          : null,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlass.enabled(context);
    final cfg = _cfg;
    final visible = cfg?.marketInAppVisible != false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 148,
              title: const Text('Market'),
              actions: [
                IconButton(
                  tooltip: 'Web market',
                  onPressed: () => launchUrl(
                    Uri.parse(
                      cfg?.marketUrl ?? 'https://app.kampusteyim.app/market',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: glass
                          ? [
                              scheme.primary.withValues(alpha: 0.35),
                              AppColors.navy.withValues(alpha: 0.85),
                            ]
                          : [
                              AppColors.navy,
                              AppColors.navySoft,
                              AppColors.cyan.withValues(alpha: 0.55),
                            ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 52, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kampüs marketi',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cfg?.paytrReady == true
                                ? 'Kart ile güvenle öde · PayTR'
                                : 'Ödeme yakında',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottom: TabBar(
                controller: _tabs,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: AppColors.cyan,
                tabs: const [
                  Tab(text: 'Ürünler'),
                  Tab(text: 'Plus'),
                  Tab(text: 'Kodlarım'),
                ],
              ),
            ),
          ];
        },
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        FilledButton(onPressed: _load, child: const Text('Yenile')),
                      ],
                    ),
                  )
                : !visible
                    ? const Center(child: Text('Market şu an kapalı.'))
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              children: [
                                for (final m
                                    in cfg?.merch ??
                                        const <Map<String, dynamic>>[])
                                  _MerchTile(
                                    item: m,
                                    glass: glass,
                                    onTap: () => _openMerch(m),
                                  ),
                                const SizedBox(height: 12),
                                _LegalLinks(),
                              ],
                            ),
                          ),
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              children: [
                                _PlusHero(
                                  cfg: cfg,
                                  glass: glass,
                                  onBuy: (months) => _buyPlus(months: months),
                                ),
                                const SizedBox(height: 12),
                                _LegalLinks(),
                              ],
                            ),
                          ),
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              children: [
                                if (_myCodes.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Sana tanımlı çek yok.\nCheckout’ta genel kampanya kodu da girebilirsin.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  )
                                else
                                  for (final c in _myCodes)
                                    Card(
                                      child: ListTile(
                                        title: Text(
                                          '${c['code']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${c['label']} · '
                                          '${c['type'] == 'fixed' ? '${c['value']} TL' : '%${c['value']}'}'
                                          '${c['remainingForMe'] != null ? ' · kalan ${c['remainingForMe']}' : ''}',
                                        ),
                                        trailing: FilledButton.tonal(
                                          onPressed: () => _buyPlus(
                                            code: '${c['code']}',
                                          ),
                                          child: const Text('Uygula'),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

class _MerchTile extends StatelessWidget {
  const _MerchTile({
    required this.item,
    required this.glass,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool glass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: glass
            ? Colors.white.withValues(alpha: 0.55)
            : Theme.of(context).colorScheme.surface,
        elevation: glass ? 0 : 1,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.navy.withValues(alpha: 0.9),
                        AppColors.cyan.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['name']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item['short'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(item['amount'] as num?)?.toStringAsFixed(0) ?? '—'}₺',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusHero extends StatelessWidget {
  const _PlusHero({
    required this.cfg,
    required this.glass,
    required this.onBuy,
  });

  final PaymentsPublicConfig? cfg;
  final bool glass;
  final void Function(int months) onBuy;

  @override
  Widget build(BuildContext context) {
    final plans = cfg?.plusPlans ?? const [];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: glass
              ? [
                  AppColors.navy.withValues(alpha: 0.88),
                  AppColors.cyan.withValues(alpha: 0.55),
                ]
              : [AppColors.navy, const Color(0xFF0E3A4A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kampüsteyim Plus',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Yeşil tick, CV-AI ve kampüs ayrıcalıkları. Kart ile güvenle öde.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 14),
          if (plans.isEmpty)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.cyan),
              onPressed: () => onBuy(1),
              child: const Text('Plus satın al'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in plans)
                  ActionChip(
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    label: Text(
                      '${p['label']} · ${(p['amount'] as num?)?.toStringAsFixed(0) ?? '—'}₺',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () =>
                        onBuy((p['months'] as num?)?.toInt() ?? 1),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in [
          ('Satış', 'https://app.kampusteyim.app/sales'),
          ('Kargo', 'https://app.kampusteyim.app/shipping'),
          ('İade', 'https://app.kampusteyim.app/returns'),
        ])
          ActionChip(
            label: Text(e.$1),
            onPressed: () => launchUrl(
              Uri.parse(e.$2),
              mode: LaunchMode.externalApplication,
            ),
          ),
      ],
    );
  }
}
