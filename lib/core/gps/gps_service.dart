import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GpsPoint {
  final double lat;
  final double lng;
  final double alt;
  final double speedMps;
  final double accuracy;
  final String timestamp;

  const GpsPoint({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.speedMps,
    required this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'alt': alt,
        'speed_mps': speedMps,
        'accuracy': accuracy,
        'timestamp': timestamp,
      };
}

class GpsTrack {
  final List<GpsPoint> points;
  final double totalDistanceM;
  final int durationSec;

  const GpsTrack({
    required this.points,
    required this.totalDistanceM,
    required this.durationSec,
  });

  double get avgPaceSecKm {
    if (totalDistanceM <= 0) return 0;
    final avgSpeedMps = totalDistanceM / durationSec;
    return avgSpeedMps > 0 ? 1000 / avgSpeedMps : 0;
  }

  // Payload exacto que espera POST /sessions/:id/gps-track
  Map<String, dynamic> toBackendPayload() => {
        'track_points': points.map((p) => p.toJson()).toList(),
        'total_distance_km': totalDistanceM / 1000,
        'total_duration_sec': durationSec,
        'avg_pace_sec_km': avgPaceSecKm,
      };
}

class GpsService {
  StreamSubscription<Position>? _sub;
  final List<GpsPoint> _points = [];
  Position? _lastPosition;
  double _totalDistanceM = 0;
  DateTime? _startTime;

  // Distancia acumulada en tiempo real para mostrar en UI
  double get totalDistanceM => _totalDistanceM;

  final _pointController = StreamController<GpsPoint>.broadcast();
  Stream<GpsPoint> get locationStream => _pointController.stream;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  void startTracking() {
    _points.clear();
    _totalDistanceM = 0;
    _lastPosition = null;
    _startTime = DateTime.now();

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // un punto cada 5 metros mínimo
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position pos) {
    // Ignorar fixes imprecisos (calentamiento GPS, interior)
    if (pos.accuracy > 20) return;

    // Calcular distancia incremental con haversine
    if (_lastPosition != null) {
      const dist = Distance();
      _totalDistanceM += dist.as(
        LengthUnit.Meter,
        LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
        LatLng(pos.latitude, pos.longitude),
      );
    }
    _lastPosition = pos;

    final point = GpsPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      alt: pos.altitude,
      speedMps: pos.speed < 0 ? 0 : pos.speed,
      accuracy: pos.accuracy,
      timestamp: pos.timestamp.toIso8601String(),
    );
    _points.add(point);
    _pointController.add(point);
  }

  GpsTrack stopTracking() {
    _sub?.cancel();
    _sub = null;
    final durationSec = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;
    return GpsTrack(
      points: List.unmodifiable(_points),
      totalDistanceM: _totalDistanceM,
      durationSec: durationSec,
    );
  }

  void dispose() {
    _sub?.cancel();
    _pointController.close();
  }
}

final gpsServiceProvider = Provider<GpsService>((_) => GpsService());
