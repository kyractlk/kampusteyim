import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import '../moderation/moderation_models.dart';
import '../moderation/report_sheet.dart';
import 'room_side_panel.dart';
import 'livekit_voice_session.dart';
import 'study_models.dart';

/// Paylaşımlı çalışma odası: senkron sayaç + açılır oda paneli + LiveKit ses.
class StudyRoomScreen extends StatefulWidget {
  const StudyRoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  final _chatCtrl = TextEditingController();
  final _player = AudioPlayer();
  final _scroll = ScrollController();

  bool _chatOpenUi = false;
  bool _joining = false;
  bool _sending = false;
  bool _playedEnd = false;
  bool _warned5min = false;
  bool _intentionalLeave = false;
  bool _isHostSession = false;
  bool _recording = false;
  String? _sessionUserId;
  Timer? _uiTick;
  final _recorder = AudioRecorder();
  DateTime? _recordStarted;
  final _liveVoice = LiveKitVoiceSession();
  bool _liveVoiceBusy = false;

  @override
  void initState() {
    super.initState();
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      unawaited(WakelockPlus.enable());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureJoined());
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    _chatCtrl.dispose();
    _player.dispose();
    _scroll.dispose();
    unawaited(_recorder.dispose());
    unawaited(_liveVoice.disconnect());
    if (!_intentionalLeave && _isHostSession && _sessionUserId != null) {
      unawaited(
        StudyRoomService.markHostLeft(widget.roomId, _sessionUserId!),
      );
    }
    if (!kIsWeb) {
      unawaited(WakelockPlus.disable());
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    super.dispose();
  }

