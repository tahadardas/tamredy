import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import 'map_illustration.dart';
import 'polyline.dart';
import 'theme.dart';

/// Real map (OpenStreetMap data, no key or card needed). Tests and screenshots
/// can set this to false to show the illustrated map instead.
bool mapsEnabled = const bool.fromEnvironment(
  'MAPS_ENABLED',
  defaultValue: true,
);

/// Raster tile server. Default is the public OSM server: fine for development and
/// light use, but its policy forbids heavy production traffic — switch to a hosted
/// or self-hosted tile service with `--dart-define=MAP_TILE_URL=https://.../{z}/{x}/{y}.png`.
const String kTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);
const String kTileAttribution = String.fromEnvironment(
  'MAP_ATTRIBUTION',
  defaultValue: '© OpenStreetMap contributors',
);

/// Damascus city centre, used before any fix is known.
const LatLng kDamascus = LatLng(33.5138, 36.2765);

TileLayer _tiles() => TileLayer(
  urlTemplate: kTileUrl,
  userAgentPackageName: 'com.tamreedy.app',
  maxNativeZoom: 19,
);

Widget _attribution() => const SimpleAttributionWidget(
  source: Text(kTileAttribution, style: TextStyle(fontSize: 10)),
  backgroundColor: Color(0xCCFFFFFF),
);

Widget _pin(IconData icon, Color color) => Container(
  width: 44,
  height: 44,
  decoration: BoxDecoration(
    color: color,
    shape: BoxShape.circle,
    border: Border.all(color: Colors.white, width: 3),
    boxShadow: const [
      BoxShadow(color: Color(0x44000000), blurRadius: 6, offset: Offset(0, 2)),
    ],
  ),
  child: Icon(icon, color: Colors.white, size: 22),
);

/// Live map for tracking and navigation: patient (home) pin, nurse pin that glides
/// between GPS fixes, route polyline, ETA chip, and automatic camera fitting.
class TamMap extends StatefulWidget {
  final LatLng? patient;
  final LatLng? nurse;
  final RouteInfo? route;
  final double height;
  const TamMap({
    super.key,
    this.patient,
    this.nurse,
    this.route,
    this.height = 300,
  });
  @override
  State<TamMap> createState() => _TamMapState();
}

class _TamMapState extends State<TamMap> with SingleTickerProviderStateMixin {
  final MapController _ctl = MapController();
  late final AnimationController _glide;
  LatLng? _from, _to;
  bool _ready = false;

