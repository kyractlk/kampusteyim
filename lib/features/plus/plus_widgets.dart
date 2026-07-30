import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../payments/payment_checkout_sheet.dart';
import 'plus_gate.dart';
import 'plus_provider.dart';

/// Gold/mavi + Plus yeşil + kampüs elçisi.
class UserVerificationBadges extends StatelessWidget {
  const UserVerificationBadges({
    super.key,
    required this.user,
    this.size = 15,
  });

  final AppUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    final u = user!;
    final plusOn = context.watch<PlusProvider>().config.features.greenBadge;
    final children = <Widget>[];
    if (u.showGoldBadge) {
      children.add(VerifiedBadge(gold: true, size: size));
    } else if (u.showBlueBadge) {
      children.add(VerifiedBadge(size: size));
    }
    if (plusOn && u.showGreenBadge && !u.showGoldBadge && !u.showBlueBadge) {
      if (children.isNotEmpty) children.add(SizedBox(width: size * 0.25));
      children.add(VerifiedBadge(green: true, size: size));
    }
    if (u.isCampusAmbassador) {
      if (children.isNotEmpty) children.add(SizedBox(width: size * 0.25));
      children.add(CampusAmbassadorBadge(size: size));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Profil · Plus ayrıcalıklarım
class PlusPrivilegesCard extends StatefulWidget {
  const PlusPrivilegesCard({super.key});

  @override
  State<PlusPrivilegesCard> createState() => _PlusPrivilegesCardState();
}

class _PlusPrivilegesCardState extends State<PlusPrivilegesCard> {
  bool _busy = false;

  Future<void> _startTrial() async {
    setState(() => _busy = true);
    final err = await startPlusTrialFlow(context);
    if (mounted) {
      setState(() => _busy = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final cfg = context.watch<PlusProvider>().config;
    if (user == null) return const SizedBox.shrink();
    final active = user.isPlusActive;

    return Material(
      color: AppColors.navy,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium, color: AppColors.lime),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Plus ayrıcalıklarım',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (active) const VerifiedBadge(green: true, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            if (active) ...[
              Text(
                user.plusSource == 'trial'
                    ? 'Ücretsiz deneme · ${user.plusDaysLeft} gün kaldı'
                    : 'Plus aktif · ${user.plusDaysLeft} gün kaldı',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              const Text(
                'Otomatik yenileme: kapalı — süre bitince yeniden satın al.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _perk('Dosya / ders notu paylaşımı', cfg.features.filePosts),
              _perk('CV dil + renk teması', cfg.features.cvTheme),
              _perk('Yüksek CV-AI kotası', cfg.features.higherCvQuota),
              _perk('Yeşil tick', cfg.features.greenBadge),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.lime,
                  side: const BorderSide(color: AppColors.lime),
                ),
                onPressed: () => openPaymentCheckout(context),
                child: const Text('Süreyi uzat / yeniden satın al'),
              ),
            ] else ...[
              const Text(
                'KampüsteyimPlus ile dosya paylaş, CV’ni renklendir, '
                'yeşil tick kazan.',
                style: TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (!user.plusTrialUsed)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lime,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: _busy ? null : _startTrial,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Ücretsiz deneme istiyorum (${cfg.trialDays} gün)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lime,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: () => openPaymentCheckout(context),
                  child: const Text(
                    'Plus satın al',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _perk(String label, bool on) {
    if (!on) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.lime, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
