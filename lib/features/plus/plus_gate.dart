import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import 'plus_provider.dart';

/// Plus gerektiren özellik kilidi — deneme CTA.
Future<bool> requirePlus(
  BuildContext context, {
  String featureLabel = 'Bu özellik',
}) async {
  final user = context.read<AuthProvider>().user;
  if (user != null && user.isPlusActive) return true;
  if (!context.mounted) return false;
  final go = await showModalBottomSheet<bool>(
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
              '$featureLabel Plus üyelerine özel. '
              'Şu an ücretsiz deneme ile açabilirsin.',
              style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ücretsiz deneme / ayrıcalıklarım'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      );
    },
  );
  if (go == true && context.mounted) {
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
