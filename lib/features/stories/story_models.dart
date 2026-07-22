import '../../models/models.dart';

/// Tek bir hikâye medyası (Firestore `stories` belgesi).
class StoryItem {
  const StoryItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    required this.expiresAt,
    this.likedBy = const [],
    this.hiddenFrom = const [],
    this.archived = false,
    this.deletedAt,
    this.reportCount = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorHandle;
  final String mediaUrl;
  final MediaType mediaType;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> likedBy;
  final List<String> hiddenFrom;
  final bool archived;
  final DateTime? deletedAt;
  final int reportCount;

  bool get isDeleted => deletedAt != null;

  bool isExpired([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (archived) return false;
    return !expiresAt.isAfter(n);
  }

  bool isVisibleTo(String viewerId, {required bool isFollowerOrSelf}) {
    if (isDeleted) return false;
    if (hiddenFrom.contains(viewerId)) return false;
    if (isExpired()) return false;
    return isFollowerOrSelf || authorId == viewerId;
  }

  bool isLikedBy(String userId) => likedBy.contains(userId);

  StoryItem copyWith({
    String? mediaUrl,
    MediaType? mediaType,
    List<String>? likedBy,
    List<String>? hiddenFrom,
    bool? archived,
    DateTime? deletedAt,
    int? reportCount,
    bool clearDeleted = false,
  }) {
    return StoryItem(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorHandle: authorHandle,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt,
      expiresAt: expiresAt,
      likedBy: likedBy ?? this.likedBy,
      hiddenFrom: hiddenFrom ?? this.hiddenFrom,
      archived: archived ?? this.archived,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      reportCount: reportCount ?? this.reportCount,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'authorId': authorId,
        'authorName': authorName,
        'authorHandle': authorHandle,
        'mediaUrl': mediaUrl,
        'mediaType': mediaType.name,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'likedBy': likedBy,
        'hiddenFrom': hiddenFrom,
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
        'reportCount': reportCount,
      };

  factory StoryItem.fromFirestore(String id, Map<String, dynamic> m) {
    final typeName = '${m['mediaType'] ?? 'image'}';
    return StoryItem(
      id: id,
      authorId: '${m['authorId'] ?? ''}',
      authorName: '${m['authorName'] ?? ''}',
      authorHandle: '${m['authorHandle'] ?? ''}',
      mediaUrl: '${m['mediaUrl'] ?? ''}',
      mediaType: typeName == 'video' ? MediaType.video : MediaType.image,
      createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime.now(),
      expiresAt: DateTime.tryParse('${m['expiresAt'] ?? ''}') ??
          DateTime.now().add(const Duration(hours: 24)),
      likedBy: _stringList(m['likedBy']),
      hiddenFrom: _stringList(m['hiddenFrom']),
      archived: m['archived'] == true,
      deletedAt: DateTime.tryParse('${m['deletedAt'] ?? ''}'),
      reportCount: (m['reportCount'] is num)
          ? (m['reportCount'] as num).toInt()
          : int.tryParse('${m['reportCount'] ?? 0}') ?? 0,
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => '$e'.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
}

/// Bir kullanıcının aktif hikâyeleri (halka görünümü).
class Story {
  const Story({
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.items,
    this.authorPhotoUrl,
  });

  final String authorId;
  final String authorName;
  final String authorHandle;
  final String? authorPhotoUrl;
  final List<StoryItem> items;

  bool get hasItems => items.isNotEmpty;

  DateTime get latestAt => items.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : items.map((e) => e.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
}
