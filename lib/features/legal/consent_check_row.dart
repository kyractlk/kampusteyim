import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Zorunlu onay satırı: metne basınca popup, kabul edilince checkbox dolu.
class ConsentCheckRow extends StatelessWidget {
  const ConsentCheckRow({
    super.key,
    required this.title,
    required this.body,
    required this.accepted,
    required this.onAccepted,
    this.subtitle = 'Okumak ve kabul etmek için dokun',
  });

  final String title;
  final String body;
  final bool accepted;
  final VoidCallback onAccepted;
  final String subtitle;

  Future<void> _open(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Text(body, style: const TextStyle(height: 1.45)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kabul ediyorum'),
          ),
        ],
      ),
    );
    if (ok == true) onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accepted
          ? AppColors.cyan.withValues(alpha: 0.12)
          : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: accepted,
                onChanged: (_) => _open(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        accepted ? 'Kabul edildi' : subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: accepted
                              ? AppColors.cyan
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.open_in_new, size: 16, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
