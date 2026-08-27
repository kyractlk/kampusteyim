import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'music_link_meta.dart';

/// Spotify embed HTML / Apple iTunes preview URL çözümü.
class MusicPreviewResolver {
  static final AudioPlayer sharedPlayer = AudioPlayer();
  static String? currentlyPlayingUrl;

  static String? spotifyTrackId(String url) {
    final m = RegExp(
      r'open\.spotify\.com/(?:intl-[a-z]{2}/)?track/([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(url);
    return m?.group(1);
  }

  /// Spotify: embed sayfasındaki audioPreview MP3 (30 sn).
  static Future<String?> spotifyPreviewUrl(String trackOrOpenUrl) async {
    final id = spotifyTrackId(trackOrOpenUrl);
    if (id == null) return null;
    try {
      final res = await http
          .get(
            Uri.parse('https://open.spotify.com/embed/track/$id'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (compatible; KampusteyimAPP/1.0; +https://kampusteyim.app)',
              'Accept': 'text/html',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final html = res.body;
      final m = RegExp(
        r'"audioPreview"\s*:\s*\{\s*"url"\s*:\s*"([^"]+)"',
      ).firstMatch(html);
      if (m != null) return m.group(1);
      final m2 = RegExp(
        r'https://p\.scdn\.co/mp3-preview/[A-Za-z0-9]+',
      ).firstMatch(html);
      return m2?.group(0);
    } catch (e) {
      debugPrint('[music-preview] spotify: $e');
      return null;
    }
  }

  /// Apple Music / iTunes: 30 sn preview.
  static Future<String?> applePreviewUrl(MusicLinkMeta meta) async {
    try {
      final u = Uri.tryParse(meta.url);
      // .../album/.../id1234567890  veya i=123
      String? songId;
      if (u != null) {
        songId = u.queryParameters['i'];
        if (songId == null || songId.isEmpty) {
          final last = u.pathSegments.isNotEmpty ? u.pathSegments.last : '';
          final idMatch = RegExp(r'id(\d+)').firstMatch(last);
          songId = idMatch?.group(1);
        }
      }
      if (songId != null && songId.isNotEmpty) {
        final lookup = await http
            .get(Uri.parse('https://itunes.apple.com/lookup?id=$songId'))
            .timeout(const Duration(seconds: 8));
        if (lookup.statusCode == 200) {
          final j = jsonDecode(lookup.body) as Map<String, dynamic>;
          final results = j['results'];
          if (results is List && results.isNotEmpty) {
            final preview = '${results.first['previewUrl'] ?? ''}';
            if (preview.isNotEmpty) return preview;
          }
        }
      }
      // Fallback: isimle ara
      final term = Uri.encodeQueryComponent(
        [meta.title, meta.artist].where((e) => (e ?? '').trim().isNotEmpty).join(' '),
      );
      if (term.isEmpty) return null;
      final search = await http
          .get(
            Uri.parse(
              'https://itunes.apple.com/search?term=$term&media=music&entity=song&limit=1',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (search.statusCode != 200) return null;
      final j = jsonDecode(search.body) as Map<String, dynamic>;
      final results = j['results'];
      if (results is List && results.isNotEmpty) {
        final preview = '${results.first['previewUrl'] ?? ''}';
        if (preview.isNotEmpty) return preview;
      }
    } catch (e) {
      debugPrint('[music-preview] apple: $e');
    }
    return null;
  }

  static Future<String?> resolvePreview(MusicLinkMeta meta) async {
    if (meta.provider == 'spotify' || meta.url.contains('spotify.com')) {
      return spotifyPreviewUrl(meta.url);
    }
    if (meta.provider == 'apple' || meta.url.contains('music.apple.com')) {
      return applePreviewUrl(meta);
    }
    return null;
  }

  static Future<void> playOrToggle(String previewUrl) async {
    if (currentlyPlayingUrl == previewUrl &&
        sharedPlayer.state == PlayerState.playing) {
      await sharedPlayer.pause();
      return;
    }
    currentlyPlayingUrl = previewUrl;
    await sharedPlayer.stop();
    await sharedPlayer.play(UrlSource(previewUrl));
  }

  static Future<void> stop() async {
    currentlyPlayingUrl = null;
    await sharedPlayer.stop();
  }
}
