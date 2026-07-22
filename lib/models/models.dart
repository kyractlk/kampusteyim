import '../core/constants/app_info.dart';
import '../features/notifications/notification_prefs.dart';

class MediaItem {
  const MediaItem({
    required this.url,
    required this.type,
  });

  final String url;
  final MediaType type;
}

enum MediaType { image, video }

class ProfileLink {
  const ProfileLink({required this.label, required this.url});

  final String label;
  final String url;
}

enum UserRole { student, community, company, admin }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.studentNo,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.city,
    required this.university,
    this.bio = '',
    this.photoUrl,
    this.links = const [],
    this.following = const [],
    this.followers = const [],
    this.isCommunity = false,
    this.role = UserRole.student,
    this.communityLogoUrl,
    this.affiliatedCommunityId,
    this.affiliatedCommunityName,
    this.affiliatedOrgLogoUrl,
    this.hasGoldBadge = false,
    this.hasBlueBadge = false,
    this.restrictionType = 'none',
    this.restrictionReason = '',
    this.restrictionUntil,
    this.staffRoleId,
    this.isSuperAdmin = false,
    this.notificationPrefs = NotificationPrefs.defaults,
    this.username,
    this.usernameStatus = 'ok',
    this.isBot = false,
    this.allowMentions = true,
    this.kvkkAcceptedAt,
    this.marketingConsent = false,
    this.marketingAcceptedAt,
    this.accountStatus = 'approved',
    this.studentIdDocUrl,
    this.studentVerificationType,
    this.studentIdFrontUrl,
    this.studentIdBackUrl,
    this.hideFromSearch = false,
    this.isPrivateAccount = false,
    this.isSpectatorMode = false,
    this.blockedUserIds = const [],
    this.incomingFollowRequests = const [],
    this.outgoingFollowRequests = const [],
  });

  final String id;
  final String email;
  final String studentNo;
  final String firstName;
  final String lastName;
  final String phone;
  final String city;
  final String university;
  final String bio;
  final String? photoUrl;
  final List<ProfileLink> links;
  final List<String> following;
  final List<String> followers;
  final bool isCommunity;
  final UserRole role;
  final String? communityLogoUrl;
  final String? affiliatedCommunityId;
  final String? affiliatedCommunityName;
  /// İlişkili kurum logosu (Twitter tarzı minik rozet).
  final String? affiliatedOrgLogoUrl;
  final bool hasGoldBadge;
  final bool hasBlueBadge;
  final String restrictionType;
  final String restrictionReason;
  final DateTime? restrictionUntil;
  final String? staffRoleId;
  final bool isSuperAdmin;
  final NotificationPrefs notificationPrefs;
  /// @ olmadan saklanan kullanıcı adı (benzersiz).
  final String? username;
  /// ok | temp | pending
  final String usernameStatus;
  /// Platform AI / resmi bot hesabı.
  final bool isBot;
  /// Diğer kullanıcılar gönderide @ ile etiketleyebilir mi?
  final bool allowMentions;
  /// KVKK metni kabul zamanı.
  final DateTime? kvkkAcceptedAt;
  /// Pazarlama / ticari iletişim izni.
  final bool marketingConsent;
  final DateTime? marketingAcceptedAt;
  /// pending | approved | rejected — öğrenci belgesi onayı.
  final String accountStatus;
  /// Öğrenci kimlik / belge Storage URL (PDF veya eski tek dosya).
  final String? studentIdDocUrl;
  /// card | document
  final String? studentVerificationType;
  /// Öğrenci kartı ön yüz.
  final String? studentIdFrontUrl;
  /// Öğrenci kartı arka yüz.
  final String? studentIdBackUrl;
  /// Aramada görünmez.
  final bool hideFromSearch;
  /// Instagram tarzı gizli hesap (takip isteği).
  final bool isPrivateAccount;
  /// Görünmezlik / izleyici modu — etkileşim yok.
  final bool isSpectatorMode;
  final List<String> blockedUserIds;
  /// Bana gelen takip istekleri.
  final List<String> incomingFollowRequests;
  /// Benim gönderdiğim takip istekleri.
  final List<String> outgoingFollowRequests;

  /// Panel erişimi: süper admin, UserRole.admin veya atanmış staff rolü.
  bool get canAccessAdmin =>
      isSuperAdmin || role == UserRole.admin || staffRoleId != null;

  bool get isAdmin => canAccessAdmin;
  bool get isCompany => role == UserRole.company;
  bool get showGoldBadge => isCommunity || hasGoldBadge;
  /// Mavi tick yalnızca açıkça verilmişse (ilişki ayrı gösterilir).
  bool get showBlueBadge => !showGoldBadge && hasBlueBadge;
  bool get hasAffiliation {
    final id = affiliatedCommunityId?.trim() ?? '';
    final name = affiliatedCommunityName?.trim() ?? '';
    return id.isNotEmpty && name.isNotEmpty;
  }

  bool get restrictionActive {
    if (restrictionType == 'none' || restrictionType.isEmpty) return false;
    if (restrictionUntil == null) return true;
    return restrictionUntil!.isAfter(DateTime.now());
  }

  bool get isAccountPending => accountStatus == 'pending';
  bool get isAccountRejected => accountStatus == 'rejected';
  bool get isAccountApproved =>
      accountStatus == 'approved' || accountStatus.isEmpty;

  bool get canInteract =>
      isAccountApproved && !isSpectatorMode && canPost;

  bool get canUseStories =>
      isAccountApproved && !isSpectatorMode;

  bool blocks(String userId) => blockedUserIds.contains(userId);

  bool get canPost =>
      isAccountApproved &&
      !isSpectatorMode &&
      (!restrictionActive ||
          (restrictionType != 'postBan' &&
              restrictionType != 'fullBan' &&
              restrictionType != 'mute'));

  bool get canComment =>
      isAccountApproved &&
      !isSpectatorMode &&
      (!restrictionActive ||
          (restrictionType != 'mute' && restrictionType != 'fullBan'));

  bool get isFullyBanned =>
      restrictionActive && restrictionType == 'fullBan';

  bool get isWarned =>
      restrictionActive && restrictionType == 'warn';

  /// Topluluk hesabı logo yüklemeden paylaşamaz.
  bool get communityCanPublish =>
      !isCommunity || (communityLogoUrl != null && communityLogoUrl!.isNotEmpty);

  bool get needsUsernameChange => usernameStatus == 'temp';

  String get fullName => '$firstName $lastName';
  String get handle {
    if (username != null && username!.trim().isNotEmpty) {
      final u = username!.trim();
      return u.startsWith('@') ? u : '@$u';
    }
    return isCommunity
        ? '@${_slug(firstName.isEmpty ? 'topluluk' : firstName)}'
        : '@${_slug(firstName)}$studentNo';
  }

  String get initials {
    if (isCommunity) return 'KA';
    return '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
        .toUpperCase();
  }

  AppUser copyWith({
    String? bio,
    String? photoUrl,
    List<ProfileLink>? links,
    List<String>? following,
    List<String>? followers,
    String? firstName,
    String? lastName,
    String? phone,
    bool? isCommunity,
    UserRole? role,
    String? communityLogoUrl,
    String? affiliatedCommunityId,
    String? affiliatedCommunityName,
    String? affiliatedOrgLogoUrl,
    bool? hasGoldBadge,
    bool? hasBlueBadge,
    String? restrictionType,
    String? restrictionReason,
    DateTime? restrictionUntil,
    String? staffRoleId,
    bool? isSuperAdmin,
    NotificationPrefs? notificationPrefs,
    String? username,
    String? usernameStatus,
    bool? isBot,
    bool? allowMentions,
    DateTime? kvkkAcceptedAt,
    bool? marketingConsent,
    DateTime? marketingAcceptedAt,
    String? accountStatus,
    String? studentIdDocUrl,
    String? studentVerificationType,
    String? studentIdFrontUrl,
    String? studentIdBackUrl,
    bool? hideFromSearch,
    bool? isPrivateAccount,
    bool? isSpectatorMode,
    List<String>? blockedUserIds,
    List<String>? incomingFollowRequests,
    List<String>? outgoingFollowRequests,
    bool clearPhoto = false,
    bool clearAffiliation = false,
    bool clearRestrictionUntil = false,
    bool clearStaffRole = false,
    bool clearStudentIdDoc = false,
  }) {
    return AppUser(
      id: id,
      email: email,
      studentNo: studentNo,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      city: city,
      university: university,
      bio: bio ?? this.bio,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      links: links ?? this.links,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      isCommunity: isCommunity ?? this.isCommunity,
      role: role ?? this.role,
      communityLogoUrl: communityLogoUrl ?? this.communityLogoUrl,
      affiliatedCommunityId: clearAffiliation
          ? null
          : (affiliatedCommunityId ?? this.affiliatedCommunityId),
      affiliatedCommunityName: clearAffiliation
          ? null
          : (affiliatedCommunityName ?? this.affiliatedCommunityName),
      affiliatedOrgLogoUrl: clearAffiliation
          ? null
          : (affiliatedOrgLogoUrl ?? this.affiliatedOrgLogoUrl),
      hasGoldBadge: hasGoldBadge ?? this.hasGoldBadge,
      hasBlueBadge: hasBlueBadge ?? this.hasBlueBadge,
      restrictionType: restrictionType ?? this.restrictionType,
      restrictionReason: restrictionReason ?? this.restrictionReason,
      restrictionUntil: clearRestrictionUntil
          ? null
          : (restrictionUntil ?? this.restrictionUntil),
      staffRoleId: clearStaffRole ? null : (staffRoleId ?? this.staffRoleId),
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      notificationPrefs: notificationPrefs ?? this.notificationPrefs,
      username: username ?? this.username,
      usernameStatus: usernameStatus ?? this.usernameStatus,
      isBot: isBot ?? this.isBot,
      allowMentions: allowMentions ?? this.allowMentions,
      kvkkAcceptedAt: kvkkAcceptedAt ?? this.kvkkAcceptedAt,
      marketingConsent: marketingConsent ?? this.marketingConsent,
      marketingAcceptedAt: marketingAcceptedAt ?? this.marketingAcceptedAt,
      accountStatus: accountStatus ?? this.accountStatus,
      studentIdDocUrl:
          clearStudentIdDoc ? null : (studentIdDocUrl ?? this.studentIdDocUrl),
      studentVerificationType: clearStudentIdDoc
          ? null
          : (studentVerificationType ?? this.studentVerificationType),
      studentIdFrontUrl: clearStudentIdDoc
          ? null
          : (studentIdFrontUrl ?? this.studentIdFrontUrl),
      studentIdBackUrl: clearStudentIdDoc
          ? null
          : (studentIdBackUrl ?? this.studentIdBackUrl),
      hideFromSearch: hideFromSearch ?? this.hideFromSearch,
      isPrivateAccount: isPrivateAccount ?? this.isPrivateAccount,
      isSpectatorMode: isSpectatorMode ?? this.isSpectatorMode,
      blockedUserIds: blockedUserIds ?? this.blockedUserIds,
      incomingFollowRequests:
          incomingFollowRequests ?? this.incomingFollowRequests,
      outgoingFollowRequests:
          outgoingFollowRequests ?? this.outgoingFollowRequests,
    );
  }

  static String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ğüşıöç]'), '');
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.content,
    required this.createdAt,
    this.parentId,
    this.likeCount = 0,
    this.isLiked = false,
    this.isPinned = false,
    this.replies = const [],
    this.deletedAt,
    this.deletedBy,
  });

  final String id;
  final String postId;
  final String? parentId;
  final String authorId;
  final String authorName;
  final String authorHandle;
  final String content;
  final DateTime createdAt;
  final int likeCount;
  final bool isLiked;
  final bool isPinned;
  final List<Comment> replies;
  final DateTime? deletedAt;
  final String? deletedBy;

  bool get isDeleted => deletedAt != null;

  Comment copyWith({
    String? content,
    int? likeCount,
    bool? isLiked,
    bool? isPinned,
    List<Comment>? replies,
    DateTime? deletedAt,
    String? deletedBy,
    bool clearDeleted = false,
  }) {
    return Comment(
      id: id,
      postId: postId,
      parentId: parentId,
      authorId: authorId,
      authorName: authorName,
      authorHandle: authorHandle,
      content: content ?? this.content,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      isPinned: isPinned ?? this.isPinned,
      replies: replies ?? this.replies,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      deletedBy: clearDeleted ? null : (deletedBy ?? this.deletedBy),
    );
  }

  Map<String, dynamic> toMap() => {
        'postId': postId,
        'parentId': parentId,
        'authorId': authorId,
        'authorName': authorName,
        'authorHandle': authorHandle,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likeCount': likeCount,
        'isPinned': isPinned,
        'replies': replies.map((r) => r.toMap()..['id'] = r.id).toList(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
        if (deletedBy != null) 'deletedBy': deletedBy,
      };

  static Comment fromMap(String id, Map<String, dynamic> m) {
    final repliesRaw = m['replies'];
    final replies = <Comment>[];
    if (repliesRaw is List) {
      for (var i = 0; i < repliesRaw.length; i++) {
        final item = repliesRaw[i];
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final rid = '${map['id'] ?? 'r_$i'}';
        replies.add(Comment.fromMap(rid, map));
      }
    }
    DateTime created;
    final rawCreated = m['createdAt'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }
    DateTime? deleted;
    final rawDeleted = m['deletedAt'];
    if (rawDeleted is String && rawDeleted.isNotEmpty) {
      deleted = DateTime.tryParse(rawDeleted);
    }
    return Comment(
      id: id,
      postId: '${m['postId'] ?? ''}',
      parentId: m['parentId'] as String?,
      authorId: '${m['authorId'] ?? ''}',
      authorName: '${m['authorName'] ?? ''}',
      authorHandle: '${m['authorHandle'] ?? ''}',
      content: '${m['content'] ?? ''}',
      createdAt: created,
      likeCount: (m['likeCount'] as num?)?.toInt() ?? 0,
      isPinned: m['isPinned'] == true,
      replies: replies,
      deletedAt: deleted,
      deletedBy: m['deletedBy'] as String?,
    );
  }
}

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.content,
    required this.createdAt,
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.isLiked = false,
    this.isReposted = false,
    this.isCommunity = false,
    this.media = const [],
    this.hashtags = const [],
    this.repostedFromId,
    this.repostedFromName,
    this.deletedAt,
    this.deletedBy,
    this.studyRoomId,
    this.studyRoomCode,
    this.studyMinutes,
    this.studyTitle,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorHandle;
  final String content;
  final DateTime createdAt;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final bool isLiked;
  final bool isReposted;
  final bool isCommunity;
  final List<MediaItem> media;
  final List<String> hashtags;
  final String? repostedFromId;
  final String? repostedFromName;
  final DateTime? deletedAt;
  final String? deletedBy;
  /// Ortak çalışma odası bağlantısı.
  final String? studyRoomId;
  final String? studyRoomCode;
  final int? studyMinutes;
  final String? studyTitle;

  bool get isStudyRoomInvite {
    if (studyRoomId != null && studyRoomId!.trim().isNotEmpty) return true;
    return content.contains('Çalışma odası açıldı');
  }

  bool get isDeleted => deletedAt != null;

  String get permalink => '${AppInfo.webBaseUrl}/post/$id';

  Post copyWith({
    bool? isLiked,
    int? likeCount,
    bool? isReposted,
    int? repostCount,
    int? replyCount,
    List<MediaItem>? media,
    List<String>? hashtags,
    DateTime? deletedAt,
    String? deletedBy,
    String? studyRoomId,
    String? studyRoomCode,
    int? studyMinutes,
    String? studyTitle,
    bool clearDeleted = false,
  }) {
    return Post(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorHandle: authorHandle,
      content: content,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      isLiked: isLiked ?? this.isLiked,
      isReposted: isReposted ?? this.isReposted,
      isCommunity: isCommunity,
      media: media ?? this.media,
      hashtags: hashtags ?? this.hashtags,
      repostedFromId: repostedFromId,
      repostedFromName: repostedFromName,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      deletedBy: clearDeleted ? null : (deletedBy ?? this.deletedBy),
      studyRoomId: studyRoomId ?? this.studyRoomId,
      studyRoomCode: studyRoomCode ?? this.studyRoomCode,
      studyMinutes: studyMinutes ?? this.studyMinutes,
      studyTitle: studyTitle ?? this.studyTitle,
    );
  }

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'authorHandle': authorHandle,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'likeCount': likeCount,
        'replyCount': replyCount,
        'repostCount': repostCount,
        'isCommunity': isCommunity,
        'hashtags': hashtags,
        'repostedFromId': repostedFromId,
        'repostedFromName': repostedFromName,
        'deletedAt': deletedAt?.toIso8601String(),
        'deletedBy': deletedBy,
        'studyRoomId': studyRoomId,
        'studyRoomCode': studyRoomCode,
        'studyMinutes': studyMinutes,
        'studyTitle': studyTitle,
        'media': media
            .map((m) => {'url': m.url, 'type': m.type.name})
            .toList(),
      };

  static Post fromMap(String id, Map<String, dynamic> m) {
    final mediaRaw = m['media'];
    final media = <MediaItem>[];
    if (mediaRaw is List) {
      for (final item in mediaRaw) {
        if (item is! Map) continue;
        final url = '${item['url'] ?? ''}';
        if (url.isEmpty) continue;
        final type = '${item['type']}' == 'video'
            ? MediaType.video
            : MediaType.image;
        media.add(MediaItem(url: url, type: type));
      }
    }
    final tags = m['hashtags'];
    DateTime created;
    final rawCreated = m['createdAt'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }
    final rawDeleted = m['deletedAt'];
    DateTime? deleted;
    if (rawDeleted is String && rawDeleted.isNotEmpty) {
      deleted = DateTime.tryParse(rawDeleted);
    }
    final roomIdRaw = '${m['studyRoomId'] ?? ''}'.trim();
    final codeRaw = '${m['studyRoomCode'] ?? ''}'.trim();
    final titleRaw = '${m['studyTitle'] ?? ''}'.trim();
    // Eski duyurulardan kod / süre çıkar
    final content = '${m['content'] ?? ''}';
    final codeMatch = RegExp(r'Kod:\s*([A-Z0-9]{4,12})', caseSensitive: false)
        .firstMatch(content);
    final minsMatch =
        RegExp(r'·\s*(\d+)\s*dk').firstMatch(content);
    return Post(
      id: id,
      authorId: '${m['authorId'] ?? ''}',
      authorName: '${m['authorName'] ?? ''}',
      authorHandle: '${m['authorHandle'] ?? ''}',
      content: content,
      createdAt: created,
      likeCount: (m['likeCount'] as num?)?.toInt() ?? 0,
      replyCount: (m['replyCount'] as num?)?.toInt() ?? 0,
      repostCount: (m['repostCount'] as num?)?.toInt() ?? 0,
      isCommunity: m['isCommunity'] == true,
      media: media,
      hashtags: tags is List
          ? tags.map((e) => '$e').toList()
          : const <String>[],
      repostedFromId: m['repostedFromId'] as String?,
      repostedFromName: m['repostedFromName'] as String?,
      deletedAt: deleted,
      deletedBy: m['deletedBy'] as String?,
      studyRoomId: roomIdRaw.isEmpty ? null : roomIdRaw,
      studyRoomCode: codeRaw.isNotEmpty
          ? codeRaw.toUpperCase()
          : codeMatch?.group(1)?.toUpperCase(),
      studyMinutes:
          (m['studyMinutes'] as num?)?.toInt() ??
              int.tryParse(minsMatch?.group(1) ?? ''),
      studyTitle: titleRaw.isEmpty ? null : titleRaw,
    );
  }
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.audience,
    this.isPinned = false,
    this.imageUrl,
    this.communityId,
    this.communityName,
    this.communityLogoUrl,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String audience;
  final bool isPinned;
  final String? imageUrl;
  final String? communityId;
  final String? communityName;
  final String? communityLogoUrl;

  String get audienceLabel {
    switch (audience) {
      case 'members':
        return 'Üyeler';
      case 'followers':
        return 'Takipçiler';
      default:
        return 'Kampüs geneli';
    }
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'audience': audience,
        'isPinned': isPinned,
        'imageUrl': imageUrl,
        'communityId': communityId,
        'communityName': communityName,
        'communityLogoUrl': communityLogoUrl,
      };

  factory Announcement.fromMap(String id, Map<String, dynamic> m) {
    return Announcement(
      id: id,
      title: '${m['title'] ?? ''}',
      body: '${m['body'] ?? ''}',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
      audience: '${m['audience'] ?? 'campus'}',
      isPinned: m['isPinned'] == true,
      imageUrl: m['imageUrl'] as String?,
      communityId: m['communityId'] as String?,
      communityName: m['communityName'] as String?,
      communityLogoUrl: m['communityLogoUrl'] as String?,
    );
  }
}

