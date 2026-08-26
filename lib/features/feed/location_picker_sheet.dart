import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';

/// Harita + canlı GPS konum seçici (OpenStreetMap).
Future<Map<String, dynamic>?> showLocationPickerSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _LocationPickerBody(),
  );
}

class _LocationPickerBody extends StatefulWidget {
  const _LocationPickerBody();

  @override
  State<_LocationPickerBody> createState() => _LocationPickerBodyState();
}

class _LocationPickerBodyState extends State<_LocationPickerBody> {
  final _map = MapController();
  final _labelCtrl = TextEditingController();
  LatLng? _point;
  bool _busy = false;
  String? _error;
  bool _live = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _useLiveLocation());
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
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
      setState(() => _error = 'Konum alınamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirm() {
    final p = _point;
    if (p == null) {
      setState(() => _error = 'Haritadan bir nokta seç veya canlı konum al.');
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
    final h = MediaQuery.sizeOf(context).height * 0.82;
    final center = _point ?? const LatLng(39.0, 35.0);
    return SizedBox(
      height: h,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Konum paylaş',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Canlı GPS veya haritada nokta seç',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Etiket (ör. Merkez Kütüphane)',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _useLiveLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Canlı konum'),
                  ),
                ),
                const SizedBox(width: 8),
                if (_busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.crimson, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: _point == null ? 5.5 : 16,
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
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.place,
                              color: AppColors.crimson,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('Konumu ekle'),
            ),
          ],
        ),
      ),
    );
  }
}
