import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Instagram tarzı hikâye katmanı — yazı / konum / gönderi sticker.
class StoryOverlay {
  const StoryOverlay({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.scale = 1,
    this.rotation = 0,
    this.text,
    this.fontStyle = 'bold',
    this.colorHex = '#FFFFFF',
    this.postId,
    this.postPreview,
    this.locationLabel,
  });

  final String id;
  /// text | post | location | poll
  final String type;
  final double x; // 0–1
  final double y;
  final double scale;
  final double rotation;
  final String? text;
  final String fontStyle; // bold | serif | handwritten | outline
  final String colorHex;
  final String? postId;
  final String? postPreview;
  final String? locationLabel;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'fontStyle': fontStyle,
        'colorHex': colorHex,
        if (text != null) 'text': text,
        if (postId != null) 'postId': postId,
        if (postPreview != null) 'postPreview': postPreview,
        if (locationLabel != null) 'locationLabel': locationLabel,
      };

  factory StoryOverlay.fromMap(Map<String, dynamic> m) => StoryOverlay(
        id: '${m['id'] ?? ''}',
        type: '${m['type'] ?? 'text'}',
        x: (m['x'] as num?)?.toDouble() ?? 0.5,
        y: (m['y'] as num?)?.toDouble() ?? 0.4,
        scale: (m['scale'] as num?)?.toDouble() ?? 1,
        rotation: (m['rotation'] as num?)?.toDouble() ?? 0,
        text: m['text'] as String?,
        fontStyle: '${m['fontStyle'] ?? 'bold'}',
        colorHex: '${m['colorHex'] ?? '#FFFFFF'}',
        postId: m['postId'] as String?,
        postPreview: m['postPreview'] as String?,
        locationLabel: m['locationLabel'] as String?,
      );

  TextStyle resolveTextStyle() {
    final color = _parseColor(colorHex);
    switch (fontStyle) {
      case 'serif':
        return TextStyle(
          fontFamily: 'serif',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.15,
        );
      case 'handwritten':
        return TextStyle(
          fontFamily: 'cursive',
          fontSize: 30,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.15,
        );
      case 'outline':
        return TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: color,
          height: 1.15,
          shadows: const [
            Shadow(offset: Offset(1, 1), blurRadius: 0, color: Colors.black),
            Shadow(offset: Offset(-1, -1), blurRadius: 0, color: Colors.black),
          ],
        );
      default:
        return TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: color,
          height: 1.15,
        );
    }
  }

  static Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFFFFF);
  }
}

class StoryOverlayLayer extends StatelessWidget {
  const StoryOverlayLayer({
    super.key,
    required this.overlays,
    this.onTapPost,
    this.interactive = false,
    this.onMove,
  });

  final List<StoryOverlay> overlays;
  final void Function(String postId)? onTapPost;
  final bool interactive;
  final void Function(String id, double x, double y)? onMove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return Stack(
          children: [
            for (final o in overlays)
              Positioned(
                left: o.x * c.maxWidth - 80,
                top: o.y * c.maxHeight - 20,
                child: GestureDetector(
                  onPanUpdate: interactive && onMove != null
                      ? (d) {
                          final nx =
                              ((o.x * c.maxWidth) + d.delta.dx) / c.maxWidth;
                          final ny =
                              ((o.y * c.maxHeight) + d.delta.dy) / c.maxHeight;
                          onMove!(
                            o.id,
                            nx.clamp(0.08, 0.92),
                            ny.clamp(0.08, 0.92),
                          );
                        }
                      : null,
                  onTap: o.type == 'post' && o.postId != null
                      ? () => onTapPost?.call(o.postId!)
                      : null,
                  child: Transform.rotate(
                    angle: o.rotation,
                    child: Transform.scale(
                      scale: o.scale,
                      child: _buildChild(o),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildChild(StoryOverlay o) {
    switch (o.type) {
      case 'location':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, color: AppColors.lime, size: 16),
              const SizedBox(width: 4),
              Text(
                o.locationLabel ?? 'Konum',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      case 'post':
        return Container(
          width: 160,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gönderi',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                o.postPreview ?? 'Gönderiye bak',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      default:
        return Text(
          o.text ?? '',
          textAlign: TextAlign.center,
          style: o.resolveTextStyle(),
        );
    }
  }
}
