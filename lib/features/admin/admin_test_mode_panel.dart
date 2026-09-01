import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../maintenance/test_mode_provider.dart';
import 'admin_provider.dart';

/// Admin · test modu paneli (bakım sekmesinde).
class AdminTestModePanel extends StatefulWidget {
  const AdminTestModePanel({super.key, required this.admin});

  final AdminProvider admin;

  @override
  State<AdminTestModePanel> createState() => _AdminTestModePanelState();
}

class _AdminTestModePanelState extends State<AdminTestModePanel> {
  final _message = TextEditingController(
    text:
        'KampüsteyimAPP şu an test modundadır. Paylaşımlar canlı yayına geçmeden önce silinebilir.',
  );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _toggle({required bool active}) async {
    if (!active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Test modunu kapat?'),
          content: const Text(
            'Test modu kapatıldığında admin hesapları hariç tüm kullanıcılar, '
            'postlar, reels, hikâyeler, firmalar, topluluklar, etkinlikler ve '
            'diğer test verileri kalıcı olarak silinir. Bu işlem geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.crimson,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kapat ve temizle'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await widget.admin.setTestMode(
        active: active,
        message: _message.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.admin.status ?? 'Kaydedildi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final testMode = context.watch<TestModeProvider>();
    final admin = widget.admin;
    final st = testMode.state;
    final fmt = DateFormat('d MMM yyyy HH:mm', 'tr');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              st.active ? Icons.science : Icons.science_outlined,
              color: st.active ? AppColors.crimson : AppColors.navy,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test modu',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    st.active
                        ? 'Açık · beta içerik üretiliyor'
                        : 'Kapalı · canlı yayın',
                    style: TextStyle(
                      color: st.active ? AppColors.crimson : AppColors.lime,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (st.active)
              FilledButton.tonal(
                onPressed: admin.busy ? null : () => _toggle(active: false),
                style: FilledButton.styleFrom(
                  foregroundColor: AppColors.crimson,
                ),
                child: const Text('Kapat'),
              )
            else
              FilledButton(
                onPressed: admin.busy ? null : () => _toggle(active: true),
                child: const Text('Test modunu aç'),
              ),
          ],
        ),
        if (st.startedAt != null) ...[
          const SizedBox(height: 6),
          Text(
            'Başlangıç: ${fmt.format(st.startedAt!.toLocal())}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
        if (st.purgedAt != null) ...[
          Text(
            'Son temizlik: ${fmt.format(st.purgedAt!.toLocal())}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Kullanıcı mesajı',
            border: OutlineInputBorder(),
            helperText: 'Test modu açıkken uygulamada banner olarak görünür',
          ),
        ),
        if (admin.status != null && admin.status!.contains('Test')) ...[
          const SizedBox(height: 8),
          Text(
            admin.status!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Test modu açıkken kullanıcılar uygulamayı kullanmaya devam eder. '
            'Kapattığınızda admin hesapları dışındaki tüm kayıtlar ve içerikler '
            '(reels, hikâye, post, firma, topluluk, etkinlik vb.) silinir.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
