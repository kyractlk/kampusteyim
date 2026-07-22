import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../data/auth_provider.dart';

/// Öğrenci belgesi onay bekleyen kullanıcı ekranı.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (user != null && user.isAccountApproved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/home');
      });
    }

    final rejected = user?.isAccountRejected == true;

    return GradientScaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const BrandHeader(compact: true, showAys: false),
              const Spacer(),
              Icon(
                rejected ? Icons.cancel_outlined : Icons.hourglass_top_rounded,
                size: 56,
                color: rejected ? AppColors.crimson : AppColors.cyan,
              ),
              const SizedBox(height: 16),
              Text(
                rejected ? 'Başvurun reddedildi' : 'Onay bekleniyor',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                rejected
                    ? 'Öğrenci belgen veya bilgiler eşleşmedi. Destek ile iletişime geçebilir veya çıkış yapıp yeniden başvurabilirsin.'
                    : 'Öğrenci belgen incelenirken ${AppInfo.appName}’e sınırlı erişimin var. '
                        'Onay veya red kararı e-posta ve cihaz bildirimiyle (iOS & Android) iletilir.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () async {
                  await auth.signOut();
                  if (context.mounted) context.go('/login');
                },
                child: const Text('Çıkış yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
