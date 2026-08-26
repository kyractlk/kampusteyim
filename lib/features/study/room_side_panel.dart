import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'study_models.dart';
import 'study_rich_widgets.dart';

/// Açılır oda paneli — yatay başlık, ses / sohbet.
class RoomSidePanel extends StatelessWidget {
  const RoomSidePanel({
    super.key,
    required this.room,
    required this.onClose,
    required this.controller,
    required this.sending,
    required this.recording,
    required this.onSend,
    required this.onStartVoice,
    required this.onStopVoice,
    required this.onToggleLiveVoice,
    required this.liveVoiceConnected,
    required this.liveVoiceBusy,
    required this.scroll,
    required this.isHost,
    required this.userId,
    required this.muted,
    required this.selfVoiceMuted,
    required this.onToggleSelfMute,
    required this.onReportUser,
  });

  final StudyRoom room;
  final VoidCallback onClose;
  final TextEditingController controller;
  final bool sending;
  final bool recording;
  final VoidCallback onSend;
  final VoidCallback onStartVoice;
  final VoidCallback onStopVoice;
  final VoidCallback onToggleLiveVoice;
  final bool liveVoiceConnected;
  final bool liveVoiceBusy;
  final ScrollController scroll;
  final bool isHost;
  final String? userId;
  final bool muted;
  final bool selfVoiceMuted;
  final VoidCallback onToggleSelfMute;
  final void Function(String uid, String name) onReportUser;

  @override
  Widget build(BuildContext context) {
    final silent = room.isSilent;
    final voiceMode = room.roomMode == 'voice';

    return Material(
      elevation: 12,
      color: const Color(0xFF0C1E33),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
            child: Row(
              children: [
                Icon(
                  silent
                      ? Icons.hearing_disabled_rounded
                      : voiceMode
                          ? Icons.graphic_eq_rounded
                          : Icons.forum_rounded,
                  color: AppColors.cyan,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    silent
                        ? 'Sessiz oda'
                        : voiceMode
                            ? 'Sesli oda'
                            : 'Oda sohbeti',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (isHost)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                    onSelected: (v) async {
                      if (userId == null) return;
                      await StudyRoomService.setRoomMode(
                        roomId: room.id,
                        hostId: userId!,
                        mode: v,
                      );
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'voice', child: Text('Sesli oda')),
                      PopupMenuItem(value: 'text', child: Text('Yazılı sohbet')),
                      PopupMenuItem(value: 'silent', child: Text('Sessiz oda')),
                    ],
                  ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                _MiniAction(
                  icon: selfVoiceMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: selfVoiceMuted ? 'Mikrofon kapalı' : 'Mikrofon açık',
                  onTap: onToggleSelfMute,
                ),
                const SizedBox(width: 6),
                _MiniAction(
                  icon: liveVoiceConnected
                      ? Icons.hearing_rounded
                      : Icons.groups_rounded,
                  label: liveVoiceBusy
                      ? 'Bağlanıyor…'
                      : liveVoiceConnected
                          ? 'Canlı ses açık'
                          : 'Canlı ses',
                  onTap: silent || muted || liveVoiceBusy
                      ? null
                      : onToggleLiveVoice,
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        silent
                            ? 'Sessiz odak · paylaşım kapalı'
                            : voiceMode
                                ? 'Canlı ses için «Canlı ses»e bas · bas-konuş ile kayıt da bırakabilirsin'
                                : 'Sohbete başla · @aystechbot sorabilirsin',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          height: 1.35,
                        ),
                      ),
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
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    return StudyMessageBubble(
                      roomId: room.id,
                      message: m,
                      mine: m.senderId == userId,
                    );
                  },
                );
              },
            ),
          ),
          if (!silent && room.status != 'ended')
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Column(
                children: [
                  if (voiceMode) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: muted
                            ? null
                            : (recording ? onStopVoice : onStartVoice),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              recording ? AppColors.crimson : AppColors.cyan,
                          foregroundColor:
                              recording ? Colors.white : AppColors.navy,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        icon: Icon(
                          recording ? Icons.stop_rounded : Icons.mic_rounded,
                        ),
                        label: Text(
                          recording ? 'Kaydı bitir' : 'Bas-konuş · ses kaydı',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          enabled: !muted && room.chatOpen,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: muted
                                ? 'Sessize alındın'
                                : !room.chatOpen
                                    ? 'Chat kapalı'
                                    : voiceMode
                                        ? 'Mesaj yaz…'
                                        : 'Mesaj…',
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
                          onSubmitted:
                              (muted || !room.chatOpen) ? null : (_) => onSend(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed:
                            (sending || muted || !room.chatOpen) ? null : onSend,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: AppColors.navy,
                        ),
                        icon: sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, size: 18, color: AppColors.cyan),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
