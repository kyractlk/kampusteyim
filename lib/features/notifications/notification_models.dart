class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.emoji,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.targetId,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String emoji;
  final String type; // like|comment|follow|repost|job|offer|community
  final DateTime createdAt;
  final String? actorId;
  final String? targetId;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        emoji: emoji,
        type: type,
        createdAt: createdAt,
        actorId: actorId,
        targetId: targetId,
        read: read ?? this.read,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'emoji': emoji,
        'type': type,
        'createdAt': createdAt.toIso8601String(),
        'actorId': actorId,
        'targetId': targetId,
        'read': read,
      };

  factory AppNotification.fromJson(String id, Map<String, dynamic> json) {
    return AppNotification(
      id: id,
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      emoji: '${json['emoji'] ?? '🔔'}',
      type: '${json['type'] ?? 'community'}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      actorId: json['actorId'] as String?,
      targetId: json['targetId'] as String?,
      read: json['read'] == true,
    );
  }
}

class NotificationCopy {
  NotificationCopy._();

  static (String title, String body, String emoji) mention(String who) =>
      ('Bahsedildin', '$who senden bahsetti', '@');

  static (String title, String body, String emoji) like(String who) =>
      ('Yeni beğeni', '$who gönderini beğendi', '❤️');

  static (String title, String body, String emoji) comment(String who) =>
      ('Yeni yorum', '$who gönderine yorum yaptı', '💬');

  static (String title, String body, String emoji) follow(String who) =>
      ('Yeni takipçi', '$who seni takip etmeye başladı', '✨');

  static (String title, String body, String emoji) repost(String who) =>
      ('Yeniden paylaşım', '$who gönderini repostladı', '🔁');

  static (String title, String body, String emoji) community(String title) =>
      ('Topluluk duyurusu', title, '📢');

  static (String title, String body, String emoji) job(String company) =>
      ('Yeni ilan', '$company yeni bir ilan paylaştı', '💼');

  /// Kullanıcıya özel ilan bildirimi.
  static (String title, String body, String emoji) jobForUser({
    required String firstName,
    required String company,
    required String jobTitle,
    required String typeLabel,
  }) {
    final who = firstName.trim().isEmpty ? 'Merhaba' : 'Merhaba $firstName';
    return (
      'Yeni $typeLabel ilanı',
      '$who, $company yeni bir $typeLabel ilanı yayınladı: $jobTitle',
      '💼',
    );
  }

  static (String title, String body, String emoji) offer(String company) =>
      ('Firma teklifi', '$company sana bir teklif gönderdi', '🎯');

  static (String title, String body, String emoji) offerForUser({
    required String firstName,
    required String company,
  }) {
    final who = firstName.trim().isEmpty ? 'Merhaba' : 'Merhaba $firstName';
    return (
      'Firma teklifi',
      '$who, $company sana özel bir teklif gönderdi.',
      '🎯',
    );
  }

  static (String title, String body, String emoji) application(String who) =>
      ('Yeni başvuru', '$who ilanına başvurdu', '📥');

  static (String title, String body, String emoji) eventApplication({
    required String who,
    required String eventTitle,
  }) =>
      ('Etkinlik başvurusu', '$who · $eventTitle etkinliğine başvurdu', '📥');

  static (String title, String body, String emoji) eventRosterFull(
          String eventTitle) =>
      ('Kadro doldu', '$eventTitle etkinliğinin kadrosu doldu', '✅');

  static (String title, String body, String emoji) eventDeadlinePassed(
          String eventTitle) =>
      (
        'Başvurular kapandı',
        '$eventTitle · son başvuru saati doldu, bekleyenler iptal edildi',
        '⏰'
      );

  static (String title, String body, String emoji) eventDeadlineExtended({
    required String eventTitle,
    required String untilLabel,
  }) =>
      (
        'Başvuru uzatıldı',
        '$eventTitle · son başvuru $untilLabel olarak güncellendi',
        '🗓️'
      );

  static (String title, String body, String emoji) eventApplicationRemoved({
    required String who,
    required String eventTitle,
  }) =>
      (
        'Başvuru silindi',
        '$who · $eventTitle başvurusu silindi, kontenjan açıldı',
        '🗑️'
      );

  static (String title, String body, String emoji) eventApplicationRejected({
    required String eventTitle,
  }) =>
      (
        'Başvuru reddedildi',
        '$eventTitle etkinlik başvurun reddedildi',
        '❌'
      );

  static (String title, String body, String emoji) eventApplicationApproved({
    required String eventTitle,
  }) =>
      (
        'Başvuru onaylandı',
        '$eventTitle etkinlik başvurun onaylandı',
        '🎉'
      );

  static (String title, String body, String emoji) eventApplicationCancelled({
    required String eventTitle,
  }) =>
      (
        'Başvuru iptal',
        '$eventTitle · son başvuru saati dolduğu için başvurun iptal edildi',
        '⏰'
      );

  static (String title, String body, String emoji) followActivity({
    required String who,
    required String snippet,
  }) =>
      (
        'Takip ettiğin paylaşım',
        '$who: $snippet',
        '✨',
      );
}
