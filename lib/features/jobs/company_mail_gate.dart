import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'jobs_provider.dart';

/// Mail/teklif/ilan öncesi imza kontrolü. Yoksa ayarlara yönlendirir.
Future<bool> ensureCompanyMailSignature(BuildContext context) async {
  final jobs = context.read<JobsProvider>();
  await jobs.refreshCompanyProfile();
  if (jobs.hasMailSignature) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mail imzası gerekli'),
      content: const Text(
        'Öğrenciye mail, teklif veya ilan bildirimi göndermeden önce '
        'Gmail tarzı mail imzanızı (logo + yetkili bilgileri) ayarlamanız gerekir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Ayarlara git'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    context.push('/firma/settings');
  }
  return false;
}
