import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'study_models.dart';

/// Odak odası paneli — yalnızca canlı ses veya sessiz (yazılı sohbet / kayıt yok).
class RoomSidePanel extends StatelessWidget {
  const RoomSidePanel({
    super.key,
    required this.room,
    required this.onClose,
    required this.onToggleLiveVoice,
    required this.liveVoiceConnected,
    required this.liveVoiceBusy,
    required this.isHost,
    required this.userId,
    required this.selfVoiceMuted,
    required this.onToggleSelfMute,
    required this.onReportUser,
  });

  final StudyRoom room;
  final VoidCallback onClose;
  final VoidCallback onToggleLiveVoice;
  final bool liveVoiceConnected;
  final bool liveVoiceBusy;
  final bool isHost;
  final String? userId;
  final bool selfVoiceMuted;
  final VoidCallback onToggleSelfMute;
  final void Function(String uid, String name) onReportUser;

  @override
  Widget build(BuildContext context) {
    final silent = room.isSilent;
    final members = <String>{room.hostId, ...room.participantIds}.toList();

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
                      : Icons.graphic_eq_rounded,
                  color: AppColors.cyan,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    silent ? 'Sessiz oda' : 'Sesli oda',
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              silent
                  ? 'Sessiz odak · mikrofon ve sohbet kapalı'
                  : 'Canlı çok kişili ses · yazılı sohbet yok',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              children: [
                Text(
                  'Katılımcılar · ${members.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                for (final uid in members)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      uid == room.hostId
                          ? Icons.star_rounded
                          : Icons.person_rounded,
                      color: AppColors.cyan,
                      size: 20,
                    ),
                    title: Text(
                      uid == userId
                          ? 'Sen'
                          : (uid.length > 10 ? '${uid.substring(0, 8)}…' : uid),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    subtitle: uid == room.hostId
                        ? Text(
                            'Oturum sahibi',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          )
                        : null,
                    trailing: uid != userId && uid != room.hostId
                        ? IconButton(
                            tooltip: 'Şikayet et',
                            onPressed: () => onReportUser(uid, uid),
                            icon: Icon(
                              Icons.flag_outlined,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
          if (!silent && room.status != 'ended')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: liveVoiceBusy ? null : onToggleLiveVoice,
                      style: FilledButton.styleFrom(
                        backgroundColor: liveVoiceConnected
                            ? AppColors.crimson
                            : AppColors.cyan,
                        foregroundColor:
                            liveVoiceConnected ? Colors.white : AppColors.navy,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      icon: Icon(
                        liveVoiceConnected
                            ? Icons.call_end_rounded
                            : Icons.hearing_rounded,
                      ),
                      label: Text(
                        liveVoiceBusy
                            ? 'Bağlanıyor…'
                            : liveVoiceConnected
                                ? 'Canlı sesten ayrıl'
                                : 'Canlı sese katıl',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (liveVoiceConnected) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onToggleSelfMute,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: Icon(
                          selfVoiceMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                        ),
                        label: Text(
                          selfVoiceMuted ? 'Mikrofon kapalı' : 'Mikrofon açık',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
