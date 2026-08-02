import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import 'partners_provider.dart';

/// Uygulama bilgisi ekranında iş ortakları listesi.
class PartnersAboutSection extends StatelessWidget {
  const PartnersAboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<PartnersProvider>().items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        const Row(
          children: [
            MtIcon(MtIcons.partners, size: 20, color: AppColors.navy),
            SizedBox(width: 8),
            Text(
              'İş ortaklarımız',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map((p) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: p.linkUrl.isEmpty
                  ? null
                  : () async {
                      final raw = p.linkUrl.trim();
                      final u = Uri.tryParse(
                        raw.startsWith('http') ? raw : 'https://$raw',
                      );
                      if (u != null) {
                        await launchUrl(u, mode: LaunchMode.externalApplication);
                      }
                    },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  color: AppColors.surface,
                ),
                child: Row(
                  children: [
                    if (p.logoUrl.startsWith('http'))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SafeNetworkImage(
                          url: p.logoUrl,
                          width: p.logoSize,
                          height: p.logoSize,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      MtIcon(MtIcons.partners, size: p.logoSize * 0.55),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          if (p.blurb.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              p.blurb,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
