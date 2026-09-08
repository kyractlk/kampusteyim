import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/safe_network_image.dart';
import '../auth/data/auth_provider.dart';
import '../commerce/commerce_service.dart';
import '../feed/feed_provider.dart';
import '../payments/payment_checkout_sheet.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _discount = TextEditingController();
  String? _tierLabel;

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final event = feed.eventById(widget.eventId);
    if (event == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => AppNav.back(context, fallback: '/events'),
          ),
          title: const Text('Etkinlik'),
        ),
        body: const Center(child: Text('Etkinlik bulunamadı')),
      );
    }
    final applied = user != null && event.hasActiveApplication(user.id);
    final blocked = event.applyBlockedReason(
      user: user,
      follows: (cid) => auth.follows(cid),
    );
    final canApply = blocked.isEmpty;
    final date =
        DateFormat('d MMMM yyyy · HH:mm', 'tr').format(event.startsAt);
    final deadlineLabel = event.applicationDeadline == null
        ? null
        : DateFormat('d MMMM yyyy · HH:mm', 'tr')
            .format(event.applicationDeadline!);
    final tiers = event.priceTiers;
    final isFree = tiers.isEmpty || tiers.every((t) => t.amount <= 0);
    _tierLabel ??= tiers.isNotEmpty ? tiers.first.label : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => AppNav.back(context, fallback: '/events'),
        ),
        title: const Text('Etkinlik'),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            onPressed: () => AppShare.shareLink(
              context: context,
              url: AppShare.event(event.id),
              subject: event.title,
              preview: '${event.title}\n$date',
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (event.imageUrl != null)
            GestureDetector(
              onTap: () => openMediaViewer(
                context,
                urls: [event.imageUrl!],
                isVideo: const [false],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SafeNetworkImage(
                    url: event.imageUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            event.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (event.communityName != null) ...[
            const SizedBox(height: 10),
            AffiliationBadge(
              orgName: event.communityName!,
              logoUrl: event.communityLogoUrl,
              orgId: event.communityId,
              verifiedGold: true,
            ),
          ],
          if (event.organizerCompanyName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Organizatör: ${event.organizerCompanyName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(date),
                  ),
                  if (event.location.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(event.location),
                    ),
                  if (event.city.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_city_outlined),
                      title: Text(event.city),
                    ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(event.audienceLabel),
                    subtitle: deadlineLabel == null
                        ? null
                        : Text('Son başvuru: $deadlineLabel'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(event.description, style: Theme.of(context).textTheme.bodyLarge),
          if (event.rules.isNotEmpty) ...[
            const SizedBox(height: 16),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  title: const Text(
                    'Kurallar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Okumak için aç'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        event.rules,
                        style: const TextStyle(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Kadro: ${event.approvedCount}/${event.capacity}'
            '${event.pendingCount > 0 ? ' · ${event.pendingCount} bekleyen' : ''}'
            '${event.isRosterFull ? ' · Kadro doldu' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (tiers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Bilet seçenekleri',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            ...tiers.map((t) {
              final selected = _tierLabel == t.label;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: selected
                      ? AppColors.navy.withValues(alpha: 0.08)
                      : AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: selected ? AppColors.navy : AppColors.border,
                      width: selected ? 1.8 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: applied
                        ? null
                        : () => setState(() => _tierLabel = t.label),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected
                                ? AppColors.navy
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.amount <= 0
                                      ? '${t.label} · Ücretsiz'
                                      : '${t.label} · ${t.amount.toStringAsFixed(2)} TL',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${t.entryLabel}'
                                  '${t.remaining != null ? ' · kalan ${t.remaining}' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Ücretsiz etkinlik — yalnızca başvuru',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (!isFree && !applied) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _discount,
              decoration: const InputDecoration(
                labelText: 'İndirim kodu (opsiyonel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: event.refundsAllowed
                  ? AppColors.cyan.withValues(alpha: 0.08)
                  : AppColors.crimson.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  event.refundsAllowed
                      ? 'Bu etkinlikte iade yapılabilir. Onaylanan iadede bilet iptal edilir, kontenjan açılır; organizatör bakiyesinden net tutar (komisyon düşülmüş hali) geri alınır.'
                      : 'Bu etkinlikte iade / iptal yoktur. Satın almadan önce satış sözleşmesini onaylaman gerekir.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: !canApply
                ? null
                : () async {
                    if (!AuthGate.requireAuth(
                      context,
                      message: 'Başvuru / bilet için giriş yapmalısın.',
                    )) {
                      return;
                    }
                    final a = context.read<AuthProvider>();
                    if (isFree) {
                      final err = await feed.applyToEvent(
                        event.id,
                        applicant: a.user,
                        follows: (cid) => a.follows(cid),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err ?? 'Başvurun alındı.')),
                      );
                      return;
                    }
                    final tier = tiers.isEmpty
                        ? null
                        : tiers.firstWhere(
                            (t) => t.label == _tierLabel,
                            orElse: () => tiers.first,
                          );
                    final amount = tier?.amount ?? 0;
                    if (tier != null && tier.isSoldOut) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stok bitti')),
                      );
                      return;
                    }
                    if (amount <= 0) {
                      final err = await feed.applyToEvent(
                        event.id,
                        applicant: a.user,
                        follows: (cid) => a.follows(cid),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err ?? 'Başvurun alındı.')),
                      );
                      return;
                    }
                    await openPaymentCheckout(
                      context,
                      product: 'event',
                      amount: amount,
                      eventId: event.id,
                      tierLabel: tier?.label,
                      refundsAllowed: event.refundsAllowed,
                      discountCode: _discount.text.trim().isEmpty
                          ? null
                          : _discount.text.trim(),
                    );
                  },
            child: Text(
              applied
                  ? 'Başvuruldu / biletin var'
                  : (blocked.isEmpty
                      ? (isFree
                          ? 'Başvur'
                          : (tiers.any((t) => !t.isSoldOut)
                              ? 'Bilet al / öde'
                              : 'Stok bitti'))
                      : blocked),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/tickets'),
            child: const Text('Biletlerim'),
          ),
          if (applied) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _renameTicketName(event.id),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Biletteki ismi değiştir'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.go('/events'),
            child: const Text('Tüm etkinlikler'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameTicketName(String eventId) async {
    try {
      final tickets = await CommerceService.getMyTickets();
      final mine = tickets.where((t) => '${t['eventId']}' == eventId).toList();
      if (!mounted) return;
      if (mine.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu etkinlikte bilet bulunamadı')),
        );
        return;
      }
      final t = mine.first;
      final used = (t['entriesUsed'] as num?)?.toInt() ?? 0;
      final st = '${t['status'] ?? 'active'}';
      if (used > 0 || st == 'used' || st == 'refunded' || st == 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giriş yapılmış bilette isim değiştirilemez'),
          ),
        );
        return;
      }
      final ctrl = TextEditingController(text: '${t['userName'] ?? ''}');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Biletteki isim'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Kapıda görünecek ad soyad',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
      final name = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true || name.length < 2 || !mounted) return;
      await CommerceService.renameTicketAttendee(
        ticketId: '${t['id']}',
        userName: name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bilet ismi güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güncellenemedi: $e')),
      );
    }
  }
}
