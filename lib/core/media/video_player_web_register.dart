import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:video_player_web/video_player_web.dart';

/// Web: plugin registrant bazen video_player_web’i drop edebiliyor.
/// Boot’ta açıkça kaydet — UnimplementedError: init() önlenir.
void ensureVideoPlayerWebRegistered() {
  VideoPlayerPlugin.registerWith(webPluginRegistrar);
}