enum EventApplicationStatus { pending, approved, rejected, cancelled }

class EventApplication {
  const EventApplication({
    required this.id,
    required this.userId,
    required this.userName,
    required this.createdAt,
    this.status = EventApplicationStatus.pending,
  });

  final String id;
  final String userId;
  final String userName;
  final DateTime createdAt;
  final EventApplicationStatus status;

  bool get holdsSlot =>
      status == EventApplicationStatus.pending ||
      status == EventApplicationStatus.approved;

  EventApplication copyWith({EventApplicationStatus? status}) {
    return EventApplication(
      id: id,
      userId: userId,
      userName: userName,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'userName': userName,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
      };

  factory EventApplication.fromMap(Map<String, dynamic> m) {
    final statusName = '${m['status'] ?? 'pending'}';
    final status = EventApplicationStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => EventApplicationStatus.pending,
    );
    return EventApplication(
      id: '${m['id'] ?? ''}',
      userId: '${m['userId'] ?? ''}',
      userName: '${m['userName'] ?? ''}',
      createdAt: DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
      status: status,
    );
  }
}

/// Kimler başvurabilir: campus | members | students
class CampusEvent {
  const CampusEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.startsAt,
    required this.capacity,
    this.applicantCount = 0,
    this.isApplied = false,
    this.imageUrl,
    this.communityId,
    this.communityName,
    this.communityLogoUrl,
    this.applications = const [],
    this.audience = 'campus',
    this.applicationDeadline,
    this.applicationsOpen = true,
  });

  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime startsAt;
  final int capacity;
  final int applicantCount;
  final bool isApplied;
  final String? imageUrl;
  final String? communityId;
  final String? communityName;
  final String? communityLogoUrl;
  final List<EventApplication> applications;
  /// campus = tüm kampüs, members = topluluk üyeleri, students = öğrenciler
  final String audience;
  final DateTime? applicationDeadline;
  /// Son başvuru geçince false olur; tarih uzatılınca tekrar true.
  final bool applicationsOpen;

  int get approvedCount => applications
      .where((a) => a.status == EventApplicationStatus.approved)
      .length;

  int get pendingCount => applications
      .where((a) => a.status == EventApplicationStatus.pending)
      .length;

  /// Onaylı + bekleyen — red/iptal slotu açar.
  int get heldSlots => applications.where((a) => a.holdsSlot).length;

  bool get isRosterFull => approvedCount >= capacity;

  bool get isCapacityFull => heldSlots >= capacity;

  bool get isDeadlinePassed {
    final d = applicationDeadline;
    if (d == null) return false;
    return !d.isAfter(DateTime.now());
  }

  bool get canAcceptApplications =>
      applicationsOpen && !isDeadlinePassed && !isCapacityFull && !isRosterFull;

  String get audienceLabel {
    switch (audience) {
      case 'members':
        return 'Topluluk üyeleri';
      case 'students':
        return 'Öğrenciler';
      case 'followers':
        return 'Takipçiler';
      default:
        return 'Tüm kampüs';
    }
  }

  bool isEligible(AppUser user, {bool Function(String communityId)? follows}) {
    switch (audience) {
      case 'members':
        return communityId != null &&
            (user.id == communityId ||
                user.affiliatedCommunityId == communityId);
      case 'students':
        return user.role == UserRole.student && !user.isCommunity;
      case 'followers':
        if (communityId == null) return false;
        if (user.id == communityId) return true;
        if (follows != null) return follows(communityId!);
        return user.following.contains(communityId);
      default:
        return true;
    }
  }

  bool hasActiveApplication(String userId) => applications.any(
        (a) =>
            a.userId == userId &&
            (a.status == EventApplicationStatus.pending ||
                a.status == EventApplicationStatus.approved),
      );

  String applyBlockedReason({
    AppUser? user,
    bool Function(String communityId)? follows,
  }) {
    if (user != null && hasActiveApplication(user.id)) return 'Başvuruldu';
    if (isApplied) return 'Başvuruldu';
    if (isRosterFull) return 'Kadro doldu';
    if (isCapacityFull) return 'Kadro doldu';
    if (!applicationsOpen || isDeadlinePassed) {
      return 'Başvurular kapandı';
    }
    if (user != null && !isEligible(user, follows: follows)) {
      return audience == 'followers'
          ? 'Yalnızca takipçiler başvurabilir'
          : 'Bu etkinliğe başvuramazsın';
    }
    return '';
  }

  CampusEvent copyWith({
    bool? isApplied,
    int? applicantCount,
    List<EventApplication>? applications,
    DateTime? startsAt,
    DateTime? applicationDeadline,
    bool clearDeadline = false,
    bool? applicationsOpen,
    String? audience,
    int? capacity,
    String? title,
    String? description,
    String? location,
    String? imageUrl,
  }) {
    return CampusEvent(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startsAt: startsAt ?? this.startsAt,
      capacity: capacity ?? this.capacity,
      applicantCount: applicantCount ?? this.applicantCount,
      isApplied: isApplied ?? this.isApplied,
      imageUrl: imageUrl ?? this.imageUrl,
      communityId: communityId,
      communityName: communityName,
      communityLogoUrl: communityLogoUrl,
      applications: applications ?? this.applications,
      audience: audience ?? this.audience,
      applicationDeadline:
          clearDeadline ? null : (applicationDeadline ?? this.applicationDeadline),
      applicationsOpen: applicationsOpen ?? this.applicationsOpen,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'description': description,
        'location': location,
        'startsAt': startsAt.toIso8601String(),
        'capacity': capacity,
        'applicantCount': applicantCount,
        'imageUrl': imageUrl,
        'communityId': communityId,
        'communityName': communityName,
        'communityLogoUrl': communityLogoUrl,
        'applications': applications.map((a) => a.toMap()).toList(),
        'audience': audience,
        'applicationDeadline': applicationDeadline?.toIso8601String(),
        'applicationsOpen': applicationsOpen,
      };

  factory CampusEvent.fromMap(String id, Map<String, dynamic> m) {
    final appsRaw = m['applications'];
    final apps = <EventApplication>[];
    if (appsRaw is List) {
      for (final e in appsRaw) {
        if (e is Map) {
          apps.add(EventApplication.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    return CampusEvent(
      id: id,
      title: '${m['title'] ?? ''}',
      description: '${m['description'] ?? ''}',
      location: '${m['location'] ?? ''}',
      startsAt: DateTime.tryParse('${m['startsAt']}') ?? DateTime.now(),
      capacity: (m['capacity'] as num?)?.toInt() ?? 40,
      applicantCount: (m['applicantCount'] as num?)?.toInt() ?? apps.length,
      imageUrl: m['imageUrl'] as String?,
      communityId: m['communityId'] as String?,
      communityName: m['communityName'] as String?,
      communityLogoUrl: m['communityLogoUrl'] as String?,
      applications: apps,
      audience: '${m['audience'] ?? 'campus'}',
      applicationDeadline: m['applicationDeadline'] != null
          ? DateTime.tryParse('${m['applicationDeadline']}')
          : null,
      applicationsOpen: m['applicationsOpen'] != false,
    );
  }
}
