import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';

/// Çalışma sayacı — mobil yatay, web geniş; AYS + MT logo; bitişte ses.
class StudyTimerScreen extends StatefulWidget {
  const StudyTimerScreen({super.key});

  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen>
    with TickerProviderStateMixin {
  final _sessionId = const Uuid().v4().substring(0, 8).toUpperCase();
  final _player = AudioPlayer();

  int _minutes = 25;
  Duration _remaining = Duration.zero;
  bool _running = false;
  bool _finished = false;
  Timer? _tick;
  late final AnimationController _pulse;
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    _ring.dispose();
    _player.dispose();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    super.dispose();
  }

  void _start() {
    if (_running) return;
    setState(() {
      _remaining = Duration(minutes: _minutes);
      _running = true;
      _finished = false;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running) return;
      if (_remaining.inSeconds <= 1) {
        _tick?.cancel();
        setState(() {
          _remaining = Duration.zero;
          _running = false;
          _finished = true;
        });
        unawaited(_playDone());
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  void _pause() {
    _tick?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    _tick?.cancel();
    setState(() {
      _running = false;
      _finished = false;
      _remaining = Duration.zero;
    });
  }

  Future<void> _playDone() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await _player.play(AssetSource('sounds/timer_done.wav'));
    } catch (e) {
      debugPrint('[timer] sound: $e');
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final display = _running || _finished
        ? _remaining
        : Duration(minutes: _minutes);
    final progress = _running && _minutes > 0
        ? 1.0 - (_remaining.inSeconds / (_minutes * 60))
        : (_finished ? 1.0 : 0.0);

    return Scaffold(
      backgroundColor: const Color(0xFF071526),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ring,
                builder: (_, _) => CustomPaint(
                  painter: _TimerOrbitPainter(
                    progress: _ring.value,
                    accent: _finished ? AppColors.gold : AppColors.cyan,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: landscape ? 28 : 20,
                vertical: 12,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          'OTURUM $_sessionId',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: landscape
                        ? Row(
                            children: [
                              Expanded(child: _logosBlock()),
                              Expanded(
                                flex: 2,
                                child: _timerBlock(display, progress),
                              ),
                              Expanded(child: _controlsBlock()),
                            ],
                          )
                        : Column(
                            children: [
                              _logosBlock(),
                              Expanded(child: _timerBlock(display, progress)),
                              _controlsBlock(),
                            ],
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

  Widget _logosBlock() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final t = _pulse.value;
        return Transform.scale(
          scale: 0.96 + t * 0.05,
          child: child,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              AppCircleLogo(logo: AppLogo.ays, size: 64, showBorder: false),
              SizedBox(width: 18),
              AppCircleLogo(logo: AppLogo.ays, size: 64, showBorder: false),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'AYS Tech  ·  KampüsteyimAPP',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Çalışma odası',
            style: TextStyle(
              color: AppColors.cyan.withValues(alpha: 0.9),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerBlock(Duration display, double progress) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: CircularProgressIndicator(
                  value: _running || _finished ? progress.clamp(0.0, 1.0) : 0,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: _finished ? AppColors.gold : AppColors.cyan,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt(display),
                    style: TextStyle(
                      color: _finished ? AppColors.gold : Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _finished
                        ? 'Süre doldu'
                        : (_running ? 'Çalışıyorsun' : 'Hazır'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controlsBlock() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!_running && !_finished) ...[
            Text(
              'Süre (dk)',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final m in [15, 25, 45, 60, 90])
                  ChoiceChip(
                    label: Text('$m'),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                    selectedColor: AppColors.cyan,
                    labelStyle: TextStyle(
                      color: _minutes == m ? AppColors.navy : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => _minutes = (_minutes - 5).clamp(5, 180),
                  ),
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.white70),
                ),
                Text(
                  '$_minutes dk',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _minutes = (_minutes + 5).clamp(5, 180),
                  ),
                  icon: const Icon(Icons.add_circle_outline,
                      color: Colors.white70),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (!_running && !_finished)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size(140, 48),
                  ),
                  onPressed: _start,
                  child: const Text('Başlat'),
                ),
              if (_running)
                FilledButton.tonal(
                  onPressed: _pause,
                  child: const Text('Duraklat'),
                ),
              if (!_running && _remaining.inSeconds > 0 && !_finished)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: () {
                    setState(() => _running = true);
                    _tick?.cancel();
                    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
                      if (_remaining.inSeconds <= 1) {
                        _tick?.cancel();
                        setState(() {
                          _remaining = Duration.zero;
                          _running = false;
                          _finished = true;
                        });
                        unawaited(_playDone());
                        return;
                      }
                      setState(
                        () => _remaining -= const Duration(seconds: 1),
                      );
                    });
                  },
                  child: const Text('Devam'),
                ),
              if (_running || _finished || _remaining.inSeconds > 0)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  onPressed: _reset,
                  child: const Text('Sıfırla'),
                ),
              if (_finished)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: () {
                    _reset();
                    _start();
                  },
                  child: const Text('Tekrar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimerOrbitPainter extends CustomPainter {
  _TimerOrbitPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: 0.12);
    for (var i = 0; i < 3; i++) {
      final r = math.min(size.width, size.height) * (0.22 + i * 0.12);
      canvas.drawCircle(c, r, paint);
      final a = progress * math.pi * 2 + i;
      canvas.drawCircle(
        Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r),
        3.2,
        Paint()..color = accent.withValues(alpha: 0.4 - i * 0.08),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimerOrbitPainter old) =>
      old.progress != progress || old.accent != accent;
}
