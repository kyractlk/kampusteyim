import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';

String promoCardCta(AppUser user) {
  if (user.isCommunity) return 'Topluluk hesabımızı takip edin';
  if (user.isCompany) return 'Firma hesabımızı takip edin';
  return 'Hesabımızı takip edin';
}

String promoCardQrUrl(AppUser user) {
  final handle = (user.username ?? '').trim().replaceFirst(RegExp(r'^@'), '');
  final slug = handle.isNotEmpty ? handle : user.id;
  return '${AppInfo.webBaseUrl}/t/$slug';
}

String promoCardUsername(AppUser user) {
  final handle = (user.username ?? '').trim().replaceFirst(RegExp(r'^@'), '');
  return handle.isNotEmpty ? handle : user.id;
}

/// Dikey tanıtım rozeti — 360×540 mantıksal, 3x PNG için 1080×1620.
class PromoBadgeCard extends StatelessWidget {
  const PromoBadgeCard({super.key, required this.user});

  final AppUser user;

  static const logicalSize = Size(360, 540);

  @override
  Widget build(BuildContext context) {
    final photo = (user.photoUrl ?? user.communityLogoUrl ?? '').trim();
    final name = user.fullName.trim().isEmpty ? user.firstName : user.fullName.trim();
    final handle = user.handle.startsWith('@') ? user.handle : '@${user.handle}';

    return SizedBox(
      width: logicalSize.width,
      height: logicalSize.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF061426), AppColors.navy, Color(0xFF123456)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
          child: Column(
            children: [
              _BrandMark(),
              const SizedBox(height: 18),
              _Avatar(url: photo, name: name),
              const SizedBox(height: 14),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  height: 1.15,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                handle,
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                promoCardCta(user),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: promoCardQrUrl(user),
                  version: QrVersions.auto,
                  size: 168,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppColors.navy,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'QR’ı okut · uygulamada aç veya indir',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'kampusteyim.app',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            AppAssets.kampusIcon,
            width: 36,
            height: 36,
            errorBuilder: (_, __, ___) => Image.network(
              'https://firebasestorage.googleapis.com/v0/b/ayskampuss.firebasestorage.app/o/branding%2Fkampusteyim_app_logo.png?alt=media',
              width: 36,
              height: 36,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school_rounded,
                color: AppColors.cyan,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Kampüsteyim'),
              TextSpan(
                text: 'APP',
                style: TextStyle(color: AppColors.cyan),
              ),
            ],
          ),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.cyan, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.28),
            blurRadius: 16,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? ColoredBox(
              color: AppColors.navySoft,
              child: Center(
                child: Text(
                  letter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 32,
                  ),
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: AppColors.navySoft,
                child: Center(
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
