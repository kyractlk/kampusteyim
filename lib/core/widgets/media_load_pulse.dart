import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/mt_icons.dart';
import '../theme/app_colors.dart';

enum MediaLoadKind { reel, story }

/// Reels / hikâye medya yüklenirken markalı SVG + orbit animasyonu.
class MediaLoadPulse extends StatefulWidget {
  const MediaLoadPulse({
    super.key,
    required this.kind,
    this.size = 72,
    this.label,
    this.compact = false,
    this.color = AppColors.cyan,
  });

  final MediaLoadKind kind;
  final double size;
  final String? label;
  final bool compact;
  final Color color;

  @override
  State<MediaLoadPulse> createState() => _MediaLoadPulseState();
}

class _MediaLoadPulseState extends State<MediaLoadPulse>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.compact ? widget.size * 0.72 : widget.size;
    final iconSvg =
        widget.kind == MediaLoadKind.reel ? MtIcons.reel : MtIcons.story;
    final fallbackLabel =
        widget.kind == MediaLoadKind.reel ? 'Reel yükleniyor' : 'Hikâye yükleniyor';
    final explicit = widget.label;
    final showLabel =
        explicit != null ? explicit.isNotEmpty : !widget.compact;
    final text =
        (explicit != null && explicit.isNotEmpty) ? explicit : fallbackLabel;

    return Semantics(
      label: text,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: s,
            height: s,
            child: AnimatedBuilder(
              animation: Listenable.merge([_spin, _pulse]),
              builder: (context, _) {
                final breath = 0.88 + (_pulse.value * 0.14);
                final glow = 0.12 + (_pulse.value * 0.18);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Soft halo
                    Container(
                      width: s * 0.78,
                      height: s * 0.78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: glow),
                            blurRadius: s * 0.28,
                            spreadRadius: s * 0.02,
                          ),
                        ],
                      ),
                    ),
                    // Orbiting arc
                    Transform.rotate(
                      angle: _spin.value * math.pi * 2,
                      child: CustomPaint(
                        size: Size(s, s),
                        painter: _OrbitPainter(
                          color: widget.color,
                          accent: Colors.white.withValues(alpha: 0.85),
                          kind: widget.kind,
                        ),
                      ),
                    ),
                    // Center SVG
                    Transform.scale(
                      scale: breath,
                      child: Container(
                        width: s * 0.46,
                        height: s * 0.46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: MtIcon(
                          iconSvg,
                          size: s * 0.28,
                          color: widget.color,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (showLabel) ...[
            SizedBox(height: widget.compact ? 6 : 12),
            Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: widget.compact ? 11 : 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.color,
    required this.accent,
    required this.kind,
  });

  final Color color;
  final Color accent;
  final MediaLoadKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.028
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(c, r, track);

    if (kind == MediaLoadKind.story) {
      // Dashed story ring feel
      final dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.034
        ..color = color.withValues(alpha: 0.35)
        ..strokeCap = StrokeCap.round;
      const segs = 10;
      for (var i = 0; i < segs; i++) {
        final start = (i / segs) * math.pi * 2;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          start,
          (math.pi * 2 / segs) * 0.55,
          false,
          dash,
        );
      }
    }

    final sweep = kind == MediaLoadKind.reel
        ? math.pi * 1.15
        : math.pi * 0.85;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: sweep,
      colors: [
        color.withValues(alpha: 0.05),
        color,
        accent,
      ],
      stops: const [0.0, 0.55, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(Rect.fromCircle(center: c, radius: r));

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.042
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );

    // Leading dot
    final tipAngle = -math.pi / 2 + sweep;
    final tip = Offset(
      c.dx + r * math.cos(tipAngle),
      c.dy + r * math.sin(tipAngle),
    );
    canvas.drawCircle(
      tip,
      size.width * 0.028,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.accent != accent ||
        oldDelegate.kind != kind;
  }
}