  LatLng? get _nurseNow {
    if (_to == null) return null;
    final f = _from ?? _to!;
    final t = Curves.easeInOut.transform(_glide.value);
    return LatLng(
      f.latitude + (_to!.latitude - f.latitude) * t,
      f.longitude + (_to!.longitude - f.longitude) * t,
    );
  }

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(() => setState(() {}));
    _to = widget.nurse;
  }

  @override
  void didUpdateWidget(TamMap old) {
    super.didUpdateWidget(old);
    if (widget.nurse != old.nurse && widget.nurse != null) {
      _from = _nurseNow ?? widget.nurse;
      _to = widget.nurse;
      _glide.forward(from: 0);
    }
    if (widget.route != old.route || widget.patient != old.patient) _fit();
  }

  void _fit() {
    if (!_ready) return;
    final pts = <LatLng>[
      if (widget.patient != null) widget.patient!,
      if (widget.nurse != null) widget.nurse!,
      if (widget.route != null)
        ...widget.route!.points.map((p) => LatLng(p.lat, p.lng)),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _ctl.move(pts.first, 15);
    } else {
      _ctl.fitCamera(
        CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.all(56),
          maxZoom: 17,
        ),
      );
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!mapsEnabled)
      return MapIllustration(
        height: widget.height,
        showPerson: widget.nurse != null,
      );
    final nurse = _nurseNow;
    final r = widget.route;
    final line = r?.points.map((p) => LatLng(p.lat, p.lng)).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(TamreedyRadii.card),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _ctl,
              options: MapOptions(
                initialCenter: widget.patient ?? kDamascus,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _ready = true;
                  Future.delayed(const Duration(milliseconds: 200), _fit);
                },
              ),
              children: [
                _tiles(),
                if (line != null) ...[
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: line,
                        strokeWidth: 9,
                        color: Colors.white,
                        strokeJoin: StrokeJoin.round,
                        strokeCap: StrokeCap.round,
                      ),
                    ],
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: line,
                        strokeWidth: 5,
                        color: TamreedyColors.teal,
                        strokeJoin: StrokeJoin.round,
                        strokeCap: StrokeCap.round,
                      ),
                    ],
                  ),
                ],
                MarkerLayer(
                  markers: [
                    if (widget.patient != null)
                      Marker(
                        point: widget.patient!,
                        width: 44,
                        height: 44,
                        child: _pin(Icons.home_rounded, TamreedyColors.navy),
                      ),
                    if (nurse != null)
                      Marker(
                        point: nurse,
                        width: 44,
                        height: 44,
                        child: _pin(
                          Icons.medical_services_rounded,
                          TamreedyColors.teal,
                        ),
                      ),
                  ],
                ),
                _attribution(),
              ],
            ),
            if (r != null)
              PositionedDirectional(
                top: 12,
                end: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: TamreedyColors.teal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        r.etaLabel,
                        style: tamText(
                          size: 13,
                          weight: FontWeight.w800,
                          color: TamreedyColors.navy,
                        ),
                      ),
                      Text(
                        '  ·  ${r.distanceLabel}',
                        style: tamText(size: 12, color: TamreedyColors.subtext),
                      ),
                    ],
                  ),
                ),
              ),
            PositionedDirectional(
              bottom: 28,
              start: 12,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(
                  icon: const Icon(
                    Icons.center_focus_strong,
                    color: TamreedyColors.navy,
                  ),
                  onPressed: _fit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Uber-style" location picker: the pin stays centred while the map moves;
/// the chosen point is reverse-geocoded on the device (no API key needed).
class TamLocationPicker extends StatefulWidget {
  final LatLng initial;
  final double height;
  final void Function(LatLng point, String address) onChanged;
  const TamLocationPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.height = 360,
  });
  @override
  State<TamLocationPicker> createState() => _TamLocationPickerState();
}

class _TamLocationPickerState extends State<TamLocationPicker> {
  final MapController _ctl = MapController();
  late LatLng _center = widget.initial;
  Timer? _debounce;
  bool _moving = false;

  @override
  void didUpdateWidget(TamLocationPicker old) {
    super.didUpdateWidget(old);
    // Device fix arrived after the screen opened: recentre once.
    if (old.initial != widget.initial &&
        !_moving &&
        (_center.latitude - widget.initial.latitude).abs() > 1e-4) {
      _ctl.move(widget.initial, 16);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _settled() async {
    String address = '';
    try {
      await geo.setLocaleIdentifier('ar');
      final p = (await geo.placemarkFromCoordinates(
        _center.latitude,
        _center.longitude,
      )).firstOrNull;
      if (p != null)
        address = [
          p.subLocality,
          p.locality,
        ].where((e) => e != null && e.isNotEmpty).join(' - ');
    } catch (_) {
      /* offline geocoder: keep coordinates only */
    }
    if (mounted) widget.onChanged(_center, address);
  }

  @override
  Widget build(BuildContext context) {
    if (!mapsEnabled) return MapIllustration(height: widget.height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(TamreedyRadii.card),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              mapController: _ctl,
              options: MapOptions(
                initialCenter: widget.initial,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: (cam, _) {
                  _center = cam.center;
                  if (!_moving) setState(() => _moving = true);
                },
                onMapEvent: (e) {
                  if (e is MapEventMoveEnd ||
                      e is MapEventFlingAnimationEnd ||
                      e is MapEventScrollWheelZoom ||
                      e is MapEventDoubleTapZoomEnd) {
                    setState(() => _moving = false);
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 400),
                      _settled,
                    );
                  }
                },
              ),
              children: [_tiles(), _attribution()],
            ),
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.only(bottom: _moving ? 44 : 28),
                child: const Icon(
                  Icons.location_on,
                  size: 46,
                  color: TamreedyColors.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
