import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/widgets/social_widgets.dart';
import '../../data/campus_catalog.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'company_applicant_widgets.dart';
import 'company_mail_gate.dart';
import 'company_offer_sheet.dart';
import 'company_portal.dart';
import 'jobs_provider.dart';

enum StudentBrowseMode { company, community, admin }

/// Öğrenci tarama — geniş filtre + mini foto.
/// Firma / topluluk / admin; diğer firma ve topluluk hesapları listede yok.
class StudentBrowseScreen extends StatefulWidget {
  const StudentBrowseScreen({
    super.key,
    this.mode = StudentBrowseMode.company,
    this.wrapCompanyShell = true,
  });

  final StudentBrowseMode mode;
  final bool wrapCompanyShell;

  @override
  State<StudentBrowseScreen> createState() => _StudentBrowseScreenState();
}

class _StudentBrowseScreenState extends State<StudentBrowseScreen> {
  final _q = TextEditingController();
  final _mail = TextEditingController();

  CampusCatalog? _catalog;
  String? _city;
  String? _university;
  String? _faculty;
  String? _department;
  bool _filtersOpen = true;
  bool _syncing = false;
  String? _syncHint;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final catalog = await CampusCatalog.load();
    if (!mounted) return;
    setState(() => _catalog = catalog);
    await _syncDirectory(silent: true);
  }

  Future<void> _syncDirectory({bool silent = false}) async {
    setState(() {
      _syncing = true;
      _syncHint = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final n = await auth.syncDirectoryFromFirestore();
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncHint = silent ? null : '$n profil yüklendi';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncHint = 'Dizin yenilenemedi';
      });
    }
  }

  @override
  void dispose() {
    _q.dispose();
    _mail.dispose();
    super.dispose();
  }

  bool _isBrowsableStudent(AppUser u) {
    if (u.isCompany || u.role == UserRole.company) return false;
    if (u.isCommunity || u.role == UserRole.community) return false;
    if (u.canAccessAdmin || u.role == UserRole.admin) return false;
    if (u.isBot) return false;
    if (u.isAccountRejected) return false;
    // Öğrenci rolü veya (eski kayıt) student varsayılanı
    return u.role == UserRole.student;
  }

  bool _matchLoose(String hay, String? needle) {
    if (needle == null || needle.trim().isEmpty) return true;
    final h = hay.trim().toLowerCase();
    final n = needle.trim().toLowerCase();
    if (h.isEmpty) return false;
    return h == n || h.contains(n) || n.contains(h);
  }

  List<AppUser> _filtered(AuthProvider auth) {
    final q = _q.text.trim().toLowerCase();
    final handleQ = q.startsWith('@') ? q : '@$q';
    final bare = q.replaceFirst(RegExp(r'^@'), '');
    final me = auth.user;

    final out = <AppUser>[];
    for (final u in auth.directory) {
      if (!_isBrowsableStudent(u)) continue;
      if (u.hideFromSearch &&
          me?.id != u.id &&
          !(me?.canAccessAdmin ?? false) &&
          widget.mode != StudentBrowseMode.admin) {
        continue;
      }
      if (me != null && (me.blocks(u.id) || u.blocks(me.id))) continue;
      if (!_matchLoose(u.city, _city)) continue;
      if (!_matchLoose(u.university, _university)) continue;
      if (!_matchLoose(u.faculty, _faculty)) continue;
      if (!_matchLoose(u.department, _department)) continue;
      if (q.isNotEmpty) {
        final uname = u.username?.trim().toLowerCase() ?? '';
        final hit = u.fullName.toLowerCase().contains(q) ||
            u.handle.toLowerCase().contains(q) ||
            u.handle.toLowerCase().contains(handleQ) ||
            (uname.isNotEmpty && (uname.contains(bare) || uname == bare)) ||
            u.bio.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            u.studentNo.contains(q) ||
            u.firstName.toLowerCase().contains(q) ||
            u.lastName.toLowerCase().contains(q) ||
            u.city.toLowerCase().contains(q) ||
            u.university.toLowerCase().contains(q) ||
            u.faculty.toLowerCase().contains(q) ||
            u.department.toLowerCase().contains(q) ||
            (u.affiliatedCommunityName?.toLowerCase().contains(q) ?? false);
        if (!hit) continue;
      }
      out.add(u);
    }
    out.sort((a, b) => a.fullName.compareTo(b.fullName));
    return out;
  }

  List<String> _citiesFromDirectory(List<AppUser> students) {
    final set = <String>{};
    for (final u in students) {
      final c = u.city.trim();
      if (c.isNotEmpty && c != '—') set.add(c);
    }
    final catalogCities = _catalog?.cities ?? const <String>[];
    for (final c in catalogCities) {
      if (c.trim().isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  List<String> _unisForCity(String? city, List<AppUser> students) {
    final set = <String>{};
    final fromCatalog = _catalog?.universitiesForCity(city) ?? const <String>[];
    set.addAll(fromCatalog);
    for (final u in students) {
      if (city != null && city.isNotEmpty && !_matchLoose(u.city, city)) {
        continue;
      }
      final uni = u.university.trim();
      if (uni.isNotEmpty && uni != '—') set.add(uni);
    }
    if (city == null || city.isEmpty) {
      for (final u in students) {
        final uni = u.university.trim();
        if (uni.isNotEmpty && uni != '—') set.add(uni);
      }
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  List<String> _faculties(String? uni, List<AppUser> students) {
    final set = <String>{};
    for (final f in _catalog?.facultiesFor(uni) ?? const []) {
      if (f.name.trim().isNotEmpty) set.add(f.name);
    }
    for (final u in students) {
      if (uni != null &&
          uni.isNotEmpty &&
          !_matchLoose(u.university, uni)) {
        continue;
      }
      final f = u.faculty.trim();
      if (f.isNotEmpty) set.add(f);
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  List<String> _departments(
    String? uni,
    String? faculty,
    List<AppUser> students,
  ) {
    final set = <String>{};
    set.addAll(
      _catalog?.departmentsFor(
            universityName: uni,
            facultyName: faculty,
          ) ??
          const [],
    );
    for (final u in students) {
      if (uni != null &&
          uni.isNotEmpty &&
          !_matchLoose(u.university, uni)) {
        continue;
      }
      if (faculty != null &&
          faculty.isNotEmpty &&
          !_matchLoose(u.faculty, faculty)) {
        continue;
      }
      final d = u.department.trim();
      if (d.isNotEmpty) set.add(d);
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }

  String get _title => switch (widget.mode) {
        StudentBrowseMode.company => 'Öğrenci tarama',
        StudentBrowseMode.community => 'Öğrenci tarama',
        StudentBrowseMode.admin => 'Öğrenci tarama (admin)',
      };

  void _clearFilters() {
    setState(() {
      _city = null;
      _university = null;
      _faculty = null;
      _department = null;
      _q.clear();
    });
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    const all = '';
    final safe =
        value != null && value.isNotEmpty && items.contains(value) ? value : all;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label|$safe|${items.length}'),
      initialValue: safe,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: all,
          child: Text('Tümü'),
        ),
        for (final item in items)
          DropdownMenuItem(
            value: item,
            child: Text(item, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => onChanged((v == null || v.isEmpty) ? null : v),
    );
  }

  Future<void> _openCv(AppUser s) async {
    await openCompanyStudentCv(
      context,
      s.id,
      fallbackName: s.fullName,
    );
  }

  Future<void> _sendMail(AppUser s, JobsProvider jobs) async {
    _mail.text =
        'Merhaba ${s.firstName}, firmamız sizi değerlendirmek istiyor.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mail · ${s.email}'),
        content: TextField(
          controller: _mail,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Mesaj'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await ensureCompanyMailSignature(context)) return;
    if (!mounted) return;
    await jobs.emailStudent(
      toEmail: s.email,
      subject: '${jobs.company?.name ?? 'KampüsteyimAPP'} · KampüsteyimAPP',
      html: '<p>${_mail.text}</p>',
      bodyText: _mail.text,
      studentName: s.firstName,
    );
    if (!mounted) return;
    final msg = jobs.status == 'MAIL_SIGNATURE_REQUIRED'
        ? 'Önce mail imzasını ayarlayın'
        : (jobs.status ?? 'Gönderildi');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendOffer(AppUser s, JobsProvider jobs) async {
    await showCompanyOfferComposer(
      context,
      studentId: s.id,
      studentName: s.fullName.trim().isNotEmpty ? s.fullName : s.firstName,
      studentEmail: s.email,
      studentPhoto: s.photoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final jobs = context.watch<JobsProvider>();
    final students = _filtered(auth);
    final pool = auth.directory.where(_isBrowsableStudent).toList();
    final cities = _citiesFromDirectory(pool);
    final unis = _unisForCity(_city, pool);
    final faculties = _faculties(_university, pool);
    final departments = _departments(_university, _faculty, pool);
    final showCompanyActions = widget.mode == StudentBrowseMode.company;

    final body = Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Dizini yenile',
            onPressed: _syncing ? null : () => _syncDirectory(),
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'İsim, handle, e-posta, bölüm…',
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _q.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _filtersOpen = !_filtersOpen),
                  icon: Icon(
                    _filtersOpen
                        ? Icons.expand_less_rounded
                        : Icons.tune_rounded,
                  ),
                  label: Text(_filtersOpen ? 'Filtreleri gizle' : 'Filtreler'),
                ),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Temizle'),
                ),
                const Spacer(),
                Text(
                  '${students.length} öğrenci',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          if (_filtersOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _dropdown(
                              label: 'Şehir',
                              value: _city,
                              items: cities,
                              onChanged: (v) => setState(() {
                                _city = v;
                                _university = null;
                                _faculty = null;
                                _department = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _dropdown(
                              label: 'Üniversite',
                              value: _university,
                              items: unis,
                              onChanged: (v) => setState(() {
                                _university = v;
                                _faculty = null;
                                _department = null;
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _dropdown(
                              label: 'Fakülte',
                              value: _faculty,
                              items: faculties,
                              onChanged: (v) => setState(() {
                                _faculty = v;
                                _department = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _dropdown(
                              label: 'Bölüm',
                              value: _department,
                              items: departments,
                              onChanged: (v) =>
                                  setState(() => _department = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Yalnızca öğrenciler · firma ve topluluk hesapları gizli',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_syncHint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _syncHint!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          Expanded(
            child: students.isEmpty
                ? const Center(
                    child: Text(
                      'Filtreye uyan öğrenci yok',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: students.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = students[i];
                      final meta = [
                        if (s.university.trim().isNotEmpty) s.university,
                        if (s.department.trim().isNotEmpty) s.department,
                        if (s.city.trim().isNotEmpty) s.city,
                      ].join(' · ');
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        leading: UserAvatar(
                          name: s.fullName,
                          photoUrl: s.photoUrl,
                          radius: 22,
                          onTap: () => AppNav.openUserProfile(context, s),
                        ),
                        title: Text(
                          s.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            s.handle,
                            if (meta.isNotEmpty) meta,
                          ].join('\n'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        isThreeLine: meta.isNotEmpty,
                        onTap: () => _openCv(s),
                        trailing: showCompanyActions
                            ? Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    tooltip: 'CV',
                                    onPressed: () => _openCv(s),
                                    icon: const Icon(
                                      Icons.description_outlined,
                                      size: 22,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Mail',
                                    onPressed: () => _sendMail(s, jobs),
                                    icon: const Icon(
                                      Icons.mail_outline,
                                      size: 22,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Teklif',
                                    onPressed: () => _sendOffer(s, jobs),
                                    icon: const Icon(
                                      Icons.handshake_outlined,
                                      size: 22,
                                    ),
                                  ),
                                ],
                              )
                            : IconButton(
                                tooltip: widget.mode == StudentBrowseMode.admin
                                    ? 'Profil'
                                    : 'CV',
                                onPressed: () {
                                  if (widget.mode == StudentBrowseMode.admin) {
                                    AppNav.openUserProfile(context, s);
                                  } else {
                                    _openCv(s);
                                  }
                                },
                                icon: Icon(
                                  widget.mode == StudentBrowseMode.admin
                                      ? Icons.person_outline
                                      : Icons.description_outlined,
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    if (widget.wrapCompanyShell &&
        widget.mode == StudentBrowseMode.company) {
      return CompanyPortalShell(child: body);
    }
    return body;
  }
}
