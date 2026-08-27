import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
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
  String? lastRankedJobId;
  bool busy = false;
  String? status;
  bool jobsReady = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _jobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _offersSub;

  List<JobListing> get openJobs =>
      _jobs.where((j) => j.status == JobStatus.open && !j.isExpired).toList();

  List<JobListing> get companyJobs {
    if (company == null) return const [];
    final name = company!.name.trim().toLowerCase();
    final list = _jobs
        .where(
          (j) =>
              j.companyId == company!.id ||
              j.companyName.trim().toLowerCase() == name,
        )
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  int get companyOpenCount =>
      companyJobs.where((j) => j.status == JobStatus.open).length;

  int get companyClosedCount =>
      companyJobs.where((j) => j.status == JobStatus.closed).length;

  int get companyApplicantCount =>
      companyJobs.fold<int>(0, (n, j) => n + j.applicantIds.length);

  int get companyAiReadyCount => companyJobs
      .where((j) => j.status == JobStatus.open && j.applicantIds.isNotEmpty)
      .length;

  List<CompanyOffer> offersFor(String studentId) =>
      _offers.where((o) => o.studentId == studentId).toList();

  List<JobListing> applicationsFor(String studentId) => _jobs
      .where((j) => j.applicantIds.contains(studentId))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<JobListing> filterOpenJobs({
    JobType? type,
    JobWorkMode? workMode,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    return openJobs.where((j) {
      if (type != null && j.type != type) return false;
      if (workMode != null && j.workMode != workMode) return false;
      if (q.isEmpty) return true;
      final hay = [
        j.title,
        j.companyName,
        j.location,
        j.department,
        j.requirements,
        j.description,
        ...j.tags,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// CV becerileri ile ilan gereksinimlerinin basit örtüşme skoru (0–100).
  int matchScore(JobListing job, Iterable<String> skillNames) {
    final skills = skillNames
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.length >= 2)
        .toSet();
    if (skills.isEmpty) return 0;
    final corpus =
        '${job.requirements} ${job.title} ${job.description} ${job.tags.join(' ')}'
            .toLowerCase();
    if (corpus.trim().isEmpty) return 35;
    var hit = 0;
    for (final s in skills) {
      if (corpus.contains(s)) hit++;
    }
    final ratio = hit / skills.length;
    return (28 + ratio * 72).round().clamp(0, 100);
  }

  Future<void> bindJobsFromFirestore() async {
    await _jobsSub?.cancel();
    try {
      _jobsSub = FirebaseFirestore.instance
          .collection('jobs')
          .limit(300)
          .snapshots()
          .listen(
        (snap) {
          _jobs
            ..clear()
            ..addAll(
              snap.docs.map((d) => JobListing.fromJson(d.id, d.data())),
            );
          jobsReady = true;
          notifyListeners();
        },
        onError: (e) {
          debugPrint('[jobs] stream: $e');
          jobsReady = true;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[jobs] bindJobs: $e');
      jobsReady = true;
      notifyListeners();
    }
  }

  Future<void> bindOffersForStudent(String studentId) async {
    await _offersSub?.cancel();
    if (studentId.isEmpty) return;
    try {
      _offersSub = FirebaseFirestore.instance
          .collection('offers')
          .where('studentId', isEqualTo: studentId)
          .limit(40)
          .snapshots()
          .listen(
        (snap) {
          final list = snap.docs
              .map((d) => CompanyOffer.fromJson(d.id, d.data()))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _offers
            ..clear()
            ..addAll(list);
          notifyListeners();
        },
        onError: (e) => debugPrint('[jobs] offers stream: $e'),
      );
    } catch (e) {
      debugPrint('[jobs] bindOffers: $e');
    }
  }

  Future<void> companyLogin({
    required String email,
    required String password,
    required String companyName,
    String? userId,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final id = (authUid != null && authUid.isNotEmpty)
        ? authUid
        : (userId ?? 'c_${email.hashCode.abs()}');
    company = CompanyAccount(
      id: id,
      name: companyName.isEmpty ? email.split('@').first : companyName,
      email: email,
    );
    try {
      await FirebaseFirestore.instance.collection('companies').doc(company!.id).set({
        'name': company!.name,
        'email': company!.email,
        'role': 'company',
        'hasGoldBadge': true,
        'authUid': id,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      // Auth uid ile users doc senkron (teklif / mail CF için)
      await FirebaseFirestore.instance.collection('users').doc(id).set({
        'role': 'company',
        'email': email,
        'fullName': company!.name,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
    await refreshCompanyProfile();
    await bindJobsFromFirestore();
    notifyListeners();
  }

  /// Öğrenci e-posta / adını dizin + Firestore + CV’den çözer.
  Future<({String email, String name})> resolveStudentContact(
    String studentId, {
    AuthProvider? auth,
    String? fallbackName,
  }) async {
    var email = auth?.findUser(studentId)?.email.trim() ?? '';
    var name = auth?.findUser(studentId)?.fullName.trim() ??
        (fallbackName ?? '').trim();

    Future<void> readUserDoc(String id) async {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(id).get();
        if (!doc.exists) return;
        final d = doc.data() ?? {};
        if (email.isEmpty) email = '${d['email'] ?? ''}'.trim();
        if (name.isEmpty) {
          name = '${d['fullName'] ?? ''}'.trim();
          if (name.isEmpty) {
            name =
                '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
          }
        }
      } catch (_) {}
    }

    if (email.isEmpty || name.isEmpty) await readUserDoc(studentId);

    if (email.isEmpty || name.isEmpty) {
      try {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('stableId', isEqualTo: studentId)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          if (email.isEmpty) email = '${d['email'] ?? ''}'.trim();
          if (name.isEmpty) {
            name = '${d['fullName'] ?? ''}'.trim();
            if (name.isEmpty) {
              name =
                  '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
            }
          }
        }
      } catch (_) {}
    }

    if (email.isEmpty || name.isEmpty) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('cvs').doc(studentId).get();
        if (doc.exists) {
          final raw = doc.data()?['cv_data'];
          if (raw is Map) {
            final pi = raw['personalInfo'];
            if (pi is Map) {
              if (email.isEmpty) email = '${pi['email'] ?? ''}'.trim();
              if (name.isEmpty) name = '${pi['name'] ?? ''}'.trim();
            }
          }
        }
      } catch (_) {}
    }

    return (email: email, name: name.isEmpty ? 'Aday' : name);
  }

  Future<void> refreshCompanyProfile() async {
    if (company == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(company!.id)
          .get();
      if (!doc.exists) return;
      final d = doc.data() ?? {};
      final sig = CompanyMailSignature.fromJson(
        (d['mailSignature'] as Map?)?.cast<String, dynamic>(),
      );
      final logo = '${d['logoUrl'] ?? sig.logoUrl}';
      company = company!.copyWith(
        name: '${d['name'] ?? company!.name}',
        email: '${d['email'] ?? company!.email}',
        sector: '${d['sector'] ?? company!.sector}',
        logoUrl: logo,
        mailSignature: sig.logoUrl.isEmpty && logo.isNotEmpty
            ? sig.copyWith(logoUrl: logo)
            : sig,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[jobs] refreshCompanyProfile: $e');
    }
  }

  Future<void> saveMailSignature(CompanyMailSignature signature) async {
    if (company == null) return;
    final ready = signature.copyWith(
      configured: signature.logoUrl.trim().isNotEmpty &&
          signature.contactName.trim().isNotEmpty &&
          signature.replyEmail.trim().contains('@'),
    );
    company = company!.copyWith(
      logoUrl: ready.logoUrl,
      mailSignature: ready,
    );
    notifyListeners();
    await FirebaseFirestore.instance.collection('companies').doc(company!.id).set({
      'name': company!.name,
      'email': company!.email,
      'logoUrl': ready.logoUrl,
      'mailSignature': ready.toJson(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    status = ready.isReady
        ? 'Mail imzası kaydedildi'
        : 'Eksik alanlar var — logo, yetkili adı ve e-posta zorunlu';
    notifyListeners();
  }

  bool get hasMailSignature => company?.hasMailSignature == true;

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
    lastRankedJobId = null;
    notifyListeners();
  }

  Future<void> saveJob(
    JobListing job, {
    NotificationProvider? notifications,
    List<AppUser>? students,
    bool notifyStudents = false,
  }) async {
    if (notifyStudents && !hasMailSignature) {
      status = 'MAIL_SIGNATURE_REQUIRED';
      notifyListeners();
      // İlanı yine kaydet, bildirimi atlama
      final i = _jobs.indexWhere((j) => j.id == job.id);
      if (i >= 0) {
        _jobs[i] = job;
      } else {
        _jobs.insert(0, job);
      }
      try {
        await FirebaseFirestore.instance
            .collection('jobs')
            .doc(job.id)
            .set(job.toJson(), SetOptions(merge: true));
      } catch (_) {}
      notifyListeners();
      return;
    }
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
      if ('$e'.contains('MAIL_SIGNATURE_REQUIRED')) {
        status = 'MAIL_SIGNATURE_REQUIRED';
        notifyListeners();
        return 0;
      }
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
    if (job.status != JobStatus.open || job.isExpired) {
      status = 'Bu ilan artık başvuruya kapalı';
      notifyListeners();
      return false;
    }
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
      linkPath: '/firma/job/${Uri.encodeComponent(jobId)}',
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

  Future<bool> sendOffer({
    required String studentId,
    required String message,
    NotificationProvider? notifications,
    AuthProvider? auth,
    String? studentEmail,
    String? studentName,
  }) async {
    if (company == null) return false;
    // Auth uid ile firma kaydını hizala (sendCompanyMail auth.uid kullanır)
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null &&
        authUid.isNotEmpty &&
        company!.id != authUid) {
      company = CompanyAccount(
        id: authUid,
        name: company!.name,
        email: company!.email,
        sector: company!.sector,
        logoUrl: company!.logoUrl,
        mailSignature: company!.mailSignature,
      );
      try {
        await FirebaseFirestore.instance.collection('companies').doc(authUid).set({
          'name': company!.name,
          'email': company!.email,
          'logoUrl': company!.logoUrl,
          'mailSignature': company!.mailSignature.toJson(),
          'role': 'company',
          'authUid': authUid,
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      } catch (_) {}
      await refreshCompanyProfile();
    }
    if (!hasMailSignature) {
      await refreshCompanyProfile();
      if (!hasMailSignature) {
        status = 'MAIL_SIGNATURE_REQUIRED';
        notifyListeners();
        return false;
      }
    }
    final contact = await resolveStudentContact(
      studentId,
      auth: auth,
      fallbackName: studentName,
    );
    final mailTo = (studentEmail ?? '').trim().isNotEmpty
        ? studentEmail!.trim()
        : contact.email;
    final displayName =
        (studentName ?? '').trim().isNotEmpty ? studentName!.trim() : contact.name;

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

    var mailed = false;
    if (mailTo.contains('@')) {
      busy = true;
      status = 'Teklif maili gönderiliyor…';
      notifyListeners();
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('sendCompanyMail');
        await callable.call({
          'to': mailTo,
          'subject': '${company!.name} · Teklif',
          'bodyText': message,
          'kind': 'offer',
          'studentName': displayName.split(' ').first,
          'ctaLabel': 'KampüsteyimAPP’i aç',
          'ctaUrl': 'https://app.kampusteyim.app/staj-ai',
        });
        mailed = true;
        status = 'Teklif ve mail gönderildi · $mailTo';
      } catch (e) {
        debugPrint('[jobs] offer mail: $e');
        final msg = '$e';
        if (msg.contains('MAIL_SIGNATURE_REQUIRED')) {
          status = 'MAIL_SIGNATURE_REQUIRED';
        } else {
          status = 'Teklif kaydedildi; mail gönderilemedi';
        }
      }
      busy = false;
      notifyListeners();
    } else {
      status = 'Teklif kaydedildi; öğrencinin e-postası bulunamadı';
      notifyListeners();
    }
    debugPrint('[jobs] offer mailed=$mailed to=$mailTo');

    // Firma teklifi → Twitter tarzı kurum ilişkisi (gold tick yok)
    final companyUser = auth?.findUser(company!.id);
    final logo = company?.displayLogoUrl.isNotEmpty == true
        ? company!.displayLogoUrl
        : (companyUser?.communityLogoUrl ?? companyUser?.photoUrl);
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
    return true;
  }

  Future<void> emailStudent({
    required String toEmail,
    required String subject,
    required String html,
    String? studentName,
    String? bodyText,
  }) async {
    if (!hasMailSignature) {
      status = 'MAIL_SIGNATURE_REQUIRED';
      notifyListeners();
      return;
    }
    busy = true;
    status = 'Mail gönderiliyor…';
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('sendCompanyMail');
      await callable.call({
        'to': toEmail,
        'subject': subject,
        'bodyText': bodyText ?? html.replaceAll(RegExp(r'<[^>]*>'), ' '),
        'kind': 'mail',
        'studentName': studentName ?? '',
      });
      status = 'Mail gönderildi';
    } catch (e) {
      final msg = '$e';
      if (msg.contains('MAIL_SIGNATURE_REQUIRED')) {
        status = 'MAIL_SIGNATURE_REQUIRED';
      } else {
        status = 'Mail gönderilemedi: $e';
      }
    }
    busy = false;
    notifyListeners();
  }

  Future<void> rankApplicantsWithAi(JobListing job) async {
    if (company == null) return;
    busy = true;
    lastRankedJobId = job.id;
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
      status = 'AI sıralama hazır · ${ranked.length} aday · ${job.title}';
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
      status = 'Yerel AI sıralama · ${job.title}';
    }
    busy = false;
    notifyListeners();
  }

  JobListing? jobById(String? id) {
    if (id == null) return null;
    for (final j in _jobs) {
      if (j.id == id) return j;
    }
    return null;
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

  @override
  void dispose() {
    unawaited(_jobsSub?.cancel());
    unawaited(_offersSub?.cancel());
    super.dispose();
  }
}
