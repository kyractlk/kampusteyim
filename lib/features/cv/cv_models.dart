class CvPersonalInfo {
  CvPersonalInfo({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.linkedin = '',
    this.github = '',
    this.website = '',
    this.about = '',
    this.motivationLetter = '',
    this.department = '',
    this.classYear = '',
    this.studentNo = '',
    this.photoUrl = '',
    this.headline = '',
  });

  String name;
  String email;
  String phone;
  String address;
  String linkedin;
  String github;
  String website;
  String about;
  /// Hakkımda özetinin altında motivasyon mektubu.
  String motivationLetter;
  String department;
  String classYear;
  String studentNo;
  /// Kullanıcı profil / CV fotoğrafı (URL).
  String photoUrl;
  String headline;

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'linkedin': linkedin,
        'github': github,
        'website': website,
        'about': about,
        'motivation_letter': motivationLetter,
        'department': department,
        'class': classYear,
        'studentNo': studentNo,
        'photoUrl': photoUrl,
        'headline': headline,
      };

  factory CvPersonalInfo.fromJson(Map<String, dynamic>? json) {
    json ??= {};
    return CvPersonalInfo(
      name: '${json['name'] ?? ''}',
      email: '${json['email'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      address: '${json['address'] ?? ''}',
      linkedin: '${json['linkedin'] ?? ''}',
      github: '${json['github'] ?? ''}',
      website: '${json['website'] ?? ''}',
      about: '${json['about'] ?? ''}',
      motivationLetter:
          '${json['motivation_letter'] ?? json['motivationLetter'] ?? ''}',
      department: '${json['department'] ?? ''}',
      classYear: '${json['class'] ?? ''}',
      studentNo: '${json['studentNo'] ?? ''}',
      photoUrl: '${json['photoUrl'] ?? json['photo_url'] ?? ''}',
      headline: '${json['headline'] ?? json['title'] ?? ''}',
    );
  }
}

class CvEducation {
  CvEducation({
    required this.id,
    this.school = '',
    this.degree = '',
    this.field = '',
    this.startDate = '',
    this.endDate = '',
    this.gpa = '',
    this.description = '',
  });

  final String id;
  String school;
  String degree;
  String field;
  String startDate;
  String endDate;
  String gpa;
  String description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'school': school,
        'degree': degree,
        'field': field,
        'startDate': startDate,
        'endDate': endDate,
        'gpa': gpa,
        'description': description,
      };

  factory CvEducation.fromJson(Map<String, dynamic> json) => CvEducation(
        id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        school: '${json['school'] ?? ''}',
        degree: '${json['degree'] ?? ''}',
        field: '${json['field'] ?? ''}',
        startDate: '${json['startDate'] ?? ''}',
        endDate: '${json['endDate'] ?? ''}',
        gpa: '${json['gpa'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

class CvExperience {
  CvExperience({
    required this.id,
    this.company = '',
    this.position = '',
    this.startDate = '',
    this.endDate = '',
    this.description = '',
  });

  final String id;
  String company;
  String position;
  String startDate;
  String endDate;
  String description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'position': position,
        'startDate': startDate,
        'endDate': endDate,
        'description': description,
      };

  factory CvExperience.fromJson(Map<String, dynamic> json) => CvExperience(
        id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        company: '${json['company'] ?? ''}',
        position: '${json['position'] ?? ''}',
        startDate: '${json['startDate'] ?? ''}',
        endDate: '${json['endDate'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

class CvProject {
  CvProject({
    required this.id,
    this.name = '',
    this.description = '',
    this.technologies = '',
    this.link = '',
  });

  final String id;
  String name;
  String description;
  String technologies;
  String link;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'technologies': technologies,
        'link': link,
      };

  factory CvProject.fromJson(Map<String, dynamic> json) => CvProject(
        id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        name: '${json['name'] ?? ''}',
        description: '${json['description'] ?? ''}',
        technologies: '${json['technologies'] ?? ''}',
        link: '${json['link'] ?? ''}',
      );
}

class CvSkill {
  CvSkill({
    required this.id,
    this.name = '',
    this.level = 'Intermediate',
  });

  final String id;
  String name;
  String level;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'level': level,
      };

  factory CvSkill.fromJson(Map<String, dynamic> json) => CvSkill(
        id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        name: '${json['name'] ?? ''}',
        level: '${json['level'] ?? 'Intermediate'}',
      );
}

class CvLanguage {
  CvLanguage({
    required this.id,
    this.language = '',
    this.level = 'B1',
  });

  final String id;
  String language;
  String level;

  Map<String, dynamic> toJson() => {
        'id': id,
        'language': language,
        'level': level,
      };

  factory CvLanguage.fromJson(Map<String, dynamic> json) => CvLanguage(
        id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
        language: '${json['language'] ?? ''}',
        level: '${json['level'] ?? 'B1'}',
      );
}

