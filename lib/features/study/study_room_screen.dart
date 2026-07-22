import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import 'study_models.dart';

/// Paylaşımlı çalışma odası: senkron sayaç + collapsible realtime chat.
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

  bool _chatOpenUi = true;
  bool _joining = false;
  bool _sending = false;
  bool _playedEnd = false;
  bool _warned5min = false;
  Timer? _uiTick;

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
    setState(() => _joining = true);
    try {
      final room = await StudyRoomService.get(widget.roomId);
      if (room == null) throw StateError('Oda bulunamadı');
      if (room.isKicked(user.id)) throw StateError('Bu odadan çıkarıldın');
      if (!room.isMember(user.id) && !room.isPending(user.id)) {
        await StudyRoomService.join(widget.roomId, user);
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
        title: const Text('5 dakika kaldı'),
        content: const Text(
          'Odak seansı bitmek üzere. İstersen süreye uzun basarak uzatabilirsin.',
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
        title: const Text('Süreyi uzat'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Kaç dakika eklensin?',
            hintText: '5',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
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
        title: const Text('Odadan çık'),
        content: const Text('Odak seansından ayrılmak istiyor musun?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) AppNav.back(context);
  }

  Future<void> _send(StudyRoom room) async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      AuthGate.requireAuth(context, message: 'Chat için giriş yap.');
      return;
    }
    if (room.isMuted(user.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessize alındın — mesaj gönderemezsin.')),
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
    final wide = MediaQuery.sizeOf(context).width >= 900;
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
                      'Bu odadan çıkarıldın',
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
                display == Duration.zero ? 'Süre doldu' : 'Çalışıyorsunuz';
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
            statusLabel = isPending ? 'Onay bekleniyor…' : 'Hazır';
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
                          'Katılma isteğin gönderildi',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${room.hostName} onaylayınca odaya gireceksin.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () => AppNav.back(context),
                          child: const Text('Geri dön'),
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
                  child: const Text('Katılma isteği gönder'),
                ),
              ),
            );
          }

          final chatPanel = _ChatPanel(
            room: room,
            chatOpenUi: _chatOpenUi,
            onToggleUi: () => setState(() => _chatOpenUi = !_chatOpenUi),
            controller: _chatCtrl,
            sending: _sending,
            onSend: () => _send(room),
            scroll: _scroll,
            isHost: isHost,
            userId: user?.id,
            muted: user != null && room.isMuted(user.id),
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
                child: wide
                    ? Row(
                        children: [
                          Expanded(flex: 3, child: timerPanel),
                          if (_chatOpenUi)
                            SizedBox(width: 360, child: chatPanel)
                          else
                            _ChatRail(
                              onOpen: () => setState(() => _chatOpenUi = true),
                            ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: timerPanel),
                          if (_chatOpenUi)
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.38,
                              child: chatPanel,
                            )
                          else
                            _ChatRail(
                              onOpen: () =>
                                  setState(() => _chatOpenUi = true),
                              horizontal: true,
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
}

class _ChatRail extends StatelessWidget {
  const _ChatRail({required this.onOpen, this.horizontal = false});

  final VoidCallback onOpen;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0C1E33),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal ? 16 : 10,
            vertical: horizontal ? 10 : 16,
          ),
          child: horizontal
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, color: AppColors.cyan),
                    SizedBox(width: 8),
                    Text(
                      'Chat’i aç',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : const RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'Chat’i aç',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ),
    );
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
            '${room.hostName} · ${room.title}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Çalışma odası · ${room.participantIds.length} kişi'
            '${room.pendingIds.isNotEmpty ? ' · ${room.pendingIds.length} bekliyor' : ''}',
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
                      'Uzun bas → süre uzat',
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
              joining ? 'Katılınıyor…' : statusLabel,
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
              child: Text('Başlat · ${room.minutes} dk'),
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
                          tooltip: 'Üye işlemleri',
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
                                    ? 'Sessizi aç'
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

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.room,
    required this.chatOpenUi,
    required this.onToggleUi,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.scroll,
    required this.isHost,
    required this.userId,
    required this.muted,
  });

  final StudyRoom room;
  final bool chatOpenUi;
  final VoidCallback onToggleUi;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final ScrollController scroll;
  final bool isHost;
  final String? userId;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0C1E33),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, color: AppColors.cyan, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Oda sohbeti',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isHost)
                  IconButton(
                    tooltip: room.chatOpen ? 'Chat’i kapat' : 'Chat’i aç',
                    onPressed: () async {
                      if (userId == null) return;
                      await StudyRoomService.setChatOpen(
                        roomId: room.id,
                        hostId: userId!,
                        open: !room.chatOpen,
                      );
                    },
                    icon: Icon(
                      room.chatOpen
                          ? Icons.mark_chat_read_outlined
                          : Icons.mark_chat_unread_outlined,
                      color: Colors.white70,
                    ),
                  ),
                IconButton(
                  tooltip: 'Chat’i gizle',
                  onPressed: onToggleUi,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: StreamBuilder<List<StudyChatMessage>>(
              stream: StudyRoomService.watchMessages(room.id),
              builder: (context, snap) {
                final msgs = snap.data ?? const [];
                if (msgs.isEmpty) {
                  return Center(
                    child: Text(
                      room.chatOpen
                          ? 'Sohbete başla · @aystechbot sorabilirsin'
                          : 'Chat kapalı',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scroll.hasClients) {
                    scroll.jumpTo(scroll.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.isAi ? 'AYS Guard' : m.senderName,
                            style: TextStyle(
                              color: m.isAi
                                  ? AppColors.cyan
                                  : Colors.white.withValues(alpha: 0.65),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            m.text,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (room.chatOpen && room.status != 'ended')
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !muted,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: muted ? 'Sessize alındın' : 'Mesaj…',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: muted ? null : (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (sending || muted) ? null : onSend,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: AppColors.navy,
                    ),
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
