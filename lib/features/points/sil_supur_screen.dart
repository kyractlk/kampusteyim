import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const double _itemH = 92;

  late final AnimationController _ctrl;
  Animation<double>? _scrollAnim;
  double _scroll = 0;

  PointsConfig _config = const PointsConfig();
  List<SilSupurSegment> _segments = const [];
  int _spinsLeft = 0;
  bool _loading = true;
  bool _spinning = false;
  String? _error;
  String? _resultLabel;
  Map<String, dynamic>? _lastReward;

  static const _palette = [
    Color(0xFF0EA5E9),
    Color(0xFF1D4ED8),
    Color(0xFFF59E0B),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFF7C3AED),
    Color(0xFF0D9488),
    Color(0xFFDB2777),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    _ctrl.addListener(() {
      final a = _scrollAnim;
      if (a != null) setState(() => _scroll = a.value);
    });
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
      final cfg = PointsConfig.fromMap(
        Map<String, dynamic>.from((res['config'] as Map?) ?? {}),
      );
      setState(() {
        _config = cfg;
        _segments = cfg.silSupur.segments.isNotEmpty
            ? cfg.silSupur.segments
            : const [
                SilSupurSegment(
                  id: 'miss',
                  label: 'Tekrar dene',
                  weight: 40,
                  type: 'none',
                ),
                SilSupurSegment(
                  id: 'pts30',
                  label: '+30 KP',
                  weight: 22,
                  type: 'points',
                  points: 30,
                ),
              ];
        _spinsLeft = (num.tryParse('${res['spinsLeft']}') ?? 0).round();
        _loading = false;
        // Ortadaki hücrede ilk dilim dursun
        _scroll = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  int _indexForId(String? id) {
    final i = _segments.indexWhere((s) => s.id == id);
    return i >= 0 ? i : 0;
  }

  Color _colorFor(int i) => _palette[i % _palette.length];

  IconData _iconFor(SilSupurSegment s) {
    switch (s.type) {
      case 'points':
        return Icons.stars_rounded;
      case 'esim':
        return Icons.sim_card_outlined;
      case 'gift':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.refresh_rounded;
    }
  }

  Future<void> _play() async {
    if (_spinning || _spinsLeft <= 0 || _segments.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _spinning = true;
      _resultLabel = null;
      _lastReward = null;
    });

    try {
      final res = await PointsService.playSilSupur();
      if (!mounted) return;
      final seg = Map<String, dynamic>.from((res['segment'] as Map?) ?? {});
      final winId = '${seg['id'] ?? ''}';
      final winIdx = _indexForId(winId);
      final n = _segments.length;

      // Ortadaki satır (index 1 of 3) = kazanan. scroll, item indeksini yukarı kaydırır.
      // Gösterilen merkez: floor(scroll / itemH) % n  →  winIdx olsun.
      final base = _scroll;
      final currentIdx = ((base / _itemH).floor() % n + n) % n;
      var steps = winIdx - currentIdx;
      if (steps <= 0) steps += n;
      steps += n * 8; // ~8 tur
      final target = base + steps * _itemH;

      _scrollAnim = Tween<double>(begin: base, end: target).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
      _ctrl.duration = const Duration(milliseconds: 4200);
      await _ctrl.forward(from: 0);

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _spinning = false;
        _scroll = target;
        _resultLabel = '${seg['label'] ?? 'Sonuç'}';
        _lastReward = res['reward'] is Map
            ? Map<String, dynamic>.from(res['reward'] as Map)
            : null;
        _spinsLeft =
            (num.tryParse('${res['spinsLeft']}') ?? _spinsLeft).round();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _spinning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final day =
        SilSupurConfig.weekdayLabels[_config.silSupur.weekday.clamp(0, 6)];
    return Scaffold(
      backgroundColor: const Color(0xFF050E1A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Sil Süpür',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Kazandıklarım',
            onPressed: () => context.push('/points/rewards'),
            icon: const Icon(Icons.card_giftcard_outlined),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [
              Color(0xFF153A62),
              Color(0xFF071526),
              Color(0xFF030912),
            ],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.cyan),
                )
              : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : !_config.enabled || !_config.silSupur.enabled
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Sil Süpür şu an kapalı.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              'Her $day · kalan hak: $_spinsLeft',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 8,
                                  ),
                                  child: _SlotMachine(
                                    itemHeight: _itemH,
                                    scroll: _scroll,
                                    segments: _segments,
                                    colorFor: _colorFor,
                                    iconFor: _iconFor,
                                    spinning: _spinning,
                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: _resultLabel == null
                                  ? const SizedBox(height: 64)
                                  : Padding(
                                      key: ValueKey(_resultLabel),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            _resultLabel!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 26,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if (_lastReward != null &&
                                              '${_lastReward!['type']}' ==
                                                  'esim')
                                            TextButton(
                                              onPressed: () => context
                                                  .push('/points/rewards'),
                                              child: const Text(
                                                'eSIMme git',
                                                style: TextStyle(
                                                  color: AppColors.cyan,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            )
                                          else
                                            const SizedBox(height: 8),
                                        ],
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                              child: SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.cyan,
                                    foregroundColor: AppColors.navy,
                                    disabledBackgroundColor:
                                        Colors.white.withValues(alpha: 0.12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: _spinning || _spinsLeft <= 0
                                      ? null
                                      : _play,
                                  child: Text(
                                    _spinning
                                        ? 'Dönüyor…'
                                        : _spinsLeft <= 0
                                            ? 'Hakkın bitti'
                                            : 'ÇEVİR',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }
}

class _SlotMachine extends StatelessWidget {
  const _SlotMachine({
    required this.itemHeight,
    required this.scroll,
    required this.segments,
    required this.colorFor,
    required this.iconFor,
    required this.spinning,
  });

  final double itemHeight;
  final double scroll;
  final List<SilSupurSegment> segments;
  final Color Function(int) colorFor;
  final IconData Function(SilSupurSegment) iconFor;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
      child: AspectRatio(
        aspectRatio: 0.78,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.cyan.withValues(alpha: spinning ? 0.35 : 0.18),
                    blurRadius: spinning ? 40 : 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A3A5C),
                    Color(0xFF0B1F3A),
                    Color(0xFF061018),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFE8C547),
                  width: 3,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final on = spinning
                          ? ((scroll / 40).floor() + i) % 2 == 0
                          : true;
                      return Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on
                              ? const Color(0xFFFFE08A)
                              : const Color(0xFF4A5568),
                          boxShadow: on
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFFFE08A)
                                        .withValues(alpha: 0.7),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final vh = constraints.maxHeight;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: const Color(0xFF030912),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.18),
                                    width: 2,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _ReelStrip(
                                  itemHeight: itemHeight,
                                  scroll: scroll,
                                  segments: segments,
                                  colorFor: colorFor,
                                  iconFor: iconFor,
                                  viewportHeight: vh,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: Center(
                                child: Container(
                                  height: itemHeight,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: AppColors.cyan,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.cyan
                                            .withValues(alpha: 0.35),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: Column(
                                children: [
                                  Container(
                                    height: math.min(
                                      itemHeight * 0.55,
                                      vh * 0.28,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(18),
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          const Color(0xFF030912),
                                          const Color(0xFF030912)
                                              .withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    height: math.min(
                                      itemHeight * 0.55,
                                      vh * 0.28,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(18),
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          const Color(0xFF030912),
                                          const Color(0xFF030912)
                                              .withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: _SidePointer(right: false),
                            ),
                            const Align(
                              alignment: Alignment.centerRight,
                              child: _SidePointer(right: true),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    spinning ? 'Şans dönüyor…' : 'Ortaya gelen kazanır',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
}

class _SidePointer extends StatelessWidget {
  const _SidePointer({required this.right});
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(right ? 6 : -6, 0),
      child: CustomPaint(
        size: const Size(14, 22),
        painter: _PointerPainter(right: right),
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  _PointerPainter({required this.right});
  final bool right;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (right) {
      path
        ..moveTo(size.width, size.height / 2)
        ..lineTo(0, 0)
        ..lineTo(0, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, size.height / 2)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFE08A), Color(0xFFD9B31E)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) =>
      oldDelegate.right != right;
}

class _ReelStrip extends StatelessWidget {
  const _ReelStrip({
    required this.itemHeight,
    required this.scroll,
    required this.segments,
    required this.colorFor,
    required this.iconFor,
    required this.viewportHeight,
  });

  final double itemHeight;
  final double scroll;
  final List<SilSupurSegment> segments;
  final Color Function(int) colorFor;
  final IconData Function(SilSupurSegment) iconFor;
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    final n = math.max(1, segments.length);
    // Merkez satırı hizala: viewport ortası − yarım item
    final centerPad = (viewportHeight - itemHeight) / 2;
    final phase = scroll % (itemHeight * n);
    // Görünen hücre indeksleri (yukarıdan aşağı)
    final firstLogical = (scroll / itemHeight).floor() - 1;
    final children = <Widget>[];
    // 5 hücre yeterli (üst fade + merkez + alt)
    for (var k = 0; k < 5; k++) {
      final logical = firstLogical + k;
      final idx = ((logical % n) + n) % n;
      final seg = segments[idx];
      children.add(
        SizedBox(
          height: itemHeight,
          child: _SlotCell(
            segment: seg,
            color: colorFor(idx),
            icon: iconFor(seg),
          ),
        ),
      );
    }

    final y = centerPad - (phase % itemHeight) - itemHeight;
    return Stack(
      children: [
        Transform.translate(
          offset: Offset(0, y),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SlotCell extends StatelessWidget {
  const _SlotCell({
    required this.segment,
    required this.color,
    required this.icon,
  });

  final SilSupurSegment segment;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              Color.lerp(color, const Color(0xFF030912), 0.35)!,
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                segment.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
