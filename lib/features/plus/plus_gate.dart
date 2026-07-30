import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import '../payments/payment_checkout_sheet.dart';
import 'plus_provider.dart';

/// Plus gerektiren özellik kilidi — deneme / satın alma CTA.
Future<bool> requirePlus(
  BuildContext context, {
  String featureLabel = 'Bu özellik',
}) async {
  final user = context.read<AuthProvider>().user;
  if (user != null && user.isPlusActive) return true;
  if (!context.mounted) return false;
  final trialUsed = user?.plusTrialUsed == true;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'KampüsteyimPlus',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              trialUsed
                  ? '$featureLabel Plus üyelerine özel. Satın alarak açabilirsin.'
                  : '$featureLabel Plus üyelerine özel. '
                      'Ücretsiz deneme veya satın alma ile açabilirsin.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            if (!trialUsed)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'trial'),
                child: const Text('Ücretsiz deneme / ayrıcalıklarım'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'buy'),
              child: Text(trialUsed ? 'Plus satın al' : 'Satın al'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      );
    },
  );
  if (!context.mounted) return false;
  if (action == 'buy') {
    await openPaymentCheckout(context);
    if (!context.mounted) return false;
    final refreshed = context.read<AuthProvider>().user;
    return refreshed?.isPlusActive == true;
  }
  if (action == 'trial') {
    context.push('/profile');
  }
  return false;
}

Future<String?> startPlusTrialFlow(BuildContext context) async {
  final err = await context.read<PlusProvider>().startTrial();
  if (!context.mounted) return err;
  if (err == null) {
    await context.read<AuthProvider>().refreshCurrentUser();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KampüsteyimPlus denemen başladı 🎉')),
      );
    }
  }
  return err;
}
