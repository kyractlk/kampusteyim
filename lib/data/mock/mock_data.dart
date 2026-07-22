import '../../models/models.dart';

class MockData {
  MockData._();

  static const cities = [
    'Gaziantep',
  ];

  static const universities = [
    'Gaziantep Üniversitesi',
  ];

  static final community = AppUser(
    id: 'community',
    email: 'mt@gantep.edu.tr',
    studentNo: '000000000',
    firstName: 'Mühendislik',
    lastName: 'Topluluğu',
    phone: '',
    city: 'Gaziantep',
    university: 'Gaziantep Üniversitesi',
    bio:
        'Gaziantep Üniversitesi Mühendislik Topluluğu resmi hesabı. Duyuru, etkinlik, staj ve kampüs haberleri.',
    photoUrl: null,
    communityLogoUrl: 'assets/logos/mt_circle.png',
    links: const [
      ProfileLink(label: 'Instagram', url: 'https://instagram.com'),
      ProfileLink(label: 'Web', url: 'https://gantep.edu.tr'),
      ProfileLink(
        label: 'Profil',
        url: 'https://gaunengineering.com.tr/user/muhendislik',
      ),
    ],
    following: const [],
    followers: const ['admin', 'company_ays'],
    isCommunity: true,
    role: UserRole.community,
    hasGoldBadge: true,
    username: 'gaunmt',
    usernameStatus: 'ok',
  );

  static final admin = AppUser(
    id: 'admin',
    email: 'admin@gaunengineering.com.tr',
    studentNo: '000000001',
    firstName: 'Platform',
    lastName: 'Admin',
    phone: '',
    city: 'Gaziantep',
    university: 'Gaziantep Üniversitesi',
    bio: 'KampüsteyimAPP süper admin · tüm yetkiler açık',
    role: UserRole.admin,
    isSuperAdmin: true,
    staffRoleId: 'role_super',
    following: const ['community', 'company_ays'],
    followers: const [],
    username: 'admin',
    usernameStatus: 'ok',
    links: const [
      ProfileLink(label: 'Profil', url: 'https://gaunengineering.com.tr/user/admin'),
    ],
  );

  static final companyDemo = AppUser(
    id: 'company_ays',
    email: 'hr@aystech.com',
    studentNo: 'C00001',
    firstName: 'AYS Tech',
    lastName: '',
    phone: '',
    city: 'Gaziantep',
    university: '—',
    bio: 'Firma hesabı · staj ve iş ilanları · onaylı işveren · AYS Tech',
    role: UserRole.company,
    hasGoldBadge: true,
    username: 'aystech',
    usernameStatus: 'ok',
    communityLogoUrl: 'assets/logos/ays_circle.png',
    following: const ['community', 'ays_guard'],
    followers: const ['admin', 'ays_guard'],
    links: const [
      ProfileLink(label: 'Web', url: 'https://aystech.com.tr'),
      ProfileLink(
        label: 'Profil',
        url: 'https://gaunengineering.com.tr/user/aystech',
      ),
    ],
  );

  /// Platform AI · AYS Tech Guard
  static final aysGuard = AppUser(
    id: 'ays_guard',
    email: 'guard@aystech.com',
    studentNo: 'AI0001',
    firstName: 'AYS Tech',
    lastName: 'Guard',
    phone: '',
    city: 'Gaziantep',
    university: '—',
    bio:
        'KampüsteyimAPP platform AI’si · içerik güvenliği, moderasyon ve yardımcı asistan. '
        'AYS Tech tarafından işletilir.',
    role: UserRole.company,
    hasBlueBadge: true,
    isBot: true,
    username: 'aystechbot',
    usernameStatus: 'ok',
    communityLogoUrl: 'assets/logos/ays_guard_circle.png',
    photoUrl: 'assets/logos/ays_guard_circle.png',
    following: const ['company_ays', 'community'],
    followers: const ['admin', 'company_ays', 'community'],
    links: const [
      ProfileLink(label: 'Web', url: 'https://aystech.com.tr'),
      ProfileLink(
        label: 'Profil',
        url: 'https://gaunengineering.com.tr/user/aystechbot',
      ),
    ],
  );

