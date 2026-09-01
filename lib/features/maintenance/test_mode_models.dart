import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore `app_config/test_mode` modeli.
class TestModeState {
  const TestModeState({
    required this.active,
    required this.message,
    this.startedAt,
    this.endedAt,
    this.purgedAt,
    this.updatedAt,
    this.updatedBy,
  });

  final bool active;
  final String message;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? purgedAt;
  final DateTime? updatedAt;
  final String? updatedBy;

  static const empty = TestModeState(
    active: false,
    message:
        'KampüsteyimAPP şu an test modundadır. Paylaşımlar canlı yayına geçmeden önce silinebilir.',
  );

  factory TestModeState.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return TestModeState.empty;
    return TestModeState(
      active: raw['active'] == true,
      message: '${raw['message'] ?? TestModeState.empty.message}',
      startedAt: _dt(raw['startedAt']),
      endedAt: _dt(raw['endedAt']),
      purgedAt: _dt(raw['purgedAt']),
      updatedAt: _dt(raw['updatedAt']),
      updatedBy: raw['updatedBy']?.toString(),
    );
  }

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse('$v');
  }
}
