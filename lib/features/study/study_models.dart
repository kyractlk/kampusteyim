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
    this.postId,
    this.isCommunity = false,
    this.chatOpen = true,
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
  final List<String> mutedIds;
  final String? postId;
  final bool isCommunity;
  final bool chatOpen;

  bool get isHostActive => status != 'ended';
  bool isHost(String uid) => hostId == uid;
  bool isKicked(String uid) => kickedIds.contains(uid);
  bool isMuted(String uid) => mutedIds.contains(uid);
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
      postId: m['postId'] as String?,
      isCommunity: m['isCommunity'] == true,
      chatOpen: m['chatOpen'] != false,
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
        'postId': postId,
        'isCommunity': isCommunity,
        'chatOpen': chatOpen,
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
  });

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime createdAt;
  final bool isAi;

  factory StudyChatMessage.fromMap(String id, Map<String, dynamic> m) {
    return StudyChatMessage(
      id: id,
      senderId: '${m['senderId'] ?? ''}',
      senderName: '${m['senderName'] ?? ''}',
      text: '${m['text'] ?? ''}',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
      isAi: m['isAi'] == true,
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
  }) async {
    final id = 'sr_${DateTime.now().millisecondsSinceEpoch}';
    final code = _newCode();
    final now = DateTime.now();
    String? postId;

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
      title: title.trim().isEmpty ? 'Çalışma odası' : title.trim(),
      hostId: host.id,
      hostName: host.fullName,
      minutes: minutes,
      createdAt: now,
      status: 'waiting',
      participantIds: [host.id],
      postId: postId,
      isCommunity: host.isCommunity,
      chatOpen: true,
    );
    await _db.collection('study_rooms').doc(id).set(room.toMap());
    await _db.collection('study_rooms').doc(id).collection('events').add({
      'type': 'created',
      'actorId': host.id,
      'actorName': host.fullName,
      'at': now.toIso8601String(),
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
        tx.set(ref, {'participantIds': parts}, SetOptions(merge: true));
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

  static Future<void> endSession(String roomId, String hostId) async {
    final ref = _db.collection('study_rooms').doc(roomId);
    await ref.set({
      'status': 'ended',
      'endedAt': DateTime.now().toIso8601String(),
      'chatOpen': false,
    }, SetOptions(merge: true));
    await ref.collection('events').add({
      'type': 'ended',
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

  static Future<void> sendMessage({
    required String roomId,
    required AppUser sender,
    required String text,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final room = await get(roomId);
    if (room == null) throw StateError('Oda yok');
    if (!room.chatOpen) throw StateError('Chat kapalı');
    if (room.isKicked(sender.id)) throw StateError('Çıkarıldın');
    if (!room.isMember(sender.id)) throw StateError('Üye değilsin');
    if (room.isMuted(sender.id)) throw StateError('Sessize alındın');

    await _db.collection('study_rooms').doc(roomId).collection('messages').add({
      'senderId': sender.id,
      'senderName': sender.fullName,
      'text': t,
      'createdAt': DateTime.now().toIso8601String(),
      'isAi': false,
    });

    // AI tetikle (@aystechbot veya her mesajda hafif şans / mention)
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

  static Future<List<StudyRoom>> listRecentForAdmin({int limit = 80}) async {
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
}
