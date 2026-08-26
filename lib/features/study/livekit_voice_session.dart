import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// Canlı çok kişili ses — LiveKit (Firebase token CF ile).
class LiveKitVoiceSession {
  Room? _room;
  bool _connecting = false;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get connecting => _connecting;
  Room? get room => _room;

  Future<void> connect({
    required String studyRoomId,
    required String displayName,
    bool micEnabled = true,
  }) async {
    if (_connecting || isConnected) return;
    _connecting = true;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getLiveKitToken');
      final res = await callable.call({
        'roomName': 'study_$studyRoomId',
        'displayName': displayName,
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final url = '${data['url'] ?? ''}'.trim();
      final token = '${data['token'] ?? ''}'.trim();
      if (url.isEmpty || token.isEmpty) {
        throw StateError('LiveKit yapılandırması eksik (CF yanıtı boş)');
      }

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      await room.connect(url, token);
      await room.localParticipant?.setMicrophoneEnabled(micEnabled);
      _room = room;
    } finally {
      _connecting = false;
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    } catch (e) {
      debugPrint('[livekit] mic: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _room?.disconnect();
    } catch (e) {
      debugPrint('[livekit] disconnect: $e');
    }
    try {
      await _room?.dispose();
    } catch (_) {}
    _room = null;
  }
}
