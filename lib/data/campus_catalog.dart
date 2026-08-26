import 'dart:convert';

import 'package:flutter/services.dart';

/// Türkiye üniversite / fakülte / bölüm kataloğu (asset JSON).
class CampusFaculty {
  const CampusFaculty({required this.name, required this.departments});
  final String name;
  final List<String> departments;
}

class CampusUniversity {
  const CampusUniversity({
    required this.name,
    required this.city,
    this.faculties = const [],
  });
  final String name;
  final String city;
  final List<CampusFaculty> faculties;

  List<String> get allDepartments {
    final out = <String>{};
    for (final f in faculties) {
      out.addAll(f.departments);
    }
    final list = out.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }
}

class CampusCatalog {
  static CampusCatalog? _instance;
  static Future<CampusCatalog>? _loading;

  final List<String> cities;
  final Map<String, List<String>> byCity;
  final Map<String, CampusUniversity> byName;

  CampusCatalog._from({
    required this.cities,
    required this.byCity,
    required this.byName,
  });

  static Future<CampusCatalog> load() {
    _loading ??= _load();
    return _loading!;
  }

  static CampusCatalog? get maybeInstance => _instance;

  static Future<CampusCatalog> _load() async {
    if (_instance != null) return _instance!;
    String raw;
    try {
      raw = await rootBundle.loadString('assets/data/universities-tr-full.json');
    } catch (_) {
      raw = await rootBundle.loadString('assets/data/universities-tr.json');
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final cities = (map['cities'] as List? ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final byCityRaw = map['byCity'];
    final byCity = <String, List<String>>{};
    if (byCityRaw is Map) {
      for (final e in byCityRaw.entries) {
        final list = (e.value as List? ?? const [])
            .map((x) => '$x')
            .where((x) => x.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => a.compareTo(b));
        byCity['${e.key}'] = list;
      }
    }
    final byName = <String, CampusUniversity>{};
    final unis = map['universities'];
    if (unis is List) {
      for (final item in unis) {
        if (item is! Map) continue;
        final name = '${item['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final city = '${item['city'] ?? ''}'.trim();
        final faculties = <CampusFaculty>[];
        final facRaw = item['faculties'];
        if (facRaw is List) {
          for (final f in facRaw) {
            if (f is! Map) continue;
            final fname = '${f['name'] ?? ''}'.trim();
            if (fname.isEmpty) continue;
            final deps = (f['departments'] as List? ?? const [])
                .map((d) => '$d'.trim())
                .where((d) => d.isNotEmpty)
                .toList()
              ..sort((a, b) => a.compareTo(b));
            faculties.add(CampusFaculty(name: fname, departments: deps));
          }
        }
        byName[name] = CampusUniversity(
          name: name,
          city: city,
          faculties: faculties,
        );
      }
    }
    // byCity'te olup universities listesinde olmayanlar
    for (final e in byCity.entries) {
      for (final name in e.value) {
        byName.putIfAbsent(
          name,
          () => CampusUniversity(name: name, city: e.key),
        );
      }
    }
    _instance = CampusCatalog._from(
      cities: cities.isEmpty ? byCity.keys.toList() : cities,
      byCity: byCity,
      byName: byName,
    );
    return _instance!;
  }

  List<String> universitiesForCity(String? city) {
    if (city == null || city.isEmpty) return const [];
    return byCity[city] ?? const [];
  }

  CampusUniversity? university(String? name) {
    if (name == null || name.isEmpty) return null;
    return byName[name];
  }

  List<CampusFaculty> facultiesFor(String? universityName) =>
      university(universityName)?.faculties ?? const [];

  List<String> departmentsFor({
    required String? universityName,
    String? facultyName,
  }) {
    final uni = university(universityName);
    if (uni == null) return const [];
    if (facultyName == null || facultyName.isEmpty) {
      return uni.allDepartments;
    }
    for (final f in uni.faculties) {
      if (f.name == facultyName) return f.departments;
    }
    return const [];
  }
}
