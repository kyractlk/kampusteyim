import '../cv/cv_models.dart';

enum JobType { internship, fulltime, parttime }

enum JobStatus { open, closed }

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
  JobType type;
  JobStatus status;
  DateTime createdAt;
  List<String> applicantIds;

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'companyName': companyName,
        'title': title,
        'description': description,
        'location': location,
        'requirements': requirements,
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
}

class CompanyAccount {
  const CompanyAccount({
    required this.id,
    required this.name,
    required this.email,
    this.sector = 'Teknoloji',
  });

  final String id;
  final String name;
  final String email;
  final String sector;
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