class CvData {
  CvData({
    CvPersonalInfo? personalInfo,
    List<CvEducation>? education,
    List<CvExperience>? experiences,
    List<CvProject>? projects,
    List<CvSkill>? skills,
    List<CvLanguage>? languages,
    this.rawNotes = '',
  })  : personalInfo = personalInfo ?? CvPersonalInfo(),
        education = education ?? [],
        experiences = experiences ?? [],
        projects = projects ?? [],
        skills = skills ?? [],
        languages = languages ?? [];

  CvPersonalInfo personalInfo;
  List<CvEducation> education;
  List<CvExperience> experiences;
  List<CvProject> projects;
  List<CvSkill> skills;
  List<CvLanguage> languages;
  /// Kullanıcının serbest notları — AI yapılandırır + çevirir.
  String rawNotes;

  /// Staj-AI / başvuru için yeterli CV içeriği var mı?
  bool get isReadyForJobs {
    final hasIdentity =
        personalInfo.name.trim().isNotEmpty && personalInfo.email.trim().isNotEmpty;
    final hasSummary = personalInfo.about.trim().length >= 30;
    final hasNotes = rawNotes.trim().length >= 40;
    final hasBody = education.isNotEmpty ||
        experiences.isNotEmpty ||
        skills.length >= 2 ||
        projects.isNotEmpty ||
        hasNotes;
    return hasIdentity && (hasSummary || hasBody);
  }

  Map<String, dynamic> toJson() => {
        'personal_info': personalInfo.toJson(),
        'education': education.map((e) => e.toJson()).toList(),
        'experiences': experiences.map((e) => e.toJson()).toList(),
        'projects': projects.map((e) => e.toJson()).toList(),
        'skills': skills.map((e) => e.toJson()).toList(),
        'languages': languages.map((e) => e.toJson()).toList(),
        'raw_notes': rawNotes,
      };

  factory CvData.fromJson(Map<String, dynamic>? json) {
    json ??= {};
    return CvData(
      personalInfo: CvPersonalInfo.fromJson(
        (json['personal_info'] as Map?)?.cast<String, dynamic>(),
      ),
      education: ((json['education'] as List?) ?? [])
          .map((e) => CvEducation.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      experiences: ((json['experiences'] as List?) ?? [])
          .map((e) => CvExperience.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      projects: ((json['projects'] as List?) ?? [])
          .map((e) => CvProject.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      skills: ((json['skills'] as List?) ?? [])
          .map((e) => CvSkill.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      languages: ((json['languages'] as List?) ?? [])
          .map((e) => CvLanguage.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      rawNotes: '${json['raw_notes'] ?? json['rawNotes'] ?? ''}',
    );
  }
}

class CvExportMeta {
  const CvExportMeta({
    required this.id,
    required this.languageCode,
    required this.languageName,
    required this.createdAt,
    required this.polished,
  });

  final String id;
  final String languageCode;
  final String languageName;
  final String createdAt;
  final Map<String, dynamic> polished;
}

class CvLanguageOption {
  const CvLanguageOption(this.code, this.name);
  final String code;
  final String name;
}

/// Dünya dilleri — resmi ATS çıktı dili (tam çeviri hedefi)
const kCvWorldLanguages = <CvLanguageOption>[
  CvLanguageOption('tr', 'Türkçe (ATS)'),
  CvLanguageOption('en', 'English (ATS)'),
  CvLanguageOption('de', 'Deutsch (ATS)'),
  CvLanguageOption('fr', 'Français (ATS)'),
  CvLanguageOption('ar', 'العربية (ATS)'),
  CvLanguageOption('es', 'Español (ATS)'),
  CvLanguageOption('it', 'Italiano (ATS)'),
  CvLanguageOption('pt', 'Português (ATS)'),
  CvLanguageOption('ru', 'Русский (ATS)'),
  CvLanguageOption('zh', '中文 · 简体 (ATS)'),
  CvLanguageOption('ja', '日本語 (ATS)'),
  CvLanguageOption('ko', '한국어 (ATS)'),
  CvLanguageOption('nl', 'Nederlands (ATS)'),
  CvLanguageOption('pl', 'Polski (ATS)'),
  CvLanguageOption('sv', 'Svenska (ATS)'),
  CvLanguageOption('no', 'Norsk (ATS)'),
  CvLanguageOption('da', 'Dansk (ATS)'),
  CvLanguageOption('fi', 'Suomi (ATS)'),
  CvLanguageOption('el', 'Ελληνικά (ATS)'),
  CvLanguageOption('he', 'עברית (ATS)'),
  CvLanguageOption('hi', 'हिन्दी (ATS)'),
  CvLanguageOption('id', 'Bahasa Indonesia (ATS)'),
  CvLanguageOption('ms', 'Bahasa Melayu (ATS)'),
  CvLanguageOption('th', 'ไทย (ATS)'),
  CvLanguageOption('vi', 'Tiếng Việt (ATS)'),
  CvLanguageOption('uk', 'Українська (ATS)'),
  CvLanguageOption('cs', 'Čeština (ATS)'),
  CvLanguageOption('ro', 'Română (ATS)'),
  CvLanguageOption('hu', 'Magyar (ATS)'),
  CvLanguageOption('bg', 'Български (ATS)'),
];