  /// Kayıt formu varsayılanları (dizin listesinde yok).
  static final demoUser = AppUser(
    id: 'u_new',
    email: '',
    studentNo: '',
    firstName: '',
    lastName: '',
    phone: '',
    city: 'Gaziantep',
    university: 'Gaziantep Üniversitesi',
    bio: '',
  );

  /// Admin + MT + AYS Tech + Guard AI.
  static final users = <AppUser>[admin, community, companyDemo, aysGuard];

  static List<Post> posts() {
    final now = DateTime.now();

    return [
      Post(
        id: 'test_mt_kickoff',
        authorId: 'community',
        authorName: 'Mühendislik Topluluğu',
        authorHandle: '@gaunmt',
        content:
            'Yeni dönem kick-off Perşembe 18:30 · A Blok amfi.\n'
            'Takvimini şimdiden boşalt 👋\n'
            '#mt #kampüs #etkinlik',
        createdAt: now.subtract(const Duration(minutes: 25)),
        likeCount: 12,
        replyCount: 1,
        repostCount: 2,
        isCommunity: true,
        hashtags: const ['mt', 'kampüs', 'etkinlik'],
        media: const [
          MediaItem(
            url: 'https://picsum.photos/seed/mtkicktest/800/500',
            type: MediaType.image,
          ),
        ],
      ),
      Post(
        id: 'test_ays_staj',
        authorId: 'company_ays',
        authorName: 'AYS Tech',
        authorHandle: '@aystech',
        content:
            'Yaz staj başvuruları açıldı — Flutter & Firebase.\n'
            'Özgeçmişini CV-AI ile hazırlayıp başvurabilirsin.\n'
            '#staj #aystech #flutter',
        createdAt: now.subtract(const Duration(hours: 2)),
        likeCount: 8,
        replyCount: 0,
        repostCount: 1,
        isCommunity: false,
        hashtags: const ['staj', 'aystech', 'flutter'],
        media: const [
          MediaItem(
            url: 'https://picsum.photos/seed/aysstaj/800/500',
            type: MediaType.image,
          ),
        ],
      ),
      Post(
        id: 'test_mt_summit',
        authorId: 'community',
        authorName: 'Mühendislik Topluluğu',
        authorHandle: '@gaunmt',
        content:
            'GAÜN Tech Summit 2026 erken kayıt başladı.\n'
            'Konuşmacılar ve atölyeler yakında.\n'
            '#techsummit #gaun',
        createdAt: now.subtract(const Duration(hours: 8)),
        likeCount: 21,
        replyCount: 1,
        repostCount: 4,
        isCommunity: true,
        hashtags: const ['techsummit', 'gaun'],
        media: const [
          MediaItem(
            url: 'https://picsum.photos/seed/summittest/800/500',
            type: MediaType.image,
          ),
        ],
      ),
      Post(
        id: 'test_ays_cv',
        authorId: 'company_ays',
        authorName: 'AYS Tech',
        authorHandle: '@aystech',
        content:
            'CV-AI ile ATS uyumlu özgeçmiş: dil seç, üret, indir.\n'
            'Firma başvurularında fark yaratır.\n'
            '#cv #ats #aystech',
        createdAt: now.subtract(const Duration(days: 1)),
        likeCount: 15,
        replyCount: 0,
        repostCount: 2,
        isCommunity: false,
        hashtags: const ['cv', 'ats', 'aystech'],
      ),
      Post(
        id: 'test_mt_hackathon',
        authorId: 'community',
        authorName: 'Mühendislik Topluluğu',
        authorHandle: '@gaunmt',
        content:
            'Hackathon mentör saatleri Cumartesi 14:00–17:00.\n'
            'Takımını getir, sorunu çözelim.\n'
            '#hackathon #mt',
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
        likeCount: 9,
        replyCount: 0,
        repostCount: 1,
        isCommunity: true,
        hashtags: const ['hackathon', 'mt'],
      ),
    ];
  }

