import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../commerce/commerce_service.dart';

class AdsProvider extends ChangeNotifier {
  List<Map<String, dynamic>> feed = [];
  List<Map<String, dynamic>> reels = [];
  List<Map<String, dynamic>> stories = [];
  bool loaded = false;

  Future<void> refresh({String? city, String? university}) async {
    try {
      final all = await CommerceService.getActiveAds(
        city: city,
        university: university,
      );
      feed = all.where((a) => (a['placements'] as List? ?? []).contains('feed')).toList();
      reels = all.where((a) => (a['placements'] as List? ?? []).contains('reels')).toList();
      stories =
          all.where((a) => (a['placements'] as List? ?? []).contains('stories')).toList();
      loaded = true;
      notifyListeners();
    } catch (_) {
      loaded = true;
      notifyListeners();
    }
  }

  Map<String, dynamic>? pick(List<Map<String, dynamic>> pool) {
    if (pool.isEmpty) return null;
    pool.shuffle();
    return pool.first;
  }
}

class AdCard extends StatelessWidget {
  const AdCard({super.key, required this.ad, this.compact = false});

  final Map<String, dynamic> ad;
  final bool compact;

  Future<void> _open(BuildContext context) async {
    final type = '${ad['linkType'] ?? 'none'}';
    if (type == 'event') {
      final id = '${ad['linkEventId'] ?? ''}';
      if (id.isNotEmpty) context.push('/events/$id');
      return;
    }
    if (type == 'job') {
      context.push('/jobs');
      return;
    }
    final url = '${ad['linkUrl'] ?? ''}';
    if (url.startsWith('http')) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = '${ad['imageUrl'] ?? ''}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'REKLAM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${ad['companyName'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (image.isNotEmpty) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: compact ? 16 / 7 : 16 / 9,
                    child: SafeNetworkImage(url: image, fit: BoxFit.cover),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${ad['title'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if ('${ad['body'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${ad['body']}',
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
