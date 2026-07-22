import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../auth/data/auth_provider.dart';
import 'study_models.dart';

/// Çalışma lobisi: solo / oda oluştur / koda katıl.
class StudyLobbyScreen extends StatefulWidget {
  const StudyLobbyScreen({super.key});

  @override
  State<StudyLobbyScreen> createState() => _StudyLobbyScreenState();
}

class _StudyLobbyScreenState extends State<StudyLobbyScreen> {
  int _minutes = 25;
  final _title = TextEditingController(text: 'Odak seansı');
  final _code = TextEditingController();
  bool _busy = false;
  bool _announce = true;

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      AuthGate.requireAuth(context, message: 'Oda açmak için giriş yap.');
      return;
    }
    setState(() => _busy = true);
    try {
      final room = await StudyRoomService.createRoom(
        host: user,
        minutes: _minutes,
        title: _title.text,
        announce: _announce,
      );
      if (!mounted) return;
      context.push('/study/${room.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Oda açılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinCode() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      AuthGate.requireAuth(context, message: 'Katılmak için giriş yap.');
      return;
    }
    setState(() => _busy = true);
    try {
      final room = await StudyRoomService.findByCode(_code.text);
      if (room == null) throw StateError('Kod bulunamadı');
      await StudyRoomService.join(room.id, user);
      if (!mounted) return;
      context.push('/study/${room.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Çalışma odası')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Row(
            children: [
              AppCircleLogo(logo: AppLogo.ays, size: 48),
              SizedBox(width: 12),
              AppCircleLogo(logo: AppLogo.ays, size: 48),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            user?.isCommunity == true
                ? 'Topluluk olarak ortak çalışma etkinliği başlatabilirsin.'
                : 'Kendi odanı aç veya kodla katıl. Odada sayaç + canlı chat var.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          const Text('Süre (dk)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in [15, 25, 45, 60, 90])
                _MinuteChip(
                  minutes: m,
                  selected: _minutes == m,
                  onTap: () => setState(() => _minutes = m),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(
                  () => _minutes = (_minutes - 5).clamp(5, 180),
                ),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_minutes dk',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => _minutes = (_minutes + 5).clamp(5, 180),
                ),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Oda başlığı',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Feed’de duyur'),
            subtitle: const Text('Diğerleri posttan katılabilsin'),
            value: _announce,
            onChanged: (v) => setState(() => _announce = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: Text(_busy ? '…' : 'Oda oluştur ve gir'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => context.push('/study/solo?m=$_minutes'),
            child: const Text('Sadece solo sayaç'),
          ),
          const Divider(height: 36),
          const Text(
            'Koda katıl',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Oda kodu',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: _busy ? null : _joinCode,
            child: const Text('Katıl'),
          ),
        ],
      ),
    );
  }
}

class _MinuteChip extends StatelessWidget {
  const _MinuteChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.cyan : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.border,
            ),
          ),
          child: Text(
            '$minutes',
            style: TextStyle(
              color: selected ? AppColors.navy : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Solo sayaç (eski timer) — chip’ler okunaklı.
class StudySoloTimerScreen extends StatefulWidget {
  const StudySoloTimerScreen({super.key, this.initialMinutes = 25});

  final int initialMinutes;

  @override
  State<StudySoloTimerScreen> createState() => _StudySoloTimerScreenState();
}

class _StudySoloTimerScreenState extends State<StudySoloTimerScreen> {
  late int _minutes;
  Duration _remaining = Duration.zero;
  bool _running = false;
  bool _finished = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _minutes = widget.initialMinutes.clamp(5, 180);
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
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    super.dispose();
  }

  void _start() {
    setState(() {
      _remaining = Duration(minutes: _minutes);
      _running = true;
      _finished = false;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining.inSeconds <= 1) {
        _tick?.cancel();
        setState(() {
          _remaining = Duration.zero;
          _running = false;
          _finished = true;
        });
        SystemSound.play(SystemSoundType.alert);
        return;
      }
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final display =
        _running || _finished ? _remaining : Duration(minutes: _minutes);
    return Scaffold(
      backgroundColor: const Color(0xFF071526),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                  const Spacer(),
                  const Text(
                    'Solo sayaç',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppCircleLogo(logo: AppLogo.ays, size: 56, showBorder: false),
                  SizedBox(width: 16),
                  AppCircleLogo(logo: AppLogo.ays, size: 56, showBorder: false),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _fmt(display),
                style: TextStyle(
                  color: _finished ? AppColors.gold : Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _finished ? 'Süre doldu' : (_running ? 'Çalışıyorsun' : 'Hazır'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
              ),
              const Spacer(),
              if (!_running && !_finished)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final m in [15, 25, 45, 60, 90])
                      _DarkMinuteChip(
                        minutes: m,
                        selected: _minutes == m,
                        onTap: () => setState(() => _minutes = m),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              if (!_running)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size(160, 48),
                  ),
                  onPressed: _finished
                      ? () {
                          setState(() => _finished = false);
                          _start();
                        }
                      : _start,
                  child: Text(_finished ? 'Tekrar' : 'Başlat'),
                ),
              if (_running)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                  ),
                  onPressed: () {
                    _tick?.cancel();
                    setState(() => _running = false);
                  },
                  child: const Text('Duraklat'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DarkMinuteChip extends StatelessWidget {
  const _DarkMinuteChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.cyan : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            '$minutes',
            style: TextStyle(
              color: selected ? AppColors.navy : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
