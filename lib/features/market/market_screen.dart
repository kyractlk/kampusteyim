import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/web_safe_image.dart';
import '../auth/data/auth_provider.dart';
import '../payments/payment_checkout_sheet.dart';
import '../payments/payments_service.dart';
import 'delivery_address_form.dart';
import 'market_product_detail_screen.dart';
import 'merch_images.dart';

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
  bool _addressPrompted = false;
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

  Future<void> _ensureDeliveryAddress({bool force = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    final user = auth.user;
    if (user == null) return;
    if (user.deliveryAddresses.isNotEmpty) return;
    if (_addressPrompted && !force) return;
    _addressPrompted = true;
    final addr = await showDeliveryAddressEditor(
      context,
      required: true,
      title: 'Teslimat adresi ekle',
    );
    if (addr == null || !mounted) return;
    try {
      await auth.upsertDeliveryAddress(addr);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teslimat adresi kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adres kaydedilemedi: $e')),
      );
    }
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
      await _ensureDeliveryAddress();
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

  Future<void> _openProduct(Map<String, dynamic> item) async {
    if (!AuthGate.requireAuth(context)) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MarketProductDetailScreen(
          item: item,
          paytrReady: _cfg?.paytrReady == true,
          merchPaytrEnabled: _cfg?.merchPaytrEnabled != false,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlass.enabled(context);
    final cfg = _cfg;
    final visible = cfg?.marketInAppVisible != false;
    final merch = (cfg?.merch ?? const <Map<String, dynamic>>[])
        .where((m) => m['available'] != false)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 132,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.navy,
                        AppColors.navySoft,
                        Color(0xFF0A4A52),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 8),
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
                                ? 'Görsel · detay · kart ile güvenli ödeme'
                                : 'Ödeme yakında',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
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
                indicatorWeight: 2.5,
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
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Yenile'),
                        ),
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
                            child: merch.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: const [
                                      SizedBox(height: 120),
                                      Center(
                                        child: Text(
                                          'Ürün yok',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      16,
                                      14,
                                      32,
                                    ),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.72,
                                    ),
                                    itemCount: merch.length + 1,
                                    itemBuilder: (context, i) {
                                      if (i == merch.length) {
                                        return const Align(
                                          alignment: Alignment.topLeft,
                                          child: Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: _LegalLinks(),
                                          ),
                                        );
                                      }
                                      return _MerchCard(
                                        item: merch[i],
                                        onTap: () => _openProduct(merch[i]),
                                      );
                                    },
                                  ),
                          ),
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              children: [
                                _PlusHero(
                                  cfg: cfg,
                                  glass: glass,
                                  onBuy: (months) => _buyPlus(months: months),
                                ),
                                const SizedBox(height: 16),
                                const _LegalLinks(),
                              ],
                            ),
                          ),
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Material(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        child: ListTile(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            side: const BorderSide(
                                              color: AppColors.border,
                                            ),
                                          ),
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
                                          trailing: TextButton(
                                            onPressed: () => _buyPlus(
                                              code: '${c['code']}',
                                            ),
                                            child: const Text('Uygula'),
                                          ),
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

class _MerchCard extends StatelessWidget {
  const _MerchCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final img = merchImageUrl(item);
    final amount = (item['amount'] as num?)?.toStringAsFixed(0) ?? '—';
    final short = '${item['short'] ?? ''}';

    return Material(
      color: AppColors.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: img != null
                    ? webSafeNetworkImage(
                        img,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (short.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          short,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            '$amount₺',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: AppColors.navy.withValues(alpha: 0.45),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceMuted,
      child: const Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          color: AppColors.textSecondary,
          size: 36,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: glass
              ? [
                  AppColors.navy.withValues(alpha: 0.92),
                  const Color(0xFF0E3A4A),
                  AppColors.cyan.withValues(alpha: 0.65),
                ]
              : const [
                  AppColors.navy,
                  Color(0xFF0E3A4A),
                  Color(0xFF0A5A5E),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kampüsteyim Plus',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Yeşil tick, CV-AI ve kampüs ayrıcalıkları.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          if (plans.isEmpty)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: AppColors.navy,
                minimumSize: const Size(0, 42),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () => onBuy(1),
              child: const Text(
                'Plus satın al',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in plans)
                  Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () =>
                          onBuy((p['months'] as num?)?.toInt() ?? 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '${p['label']} · ${(p['amount'] as num?)?.toStringAsFixed(0) ?? '—'}₺',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in [
          ('Satış', 'https://app.kampusteyim.app/sales'),
          ('Kargo', 'https://app.kampusteyim.app/shipping'),
          ('İade', 'https://app.kampusteyim.app/returns'),
        ])
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () => launchUrl(
              Uri.parse(e.$2),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(e.$1),
          ),
      ],
    );
  }
}
