import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/gps/gps_service.dart';

// ── Zona de FC por color ─────────────────────────────────────────
enum _HRZone { z1z2, z3, z4, z5, unknown }

const _zoneColors = {
  _HRZone.z1z2:    Color(0xFF4CAF50), // verde
  _HRZone.z3:      Color(0xFFFFEB3B), // amarillo
  _HRZone.z4:      Color(0xFFFF9800), // naranja
  _HRZone.z5:      Color(0xFFF44336), // rojo
  _HRZone.unknown: Color(0xFF42A5F5), // azul (sin FC)
};

const _zoneLabels = {
  _HRZone.z1z2:    'Z1-Z2 Recuperación/Base',
  _HRZone.z3:      'Z3 Aeróbico',
  _HRZone.z4:      'Z4 Umbral',
  _HRZone.z5:      'Z5 VO2max',
  _HRZone.unknown: 'Sin datos FC',
};

// ── Widget público ───────────────────────────────────────────────
class RouteMapWidget extends StatefulWidget {
  final List<GpsPoint> points;

  /// FCmax del atleta para calcular zonas.
  /// Si es null se usan breakpoints 60/70/80/90% de 190 bpm (estimación).
  final int? maxHR;

  const RouteMapWidget({
    super.key,
    required this.points,
    this.maxHR,
  });

  @override
  State<RouteMapWidget> createState() => _RouteMapWidgetState();
}

class _RouteMapWidgetState extends State<RouteMapWidget> {
  late final MapController _mapCtrl;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
  }

  // Determina la zona dado un bpm y FCmax
  _HRZone _zone(int? hr) {
    if (hr == null || hr <= 0) return _HRZone.unknown;
    final max = (widget.maxHR ?? 190).toDouble();
    final pct = hr / max;
    if (pct < 0.70) return _HRZone.z1z2;
    if (pct < 0.80) return _HRZone.z3;
    if (pct < 0.90) return _HRZone.z4;
    return _HRZone.z5;
  }

  // Segmenta la lista de puntos en tramos de color continuo
  List<({List<LatLng> pts, Color color})> _buildSegments() {
    if (widget.points.length < 2) return [];

    final segments = <({List<LatLng> pts, Color color})>[];
    var currentZone = _zone(widget.points.first.hr);
    var currentPts  = <LatLng>[
      LatLng(widget.points.first.lat, widget.points.first.lng),
    ];

    for (var i = 1; i < widget.points.length; i++) {
      final p    = widget.points[i];
      final zone = _zone(p.hr);
      final ll   = LatLng(p.lat, p.lng);

      if (zone == currentZone) {
        currentPts.add(ll);
      } else {
        // Comparte el punto de unión con el siguiente segmento para que no haya huecos
        currentPts.add(ll);
        segments.add((
          pts:   List.of(currentPts),
          color: _zoneColors[currentZone]!,
        ));
        currentPts  = [ll];
        currentZone = zone;
      }
    }
    if (currentPts.length >= 2) {
      segments.add((
        pts:   currentPts,
        color: _zoneColors[currentZone]!,
      ));
    }
    return segments;
  }

  // Centro y zoom automáticos para encuadrar la ruta
  LatLng get _center {
    if (widget.points.isEmpty) return const LatLng(40.416775, -3.703790);
    final lats = widget.points.map((p) => p.lat);
    final lngs = widget.points.map((p) => p.lng);
    return LatLng(
      (lats.reduce((a, b) => a + b)) / lats.length,
      (lngs.reduce((a, b) => a + b)) / lngs.length,
    );
  }

  // Marcadores inicio y fin
  List<Marker> get _markers {
    if (widget.points.isEmpty) return [];
    final markers = <Marker>[];
    final first   = widget.points.first;
    final last    = widget.points.last;

    markers.add(Marker(
      point: LatLng(first.lat, first.lng),
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: const Icon(Icons.play_arrow, color: Colors.white, size: 14),
      ),
    ));

    if (widget.points.length > 1) {
      markers.add(Marker(
        point: LatLng(last.lat, last.lng),
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF44336),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: const Icon(Icons.stop, color: Colors.white, size: 14),
        ),
      ));
    }
    return markers;
  }

  // Determina si la ruta tiene datos de FC
  bool get _hasHR => widget.points.any((p) => p.hr != null && p.hr! > 0);

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Sin datos GPS suficientes',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    final segments = _buildSegments();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                // Capa de tiles OpenStreetMap (sin API key)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.antigravity.ritmooptimo_mobile',
                ),
                // Polilíneas coloreadas por zona
                PolylineLayer(
                  polylines: segments.map((seg) => Polyline(
                    points: seg.pts,
                    color: seg.color,
                    strokeWidth: 5.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  )).toList(),
                ),
                // Marcadores inicio/fin
                MarkerLayer(markers: _markers),
              ],
            ),

            // Leyenda — solo si hay FC
            if (_hasHR)
              Positioned(
                bottom: 8,
                left: 8,
                child: _Legend(),
              ),

            // Atribución OSM
            Positioned(
              bottom: 2,
              right: 4,
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Leyenda de zonas ─────────────────────────────────────────────
class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final zones = [_HRZone.z1z2, _HRZone.z3, _HRZone.z4, _HRZone.z5];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: zones.map((z) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12, height: 4,
                decoration: BoxDecoration(
                  color: _zoneColors[z],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _zoneLabels[z]!,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}
