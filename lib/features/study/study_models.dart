import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';

class StudyRoom {
  const StudyRoom({
    required this.id,
    required this.code,
    required this.title,
    required this.hostId,
    required this.hostName,
    required this.minutes,
    required this.createdAt,
    this.startedAt,
    this.endsAt,
    this.status = 'waiting',
    this.participantIds = const [],
    this.pendingIds = const [],
    this.kickedIds = const [],
    this.mutedIds = const [],
    this.voiceMutedIds = const [],
    this.postId,
    this.isCommunity = false,
    this.chatOpen = true,
    this.roomMode = 'voice',
    this.hostLeftAt,
    this.endedAt,
    this.endReason,
  });

  final String id;
  final String code;
  final String title;
  final String hostId;
  final String hostName;
  final int minutes;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endsAt;
  final String status; // waiting | active | ended
  final List<String> participantIds;
  final List<String> pendingIds;
  final List<String> kickedIds;
  /// Chat / ses notu gönderme engeli (host mute).
  final List<String> mutedIds;
  /// Kendi mikini kapalı tutanlar (self mute).
  final List<String> voiceMutedIds;
  final String? postId;
  final bool isCommunity;
  final bool chatOpen;
  /// voice | text | silent — silent: sohbet+ses kapalı.
  final String roomMode;
  /// Host odadan çıktığında set edilir; 1 saat sonra CF kapatır.
  final DateTime? hostLeftAt;
  final DateTime? endedAt;
  /// manual | host_left_timeout | …
  final String? endReason;

  bool get isHostActive => status != 'ended';
  bool get isSilent => roomMode == 'silent';
  bool get isVoicePrimary => roomMode == 'voice' || roomMode == 'silent';
  bool isHost(String uid) => hostId == uid;
  bool isKicked(String uid) => kickedIds.contains(uid);
  bool isMuted(String uid) => mutedIds.contains(uid);
  bool isVoiceSelfMuted(String uid) => voiceMutedIds.contains(uid);
  bool isPending(String uid) => pendingIds.contains(uid);
  bool isMember(String uid) =>
      hostId == uid || participantIds.contains(uid);

  Duration? get remaining {
    final end = endsAt;
    if (end == null) return null;
    final d = end.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  factory StudyRoom.fromMap(String id, Map<String, dynamic> m) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse('$v');
    }

    List<String> ids(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }

    return StudyRoom(
      id: id,
      code: '${m['code'] ?? id}'.toUpperCase(),
      title: '${m['title'] ?? 'Çalışma odası'}',
      hostId: '${m['hostId'] ?? ''}',
      hostName: '${m['hostName'] ?? ''}',
      minutes: (m['minutes'] as num?)?.toInt() ?? 25,
      createdAt: parse(m['createdAt']) ?? DateTime.now(),
      startedAt: parse(m['startedAt']),
      endsAt: parse(m['endsAt']),
      status: '${m['status'] ?? 'waiting'}',
      participantIds: ids(m['participantIds']),
      pendingIds: ids(m['pendingIds']),
      kickedIds: ids(m['kickedIds']),
      mutedIds: ids(m['mutedIds']),
      voiceMutedIds: ids(m['voiceMutedIds']),
      postId: m['postId'] as String?,
      isCommunity: m['isCommunity'] == true,
      chatOpen: m['chatOpen'] != false,
      roomMode: '${m['roomMode'] ?? 'voice'}',
      hostLeftAt: parse(m['hostLeftAt']),
      endedAt: parse(m['endedAt']),
      endReason: m['endReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'code': code,
        'title': title,
        'hostId': hostId,
        'hostName': hostName,
        'minutes': minutes,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'status': status,
        'participantIds': participantIds,
        'pendingIds': pendingIds,
        'kickedIds': kickedIds,
        'mutedIds': mutedIds,
        'voiceMutedIds': voiceMutedIds,
        'postId': postId,
        'isCommunity': isCommunity,
        'chatOpen': chatOpen,
        'roomMode': roomMode,
        if (hostLeftAt != null) 'hostLeftAt': hostLeftAt!.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        if (endReason != null) 'endReason': endReason,
      };
}

class StudyChatMessage {
  const StudyChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    this.isAi = false,
    this.type = 'text',
    this.meta = const {},
  });

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime createdAt;
  final bool isAi;
  /// text | voice | music | location | poll | system
  final String type;
  final Map<String, dynamic> meta;

  factory StudyChatMessage.fromMap(String id, Map<String, dynamic> m) {
    final metaRaw = m['meta'];
    return StudyChatMessage(
      id: id,
      senderId: '${m['senderId'] ?? ''}',
      senderName: '${m['senderName'] ?? ''}',
      text: '${m['text'] ?? ''}',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
      isAi: m['isAi'] == true,
      type: '${m['type'] ?? 'text'}',
      meta: metaRaw is Map
          ? Map<String, dynamic>.from(metaRaw)
          : const {},
    );
  }
}

