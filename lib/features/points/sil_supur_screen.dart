import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'points_models.dart';

class SilSupurScreen extends StatefulWidget {
  const SilSupurScreen({super.key});

  @override
  State<SilSupurScreen> createState() => _SilSupurScreenState();
}

class _SilSupurScreenState extends State<SilSupurScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  PointsConfig _config = const PointsConfig();
  int _spinsLeft = 0;
  bool _loading = true;
  bool _spinning = false;
  String? _error;
  String? _resultLabel;
  Map<String, dynamic>? _lastReward;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
    _load();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await PointsService.getConfig();
      if (!mounted) return;
      setState(() {
        _config = PointsConfig.fromMap(
          Map<String, dynamic>.from((res['config'] as Map?) ?? {}),
        );
        _spinsLeft = (num.tryParse('${res['spinsLeft']}') ?? 0).round();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _play() async {
    if (_spinning || _spinsLeft <= 0) return;
    final deviceWd = DateTime.now().weekday % 7;
    if (deviceWd != _config.silSupur.weekday) {
      final day = SilSupurConfig.weekdayLabels[_config.silSupur.weekday.clamp(0, 6)];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sil Süpür yalnızca $day günü açık')),
      );
      // still allow server to decide — server is source of truth
    }

    setState(() {
      _spinning = true;
      _resultLabel = null;
      _lastReward = null;
    });

    _spin
      ..reset()
      ..forward();

    try {
      final res = await PointsService.playSilSupur();
      // let animation finish
      if (_spin.isAnimating) await _spin.forward();
      if (!mounted) return;
      final seg = Map<String, dynamic>.from((res['segment'] as Map?) ?? {});
      setState(() {
        _spinning = false;
        _resultLabel = '${seg['label'] ?? 'Sonuç'}';
        _lastReward = res['reward'] is Map
            ? Map<String, dynamic>.from(res['reward'] as Map)
            : null;
        _spinsLeft = (num.tryParse('${res['spinsLeft']}') ?? _spinsLeft).round();
      });
      final type = '${seg['type'] ?? ''}';
      if (type == 'esim' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('eSIM hazırlanıyor — Kazandıklarım’a bak')),
        );
      }
    } catch (e) {
      _spin.stop();
      if (!mounted) return;
      setState(() => _spinning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final segs = _config.silSupur.segments;
    return Scaffold(
      backgroundColor: const Color(0xFF071526),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Sil Süpür'),
        actions: [
          IconButton(
            onPressed: () => context.push('/points/rewards'),
            icon: const Icon(Icons.card_giftcard_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
              : !_config.enabled || !_config.silSupur.enabled
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Sil Süpür Market ile birlikte kapalı.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                      ),
                    )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Her ${SilSupurConfig.weekdayLabels[_config.silSupur.weekday.clamp(0, 6)]} · kalan hak: $_spinsLeft',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: 320,
                          height: 340,
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              const Positioned(
                                top: 0,
                                child: Icon(
                                  Icons.arrow_drop_down,
                                  color: AppColors.gold,
                                  size: 56,
                                ),
                              ),
                              Positioned(
                                top: 36,
                                left: 10,
                                right: 10,
                                bottom: 10,
                                child: AnimatedBuilder(
                                  animation: _spin,
                                  builder: (context, _) {
                                    final t = Curves.easeOutCubic.transform(_spin.value);
                                    final turns = t * 6.2;
                                    return Transform.rotate(
                                      angle: turns * 2 * math.pi,
                                      child: CustomPaint(
                                        painter: _WheelPainter(segments: segs),
                                        child: const SizedBox.expand(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_resultLabel != null) ...[
                      Text(
                        _resultLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_lastReward != null && '${_lastReward!['type']}' == 'esim')
                        TextButton(
                          onPressed: () => context.push('/points/rewards'),
                          child: const Text('eSIMme git'),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: AppColors.navy,
                          ),
                          onPressed: _spinning || _spinsLeft <= 0 ? null : _play,
                          child: Text(
                            _spinning
                                ? 'Çevriliyor…'
                                : _spinsLeft <= 0
                                    ? 'Hakkın bitti'
                                    : 'ÇEVİR',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.segments});

  final List<SilSupurSegment> segments;

  static const _palette = [
    Color(0xFF00D4C8),
    Color(0xFF0B1F3A),
    Color(0xFFD9B31E),
    Color(0xFFC8102E),
    Color(0xFF89C741),
    Color(0xFF163356),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final list = segments.isEmpty
        ? [const SilSupurSegment(id: 'x', label: '?', weight: 1, type: 'none')]
        : segments;
    final total = list.fold<int>(0, (a, s) => a + math.max(1, s.weight));
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    var start = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white24
      ..strokeWidth = 2;

    for (var i = 0; i < list.length; i++) {
      final sweep = (math.max(1, list[i].weight) / total) * 2 * math.pi;
      paint.color = _palette[i % _palette.length];
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, paint);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, border);

      final mid = start + sweep / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: list[i].label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: r * 0.55);
      canvas.save();
      canvas.translate(c.dx + math.cos(mid) * r * 0.62, c.dy + math.sin(mid) * r * 0.62);
      canvas.rotate(mid + math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();

      start += sweep;
    }

    canvas.drawCircle(c, r * 0.16, Paint()..color = Colors.white);
    canvas.drawCircle(c, r * 0.12, Paint()..color = AppColors.navy);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.segments != segments;
}
