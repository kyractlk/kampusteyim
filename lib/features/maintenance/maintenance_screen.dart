import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../auth/data/auth_provider.dart';
import 'maintenance_provider.dart';

/// Tam ekran AYS Tech bakım — geri sayım + haber et.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _orbit;
  Timer? _tick;
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final m = context.read<MaintenanceProvider>();
      final cached = m.cachedEmail;
      if (cached != null && cached.isNotEmpty && _emailCtrl.text.isEmpty) {
        _emailCtrl.text = cached;
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    _orbit.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String _fmt(Duration? d) {
    if (d == null) return '--:--:--';
    final total = d.inSeconds.clamp(0, 9999999);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h >= 24) {
      final days = h ~/ 24;
      final rh = h % 24;
      return '${days}g ${two(rh)}:${two(m)}:${two(s)}';
    }
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  Future<void> _notify() async {
    final maint = context.read<MaintenanceProvider>();
    final auth = context.read<AuthProvider>();
    var email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      email = maint.cachedEmail ?? auth.user?.email ?? '';
    }
    if (email.isEmpty && !kIsWeb) {
      email = auth.user?.email ?? '';
    }
    await maint.subscribeNotify(email: email, uid: auth.user?.id);
  }

  @override
  Widget build(BuildContext context) {
    final maint = context.watch<MaintenanceProvider>();
    final auth = context.watch<AuthProvider>();
    final st = maint.state;
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 520;
    final remaining = st.remaining;
    final endedClock = remaining != null && remaining == Duration.zero;

    final hasCached = (maint.cachedEmail ?? '').contains('@') ||
        (auth.user?.email ?? '').contains('@');
    final showEmailField = kIsWeb || !hasCached;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF071526),
              AppColors.navy,
              Color(0xFF0E2A4A),
              Color(0xFF123A52),
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _orbit,
                  builder: (_, _) {
                    return CustomPaint(
                      painter: _OrbitPainter(progress: _orbit.value),
                    );
                  },
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: narrow ? 22 : 40,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, child) {
                            final t = _pulse.value;
                            final scale = 0.94 + (t * 0.08);
                            final glow = 12 + (t * 22);
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.cyan
                                          .withValues(alpha: 0.35 + t * 0.25),
                                      blurRadius: glow,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: child,
                              ),
                            );
                          },
                          child: const AppCircleLogo(
                            logo: AppLogo.ays,
                            size: 96,
                            showBorder: false,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'AYS Tech',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          st.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          st.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                endedClock
                                    ? 'Planlanan süre doldu'
                                    : 'Tahmini kalan süre',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 12,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _fmt(remaining),
                                style: TextStyle(
                                  color: endedClock
                                      ? AppColors.gold
                                      : AppColors.cyan,
                                  fontSize: narrow ? 36 : 42,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (st.plannedEnd != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _endLabel(st.plannedEnd!),
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.55),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            kIsWeb
                                ? 'Bitince e-posta al'
                                : 'Bitince haber et',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          kIsWeb
                              ? 'Bakım tamamlanınca e-posta ile haber veririz.'
                              : 'Bakım tamamlanınca push bildirim göndeririz.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (showEmailField) ...[
                          TextField(
                            controller: _emailCtrl,
                            enabled: !maint.alreadySubscribed,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'e-posta@ornek.com',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: maint.subscribing ||
                                    maint.alreadySubscribed
                                ? null
                                : _notify,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: AppColors.navy,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.12),
                              disabledForegroundColor:
                                  Colors.white.withValues(alpha: 0.45),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              maint.alreadySubscribed
                                  ? (kIsWeb
                                      ? 'E-posta kaydı alındı'
                                      : 'Haber kaydı alındı')
                                  : maint.subscribing
                                      ? 'Kaydediliyor…'
                                      : (kIsWeb
                                          ? 'E-posta al'
                                          : 'Haber et'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (maint.status != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            maint.status!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.lime.withValues(alpha: 0.95),
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        TextButton(
                          onPressed: () => GoRouter.of(context).go('/admin'),
                          child: Text(
                            'Personel girişi',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'KampüsteyimAPP · AYS Tech',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
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

  String _endLabel(DateTime end) {
    final local = end.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Planlanan bitiş · ${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * 0.38);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.cyan.withValues(alpha: 0.12);
    for (var i = 0; i < 3; i++) {
      final r = 70.0 + i * 48;
      canvas.drawCircle(c, r, paint);
      final a = (progress * math.pi * 2) + i * 1.2;
      final dot = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      canvas.drawCircle(
        dot,
        3.5,
        Paint()..color = AppColors.cyan.withValues(alpha: 0.45 - i * 0.1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.progress != progress;
}
