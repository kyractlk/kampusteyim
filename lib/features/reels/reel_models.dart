import '../../models/models.dart';

enum ReelMediaType { video, image }

class CampusReel {
  const CampusReel({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.mediaUrl,
    required this.createdAt,
    this.authorPhotoUrl,
    this.caption = '',
    this.mediaType = ReelMediaType.video,
    this.likedBy = const [],
    this.viewedBy = const [],
    this.commentCount = 0,
    this.reportCount = 0,
    this.deletedAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorHandle;
  final String? authorPhotoUrl;
  final String mediaUrl;
  final ReelMediaType mediaType;
  final String caption;
  final DateTime createdAt;
  final List<String> likedBy;
  final List<String> viewedBy;
  final int commentCount;
  final int reportCount;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool likedByUser(String uid) => likedBy.contains(uid);
  bool viewedByUser(String uid) => viewedBy.contains(uid);

  CampusReel copyWith({
    List<String>? likedBy,
    List<String>? viewedBy,
    int? commentCount,
    DateTime? deletedAt,
  }) =>
      CampusReel(
        id: id,
        authorId: authorId,
        authorName: authorName,
        authorHandle: authorHandle,
        authorPhotoUrl: authorPhotoUrl,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        caption: caption,
        createdAt: createdAt,
        likedBy: likedBy ?? this.likedBy,
        viewedBy: viewedBy ?? this.viewedBy,
        commentCount: commentCount ?? this.commentCount,
        reportCount: reportCount,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toFirestore() => {
        'authorId': authorId,
        'authorName': authorName,
        'authorHandle': authorHandle,
        'authorPhotoUrl': authorPhotoUrl,
        'mediaUrl': mediaUrl,
        'mediaType': mediaType == ReelMediaType.video ? 'video' : 'image',
        'caption': caption,
        'createdAt': createdAt.toIso8601String(),
        'likedBy': likedBy,
        'viewedBy': viewedBy,
        'commentCount': commentCount,
        'reportCount': reportCount,
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };

  factory CampusReel.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime parse(dynamic v) {
      if (v is DateTime) return v;
      return DateTime.tryParse('$v') ?? DateTime.now();
    }

    List<String> strList(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    }

    return CampusReel(
      id: id,
      authorId: '${d['authorId'] ?? ''}',
      authorName: '${d['authorName'] ?? ''}',
      authorHandle: '${d['authorHandle'] ?? ''}',
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
      mediaUrl: '${d['mediaUrl'] ?? ''}',
      mediaType: '${d['mediaType']}' == 'image'
          ? ReelMediaType.image
          : ReelMediaType.video,
      caption: '${d['caption'] ?? ''}',
      createdAt: parse(d['createdAt']),
      likedBy: strList(d['likedBy']),
      viewedBy: strList(d['viewedBy']),
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
      reportCount: (d['reportCount'] as num?)?.toInt() ?? 0,
      deletedAt: d['deletedAt'] != null ? parse(d['deletedAt']) : null,
    );
  }

  static CampusReel fromAuthor({
    required String id,
    required AppUser author,
    required String mediaUrl,
    required bool isVideo,
    String caption = '',
  }) {
    return CampusReel(
      id: id,
      authorId: author.id,
      authorName: author.fullName,
      authorHandle: author.handle,
      authorPhotoUrl: author.photoUrl,
      mediaUrl: mediaUrl,
      mediaType: isVideo ? ReelMediaType.video : ReelMediaType.image,
      caption: caption,
      createdAt: DateTime.now(),
    );
  }
}
