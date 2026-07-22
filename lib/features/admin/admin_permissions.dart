/// Platform admin yetkileri — string key ile parse edilir.
enum AdminPermission {
  manageUsers(
    'manage_users',
    'Kullanıcıları görüntüle / düzenle',
    'Kullanıcılar',
  ),
  manageBadges(
    'manage_badges',
    'Gold / mavi badge ver-al',
    'Kullanıcılar',
  ),
  restrictUsers(
    'restrict_users',
    'Ban / paylaşım yasağı uygula',
    'Moderasyon',
  ),
  resetPassword(
    'reset_password',
    'Şifre sıfırlama bağlantısı gönder',
    'Kullanıcılar',
  ),
  reviewReports(
    'review_reports',
    'Şikayetleri incele ve sonuçlandır',
    'Moderasyon',
  ),
  viewPosts(
    'view_posts',
    'Tüm paylaşımları görüntüle',
    'İçerik',
  ),
  createCompany(
    'create_company',
    'Firma hesabı aç',
    'Hesaplar',
  ),
  createCommunity(
    'create_community',
    'Topluluk hesabı aç',
    'Hesaplar',
  ),
  manageRoles(
    'manage_roles',
    'Yeni rol oluştur / yetki seç',
    'Yönetim',
  ),
  manageAdmins(
    'manage_admins',
    'Admin ekle ve rol ata',
    'Yönetim',
  ),
  sendBroadcast(
    'send_broadcast',
    'Seçili / tüm kullanıcılara push gönder',
    'Bildirim',
  ),
  manageMaintenance(
    'manage_maintenance',
    'AYS Tech bakım modu planla / bitir',
    'Sistem',
  ),
  accessDuringMaintenance(
    'access_during_maintenance',
    'Bakım sırasında uygulamaya / admin paneline eriş',
    'Sistem',
  ),
  moderateFeed(
    'moderate_feed',
    'Akışta gönderi sil / kullanıcıyı sustur',
    'Moderasyon',
  ),
  reviewFeedback(
    'review_feedback',
    'Kullanıcı geri bildirimlerini incele',
    'Sistem',
  ),
  reviewStudyRooms(
    'review_study_rooms',
    'Çalışma odası ve chat kayıtlarını incele',
    'Sistem',
  ),
  manageLegalTexts(
    'manage_legal_texts',
    'KVKK ve pazarlama metinlerini düzenle',
    'Sistem',
  );

  const AdminPermission(this.key, this.label, this.group);

  final String key;
  final String label;
  final String group;

  /// Tek yetki parse: `manage_users`, `manageUsers`, `ManageUsers` kabul eder.
  static AdminPermission? tryParse(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final normalized = s
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .toLowerCase();
    for (final p in AdminPermission.values) {
      if (p.key == normalized || p.name.toLowerCase() == normalized) {
        return p;
      }
    }
    // camelCase → snake: manageUsers → manage_users
    final snake = normalized.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]}_${m[2]!.toLowerCase()}',
    );
    for (final p in AdminPermission.values) {
      if (p.key == snake) return p;
    }
    return null;
  }

  static AdminPermission parse(String raw) {
    final p = tryParse(raw);
    if (p == null) {
      throw FormatException('Bilinmeyen admin yetkisi: $raw');
    }
    return p;
  }

  /// Liste / CSV / JSON dizi parse.
  static Set<AdminPermission> parseMany(dynamic raw) {
    if (raw == null) return {};
    final items = <String>[];
    if (raw is String) {
      items.addAll(
        raw.split(RegExp(r'[,|;]')).map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    } else if (raw is Iterable) {
      for (final e in raw) {
        items.add('$e');
      }
    }
    final out = <AdminPermission>{};
    for (final item in items) {
      final p = tryParse(item);
      if (p != null) out.add(p);
    }
    return out;
  }

  static List<String> keysOf(Iterable<AdminPermission> perms) =>
      perms.map((p) => p.key).toList()..sort();

  static Map<String, List<AdminPermission>> get byGroup {
    final map = <String, List<AdminPermission>>{};
    for (final p in AdminPermission.values) {
      map.putIfAbsent(p.group, () => []).add(p);
    }
    return map;
  }
}

/// Özelleştirilebilir personel rolü.
class StaffRole {
  StaffRole({
    required this.id,
    required this.name,
    required this.description,
    required this.permissions,
    this.isSystem = false,
    this.isSuper = false,
  });

