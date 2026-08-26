import 'dart:convert';

import 'package:http/http.dart' as http;

/// Spotify / Apple Music URL → zengin kart meta.
class MusicLinkMeta {
  const MusicLinkMeta({
    required this.provider,
    required this.url,
    required this.title,
    this.artist,
    this.thumbnailUrl,
    this.embedHtml,
  });

  final String provider; // spotify | apple
  final String url;
  final String title;
  final String? artist;
  final String? thumbnailUrl;
  final String? embedHtml;

  Map<String, dynamic> toMap() => {
        'provider': provider,
        'url': url,
        'title': title,
        if (artist != null) 'artist': artist,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (embedHtml != null) 'embedHtml': embedHtml,
      };

  factory MusicLinkMeta.fromMap(Map<String, dynamic> m) => MusicLinkMeta(
        provider: '${m['provider'] ?? 'spotify'}',
        url: '${m['url'] ?? ''}',
        title: '${m['title'] ?? 'Şarkı'}',
        artist: m['artist'] as String?,
        thumbnailUrl: m['thumbnailUrl'] as String?,
        embedHtml: m['embedHtml'] as String?,
      );
}

final _spotifyRe = RegExp(
  r'https?://open\.spotify\.com/(track|album|playlist|episode)/[A-Za-z0-9]+',
  caseSensitive: false,
);
final _appleRe = RegExp(
  r'https?://music\.apple\.com/[a-z]{2}/(album|song|playlist)/[^\s]+',
  caseSensitive: false,
);

String? firstMusicUrl(String text) {
  final s = _spotifyRe.firstMatch(text)?.group(0);
  if (s != null) return s;
  return _appleRe.firstMatch(text)?.group(0);
}

bool isMusicUrl(String url) =>
    _spotifyRe.hasMatch(url) || _appleRe.hasMatch(url);

Future<MusicLinkMeta?> resolveMusicLink(String rawUrl) async {
  final url = rawUrl.trim();
  if (url.isEmpty) return null;

  if (_spotifyRe.hasMatch(url)) {
    try {
      final uri = Uri.parse(
        'https://open.spotify.com/oembed?url=${Uri.encodeComponent(url)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final title = '${j['title'] ?? 'Spotify'}';
        String? artist;
        // "Song · Artist" formatı sık
        if (title.contains(' · ')) {
          final parts = title.split(' · ');
          if (parts.length >= 2) {
            return MusicLinkMeta(
              provider: 'spotify',
              url: url,
              title: parts.first.trim(),
              artist: parts.sublist(1).join(' · ').trim(),
              thumbnailUrl: j['thumbnail_url'] as String?,
              embedHtml: j['html'] as String?,
            );
          }
        }
        return MusicLinkMeta(
          provider: 'spotify',
          url: url,
          title: title,
          artist: artist,
          thumbnailUrl: j['thumbnail_url'] as String?,
          embedHtml: j['html'] as String?,
        );
      }
    } catch (_) {}
    return MusicLinkMeta(
      provider: 'spotify',
      url: url,
      title: 'Spotify',
      artist: 'Bağlantıyı aç',
    );
  }

  if (_appleRe.hasMatch(url)) {
    // Apple Music oEmbed resmi değil — URL’den isim çıkar.
    final path = Uri.tryParse(url)?.pathSegments ?? const [];
    String title = 'Apple Music';
    if (path.length >= 3) {
      title = Uri.decodeComponent(path[2]).replaceAll('-', ' ');
    }
    return MusicLinkMeta(
      provider: 'apple',
      url: url,
      title: title,
      artist: 'Apple Music',
      // Embed: music.apple.com embed player
      embedHtml:
          '<iframe allow="autoplay *; encrypted-media *;" frameborder="0" height="150" style="width:100%;max-width:660px;overflow:hidden;background:transparent;" sandbox="allow-forms allow-popups allow-same-origin allow-scripts allow-storage-access-by-user-activation allow-top-navigation-by-user-activation" src="${url.contains('?') ? '$url&' : '$url?'}app=music"></iframe>',
    );
  }
  return null;
}