  Future<void> _ensureJoined() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;
    _sessionUserId = user.id;
    setState(() => _joining = true);
    try {
      final room = await StudyRoomService.get(widget.roomId);
      if (room == null) throw StateError('Oda bulunamadÄ±');
      if (room.isKicked(user.id)) throw StateError('Bu odadan Ã§Ä±karÄ±ldÄ±n');
      if (!room.isMember(user.id) && !room.isPending(user.id)) {
        await StudyRoomService.join(widget.roomId, user);
      }
      if (room.isHost(user.id) && room.status != 'ended') {
        _isHostSession = true;
        await StudyRoomService.clearHostLeft(widget.roomId, user.id);
      } else {
        _isHostSession = room.isHost(user.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      AppNav.back(context);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _playEnd() async {
    if (_playedEnd) return;
    _playedEnd = true;
    try {
      await _player.play(AssetSource('sounds/timer_done.wav'));
    } catch (_) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _maybeWarn5min(Duration remaining) async {
    if (_warned5min) return;
    if (remaining <= Duration.zero || remaining > const Duration(minutes: 5)) {
      return;
    }
    _warned5min = true;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('5 dakika kaldÄ±'),
        content: const Text(
          'Odak seansÄ± bitmek Ã¼zere. Ä°stersen sÃ¼reye uzun basarak uzatabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _askExtend(StudyRoom room, String hostId) async {
    final ctrl = TextEditingController(text: '5');
    final mins = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SÃ¼reyi uzat'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'KaÃ§ dakika eklensin?',
            hintText: '5',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('VazgeÃ§'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(ctx, n);
            },
            child: const Text('Uzat'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (mins == null || mins <= 0 || !mounted) return;
    try {
      await StudyRoomService.extendSession(
        roomId: room.id,
        hostId: hostId,
        extraMinutes: mins,
      );
      _warned5min = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$mins dk eklendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Odadan Ã§Ä±k'),
        content: const Text(
          'Odak seansÄ±ndan ayrÄ±lmak istiyor musun?\n\n'
          'Oturum sahibiysen 1 saat iÃ§inde geri dÃ¶nmezsen oda otomatik kapanÄ±r.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ã‡Ä±k'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _intentionalLeave = true;
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user != null) {
      try {
        final room = await StudyRoomService.get(widget.roomId);
        if (room != null && room.isHost(user.id) && room.status != 'ended') {
          await StudyRoomService.markHostLeft(widget.roomId, user.id);
        }
      } catch (e) {
        debugPrint('[study] markHostLeft: $e');
      }
    }
    if (mounted) AppNav.back(context);
  }

  Future<void> _send(StudyRoom room) async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      AuthGate.requireAuth(context, message: 'Chat iÃ§in giriÅŸ yap.');
      return;
    }
    if (room.isMuted(user.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessize alÄ±ndÄ±n â€” mesaj gÃ¶nderemezsin.')),
      );
      return;
    }
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await StudyRoomService.sendMessage(
        roomId: widget.roomId,
        sender: user,
        text: text,
      );
      _chatCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: StreamBuilder<StudyRoom?>(
        stream: StudyRoomService.watchRoom(widget.roomId),
        builder: (context, snap) {
          final room = snap.data;
          if (room == null) {
            return const Scaffold(
              backgroundColor: Color(0xFF071526),
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (user != null && room.isKicked(user.id)) {
            return Scaffold(
              backgroundColor: const Color(0xFF071526),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bu odadan Ã§Ä±karÄ±ldÄ±n',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => AppNav.back(context),
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
              ),
            );
          }

          final isHost = user != null && room.isHost(user.id);
          final isPending =
              user != null && room.isPending(user.id) && !room.isMember(user.id);
          final isMember = user != null && room.isMember(user.id);

          Duration display;
          String statusLabel;
          if (room.status == 'active') {
            display = room.remaining ?? Duration.zero;
            statusLabel =
                display == Duration.zero ? 'SÃ¼re doldu' : 'Ã‡alÄ±ÅŸÄ±yorsunuz';
            if (display == Duration.zero) {
              unawaited(_playEnd());
            } else {
              unawaited(_maybeWarn5min(display));
            }
          } else if (room.status == 'ended') {
            display = Duration.zero;
            statusLabel = 'Oturum bitti';
          } else {
            display = Duration(minutes: room.minutes);
            statusLabel = isPending ? 'Onay bekleniyorâ€¦' : 'HazÄ±r';
          }

          if (isPending && !isHost) {
            return Scaffold(
              backgroundColor: const Color(0xFF071526),
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.cyan),
                        const SizedBox(height: 20),
                        const Text(
                          'KatÄ±lma isteÄŸin gÃ¶nderildi',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${room.hostName} onaylayÄ±nca odaya gireceksin.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => AppNav.back(context),
                          child: const Text('Geri dÃ¶n'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          if (!isMember && !isHost && !_joining) {
            return Scaffold(
              backgroundColor: const Color(0xFF071526),
              body: Center(
                child: FilledButton(
                  onPressed: _ensureJoined,
                  child: const Text('KatÄ±lma isteÄŸi gÃ¶nder'),
                ),
              ),
            );
          }

          final chatPanel = RoomSidePanel(
            room: room,
            onClose: () => setState(() => _chatOpenUi = false),
            controller: _chatCtrl,
            sending: _sending,
            recording: _recording,
            onSend: () => _send(room),
            onStartVoice: () => _startVoice(room),
            onStopVoice: () => _stopVoice(room),
            onToggleLiveVoice: () => _toggleLiveVoice(room),
            liveVoiceConnected: _liveVoice.isConnected,
            liveVoiceBusy: _liveVoiceBusy,
            scroll: _scroll,
            isHost: isHost,
            userId: user?.id,
            muted: user != null && room.isMuted(user.id),
            selfVoiceMuted:
                user != null && room.isVoiceSelfMuted(user.id),
            onToggleSelfMute: () async {
              if (user == null) return;
              final nextMuted = !room.isVoiceSelfMuted(user.id);
              await StudyRoomService.setSelfVoiceMute(
                roomId: room.id,
                userId: user.id,
                muted: nextMuted,
              );
              await _liveVoice.setMicEnabled(!nextMuted);
            },
            onReportUser: (uid, name) {
              showReportSheet(
                context: context,
                targetType: ReportTargetType.account,
                targetId: uid,
                snapshotAuthor: name,
              );
            },
          );

          final timerPanel = _TimerPanel(
            room: room,
            display: display,
            statusLabel: statusLabel,
            isHost: isHost,
            joining: _joining,
            onStart: () async {
              if (user == null) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await StudyRoomService.startSession(room.id, user.id);
                _playedEnd = false;
                _warned5min = false;
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            onEnd: () async {
              if (user == null) return;
              await StudyRoomService.endSession(room.id, user.id);
            },
            onExtend: isHost && room.status == 'active'
                ? () => _askExtend(room, user.id)
                : null,
            onLeave: _confirmLeave,
            onAccept: (uid, name) async {
              if (user == null) return;
              await StudyRoomService.acceptJoin(
                roomId: room.id,
                hostId: user.id,
                targetId: uid,
                targetName: name,
              );
            },
            onReject: (uid) async {
              if (user == null) return;
              await StudyRoomService.rejectJoin(
                roomId: room.id,
                hostId: user.id,
                targetId: uid,
              );
            },
            onKick: (uid, name) async {
              if (user == null) return;
              await StudyRoomService.kick(
                roomId: room.id,
                hostId: user.id,
                targetId: uid,
                targetName: name,
              );
            },
            onMute: (uid, muted) async {
              if (user == null) return;
              await StudyRoomService.setMuted(
                roomId: room.id,
                hostId: user.id,
                targetId: uid,
                muted: muted,
              );
            },
            auth: auth,
          );

          return Scaffold(
            backgroundColor: const Color(0xFF071526),
            resizeToAvoidBottomInset: true,
            body: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(child: timerPanel),
                    // AÃ§Ä±lÄ±r oda paneli â€” dar sÃ¼tun yerine overlay.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      top: 8,
                      bottom: 8,
                      right: _chatOpenUi ? 8 : -_panelWidth - 20,
                      width: _panelWidth,
                      child: chatPanel,
                    ),
                    if (!_chatOpenUi)
                      Positioned(
                        right: 12,
                        bottom: 16,
                        child: FloatingActionButton.extended(
                          heroTag: 'study_room_panel',
                          backgroundColor: AppColors.cyan,
                          foregroundColor: AppColors.navy,
                          onPressed: () =>
                              setState(() => _chatOpenUi = true),
                          icon: Icon(
                            room.isSilent
                                ? Icons.hearing_disabled_rounded
                                : room.roomMode == 'voice'
                                    ? Icons.mic_rounded
                                    : Icons.forum_rounded,
                          ),
                          label: Text(
                            room.isSilent
                                ? 'Oda'
                                : room.roomMode == 'voice'
                                    ? 'Ses & oda'
                                    : 'Sohbet',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double get _panelWidth {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 900) return 380;
    return (w * 0.48).clamp(280.0, 360.0);
  }

  Future<void> _startVoice(StudyRoom room) async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null || room.isMuted(user.id) || room.isSilent) return;
    if (room.isVoiceSelfMuted(user.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ã–nce mikronu aÃ§')),
      );
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses kaydÄ± mobil uygulamada')),
      );
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mikrofon izni gerekli')),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/study_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    _recordStarted = DateTime.now();
    setState(() => _recording = true);
  }

  Future<void> _stopVoice(StudyRoom room) async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (!_recording || user == null) return;
    final path = await _recorder.stop();
    final started = _recordStarted;
    setState(() {
      _recording = false;
      _recordStarted = null;
    });
    if (path == null || path.isEmpty || started == null) return;
    final ms = DateTime.now().difference(started).inMilliseconds;
    if (ms < 400) return;
    try {
      final url = await MediaUpload.uploadXFile(
        file: XFile(path),
        folder: 'study_voice/${room.id}',
        firstName: user.firstName,
        lastName: user.lastName,
        studentNo: user.studentNo,
        isVideo: false,
        isFile: true,
      );
      await StudyRoomService.sendVoiceNote(
        roomId: room.id,
        sender: user,
        audioUrl: url,
        durationMs: ms,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleLiveVoice(StudyRoom room) async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;
    if (_liveVoice.isConnected) {
      await _liveVoice.disconnect();
      if (mounted) setState(() {});
      return;
    }
    setState(() => _liveVoiceBusy = true);
    try {
      await _liveVoice.connect(
        studyRoomId: room.id,
        displayName: user.fullName,
        micEnabled: !room.isVoiceSelfMuted(user.id),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canlı ses odasına bağlandın')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('LiveKit yapılandırılmamış')
                ? 'Canlı ses henüz sunucuda yapılandırılmadı (LiveKit).'
                : 'Canlı sese bağlanılamadı: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _liveVoiceBusy = false);
    }
  }
}


class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.room,
    required this.display,
    required this.statusLabel,
    required this.isHost,
    required this.joining,
    required this.onStart,
    required this.onEnd,
    required this.onLeave,
    required this.onAccept,
    required this.onReject,
    required this.onKick,
    required this.onMute,
    required this.auth,
    this.onExtend,
  });

  final StudyRoom room;
  final Duration display;
  final String statusLabel;
  final bool isHost;
  final bool joining;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onLeave;
  final VoidCallback? onExtend;
  final void Function(String uid, String name) onAccept;
  final void Function(String uid) onReject;
  final void Function(String uid, String name) onKick;
  final void Function(String uid, bool muted) onMute;
  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Geri',
                onPressed: onLeave,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'OTURUM ${room.code}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          Text(
            '${room.hostName} ┬╖ ${room.title}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '├çal─▒┼ƒma odas─▒ ┬╖ ${room.participantIds.length} ki┼ƒi'
            '${room.pendingIds.isNotEmpty ? ' ┬╖ ${room.pendingIds.length} bekliyor' : ''}',
            style: TextStyle(color: AppColors.cyan.withValues(alpha: 0.9)),
          ),
          const Spacer(),
          GestureDetector(
            onLongPress: onExtend,
            child: Center(
              child: Column(
                children: [
                  Text(
                    _fmt(display),
                    style: TextStyle(
                      color:
                          statusLabel.contains('doldu') || room.status == 'ended'
                              ? AppColors.gold
                              : Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  if (onExtend != null)
                    Text(
                      'Uzun bas ΓåÆ s├╝re uzat',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              joining ? 'Kat─▒l─▒n─▒yorΓÇª' : statusLabel,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          const Spacer(),
          if (isHost && room.status == 'waiting')
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: AppColors.navy,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: onStart,
              child: Text('Ba┼ƒlat ┬╖ ${room.minutes} dk'),
            ),
          if (isHost && room.status == 'active')
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: onEnd,
              child: const Text('Oturumu bitir'),
            ),
          if (isHost) ...[
            if (room.pendingIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Bekleyenler',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final uid in room.pendingIds)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(
                            auth.findUser(uid)?.fullName ??
                                (uid.length > 6 ? uid.substring(0, 6) : uid),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => onAccept(
                            uid,
                            auth.findUser(uid)?.fullName ?? uid,
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => onReject(uid),
                          avatar: const Icon(Icons.check_circle_outline, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final uid in room.participantIds)
                    if (uid != room.hostId)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PopupMenuButton<String>(
                          tooltip: '├£ye i┼ƒlemleri',
                          onSelected: (v) {
                            final name =
                                auth.findUser(uid)?.fullName ?? uid;
                            if (v == 'kick') onKick(uid, name);
                            if (v == 'mute') {
                              onMute(uid, !room.isMuted(uid));
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'mute',
                              child: Text(
                                room.isMuted(uid)
                                    ? 'Sessizi a├º'
                                    : 'Sessize al',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'kick',
                              child: Text('Odadan at'),
                            ),
                          ],
                          child: Chip(
                            avatar: Icon(
                              room.isMuted(uid)
                                  ? Icons.volume_off
                                  : Icons.person,
                              size: 16,
                            ),
                            label: Text(
                              auth.findUser(uid)?.fullName ??
                                  (uid.length > 6 ? uid.substring(0, 6) : uid),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}

