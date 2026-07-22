import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Kullanıcı geri bildirimi.
class UserFeedback {
  const UserFeedback({
    required this.id,
    required this.userId,
    required this.userName,
    required this.email,
    required this.message,
    required this.createdAt,
    this.status = 'open',
    this.adminNote = '',
  });

  final String id;
  final String userId;
  final String userName;
  final String email;
  final String message;
  final DateTime createdAt;
  final String status; // open | reviewing | done
  final String adminNote;

  factory UserFeedback.fromMap(String id, Map<String, dynamic> m) {
    return UserFeedback(
      id: id,
      userId: '${m['userId'] ?? ''}',
      userName: '${m['userName'] ?? ''}',
      email: '${m['email'] ?? ''}',
      message: '${m['message'] ?? ''}',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
      status: '${m['status'] ?? 'open'}',
      adminNote: '${m['adminNote'] ?? ''}',
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'email': email,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'adminNote': adminNote,
      };

  static Future<void> submit({
    required String userId,
    required String userName,
    required String email,
    required String message,
  }) async {
    final text = message.trim();
    if (text.isEmpty) throw StateError('Mesaj boş');
    await FirebaseFirestore.instance.collection('feedback').add({
      'userId': userId,
      'userName': userName,
      'email': email,
      'message': text,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'open',
      'adminNote': '',
      'platform': kIsWeb ? 'web' : 'mobile',
    });
  }

  static Future<List<UserFeedback>> loadForAdmin({int limit = 100}) async {
    final snap = await FirebaseFirestore.instance
        .collection('feedback')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => UserFeedback.fromMap(d.id, d.data())).toList();
  }

  static Future<void> updateStatus(String id, String status) async {
    await FirebaseFirestore.instance.collection('feedback').doc(id).set({
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}