class StudyRoomService {
  StudyRoomService._();
  static final _db = FirebaseFirestore.instance;

  static String _newCode() =>
      const Uuid().v4().replaceAll('-', '').substring(0, 6).toUpperCase();

  static Future<StudyRoom> createRoom({
    required AppUser host,
    required int minutes,
    required String title,
    bool announce = true,
    String roomMode = 'voice',
  }) async {
    final id = 'sr_${DateTime.now().millisecondsSinceEpoch}';
    final code = _newCode();
    final now = DateTime.now();
    String? postId;
    final mode = ['voice', 'text', 'silent'].contains(roomMode)
        ? roomMode
        : 'voice';

    if (announce) {
      postId = 'p_study_$id';
      final roomTitle =
          title.trim().isEmpty ? 'Odak seansı' : title.trim();
      final content =
          'Hadi bana katıl — birlikte odaklanalım!\n'
          '$roomTitle · $minutes dk\n'
          'Kod: $code\n'
          '#çalışma #odak #mt';
      await _db.collection('posts').doc(postId).set({
        'authorId': host.id,
        'authorName': host.fullName,
        'authorHandle': host.handle,
        'content': content,
        'createdAt': now.toIso8601String(),
        'likeCount': 0,
        'replyCount': 0,
        'repostCount': 0,
        'isCommunity': host.isCommunity,
        'hashtags': ['çalışma', 'odak', 'mt'],
        'media': [],
        'studyRoomId': id,
        'studyRoomCode': code,
        'studyMinutes': minutes,
        'studyTitle': roomTitle,
      });
    }

    final room = StudyRoom(
      id: id,
      code: code,
      title: title.trim().isEmpty ? 'Odak seansı' : title.trim(),
      hostId: host.id,
      hostName: host.fullName,
      minutes: minutes,
      createdAt: now,
      participantIds: [host.id],
      postId: postId,
      isCommunity: host.isCommunity,
      roomMode: mode,
      chatOpen: mode != 'silent',
    );
    await _db.collection('study_rooms').doc(id).set(room.toMap());
    await _db.collection('study_rooms').doc(id).collection('events').add({
      'type': 'created',
      'actorId': host.id,
      'at': now.toIso8601String(),
      'roomMode': mode,
    });
    return room;
  }

