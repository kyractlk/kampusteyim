import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/web_safe_image.dart';
import '../auth/data/auth_provider.dart';
import 'music_link_meta.dart';
import 'study_models.dart';

class StudyMessageBubble extends StatelessWidget {
  const StudyMessageBubble({
    super.key,
    required this.roomId,
    required this.message,
    required this.mine,
  });

  final String roomId;
  final StudyChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case 'system':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case 'music':
        return _MusicCard(meta: MusicLinkMeta.fromMap(message.meta));
      case 'location':
        return _LocationCard(message: message);
      case 'poll':
        return StudyPollCard(roomId: roomId, message: message);
      case 'voice':
        return _VoiceCard(message: message, mine: mine);
      default:
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: message.isAi
                  ? AppColors.cyan.withValues(alpha: 0.18)
                  : mine
                      ? AppColors.navy.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine)
                  Text(
                    message.isAi ? 'AYS Bot' : message.senderName,
                    style: TextStyle(
                      color: AppColors.cyan.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _MusicCard extends StatelessWidget {
  const _MusicCard({required this.meta});
  final MusicLinkMeta meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: meta.thumbnailUrl != null
                  ? webSafeNetworkImage(
                      meta.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _artFallback(),
                    )
                  : _artFallback(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if ((meta.artist ?? '').isNotEmpty)
                  Text(
                    meta.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11.5,
                    ),
                  ),
                Text(
                  meta.provider == 'apple' ? 'Apple Music' : 'Spotify',
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dinle',
            onPressed: () async {
              final uri = Uri.tryParse(meta.url);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.play_circle_fill_rounded,
                color: AppColors.cyan, size: 34),
          ),
        ],
      ),
    );
  }

  Widget _artFallback() => Container(
        color: const Color(0xFF1DB954).withValues(alpha: 0.35),
        child: const Icon(Icons.music_note_rounded, color: Colors.white),
      );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.message});
  final StudyChatMessage message;

  @override
  Widget build(BuildContext context) {
    final label = '${message.meta['label'] ?? message.text}';
    final maps = '${message.meta['mapsUrl'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: maps.isEmpty
              ? null
              : () => launchUrl(
                    Uri.parse(maps),
                    mode: LaunchMode.externalApplication,
                  ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.place_rounded, color: AppColors.lime),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.senderName,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new_rounded,
                    size: 16, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceCard extends StatefulWidget {
  const _VoiceCard({required this.message, required this.mine});
  final StudyChatMessage message;
  final bool mine;

  @override
  State<_VoiceCard> createState() => _VoiceCardState();
}

class _VoiceCardState extends State<_VoiceCard> {
  final _player = AudioPlayer();
  var _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = '${widget.message.meta['audioUrl'] ?? ''}';
    if (url.isEmpty) return;
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    await _player.play(UrlSource(url));
    setState(() => _playing = true);
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sec =
        ((widget.message.meta['durationMs'] as num?)?.toInt() ?? 0) / 1000;
    return Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _toggle,
              icon: Icon(
                _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: AppColors.cyan,
              ),
            ),
            Text(
              '${sec.round()} sn · ${widget.message.senderName}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class StudyPollCard extends StatelessWidget {
  const StudyPollCard({
    super.key,
    required this.roomId,
    required this.message,
  });

  final String roomId;
  final StudyChatMessage message;

  @override
  Widget build(BuildContext context) {
    final pollId = '${message.meta['pollId'] ?? ''}';
    if (pollId.isEmpty) {
      return Text(message.text, style: const TextStyle(color: Colors.white70));
    }
    final me = context.watch<AuthProvider>().user?.id;
    return StreamBuilder<Map<String, dynamic>?>(
      stream: StudyRoomService.watchPoll(roomId, pollId),
      builder: (context, snap) {
        final data = snap.data ?? message.meta;
        final question = '${data['question'] ?? message.text}';
        final options = (data['options'] as List? ?? const [])
            .map((e) => '$e')
            .toList();
        final multi = data['multi'] == true;
        final votes = Map<String, dynamic>.from(data['votes'] as Map? ?? {});
        int countFor(int i) =>
            List<String>.from((votes['$i'] as List?) ?? const []).length;
        final total = options.asMap().entries.fold<int>(
              0,
              (a, e) => a + countFor(e.key),
            );

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.poll_rounded, color: AppColors.gold, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      question,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                multi ? 'Çoklu seçim' : 'Tek seçim',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: me == null
                        ? null
                        : () async {
                            try {
                              await StudyRoomService.votePoll(
                                roomId: roomId,
                                pollId: pollId,
                                userId: me,
                                optionIndexes: [i],
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')),
                                );
                              }
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              options[i],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Text(
                            total == 0
                                ? '0'
                                : '${((countFor(i) / total) * 100).round()}%',
                            style: const TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w800,
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
        );
      },
    );
  }
}

/// Spotify/Apple gömülü oynatıcı (opsiyonel tam ekran).
Future<void> openMusicEmbedSheet(
  BuildContext context,
  MusicLinkMeta meta,
) async {
  if ((meta.embedHtml ?? '').isEmpty) {
    final uri = Uri.tryParse(meta.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  // Basit: harici uygulama — embed WebView bazı platformlarda kısıtlı.
  final uri = Uri.tryParse(meta.url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
