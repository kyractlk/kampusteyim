import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/security/safe_text.dart';

/// Firestore `app_config/maintenance` modeli.
class MaintenanceState {
  const MaintenanceState({
    required this.active,
    required this.title,
    required this.message,
    this.plannedStart,
    this.plannedEnd,
    this.startedAt,
    this.endedAt,
    this.updatedAt,
    this.updatedBy,
    this.autoActivate = true,
    this.sessionId,
    this.subscriberCount = 0,
  });

  final bool active;
  final String title;
  final String message;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final bool autoActivate;
  /// Aynı bakım oturumu için abonelik anahtarı.
  final String? sessionId;
  final int subscriberCount;

  static const empty = MaintenanceState(
    active: false,
    title: 'Planlı bakım',
    message:
        'KampüsteyimAPP şu an AYS Tech tarafından planlı bakıma alındı. Kısa süre içinde geri döneceğiz.',
  );

  bool get isBlocking => active;

  Duration? get remaining {
    final end = plannedEnd;
    if (end == null) return null;
    final d = end.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  factory MaintenanceState.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return empty;
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.tryParse('$v');
    }

    final title = SafeText.plain('${raw['title'] ?? empty.title}', maxLen: 120);
    final message =
        SafeText.plain('${raw['message'] ?? empty.message}', maxLen: 800);

    return MaintenanceState(
      active: raw['active'] == true,
      title: title.isEmpty ? empty.title : title,
      message: message.isEmpty ? empty.message : message,
      plannedStart: parse(raw['plannedStart']),
      plannedEnd: parse(raw['plannedEnd']),
      startedAt: parse(raw['startedAt']),
      endedAt: parse(raw['endedAt']),
      updatedAt: parse(raw['updatedAt']),
      updatedBy: raw['updatedBy']?.toString(),
      autoActivate: raw['autoActivate'] != false,
      sessionId: raw['sessionId']?.toString(),
      subscriberCount: (raw['subscriberCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'active': active,
        'title': title,
        'message': message,
        'plannedStart': plannedStart?.toIso8601String(),
        'plannedEnd': plannedEnd?.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'updatedBy': updatedBy,
        'autoActivate': autoActivate,
        'sessionId': sessionId,
        'subscriberCount': subscriberCount,
      };
}