  static List<Comment> comments() {
    final now = DateTime.now();
    return [
      Comment(
        id: 'test_c1',
        postId: 'test_mt_kickoff',
        authorId: 'admin',
        authorName: 'Platform Admin',
        authorHandle: '@admin',
        content: 'Not alındı, yayındayız 🚀',
        createdAt: now.subtract(const Duration(minutes: 18)),
        likeCount: 2,
        isPinned: true,
      ),
      Comment(
        id: 'test_c2',
        postId: 'test_mt_summit',
        authorId: 'company_ays',
        authorName: 'AYS Tech',
        authorHandle: '@aystech',
        content: 'Sponsor masamız hazır — görüşmek üzere.',
        createdAt: now.subtract(const Duration(hours: 6)),
        likeCount: 3,
      ),
    ];
  }

  static List<Announcement> announcements() {
    final now = DateTime.now();
    return [
      Announcement(
        id: 'test_a_meeting',
        title: 'Üye toplantısı',
        body:
            'Dönem planı ve komite seçimleri. Detaylar toplantıda paylaşılacak.',
        createdAt: now.subtract(const Duration(hours: 3)),
        audience: 'members',
        isPinned: true,
        imageUrl: 'https://picsum.photos/seed/testmeeting/900/420',
        communityId: 'community',
        communityName: 'Mühendislik Topluluğu',
        communityLogoUrl: 'assets/logos/mt_circle.png',
      ),
      Announcement(
        id: 'test_a_mentor',
        title: 'Hackathon mentör saatleri',
        body: 'Cumartesi 14:00–17:00. Takımını getir, sorunu çözelim.',
        createdAt: now.subtract(const Duration(hours: 8)),
        audience: 'campus',
        imageUrl: 'https://picsum.photos/seed/testmentor/900/420',
        communityId: 'community',
        communityName: 'Mühendislik Topluluğu',
        communityLogoUrl: 'assets/logos/mt_circle.png',
      ),
    ];
  }

  static List<CampusEvent> events() {
    final now = DateTime.now();
    return [
      CampusEvent(
        id: 'test_e_flutter',
        title: 'Flutter Kampüs Atölyesi',
        description:
            '3 saatlik pratik workshop.',
        location: 'Müh. A Blok · Lab 204',
        startsAt: now.add(const Duration(days: 4, hours: 2)),
        capacity: 40,
        applicantCount: 1,
        imageUrl: 'https://picsum.photos/seed/testflutter/900/420',
        communityId: 'community',
        communityName: 'Mühendislik Topluluğu',
        communityLogoUrl: 'assets/logos/mt_circle.png',
        audience: 'campus',
        applicationDeadline: now.add(const Duration(days: 3)),
        applications: [
          EventApplication(
            id: 'test_ea1',
            userId: 'admin',
            userName: 'Platform Admin',
            createdAt: now.subtract(const Duration(hours: 4)),
          ),
        ],
      ),
      CampusEvent(
        id: 'test_e_hack',
        title: 'Hackathon: Kampüs Çözümleri',
        description:
            '24 saatlik takım yarışması.',
        location: 'Kongre Merkezi',
        startsAt: now.add(const Duration(days: 12)),
        capacity: 120,
        applicantCount: 0,
        imageUrl: 'https://picsum.photos/seed/testhack/900/420',
        communityId: 'community',
        communityName: 'Mühendislik Topluluğu',
        communityLogoUrl: 'assets/logos/mt_circle.png',
        audience: 'students',
        applicationDeadline: now.add(const Duration(days: 10)),
      ),
    ];
  }
}
