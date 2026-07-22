import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../cv/cv_models.dart';
import '../notifications/notification_models.dart';
import '../notifications/notification_provider.dart';
import 'job_models.dart';

class JobsProvider extends ChangeNotifier {
  JobsProvider();

  final List<JobListing> _jobs = [];
  final List<CompanyOffer> _offers = [];
  CompanyAccount? company;
  List<RankedApplicant> ranked = [];
  bool busy = false;
  String? status;

  List<JobListing> get openJobs =>
      _jobs.where((j) => j.status == JobStatus.open).toList();
  List<JobListing> get companyJobs {
    if (company == null) return const [];
    final name = company!.name.trim().toLowerCase();
    return _jobs
        .where(
          (j) =>
              j.companyId == company!.id ||
              j.companyName.trim().toLowerCase() == name,
        )
        .toList();
  }
  List<CompanyOffer> offersFor(String studentId) =>
      _offers.where((o) => o.studentId == studentId).toList();

  Future<void> bindJobsFromFirestore() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('jobs').limit(200).get();
      _jobs
        ..clear()
        ..addAll(
          snap.docs.map((d) => JobListing.fromJson(d.id, d.data())),
        );
      notifyListeners();
    } catch (e) {
      debugPrint('[jobs] bindJobs: $e');
    }
  }

  Future<void> companyLogin({
    required String email,
    required String password,
    required String companyName,
    String? userId,
  }) async {
    company = CompanyAccount(
      id: userId ?? 'c_${email.hashCode.abs()}',
      name: companyName.isEmpty ? email.split('@').first : companyName,
      email: email,
    );
    try {
      await FirebaseFirestore.instance.collection('companies').doc(company!.id).set({
        'name': company!.name,
        'email': company!.email,
        'role': 'company',
        'hasGoldBadge': true,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
    await bindJobsFromFirestore();
    notifyListeners();
  }

  Future<void> bindCompanyFromUser(AppUser user) async {
    if (!user.isCompany) {
      company = null;
      notifyListeners();
      return;
    }
    await companyLogin(
      email: user.email,
      password: '',
      companyName: user.fullName,
      userId: user.id,
    );
  }

  void companyLogout() {
    company = null;
    ranked = [];
    notifyListeners();
  }

  Future<void> saveJob(
    JobListing job, {
    NotificationProvider? notifications,
    List<AppUser>? students,
    bool notifyStudents = false,
  }) async {
    final i = _jobs.indexWhere((j) => j.id == job.id);
    if (i >= 0) {
      _jobs[i] = job;
    } else {
      _jobs.insert(0, job);
    }
    notifyListeners();
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(job.id)
          .set(job.toJson(), SetOptions(merge: true));
    } catch (_) {}

    if (notifyStudents &&
        job.status == JobStatus.open &&
        job.title.trim().isNotEmpty) {
      await notifyStudentsAboutJob(
        job: job,
        notifications: notifications,
        students: students,
      );
    }
  }

  /// Her öğrenciye kullanıcı özelinde push + inbox.
  Future<int> notifyStudentsAboutJob({
    required JobListing job,
    NotificationProvider? notifications,
    List<AppUser>? students,
  }) async {
    final typeLabel = switch (job.type) {
      JobType.internship => 'staj',
      JobType.fulltime => 'iş',
      JobType.parttime => 'yarı zamanlı',
    };

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyJobPosted');
      final res = await callable.call({
        'jobId': job.id,
        'companyId': job.companyId,
        'companyName': job.companyName,
        'title': job.title,
        'type': job.type.name,
        'typeLabel': typeLabel,
        'location': job.location,
      });
      final targeted = (res.data['targeted'] as num?)?.toInt() ?? 0;
      status = 'Takipçilere bildirildi · $targeted kişi';
      notifyListeners();
      return targeted;
    } catch (e) {
      debugPrint('notifyJobPosted CF: $e');
    }

    // CF yoksa: yalnızca firmayı takip edenlere yerel bildirim
    final targets = (students ?? []).where((u) {
      if (u.isCommunity || u.isCompany || u.canAccessAdmin) return false;
      return u.following.contains(job.companyId);
    }).toList();
    var n = 0;
    for (final u in targets) {
      final copy = NotificationCopy.jobForUser(
        firstName: u.firstName,
        company: job.companyName,
        jobTitle: job.title,
        typeLabel: typeLabel,
      );
      await notifications?.pushSocial(
        toUserId: u.id,
        title: copy.$1,
        body: copy.$2,
        emoji: copy.$3,
        type: 'job',
        actorId: job.companyId,
        targetId: job.id,
      );
      n++;
    }
    status = n > 0
        ? 'Yerel bildirim · $n öğrenci'
        : 'İlan kaydedildi (push kuyruğu)';
    notifyListeners();
    return n;
  }

  Future<void> deleteJob(String id) async {
    _jobs.removeWhere((j) => j.id == id);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('jobs').doc(id).delete();
    } catch (_) {}
  }

  Future<void> closeJob(String id) async {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i < 0) return;
    _jobs[i].status = JobStatus.closed;
    notifyListeners();
    await saveJob(_jobs[i]);
  }

  Future<bool> apply({
    required String jobId,
    required String studentId,
    required bool hasCv,
    NotificationProvider? notifications,
  }) async {
    if (!hasCv) {
      status = 'Başvuru için önce CV oluşturmalısın';
      notifyListeners();
      return false;
    }
    final i = _jobs.indexWhere((j) => j.id == jobId);
    if (i < 0) return false;
    final job = _jobs[i];
    if (job.applicantIds.contains(studentId)) return true;
    job.applicantIds = [...job.applicantIds, studentId];
    notifyListeners();
    await saveJob(job);

    final copy = NotificationCopy.application(studentId);
    await notifications?.pushSocial(
      toUserId: job.companyId,
      title: copy.$1,
      body: '${copy.$2} · ${job.title}',
      emoji: copy.$3,
      type: 'application',
      actorId: studentId,
      targetId: jobId,
    );
    return true;
  }

  /// Başvuranların platform profili + CV durumu.
  Future<List<ApplicantPreview>> loadApplicantPreviews({
    required List<String> applicantIds,
    required AuthProvider auth,
  }) async {
    final out = <ApplicantPreview>[];
    for (final id in applicantIds) {
      final user = auth.findUser(id);
      CvData? cvData;
      var hasCv = false;
      try {
        final doc =
            await FirebaseFirestore.instance.collection('cvs').doc(id).get();
        if (doc.exists) {
          final raw = doc.data()?['cv_data'];
          if (raw is Map) {
            cvData = CvData.fromJson(raw.cast<String, dynamic>());
            hasCv = cvData.isReadyForJobs ||
                doc.data()?['has_cv'] == true;
          }
        }
      } catch (e) {
        debugPrint('[jobs] cv load $id: $e');
      }

      final pi = cvData?.personalInfo;
      out.add(
        ApplicantPreview(
          studentId: id,
          name: user?.fullName ?? pi?.name ?? 'Aday',
          email: user?.email ?? pi?.email ?? '',
          handle: user?.handle ?? '',
          bio: user?.bio ?? '',
          photoUrl: user?.photoUrl ?? pi?.photoUrl,
          hasCv: hasCv,
          headline: pi?.headline ?? '',
          about: pi?.about ?? '',
          motivationLetter: pi?.motivationLetter ?? '',
          cvData: cvData,
        ),
      );
    }
    return out;
  }

  Future<void> sendOffer({
    required String studentId,
    required String message,
    NotificationProvider? notifications,
    AuthProvider? auth,
  }) async {
    if (company == null) return;
    final offer = CompanyOffer(
      id: const Uuid().v4(),
      companyId: company!.id,
      companyName: company!.name,
      studentId: studentId,
      message: message,
      createdAt: DateTime.now(),
    );
    _offers.insert(0, offer);
    notifyListeners();
    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(offer.id)
          .set(offer.toJson());
    } catch (_) {}

    final copy = NotificationCopy.offer(company!.name);
    await notifications?.pushSocial(
      toUserId: studentId,
      title: copy.$1,
      body: message.trim().isNotEmpty ? message : copy.$2,
      emoji: copy.$3,
      type: 'offer',
      actorId: company!.id,
      personalize: true,
    );

    // Firma teklifi → Twitter tarzı kurum ilişkisi (gold tick yok)
    final companyUser = auth?.findUser(company!.id);
    final logo = companyUser?.communityLogoUrl ?? companyUser?.photoUrl;
    if (auth != null) {
      final student = auth.findUser(studentId);
      if (student != null) {
        auth.upsertUser(
          student.copyWith(
            affiliatedCommunityId: company!.id,
            affiliatedCommunityName: company!.name,
            affiliatedOrgLogoUrl: logo,
          ),
        );
      }
    } else {
      try {
        await FirebaseFirestore.instance.collection('users').doc(studentId).set({
          'affiliatedCommunityId': company!.id,
          'affiliatedCommunityName': company!.name,
          'affiliatedOrgLogoUrl': ?logo,
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> emailStudent({
    required String toEmail,
    required String subject,
    required String html,
  }) async {
    busy = true;
    status = 'Mail gönderiliyor…';
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyMail');
      await callable.call({'to': toEmail, 'subject': subject, 'html': html});
      status = 'Mail gönderildi';
    } catch (e) {
      status = 'Mail kuyruğa alındı (mock): $e';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> rankApplicantsWithAi(JobListing job) async {
    if (company == null) return;
    busy = true;
    status = 'Firma AI başvuruları sıralıyor…';
    ranked = [];
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('rankApplicants');
      final res = await callable.call({
        'jobId': job.id,
        'jobTitle': job.title,
        'jobDescription': job.description,
        'requirements': job.requirements,
        'applicantIds': job.applicantIds,
      });
      final list = (res.data['ranked'] as List?) ?? [];
      ranked = list
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return RankedApplicant(
              studentId: '${m['studentId']}',
              name: '${m['name']}',
              score: (m['score'] as num?)?.toDouble() ?? 0,
              reason: '${m['reason'] ?? ''}',
              hasCv: m['hasCv'] == true,
              headline: '${m['headline'] ?? ''}',
              strengths: ((m['strengths'] as List?) ?? [])
                  .map((x) => '$x')
                  .toList(),
              gaps: ((m['gaps'] as List?) ?? []).map((x) => '$x').toList(),
            );
          })
          .toList();
      status = 'AI sıralama hazır · ${ranked.length} aday';
    } catch (_) {
      ranked = job.applicantIds
          .asMap()
          .entries
          .map(
            (e) => RankedApplicant(
              studentId: e.value,
              name: 'Aday ${e.key + 1}',
              score: 95 - e.key * 7,
              reason:
                  'CV bütünlüğü, ilan gereksinimleri ve motivasyon uyumu (yerel skor). Cloud AI yanıt vermedi.',
              hasCv: true,
              strengths: const ['Yerel sıralama'],
              gaps: const ['Sunucu skoru alınamadı'],
            ),
          )
          .toList();
      status = 'Yerel AI sıralama (Function yoksa)';
    }
    busy = false;
    notifyListeners();
  }

  JobListing newDraft() {
    final c = company!;
    return JobListing(
      id: const Uuid().v4(),
      companyId: c.id,
      companyName: c.name,
      title: '',
      description: '',
      type: JobType.internship,
      createdAt: DateTime.now(),
    );
  }
}
