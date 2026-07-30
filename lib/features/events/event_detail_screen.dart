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
          const SizedBox(height: 8),
          Text(
            date,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (event.location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              event.location,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (event.city.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Şehir: ${event.city}'),
          ],
          const SizedBox(height: 8),
          Text(
            'Kimler: ${event.audienceLabel}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (deadlineLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              'Son başvuru: $deadlineLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          Text(event.description, style: Theme.of(context).textTheme.bodyLarge),
          if (event.rules.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Kurallar', style: Theme.of(context).textTheme.titleSmall),
            Text(event.rules),
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
            ...tiers.map(
              (t) => RadioListTile<String>(
                value: t.label,
                groupValue: _tierLabel,
                onChanged:
                    applied ? null : (v) => setState(() => _tierLabel = v),
                title: Text(
                  t.amount <= 0
                      ? '${t.label} · Ücretsiz'
                      : '${t.label} · ${t.amount.toStringAsFixed(2)} TL',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
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
            const SizedBox(height: 6),
            const Text(
              'Ödeme yapan hesap = katılımcı hesap. Bilet devredilemez. '
              'İade / iptal talebi yoktur.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                      discountCode: _discount.text.trim().isEmpty
                          ? null
                          : _discount.text.trim(),
                    );
                  },
            child: Text(
              applied
                  ? 'Başvuruldu / biletin var'
                  : (blocked.isEmpty
                      ? (isFree ? 'Başvur' : 'Bilet al / öde')
                      : blocked),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/tickets'),
            child: const Text('Biletlerim'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.go('/events'),
            child: const Text('Tüm etkinlikler'),
          ),
        ],
      ),
    );
  }
}