  static Future<StudyRoom?> findByCode(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;
    final snap = await _db
        .collection('study_rooms')
        .where('code', isEqualTo: c)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return StudyRoom.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  static Future<StudyRoom?> get(String id) async {
    final snap = await _db.collection('study_rooms').doc(id).get();
    if (!snap.exists) return null;
    return StudyRoom.fromMap(snap.id, snap.data()!);
  }

  static Stream<StudyRoom?> watchRoom(String id) {
    return _db.collection('study_rooms').doc(id).snapshots().map((s) {
      if (!s.exists) return null;
      return StudyRoom.fromMap(s.id, s.data()!);
    });
  }

  static Stream<List<StudyChatMessage>> watchMessages(String roomId) {
    return _db
        .collection('study_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(120)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => StudyChatMessage.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  static Future<void> join(String roomId, AppUser user) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Oda bulunamadı');
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.status == 'ended') throw StateError('Oda kapandı');
      if (room.isKicked(user.id)) throw StateError('Bu odadan çıkarıldın');
      if (room.isMember(user.id)) return;
      // Host doğrudan üye; diğerleri pending’e düşer.
      if (room.isHost(user.id)) {
        final parts = {...room.participantIds, user.id}.toList();
        tx.set(
          ref,
          {
            'participantIds': parts,
            'hostLeftAt': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
        return;
      }
      final pending = {...room.pendingIds, user.id}.toList();
      tx.set(ref, {'pendingIds': pending}, SetOptions(merge: true));
    });
    await ref.collection('events').add({
      'type': 'join_request',
      'actorId': user.id,
      'actorName': user.fullName,
      'at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> acceptJoin({
    required String roomId,
    required String hostId,
    required String targetId,
    required String targetName,
  }) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.hostId != hostId) throw StateError('Yetki yok');
      final pending = room.pendingIds.where((e) => e != targetId).toList();
      final parts = {...room.participantIds, targetId}.toList();
      tx.set(
        ref,
        {'pendingIds': pending, 'participantIds': parts},
        SetOptions(merge: true),
      );
    });
    await ref.collection('events').add({
      'type': 'accept',
      'actorId': hostId,
      'targetId': targetId,
      'targetName': targetName,
      'at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> rejectJoin({
    required String roomId,
    required String hostId,
    required String targetId,
  }) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.hostId != hostId) throw StateError('Yetki yok');
      final pending = room.pendingIds.where((e) => e != targetId).toList();
      tx.set(ref, {'pendingIds': pending}, SetOptions(merge: true));
    });
  }

  static Future<void> setMuted({
    required String roomId,
    required String hostId,
    required String targetId,
    required bool muted,
  }) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.hostId != hostId) throw StateError('Yetki yok');
      if (targetId == hostId) return;
      final mutedIds = muted
          ? {...room.mutedIds, targetId}.toList()
          : room.mutedIds.where((e) => e != targetId).toList();
      tx.set(ref, {'mutedIds': mutedIds}, SetOptions(merge: true));
    });
  }

  static Future<void> kick({
    required String roomId,
    required String hostId,
    required String targetId,
    required String targetName,
  }) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.hostId != hostId) throw StateError('Yetki yok');
      if (targetId == hostId) return;
      final parts = room.participantIds.where((e) => e != targetId).toList();
      final pending = room.pendingIds.where((e) => e != targetId).toList();
      final muted = room.mutedIds.where((e) => e != targetId).toList();
      final kicked = {...room.kickedIds, targetId}.toList();
      tx.set(
        ref,
        {
          'participantIds': parts,
          'pendingIds': pending,
          'mutedIds': muted,
          'kickedIds': kicked,
        },
        SetOptions(merge: true),
      );
    });
    await ref.collection('events').add({
      'type': 'kick',
      'actorId': hostId,
      'targetId': targetId,
      'targetName': targetName,
      'at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> startSession(String roomId, String hostId) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.hostId != hostId) throw StateError('Yetki yok');
      if (room.status == 'active') return;
      final now = DateTime.now();
      final ends = now.add(Duration(minutes: room.minutes));
      tx.set(
        ref,
        {
          'status': 'active',
          'startedAt': now.toIso8601String(),
          'endsAt': ends.toIso8601String(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Aktif oturuma dakika ekler (host).
  static Future<void> extendSession({
    required String roomId,
    required String hostId,
    required int extraMinutes,
  }) async {
    if (extraMinutes <= 0) return;
    final ref = _db.collection('study_rooms').doc(roomId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final room = StudyRoom.fromMap(snap.id, snap.data()!);
      if (room.hostId != hostId) throw StateError('Yetki yok');
      if (room.status != 'active') throw StateError('Oturum aktif değil');
      final base = room.endsAt ?? DateTime.now();
      final ends = base.add(Duration(minutes: extraMinutes));
      tx.set(
        ref,
        {
          'endsAt': ends.toIso8601String(),
          'minutes': room.minutes + extraMinutes,
        },
        SetOptions(merge: true),
      );
    });
    await ref.collection('events').add({
      'type': 'extend',
      'actorId': hostId,
      'extraMinutes': extraMinutes,
      'at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> endSession(
    String roomId,
    String hostId, {
    String reason = 'manual',
  }) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await ref.set({
      'status': 'ended',
      'endedAt': DateTime.now().toIso8601String(),
      'chatOpen': false,
      'endReason': reason,
      'hostLeftAt': FieldValue.delete(),
    }, SetOptions(merge: true));
    await ref.collection('events').add({
      'type': 'ended',
      'actorId': hostId,
      'reason': reason,
      'at': DateTime.now().toIso8601String(),
    });
  }

  /// Host odadan ayrılınca 1 saatlik kapanma zamanlayıcısını başlatır.
  static Future<void> markHostLeft(String roomId, String hostId) async {
    final snap = await _db.collection('study_rooms').doc(roomId).get();
    if (!snap.exists) return;
    final room = StudyRoom.fromMap(snap.id, snap.data()!);
    if (room.hostId != hostId || room.status == 'ended') return;
    if (room.hostLeftAt != null) return;
    final now = DateTime.now().toIso8601String();
    await snap.reference.set({'hostLeftAt': now}, SetOptions(merge: true));
    await snap.reference.collection('events').add({
      'type': 'host_left',
      'actorId': hostId,
      'at': now,
    });
  }

  /// Host odaya geri dönünce zamanlayıcıyı iptal eder.
  static Future<void> clearHostLeft(String roomId, String hostId) async {
    final snap = await _db.collection('study_rooms').doc(roomId).get();
    if (!snap.exists) return;
    final room = StudyRoom.fromMap(snap.id, snap.data()!);
    if (room.hostId != hostId || room.hostLeftAt == null) return;
    await snap.reference.set(
      {'hostLeftAt': FieldValue.delete()},
      SetOptions(merge: true),
    );
    await snap.reference.collection('events').add({
      'type': 'host_returned',
      'actorId': hostId,
      'at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> setChatOpen({
    required String roomId,
    required String hostId,
    required bool open,
  }) async {
    final snap = await _db.collection('study_rooms').doc(roomId).get();
    if (!snap.exists) return;
    final room = StudyRoom.fromMap(snap.id, snap.data()!);
    if (room.hostId != hostId) throw StateError('Yetki yok');
    await snap.reference.set({'chatOpen': open}, SetOptions(merge: true));
  }

  static Future<void> setRoomMode({
    required String roomId,
    required String hostId,
    required String mode,
  }) async {
    final m = ['voice', 'silent'].contains(mode) ? mode : 'voice';
    final snap = await _db.collection('study_rooms').doc(roomId).get();
    if (!snap.exists) return;
    final room = StudyRoom.fromMap(snap.id, snap.data()!);
    if (room.hostId != hostId) throw StateError('Yetki yok');
    await snap.reference.set({
      'roomMode': m,
      if (m == 'silent') 'chatOpen': false,
    }, SetOptions(merge: true));
    await snap.reference.collection('messages').add({
      'senderId': 'system',
      'senderName': 'Sistem',
      'text': m == 'silent'
          ? 'Oda sessiz moda alındı'
          : 'Sesli oda aktif · canlı çok kişili ses',
      'type': 'system',
      'createdAt': DateTime.now().toIso8601String(),
      'isAi': false,
      'meta': {},
    });
  }

  static Future<void> setSelfVoiceMute({
    required String roomId,
    required String userId,
    required bool muted,
  }) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await ref.set({
      'voiceMutedIds': muted
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    }, SetOptions(merge: true));
  }

  static Future<void> sendRichMessage({
    required String roomId,
    required AppUser sender,
    required String type,
    required String text,
    Map<String, dynamic> meta = const {},
    bool notifyMembers = true,
    String? notifyTitle,
  }) async {
    final room = await get(roomId);
    if (room == null) throw StateError('Oda yok');
    if (room.isSilent && type != 'system') {
      throw StateError('Sessiz oda — paylaşım kapalı');
    }
    if (!room.chatOpen && type == 'text') {
      throw StateError('Chat kapalı');
    }
    if (room.isKicked(sender.id)) throw StateError('Çıkarıldın');
    if (!room.isMember(sender.id)) throw StateError('Üye değilsin');
    if (room.isMuted(sender.id)) throw StateError('Sessize alındın');

    await _db.collection('study_rooms').doc(roomId).collection('messages').add({
      'senderId': sender.id,
      'senderName': sender.fullName,
      'text': text,
      'type': type,
      'meta': meta,
      'createdAt': DateTime.now().toIso8601String(),
      'isAi': false,
    });

    if (notifyMembers && notifyTitle != null) {
      final targets = <String>{
        room.hostId,
        ...room.participantIds,
      }..remove(sender.id);
      for (final uid in targets) {
        try {
          final callable =
              FirebaseFunctions.instanceFor(region: 'europe-west1')
                  .httpsCallable('dispatchPush');
          await callable.call({
            'toUserId': uid,
            'title': notifyTitle,
            'body': text,
            'emoji': type == 'music'
                ? '🎵'
                : type == 'poll'
                    ? '📊'
                    : type == 'location'
                        ? '📍'
                        : type == 'voice'
                            ? '🎙️'
                            : '💬',
            'type': 'study_$type',
            'actorId': sender.id,
            'targetId': roomId,
          });
        } catch (e) {
          debugPrint('[study] notify: $e');
        }
      }
    }
  }

  static Future<void> sendMessage({
    required String roomId,
    required AppUser sender,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await sendRichMessage(
      roomId: roomId,
      sender: sender,
      type: 'text',
      text: t,
      notifyMembers: false,
    );

    final askAi = t.toLowerCase().contains('@aystechbot') ||
        t.toLowerCase().contains('guard') ||
        t.endsWith('?');
    if (askAi) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('studyChatAi');
        await callable.call({
          'roomId': roomId,
          'message': t,
          'senderName': sender.fullName,
        });
      } catch (e) {
        debugPrint('[study] ai: $e');
      }
    }
  }

  static Future<void> sendVoiceNote({
    required String roomId,
    required AppUser sender,
    required String audioUrl,
    required int durationMs,
  }) async {
    await sendRichMessage(
      roomId: roomId,
      sender: sender,
      type: 'voice',
      text: 'Ses kaydı · ${(durationMs / 1000).round()} sn',
      meta: {
        'audioUrl': audioUrl,
        'durationMs': durationMs,
      },
      notifyTitle: 'Odada ses kaydı',
    );
  }

  static Future<void> shareLocation({
    required String roomId,
    required AppUser sender,
    required String label,
    double? lat,
    double? lng,
  }) async {
    await sendRichMessage(
      roomId: roomId,
      sender: sender,
      type: 'location',
      text: label,
      meta: {
        'label': label,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (lat != null && lng != null)
          'mapsUrl': 'https://maps.google.com/?q=$lat,$lng',
      },
      notifyTitle: 'Odada konum paylaşıldı',
    );
  }

  static Future<String> createPoll({
    required String roomId,
    required AppUser sender,
    required String question,
    required List<String> options,
    bool multi = false,
    DateTime? endsAt,
  }) async {
    final opts = options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (question.trim().isEmpty || opts.length < 2) {
      throw StateError('Soru ve en az 2 seçenek gerekli');
    }
    final pollRef =
        _db.collection('study_rooms').doc(roomId).collection('polls').doc();
    await pollRef.set({
      'question': question.trim(),
      'options': opts,
      'multi': multi,
      'createdBy': sender.id,
      'createdAt': DateTime.now().toIso8601String(),
      'endsAt': endsAt?.toIso8601String(),
      'votes': <String, List<String>>{},
    });
    await sendRichMessage(
      roomId: roomId,
      sender: sender,
      type: 'poll',
      text: question.trim(),
      meta: {
        'pollId': pollRef.id,
        'question': question.trim(),
        'options': opts,
        'multi': multi,
        if (endsAt != null) 'endsAt': endsAt.toIso8601String(),
      },
      notifyTitle: 'Odada oylama başladı',
    );
    return pollRef.id;
  }

  static Future<void> votePoll({
    required String roomId,
    required String pollId,
    required String userId,
    required List<int> optionIndexes,
  }) async {
    final ref = _db
        .collection('study_rooms')
        .doc(roomId)
        .collection('polls')
        .doc(pollId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Oylama yok');
      final data = snap.data()!;
      final ends = DateTime.tryParse('${data['endsAt'] ?? ''}');
      if (ends != null && DateTime.now().isAfter(ends)) {
        throw StateError('Oylama süresi doldu');
      }
      final multi = data['multi'] == true;
      final votes = Map<String, dynamic>.from(data['votes'] as Map? ?? {});
      // Clear previous votes of user
      for (final e in votes.entries.toList()) {
        final list = List<String>.from((e.value as List?) ?? const []);
        list.remove(userId);
        if (list.isEmpty) {
          votes.remove(e.key);
        } else {
          votes[e.key] = list;
        }
      }
      final idxs = multi ? optionIndexes : optionIndexes.take(1);
      for (final i in idxs) {
        final key = '$i';
        final list = List<String>.from((votes[key] as List?) ?? const []);
        if (!list.contains(userId)) list.add(userId);
        votes[key] = list;
      }
      tx.set(ref, {'votes': votes}, SetOptions(merge: true));
    });
  }

  static Stream<Map<String, dynamic>?> watchPoll(String roomId, String pollId) {
    return _db
        .collection('study_rooms')
        .doc(roomId)
        .collection('polls')
        .doc(pollId)
        .snapshots()
        .map((s) => s.exists ? s.data() : null);
  }

  static Future<List<StudyRoom>> listRecentForAdmin({int limit = 200}) async {
    final snap = await _db
        .collection('study_rooms')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => StudyRoom.fromMap(d.id, d.data()))
        .toList();
  }

  static Future<List<StudyChatMessage>> loadMessages(String roomId) async {
    final snap = await _db
        .collection('study_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(300)
        .get();
    return snap.docs
        .map((d) => StudyChatMessage.fromMap(d.id, d.data()))
        .toList();
  }

  /// Admin / moderatör: sohbet mesajını soft-delete.
  static Future<void> softDeleteMessage({
    required String roomId,
    required String messageId,
    required String byUserId,
  }) async {
    await _db
        .collection('study_rooms')
        .doc(roomId)
        .collection('messages')
        .doc(messageId)
        .set(
          {
            'text': 'Bu mesaj silindi',
            'type': 'system',
            'deletedAt': DateTime.now().toIso8601String(),
            'deletedBy': byUserId,
            'meta': {'moderated': true},
          },
          SetOptions(merge: true),
        );
  }
}
