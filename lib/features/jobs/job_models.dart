import '../cv/cv_models.dart';

enum JobType { internship, fulltime, parttime }

enum JobStatus { open, closed }

enum JobWorkMode { onsite, hybrid, remote }

class JobListing {
  JobListing({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.title,
    required this.description,
    required this.type,
    required this.createdAt,
    this.location = 'Gaziantep',
    this.requirements = '',
    this.department = '',
    this.workMode = JobWorkMode.onsite,
    this.tags = const [],
    this.deadline,
    this.status = JobStatus.open,
    this.applicantIds = const [],
  });

  final String id;
  final String companyId;
  final String companyName;
  String title;
  String description;
  String location;
  String requirements;
  String department;
  JobWorkMode workMode;
  List<String> tags;
  DateTime? deadline;
  JobType type;
  JobStatus status;
  DateTime createdAt;
  List<String> applicantIds;

  bool get isExpired {
    final d = deadline;
    if (d == null) return false;
    final today = DateTime.now();
    final end = DateTime(d.year, d.month, d.day, 23, 59, 59);
    return today.isAfter(end);
  }

  String get typeLabel => switch (type) {
        JobType.internship => 'Staj',
        JobType.fulltime => 'Tam zamanlı',
        JobType.parttime => 'Part-time',
      };

  String get workModeLabel => switch (workMode) {
        JobWorkMode.onsite => 'Ofis',
        JobWorkMode.hybrid => 'Hibrit',
        JobWorkMode.remote => 'Uzaktan',
      };

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'companyName': companyName,
        'title': title,
        'description': description,
        'location': location,
        'requirements': requirements,
        'department': department,
        'workMode': workMode.name,
        'tags': tags,
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
        'type': type.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'applicantIds': applicantIds,
      };

  factory JobListing.fromJson(String id, Map<String, dynamic> json) {
    return JobListing(
      id: id,
      companyId: '${json['companyId']}',
      companyName: '${json['companyName']}',
      title: '${json['title']}',
      description: '${json['description']}',
      location: '${json['location'] ?? ''}',
      requirements: '${json['requirements'] ?? ''}',
      department: '${json['department'] ?? ''}',
      workMode: JobWorkMode.values.firstWhere(
        (e) => e.name == json['workMode'],
        orElse: () => JobWorkMode.onsite,
      ),
      tags: ((json['tags'] as List?) ?? [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      deadline: DateTime.tryParse('${json['deadline'] ?? ''}'),
      type: JobType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => JobType.internship,
      ),
      status: JobStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => JobStatus.open,
      ),
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      applicantIds: ((json['applicantIds'] as List?) ?? [])
          .map((e) => '$e')
          .toList(),
    );
  }
}

class CompanyOffer {
  const CompanyOffer({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.studentId,
    required this.message,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String studentId;
  final String message;
  final DateTime createdAt;
  final bool read;

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'companyName': companyName,
        'studentId': studentId,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'read': read,
      };

  factory CompanyOffer.fromJson(String id, Map<String, dynamic> json) {
    return CompanyOffer(
      id: id,
      companyId: '${json['companyId']}',
      companyName: '${json['companyName']}',
      studentId: '${json['studentId']}',
      message: '${json['message'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      read: json['read'] == true,
    );
  }
}

class CompanyMailSignature {
  const CompanyMailSignature({
    this.logoUrl = '',
    this.contactName = '',
    this.jobTitle = '',
    this.replyEmail = '',
    this.phone = '',
    this.website = '',
    this.address = '',
    this.extraText = '',
    this.configured = false,
  });

  final String logoUrl;
  final String contactName;
  final String jobTitle;
  final String replyEmail;
  final String phone;
  final String website;
  final String address;
  final String extraText;
  final bool configured;

  bool get isReady =>
      configured &&
      logoUrl.trim().isNotEmpty &&
      contactName.trim().isNotEmpty &&
      replyEmail.trim().contains('@');

  CompanyMailSignature copyWith({
    String? logoUrl,
    String? contactName,
    String? jobTitle,
    String? replyEmail,
    String? phone,
    String? website,
    String? address,
    String? extraText,
    bool? configured,
  }) {
    return CompanyMailSignature(
      logoUrl: logoUrl ?? this.logoUrl,
      contactName: contactName ?? this.contactName,
      jobTitle: jobTitle ?? this.jobTitle,
      replyEmail: replyEmail ?? this.replyEmail,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      address: address ?? this.address,
      extraText: extraText ?? this.extraText,
      configured: configured ?? this.configured,
    );
  }

  Map<String, dynamic> toJson() => {
        'logoUrl': logoUrl,
        'contactName': contactName,
        'jobTitle': jobTitle,
        'replyEmail': replyEmail,
        'phone': phone,
        'website': website,
        'address': address,
        'extraText': extraText,
        'configured': configured,
      };

  factory CompanyMailSignature.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CompanyMailSignature();
    return CompanyMailSignature(
      logoUrl: '${json['logoUrl'] ?? ''}',
      contactName: '${json['contactName'] ?? ''}',
      jobTitle: '${json['jobTitle'] ?? ''}',
      replyEmail: '${json['replyEmail'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      website: '${json['website'] ?? ''}',
      address: '${json['address'] ?? ''}',
      extraText: '${json['extraText'] ?? ''}',
      configured: json['configured'] == true,
    );
  }
}

class CompanyAccount {
  const CompanyAccount({
    required this.id,
    required this.name,
    required this.email,
    this.sector = 'Teknoloji',
    this.logoUrl = '',
    this.mailSignature = const CompanyMailSignature(),
  });

  final String id;
  final String name;
  final String email;
  final String sector;
  final String logoUrl;
  final CompanyMailSignature mailSignature;

  bool get hasMailSignature => mailSignature.isReady;

  String get displayLogoUrl =>
      mailSignature.logoUrl.trim().isNotEmpty
          ? mailSignature.logoUrl
          : logoUrl;

  CompanyAccount copyWith({
    String? name,
    String? email,
    String? sector,
    String? logoUrl,
    CompanyMailSignature? mailSignature,
  }) {
    return CompanyAccount(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      sector: sector ?? this.sector,
      logoUrl: logoUrl ?? this.logoUrl,
      mailSignature: mailSignature ?? this.mailSignature,
    );
  }
}

class RankedApplicant {
  const RankedApplicant({
    required this.studentId,
    required this.name,
    required this.score,
    required this.reason,
    this.hasCv = false,
    this.headline = '',
    this.strengths = const [],
    this.gaps = const [],
  });

  final String studentId;
  final String name;
  final double score;
  final String reason;
  final bool hasCv;
  final String headline;
  final List<String> strengths;
  final List<String> gaps;
}

/// Firma panelinde başvuran özeti.
class ApplicantPreview {
  const ApplicantPreview({
    required this.studentId,
    required this.name,
    required this.email,
    this.handle = '',
    this.bio = '',
    this.photoUrl,
    this.hasCv = false,
    this.headline = '',
    this.about = '',
    this.motivationLetter = '',
    this.cvData,
  });

  final String studentId;
  final String name;
  final String email;
  final String handle;
  final String bio;
  final String? photoUrl;
  final bool hasCv;
  final String headline;
  final String about;
  final String motivationLetter;
  final CvData? cvData;
}
