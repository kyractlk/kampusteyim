import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/data/auth_provider.dart';
import '../theme/app_colors.dart';

/// Misafir kısıtlı aksiyonlarda giriş ister.
class AuthGate {
  AuthGate._();

  static bool requireAuth(
    BuildContext context, {
    String message = 'Bu işlem için giriş yapmalısın.',
  }) {
    final auth = context.read<AuthProvider>();
    if (auth.isAuthenticated) return true;
    _showSheet(context, message);
    return false;
  }

  static Future<void> _showSheet(BuildContext context, String message) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Giriş gerekli',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/login');
                },
                child: const Text('Giriş Yap'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/register');
                },
                child: const Text('Kayıt Ol'),
              ),
            ],
          ),
        );
      },
    );
  }
}
