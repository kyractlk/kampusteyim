enum RestrictionType { none, postBan, fullBan }

enum ReportTargetType { post, comment, account }

enum ReportStatus { open, reviewing, resolved, dismissed }

class UserRestriction {
  const UserRestriction({
    this.type = RestrictionType.none,
    this.reason = '',
    this.until,
  });

  final RestrictionType type;
  final String reason;
  final DateTime? until;

  bool get isActive {
    if (type == RestrictionType.none) return false;
    if (until == null) return true;
    return until!.isAfter(DateTime.now());
  }

  bool get canPost =>
      !isActive || type == RestrictionType.none;

  bool get isFullyBanned =>
      isActive && type == RestrictionType.fullBan;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'reason': reason,
        'until': until?.toIso8601String(),
      };

  factory UserRestriction.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserRestriction();
    return UserRestriction(
      type: RestrictionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RestrictionType.none,
      ),
      reason: '${json['reason'] ?? ''}',
      until: DateTime.tryParse('${json['until'] ?? ''}'),
    );
  }
}

class ContentReport {
  ContentReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reporterId,
    required this.reason,
    required this.createdAt,
    this.status = ReportStatus.open,
    this.targetOwnerId,
    this.details = '',
    this.snapshotTitle = '',
    this.snapshotBody = '',
    this.snapshotAuthor = '',
    this.snapshotUrl = '',
    this.reporterEmail = '',
    this.reporterName = '',
    this.aiDecision = '',
    this.aiSummary = '',
    this.aiConfidence = 0,
    this.aiActed = false,
    this.aiAdminNote = '',
    this.aiLabels = const [],
  });

  final String id;
  final ReportTargetType targetType;
  final String targetId;
  final String? targetOwnerId;
  final String reporterId;
  final String reason;
  final String details;
  final DateTime createdAt;
  ReportStatus status;
  /// Şikayet anındaki içerik kopyası (silinse bile admin görür).
  final String snapshotTitle;
  final String snapshotBody;
  final String snapshotAuthor;
  final String snapshotUrl;
  final String reporterEmail;
  final String reporterName;
  String aiDecision;
  String aiSummary;
  double aiConfidence;
  bool aiActed;
  String aiAdminNote;
  List<String> aiLabels;

  Map<String, dynamic> toJson() => {
        'targetType': targetType.name,
        'targetId': targetId,
        'targetOwnerId': targetOwnerId,
        'reporterId': reporterId,
        'reason': reason,
        'details': details,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'snapshotTitle': snapshotTitle,
        'snapshotBody': snapshotBody,
        'snapshotAuthor': snapshotAuthor,
        'snapshotUrl': snapshotUrl,
        'reporterEmail': reporterEmail,
        'reporterName': reporterName,
        'aiDecision': aiDecision,
        'aiSummary': aiSummary,
        'aiConfidence': aiConfidence,
        'aiActed': aiActed,
        'aiAdminNote': aiAdminNote,
        'aiLabels': aiLabels,
      };

  factory ContentReport.fromJson(String id, Map<String, dynamic> json) {
    return ContentReport(
      id: id,
      targetType: ReportTargetType.values.firstWhere(
        (e) => e.name == json['targetType'],
        orElse: () => ReportTargetType.post,
      ),
      targetId: '${json['targetId']}',
      targetOwnerId: json['targetOwnerId'] as String?,
      reporterId: '${json['reporterId']}',
      reason: '${json['reason']}',
      details: '${json['details'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      status: ReportStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ReportStatus.open,
      ),
      snapshotTitle: '${json['snapshotTitle'] ?? ''}',
      snapshotBody: '${json['snapshotBody'] ?? ''}',
      snapshotAuthor: '${json['snapshotAuthor'] ?? ''}',
      snapshotUrl: '${json['snapshotUrl'] ?? ''}',
      reporterEmail: '${json['reporterEmail'] ?? ''}',
      reporterName: '${json['reporterName'] ?? ''}',
      aiDecision: '${json['aiDecision'] ?? ''}',
      aiSummary: '${json['aiSummary'] ?? ''}',
      aiConfidence: (json['aiConfidence'] as num?)?.toDouble() ?? 0,
      aiActed: json['aiActed'] == true,
      aiAdminNote: '${json['aiAdminNote'] ?? ''}',
      aiLabels: ((json['aiLabels'] as List?) ?? []).map((e) => '$e').toList(),
    );
  }
}
