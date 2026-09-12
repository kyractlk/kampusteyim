import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import 'points_models.dart';
import 'points_provider.dart';

class PointsMarketScreen extends StatefulWidget {
  const PointsMarketScreen({super.key});

  @override
  State<PointsMarketScreen> createState() => _PointsMarketScreenState();
}

class _PointsMarketScreenState extends State<PointsMarketScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PointsProvider>().refresh();
    });
  }

  void _showEarnInfo(PointsConfig cfg) {
    final e = cfg.earn;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nasıl KP kazanırım?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _earnRow('Gönderi paylaş', e.post),
            _earnRow('Reel paylaş', e.reel),
            _earnRow('Hikâye paylaş', e.story),
            _earnRow('Beğeni al', e.likeReceived),
            _earnRow('Yorum al', e.commentReceived),
            _earnRow('Repost al', e.repostReceived),
            const SizedBox(height: 8),
            Text(
              '1 KP ≈ ${cfg.tlPerPoint.toStringAsFixed(2)} ₺',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Beğeni geri alınırsa kazandığın KP de düşer. Bakiye negatife inebilir.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _earnRow(String label, int pts) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '+$pts KP',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.cyan,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _redeem(PointsCatalogItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.title),
        content: Text(
          '${item.pointsCost} KP karşılığında almak istiyor musun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Al'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Hazırlanıyor…'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await context.read<PointsProvider>().redeem(item.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.title} kazandıklarına eklendi'),
          action: SnackBarAction(
            label: 'Gör',
            onPressed: () => context.push('/points/rewards'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = context.watch<PointsProvider>();
    final cfg = pts.config;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Kampüsteyim Puan'),
        actions: [
          IconButton(
            tooltip: 'Nasıl KP kazanırım?',
            onPressed: () => _showEarnInfo(cfg),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Kazandıklarım',
            onPressed: () => context.push('/points/rewards'),
            icon: const Icon(Icons.card_giftcard_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: pts.refresh,
        child: !pts.loading && !cfg.enabled
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 48),
                  Icon(Icons.storefront_outlined, size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    'Market şu an kapalı',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Kampüsteyim Puan, Sil Süpür ve eSIM ödülleri Market ile birlikte açılır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              )
            : ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _BalanceHero(
              balance: pts.balance,
              tlLabel: cfg.tlLabel(pts.balance),
              loading: pts.loading,
            ),
            const SizedBox(height: 12),
            if (cfg.silSupur.enabled)
              _SilSupurBanner(
                open: pts.isSilSupurDay,
                spinsLeft: pts.spinsLeft,
                weekday: SilSupurConfig.weekdayLabels[
                    cfg.silSupur.weekday.clamp(0, 6)],
                onTap: () => context.push('/points/sil-supur'),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  'Ödüller',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '1 KP = ${cfg.tlPerPoint.toStringAsFixed(2)}₺',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (pts.loading && pts.catalog.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (pts.catalog.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz ürün yok. Admin panelinden eSIM / hediye ekleyebilirsin.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...pts.catalog.map(
                (item) => _CatalogCard(
                  item: item,
                  tlHint: cfg.tlLabel(item.pointsCost),
                  canAfford: pts.balance >= item.pointsCost,
                  onRedeem: () => _redeem(item),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/market'),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Klasik Market (merch / Plus)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.balance,
    required this.tlLabel,
    required this.loading,
  });

  final int balance;
  final String tlLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navySoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kampüsteyim Puan',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  loading ? '…' : '$balance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  tlLabel,
                  style: const TextStyle(color: AppColors.cyan, fontSize: 13),
                ),
                if (balance < 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Negatif bakiye — etkileşim veya Sil Süpür ile toparlayabilirsin',
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.stars_rounded, color: AppColors.gold, size: 48),
        ],
      ),
    );
  }
}

class _SilSupurBanner extends StatelessWidget {
  const _SilSupurBanner({
    required this.open,
    required this.spinsLeft,
    required this.weekday,
    required this.onTap,
  });

  final bool open;
  final int spinsLeft;
  final String weekday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: open ? const Color(0xFFFFF4D6) : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.casino_rounded, color: AppColors.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sil Süpür',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(
                      open
                          ? 'Bugün açık · $spinsLeft hak kaldı'
                          : 'Her $weekday açılır',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: open ? AppColors.navy : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.tlHint,
    required this.canAfford,
    required this.onRedeem,
  });

  final PointsCatalogItem item;
  final String tlHint;
  final bool canAfford;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item.isEsim ? Icons.sim_card_outlined : Icons.card_giftcard,
                color: AppColors.navy,
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
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (item.isEsim)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'eSIM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (item.locationLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.locationLabel!,
                      style: const TextStyle(fontSize: 11, color: AppColors.cyan),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${item.pointsCost} KP',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tlHint,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (item.cashPriceTl != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${item.cashPriceTl!.toStringAsFixed(0)} ₺',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                      const Spacer(),
                      FilledButton(
                        onPressed: canAfford ? onRedeem : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Al'),
                      ),
                    ],
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
