import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../home/shell_chrome.dart';

/// Kompakt harita + Photon arama + canlı GPS.
Future<Map<String, dynamic>?> showLocationPickerSheet(BuildContext context) {
  ShellChrome.setBottomNavHidden(true);
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (ctx) => const _LocationPickerBody(),
  ).whenComplete(() => ShellChrome.setBottomNavHidden(false));
}

class _LocationPickerBody extends StatefulWidget {
  const _LocationPickerBody();

  @override
  State<_LocationPickerBody> createState() => _LocationPickerBodyState();
}

class _LocationPickerBodyState extends State<_LocationPickerBody> {
  final _map = MapController();
  final _labelCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  LatLng? _point;
  bool _busy = false;
  bool _searching = false;
  String? _error;
  bool _live = false;
  List<_PlaceHit> _hits = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _useLiveLocation());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    if (kIsWeb) return true;
    var enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() => _error = 'Konum servisi kapalı. Ayarlardan aç.');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      setState(() => _error = 'Konum izni gerekli.');
      return false;
    }
    if (perm == LocationPermission.deniedForever) {
      setState(
        () => _error =
            'Konum izni kalıcı reddedilmiş. Uygulama ayarlarından açabilirsin.',
      );
      return false;
    }
    return true;
  }

  Future<void> _useLiveLocation() async {
    setState(() {
      _busy = true;
      _error = null;
      _live = true;
    });
    try {
      if (!await _ensurePermission()) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _point = p;
        if (_labelCtrl.text.trim().isEmpty) {
          _labelCtrl.text = 'Canlı konumum';
        }
      });
      _map.move(p, 16);
    } catch (e) {
      setState(() => _error = 'Konum alınamadı');
      debugPrint('[location] $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_searchPlaces(q));
    });
  }

  Future<void> _searchPlaces(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      setState(() => _hits = const []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      // Photon (Komoot) — Nominatim’den daha iyi TR sonuçları
      final photonUri = Uri.https('photon.komoot.io', '/api/', {
        'q': q,
        'lang': 'tr',
        'limit': '8',
      });
      final res = await http
          .get(
            photonUri,
            headers: {
              'User-Agent': 'KampusteyimAPP/1.0 (campus social)',
              'Accept-Language': 'tr',
            },
          )
          .timeout(const Duration(seconds: 10));
      var hits = <_PlaceHit>[];
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final features = j is Map ? j['features'] : null;
        if (features is List) {
          for (final f in features) {
            if (f is! Map) continue;
            final geom = f['geometry'];
            final props = f['properties'];
            if (geom is! Map || props is! Map) continue;
            final coords = geom['coordinates'];
            if (coords is! List || coords.length < 2) continue;
            final lon = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            final name = _photonLabel(Map<String, dynamic>.from(props));
            if (name.isEmpty) continue;
            hits.add(_PlaceHit(name: name, point: LatLng(lat, lon)));
          }
        }
      }
      // Photon boşsa Nominatim yedek
      if (hits.isEmpty) {
        hits = await _nominatim(q);
      }
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      debugPrint('[location-search] $e');
      try {
        final hits = await _nominatim(q);
        if (mounted) setState(() => _hits = hits);
      } catch (_) {
        if (mounted) {
          setState(() {
            _hits = const [];
            _error = 'Arama yapılamadı';
          });
        }
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _photonLabel(Map<String, dynamic> props) {
    final parts = <String>[
      '${props['name'] ?? ''}'.trim(),
      '${props['street'] ?? ''}'.trim(),
      '${props['city'] ?? props['town'] ?? props['village'] ?? ''}'.trim(),
      '${props['state'] ?? ''}'.trim(),
      '${props['country'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '${props['osm_value'] ?? ''}'.trim();
    return parts.join(', ');
  }

  Future<List<_PlaceHit>> _nominatim(String q) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '8',
      'countrycodes': 'tr',
    });
    final res = await http
        .get(
          uri,
          headers: {
            'User-Agent': 'KampusteyimAPP/1.0 (campus social; location)',
            'Accept-Language': 'tr',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return const [];
    final list = jsonDecode(res.body);
    final hits = <_PlaceHit>[];
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final lat = double.tryParse('${e['lat']}');
        final lon = double.tryParse('${e['lon']}');
        final name = '${e['display_name'] ?? ''}'.trim();
        if (lat == null || lon == null || name.isEmpty) continue;
        hits.add(_PlaceHit(name: name, point: LatLng(lat, lon)));
      }
    }
    return hits;
  }

  void _selectHit(_PlaceHit hit) {
    final short = hit.name.split(',').first.trim();
    setState(() {
      _point = hit.point;
      _live = false;
      _labelCtrl.text = short.isEmpty ? hit.name : short;
      _hits = const [];
      _searchCtrl.text = short;
      _error = null;
    });
    _map.move(hit.point, 16);
    FocusScope.of(context).unfocus();
  }

  void _confirm() {
    final p = _point;
    if (p == null) {
      setState(() => _error = 'Haritadan bir nokta seç, ara veya canlı konum al.');
      return;
    }
    final label = _labelCtrl.text.trim().isEmpty
        ? (_live ? 'Canlı konumum' : 'Seçilen konum')
        : _labelCtrl.text.trim();
    Navigator.pop(context, {
      'label': label,
      'lat': p.latitude,
      'lng': p.longitude,
      'live': _live,
      'mapsUrl':
          'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final h = (media.size.height * 0.55).clamp(360.0, 520.0);
    final center = _point ?? const LatLng(39.0, 35.0);
    final bottomPad = media.viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: SizedBox(
        height: h,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Konum',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => unawaited(_searchPlaces(v)),
                decoration: InputDecoration(
                  hintText: 'Üniversite, cadde, yer ara…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _hits = const []);
                              },
                            )),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              if (_hits.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: Material(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _hits.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final hit = _hits[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 18),
                          title: Text(
                            hit.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          onTap: () => _selectHit(hit),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Etiket',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Canlı konum',
                    onPressed: _busy ? null : _useLiveLocation,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.my_location, size: 20),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.crimson,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: _point == null ? 5.5 : 15,
                      onTap: (_, latLng) {
                        setState(() {
                          _point = latLng;
                          _live = false;
                          _error = null;
                          if (_labelCtrl.text.trim() == 'Canlı konumum' ||
                              _labelCtrl.text.trim().isEmpty) {
                            _labelCtrl.text = 'Seçilen konum';
                          }
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.aystech.kampusteyimapp',
                      ),
                      if (_point != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _point!,
                              width: 36,
                              height: 36,
                              child: const Icon(
                                Icons.place,
                                color: AppColors.crimson,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Konumu ekle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceHit {
  const _PlaceHit({required this.name, required this.point});
  final String name;
  final LatLng point;
}
