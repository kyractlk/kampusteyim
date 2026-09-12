import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/panel_chrome.dart';
import '../../core/widgets/social_widgets.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import 'company_mail_gate.dart';
import 'job_models.dart';
import 'jobs_provider.dart';

/// Öğrenci tarama / aday kartından teklif: imza şart, mail + push.
Future<bool> showCompanyOfferComposer(
  BuildContext context, {
  required String studentId,
  required String studentName,
  String? studentEmail,
  String? studentPhoto,
  String? presetMessage,
}) async {
  if (!await ensureCompanyMailSignature(context)) return false;
  if (!context.mounted) return false;

  final jobs = context.read<JobsProvider>();
  final company = jobs.company;
  final sig = company?.mailSignature ?? const CompanyMailSignature();
  final first = studentName.trim().split(' ').first;
  final greetingName = first.isEmpty ? 'Merhaba' : 'Merhaba $first';
  final companyName = company?.name ?? 'Firmamız';

  final message = TextEditingController(
    text: (presetMessage ?? '').trim().isNotEmpty
        ? presetMessage!.trim()
        : '$greetingName,\n\n'
            '$companyName olarak özgeçmişinizi inceledik. '
            'Sizinle staj / iş görüşmesi yapmak isteriz.\n\n'
            'Uygun olduğunuzda uygulama üzerinden veya imzamızdaki iletişim '
            'kanallarından bize dönüş yapabilirsiniz.',
  );

  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Teklif gönder',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Öğrenciye kurumsal e-posta ve anlık bildirim gider. '
                    'İletişim bilgileriniz imza olarak eklenir.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  PanelCard(
                    child: Row(
                      children: [
                        UserAvatar(
                          name: studentName,
                          photoUrl: studentPhoto,
                          radius: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName.trim().isEmpty
                                    ? 'Aday'
                                    : studentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if ((studentEmail ?? '').isNotEmpty)
                                Text(
                                  studentEmail!,
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: message,
                    maxLines: 7,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Teklif metni',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PanelCard(
                    color: AppColors.navy.withValues(alpha: 0.04),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mail imzası · öğrenci bunu görür',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (sig.contactName.trim().isNotEmpty)
                              sig.contactName,
                            if (sig.jobTitle.trim().isNotEmpty) sig.jobTitle,
                            companyName,
                            if (sig.replyEmail.trim().isNotEmpty)
                              sig.replyEmail,
                            if (sig.phone.trim().isNotEmpty) sig.phone,
                            if (sig.website.trim().isNotEmpty) sig.website,
                          ].join('\n'),
                          style: const TextStyle(
                            height: 1.4,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final text = message.text.trim();
                            if (text.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Teklif metni boş olamaz'),
                                ),
                              );
                              return;
                            }
                            setLocal(() => busy = true);
                            final ok = await jobs.sendOffer(
                              studentId: studentId,
                              message: text,
                              notifications:
                                  context.read<NotificationProvider>(),
                              auth: context.read<AuthProvider>(),
                              studentEmail: studentEmail,
                              studentName: first,
                            );
                            if (!ctx.mounted) return;
                            setLocal(() => busy = false);
                            Navigator.pop(ctx, ok);
                          },
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      busy ? 'Gönderiliyor…' : 'Teklif + mail gönder',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Vazgeç'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  message.dispose();
  if (!context.mounted) return false;
  if (sent != true) {
    if (jobs.status == 'MAIL_SIGNATURE_REQUIRED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce mail imza sayfasını doldurun')),
      );
    }
    return false;
  }
  final status = jobs.status ?? '';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        status.contains('mail') || status.contains('bildirim')
            ? status
            : 'Teklif gönderildi. Öğrenciye mail ve bildirim iletildi.',
      ),
    ),
  );
  return true;
}
