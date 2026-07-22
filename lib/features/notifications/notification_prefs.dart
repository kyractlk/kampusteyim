/// Kullanıcı bildirim / izin tercihleri.
class NotificationPrefs {
  const NotificationPrefs({
    this.pushEnabled = true,
    this.likes = true,
    this.comments = true,
    this.follows = true,
    this.reposts = true,
    this.mentions = true,
    this.jobs = true,
    this.offers = true,
    this.community = true,
    this.activity = true,
    this.admin = true,
  });

  final bool pushEnabled;
  final bool likes;
  final bool comments;
  final bool follows;
  final bool reposts;
  final bool mentions;
  final bool jobs;
  final bool offers;
  final bool community;
  /// Takip edilen hesapların yeni gönderi / hareket bildirimleri.
  final bool activity;
  final bool admin;

  static const defaults = NotificationPrefs();

  bool allowsType(String type) {
    if (!pushEnabled) return false;
    switch (type) {
      case 'like':
        return likes;
      case 'comment':
        return comments;
      case 'follow':
        return follows;
      case 'repost':
        return reposts;
      case 'mention':
        return mentions;
      case 'job':
      case 'application':
        return jobs;
      case 'offer':
        return offers;
      case 'community':
        return community;
      case 'activity':
        return activity;
      case 'admin_broadcast':
        return admin;
      default:
        return pushEnabled;
    }
  }

  NotificationPrefs copyWith({
    bool? pushEnabled,
    bool? likes,
    bool? comments,
    bool? follows,
    bool? reposts,
    bool? mentions,
    bool? jobs,
    bool? offers,
    bool? community,
    bool? activity,
    bool? admin,
  }) {
    return NotificationPrefs(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      follows: follows ?? this.follows,
      reposts: reposts ?? this.reposts,
      mentions: mentions ?? this.mentions,
      jobs: jobs ?? this.jobs,
      offers: offers ?? this.offers,
      community: community ?? this.community,
      activity: activity ?? this.activity,
      admin: admin ?? this.admin,
    );
  }

  Map<String, dynamic> toJson() => {
        'pushEnabled': pushEnabled,
        'likes': likes,
        'comments': comments,
        'follows': follows,
        'reposts': reposts,
        'mentions': mentions,
        'jobs': jobs,
        'offers': offers,
        'community': community,
        'activity': activity,
        'admin': admin,
      };

  factory NotificationPrefs.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    bool b(String k, [bool d = true]) => json[k] is bool ? json[k] as bool : d;
    return NotificationPrefs(
      pushEnabled: b('pushEnabled'),
      likes: b('likes'),
      comments: b('comments'),
      follows: b('follows'),
      reposts: b('reposts'),
      mentions: b('mentions'),
      jobs: b('jobs'),
      offers: b('offers'),
      community: b('community'),
      activity: b('activity'),
      admin: b('admin'),
    );
  }
}
