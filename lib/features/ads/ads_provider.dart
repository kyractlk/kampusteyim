import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../core/widgets/social_widgets.dart';
import '../auth/data/auth_provider.dart';
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
      feed = all
          .where((a) => (a['placements'] as List? ?? []).contains('feed'))
          .toList();
      reels = all
          .where((a) => (a['placements'] as List? ?? []).contains('reels'))
          .toList();
      stories = all
          .where((a) => (a['placements'] as List? ?? []).contains('stories'))
          .toList();
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

class AdCard extends StatefulWidget {
  const AdCard({
    super.key,
    required this.ad,
    this.compact = false,
    this.placement,
  });

  final Map<String, dynamic> ad;
  final bool compact;

  /// feed | reels | stories — varyant seçimi için
  final String? placement;

  @override
  State<AdCard> createState() => _AdCardState();
}

class _AdCardState extends State<AdCard> {
  bool _impressionSent = false;

  Map<String, dynamic> get ad => widget.ad;

  String get _ownerId =>
      '${ad['ownerId'] ?? ad['companyId'] ?? ad['communityId'] ?? ''}'.trim();

  String get _ownerName {
    final name =
        '${ad['ownerName'] ?? ad['companyName'] ?? ad['ownerHandle'] ?? ''}'
            .trim();
    return name.isEmpty ? 'Sponsor' : name;
  }

  String get _ownerHandle {
    final handle = '${ad['ownerHandle'] ?? ''}'.trim();
    if (handle.isNotEmpty) return handle;
    final username = '${ad['ownerUsername'] ?? ''}'.trim();
    if (username.isNotEmpty) return '@$username';
    return '';
  }

  String? get _ownerPhoto {
    final url = '${ad['ownerPhotoUrl'] ?? ''}'.trim();
    return url.startsWith('http') ? url : null;
  }

  bool get _isCommunity =>
      ad['isCommunity'] == true || '${ad['ownerType'] ?? ''}' == 'community';

  String get _image {
    final variants = ad['imageVariants'];
    if (variants is Map) {
      final key = widget.placement ?? 'feed';
      final preferred = '${variants[key] ?? ''}';
      if (preferred.startsWith('http')) return preferred;
      final feed = '${variants['feed'] ?? ''}';
      if (feed.startsWith('http')) return feed;
    }
    return '${ad['imageUrl'] ?? ''}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trackImpression());
  }

  Future<void> _trackImpression() async {
    if (!mounted || _impressionSent) return;
    _impressionSent = true;
    final me = context.read<AuthProvider>().user;
    try {
      await CommerceService.trackAd(
        adId: '${ad['id'] ?? ''}',
        event: 'impression',
        placement: widget.placement ?? 'feed',
        city: me?.city,
        university: me?.university,
      );
    } catch (_) {}
  }

  Future<void> _trackClick() async {
    final me = context.read<AuthProvider>().user;
    try {
      await CommerceService.trackAd(
        adId: '${ad['id'] ?? ''}',
        event: 'click',
        placement: widget.placement ?? 'feed',
        city: me?.city,
        university: me?.university,
      );
    } catch (_) {}
  }

  void _openOwner() {
    final id = _ownerId;
    if (id.isEmpty) return;
    final username = '${ad['ownerUsername'] ?? ''}'.trim();
    AppNav.openUser(context, username.isNotEmpty ? username : id);
  }

  Future<void> _openCreative() async {
    await _trackClick();
    if (!mounted) return;
    final type = '${ad['linkType'] ?? 'none'}';
    if (type == 'event') {
      final id = '${ad['linkEventId'] ?? ''}';
      if (id.isNotEmpty) {
        context.push('/event/${Uri.encodeComponent(id)}');
        return;
      }
    }
    if (type == 'job') {
      context.push('/jobs');
      return;
    }
    final url = '${ad['linkUrl'] ?? ''}';
    if (url.startsWith('http')) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    // Bağlantı yoksa reklam veren hesaba git.
    _openOwner();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final aspect = switch (widget.placement) {
      'stories' => 9 / 16,
      'reels' => 4 / 5,
      _ => widget.compact ? 16 / 7 : 16 / 9,
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _openOwner,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  UserAvatar(
                    name: _ownerName,
                    photoUrl: _ownerPhoto,
                    radius: widget.compact ? 18 : 20,
                    isCommunity: _isCommunity,
                    onTap: _openOwner,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _ownerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.navy.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${ad['badge'] ?? 'Sponsorlu'}',
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_ownerHandle.isNotEmpty)
                          Text(
                            _ownerHandle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hesabı aç',
                    onPressed: _openOwner,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _openCreative,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (image.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: SafeNetworkImage(url: image, fit: BoxFit.cover),
                      ),
                    ),
                  if (image.isNotEmpty) const SizedBox(height: 8),
                  Text(
                    '${ad['title'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if ('${ad['body'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${ad['body']}',
                      maxLines: widget.compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _ctaLabel,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _ctaLabel {
    final custom = '${ad['ctaLabel'] ?? ''}'.trim();
    if (custom.isNotEmpty) return custom;
    final type = '${ad['linkType'] ?? 'none'}';
    return switch (type) {
      'event' => 'Etkinliği gör',
      'job' => 'İlanı gör',
      'url' || 'sponsor' => 'Bağlantıyı aç',
      _ => 'Hesabı gör',
    };
  }
}