  final String id;
  String name;
  String description;
  Set<AdminPermission> permissions;
  final bool isSystem;
  final bool isSuper;

  bool has(AdminPermission p) => isSuper || permissions.contains(p);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'permissions': AdminPermission.keysOf(permissions),
        'isSystem': isSystem,
        'isSuper': isSuper,
      };

  factory StaffRole.fromJson(Map<String, dynamic> json) {
    return StaffRole(
      id: '${json['id']}',
      name: '${json['name']}',
      description: '${json['description'] ?? ''}',
      permissions: AdminPermission.parseMany(json['permissions']),
      isSystem: json['isSystem'] == true,
      isSuper: json['isSuper'] == true,
    );
  }

  StaffRole copyWith({
    String? name,
    String? description,
    Set<AdminPermission>? permissions,
  }) {
    return StaffRole(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      permissions: permissions ?? Set.of(this.permissions),
      isSystem: isSystem,
      isSuper: isSuper,
    );
  }

  static List<StaffRole> defaults() => [
        StaffRole(
          id: 'role_super',
          name: 'Süper Admin',
          description: 'Tüm platform yetkileri. Silinemez.',
          permissions: {...AdminPermission.values},
          isSystem: true,
          isSuper: true,
        ),
        StaffRole(
          id: 'role_moderator',
          name: 'Moderatör',
          description: 'Şikayet, paylaşım, kısıtlama ve kullanıcı inceleme.',
          permissions: {
            AdminPermission.reviewReports,
            AdminPermission.viewPosts,
            AdminPermission.restrictUsers,
            AdminPermission.moderateFeed,
            AdminPermission.manageUsers,
            AdminPermission.sendBroadcast,
            AdminPermission.reviewStudyRooms,
            AdminPermission.accessDuringMaintenance,
          },
          isSystem: true,
        ),
        StaffRole(
          id: 'role_community_mgr',
          name: 'Topluluk Yöneticisi',
          description: 'Badge, topluluk hesabı ve içerik görünümü.',
          permissions: {
            AdminPermission.manageUsers,
            AdminPermission.manageBadges,
            AdminPermission.createCommunity,
            AdminPermission.viewPosts,
            AdminPermission.reviewReports,
            AdminPermission.moderateFeed,
            AdminPermission.sendBroadcast,
            AdminPermission.reviewStudyRooms,
            AdminPermission.accessDuringMaintenance,
          },
          isSystem: true,
        ),
        StaffRole(
          id: 'role_ops',
          name: 'Hesap Operasyon',
          description: 'Firma/topluluk hesabı ve şifre sıfırlama.',
          permissions: {
            AdminPermission.createCompany,
            AdminPermission.createCommunity,
            AdminPermission.resetPassword,
            AdminPermission.manageUsers,
            AdminPermission.accessDuringMaintenance,
          },
          isSystem: true,
        ),
        StaffRole(
          id: 'role_sysops',
          name: 'Sistem Operasyon',
          description: 'AYS Tech bakım, push ve yayın bildirimleri.',
          permissions: {
            AdminPermission.manageMaintenance,
            AdminPermission.accessDuringMaintenance,
            AdminPermission.sendBroadcast,
            AdminPermission.manageUsers,
            AdminPermission.viewPosts,
            AdminPermission.manageLegalTexts,
          },
          isSystem: true,
        ),
        StaffRole(
          id: 'role_hr_desk',
          name: 'Destek Masası',
          description: 'Kullanıcı desteği, şifre ve şikayet triyajı.',
          permissions: {
            AdminPermission.manageUsers,
            AdminPermission.resetPassword,
            AdminPermission.reviewReports,
            AdminPermission.viewPosts,
            AdminPermission.reviewFeedback,
            AdminPermission.reviewStudyRooms,
            AdminPermission.manageLegalTexts,
            AdminPermission.accessDuringMaintenance,
          },
          isSystem: true,
        ),
      ];

  /// Sistem rollerini güncel izin kataloğuna göre yeniden kurar.
  /// Özel (non-system) roller korunur; eksik yeni izinler süper role eklenir.
  static List<StaffRole> mergeWithDefaults(List<StaffRole> current) {
    final base = StaffRole.defaults();
    final custom = current.where((r) => !r.isSystem).toList();
    final byId = {for (final r in base) r.id: r};
    final out = <StaffRole>[...base];
    for (final c in custom) {
      if (!byId.containsKey(c.id)) out.add(c);
    }
    return out;
  }
}
