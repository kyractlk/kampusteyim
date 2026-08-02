import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Instagram tarzı çift tık → kalp animasyonu + beğeni.
/// Web’de kapalı (çift tık seçimle çakışır); mobil / masaüstünde açık.
class DoubleTapLike extends StatefulWidget {
  const DoubleTapLike({
    super.key,
    required this.child,
    required this.onLike,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onLike;
  final bool enabled;

  static bool get supported => !kIsWeb;

  @override
  State<DoubleTapLike> createState() => _DoubleTapLikeState();
}

class _DoubleTapLikeState extends State<DoubleTapLike>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.35, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 0.9)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_ctrl);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 35),
    ]).animate(_ctrl);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _show = false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flash() {
    setState(() => _show = true);
    _ctrl.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (!widget.enabled) return;
    widget.onLike();
    _flash();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && DoubleTapLike.supported;
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onDoubleTap: active ? _handleDoubleTap : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_show)
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Opacity(
                    opacity: _opacity.value.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 88,
                        color: AppColors.crimson.withValues(alpha: 0.95),
                        shadows: const [
                          Shadow(
                            blurRadius: 18,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
