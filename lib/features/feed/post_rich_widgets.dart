import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/web_safe_image.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../study/music_link_meta.dart';
import '../study/music_preview.dart';

/// Spotify / Apple kapak + play — önizleme MP3 doğrudan kartta çalar.
class PostMusicCard extends StatefulWidget {
  const PostMusicCard({super.key, required this.meta});

  final MusicLinkMeta meta;

  @override
  State<PostMusicCard> createState() => _PostMusicCardState();
}

class _PostMusicCardState extends State<PostMusicCard> {
  bool _loading = false;
  bool _playing = false;
  String? _previewUrl;
  StreamSubscription<PlayerState>? _sub;

  MusicLinkMeta get meta => widget.meta;

  @override
  void initState() {
    super.initState();
    _sub = MusicPreviewResolver.sharedPlayer.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      final mine = MusicPreviewResolver.currentlyPlayingUrl == _previewUrl &&
          _previewUrl != null;
      setState(() => _playing = mine && s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    setState(() => _loading = true);
    try {
      _previewUrl ??= await MusicPreviewResolver.resolvePreview(meta);
      if (_previewUrl == null || _previewUrl!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu parça için önizleme bulunamadı. Uygulamada açılıyor…'),
            ),
          );
          final uri = Uri.tryParse(meta.url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        return;
      }
      await MusicPreviewResolver.playOrToggle(_previewUrl!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çalınamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = meta.provider == 'apple'
        ? const Color(0xFFFA233B)
        : const Color(0xFF1DB954);
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: meta.thumbnailUrl != null
                    ? webSafeNetworkImage(
                        meta.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _artFallback(),
                      )
                    : _artFallback(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if ((meta.artist ?? '').isNotEmpty)
                    Text(
                      meta.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  Text(
                    _playing
                        ? 'Çalıyor · 30 sn önizleme'
                        : (meta.provider == 'apple'
                            ? 'Apple Music · Önizleme'
                            : 'Spotify · Önizleme'),
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _playing ? 'Duraklat' : 'Çal',
              onPressed: _loading ? null : _togglePlay,
              iconSize: 40,
              icon: _loading
                  ? SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: accent,
                      ),
                    )
                  : Icon(
                      _playing
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_filled_rounded,
                      color: accent,
                      size: 40,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artFallback() => ColoredBox(
        color: AppColors.navy.withValues(alpha: 0.12),
        child: const Icon(Icons.music_note_rounded, color: AppColors.navy),
      );
}

class PostLocationCard extends StatelessWidget {
  const PostLocationCard({super.key, required this.location});

  final Map<String, dynamic> location;

  @override
  Widget build(BuildContext context) {
    final label = '${location['label'] ?? 'Konum'}';
    final maps = '${location['mapsUrl'] ?? ''}'.trim();
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: maps.isEmpty
            ? null
            : () async {
                final uri = Uri.tryParse(maps);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.place_rounded, color: AppColors.crimson),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (maps.isNotEmpty)
                Text(
                  'Harita',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostPollCard extends StatelessWidget {
  const PostPollCard({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final poll = post.poll;
    if (poll == null) return const SizedBox.shrink();
    final question = '${poll['question'] ?? ''}';
    final options = (poll['options'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    final multi = poll['multi'] == true;
    final endsAt = DateTime.tryParse('${poll['endsAt'] ?? ''}');
    final expired = endsAt != null && DateTime.now().isAfter(endsAt);
    final votesRaw = poll['votes'];
    final votes = <String, List<int>>{};
    if (votesRaw is Map) {
      for (final e in votesRaw.entries) {
        final idxs = (e.value is List)
            ? (e.value as List)
                .map((x) => int.tryParse('$x') ?? -1)
                .where((x) => x >= 0)
                .toList()
            : <int>[];
        votes['${e.key}'] = idxs;
      }
    }
    final me = context.watch<AuthProvider>().user;
    final myVote = me == null ? const <int>[] : (votes[me.id] ?? const []);
    final totals = List<int>.filled(options.length, 0);
    var totalBallots = 0;
    for (final idxs in votes.values) {
      if (idxs.isEmpty) continue;
      totalBallots++;
      for (final i in idxs) {
        if (i >= 0 && i < totals.length) totals[i]++;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_rounded, size: 18, color: AppColors.navy),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              multi ? 'Çok seçimli' : 'Tek seçimli',
              endsAt == null
                  ? 'Süresiz'
                  : (expired
                      ? 'Süre doldu'
                      : 'Bitiş · ${endsAt.day}.${endsAt.month} ${endsAt.hour.toString().padLeft(2, '0')}:${endsAt.minute.toString().padLeft(2, '0')}'),
              '$totalBallots oy',
            ].join(' · '),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _PollOptionTile(
              label: options[i],
              selected: myVote.contains(i),
              count: totals[i],
              total: totalBallots,
              enabled: !expired && me != null,
              onTap: () => _vote(context, i, multi: multi, myVote: myVote),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _vote(
    BuildContext context,
    int index, {
    required bool multi,
    required List<int> myVote,
  }) async {
    final me = context.read<AuthProvider>().user;
    if (me == null) return;
    final next = List<int>.from(myVote);
    if (multi) {
      if (next.contains(index)) {
        next.remove(index);
      } else {
        next.add(index);
      }
    } else {
      next
        ..clear()
        ..add(index);
    }
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final ref = FirebaseFirestore.instance.collection('posts').doc(post.id);
        final snap = await tx.get(ref);
        final data = snap.data() ?? {};
        final pollMap = Map<String, dynamic>.from(data['poll'] as Map? ?? {});
        final votes = Map<String, dynamic>.from(pollMap['votes'] as Map? ?? {});
        votes[me.id] = next;
        pollMap['votes'] = votes;
        tx.set(ref, {'poll': pollMap}, SetOptions(merge: true));
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Oy kaydedilemedi: $e')),
        );
      }
    }
  }
}

class _PollOptionTile extends StatelessWidget {
  const _PollOptionTile({
    required this.label,
    required this.selected,
    required this.count,
    required this.total,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final int count;
  final int total;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : count / total;
    return Material(
      color: selected
          ? AppColors.cyan.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 18,
                    color: selected ? AppColors.cyan : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label)),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
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
