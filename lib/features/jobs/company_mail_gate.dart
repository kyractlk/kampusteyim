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
      title: const Text('Mail imzası zorunlu'),
      content: const Text(
        'Teklif, öğrenciye e-posta ve bildirim olarak gider. '
        'Göndermeden önce logo, yetkili adı ve yanıt e-postasını '
        'imza sayfasında doldurmanız gerekir. İletişim bilgileriniz '
        'mailin imzasına otomatik eklenir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('İptal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('İmza sayfasına git'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    context.push('/firma/settings');
  }
  return false;
}
