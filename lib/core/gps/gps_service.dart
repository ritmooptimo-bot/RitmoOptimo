import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// FIX 1: Umbral de precisión más permisivo (20m → 35m).
//         Con 20m se descartaban demasiados fixes en exterior con nubes o arboles.
// PRECISIÓN MÍNIMA PARA ACEPTAR UN PUNTO.
//
// Estaba en 35 m y era la causa REAL de los entrenamientos sin recorrido.
// Medido en el móvil del atleta el 20/07/2026 en plena calle:
//     Location[gps hAcc=48.0 satellites=6 meanCn0=20]
// El sistema entregaba posiciones (51 en 7 minutos, en alta precisión), pero
// TODAS se descartaban aquí por 13 metros — sin avisar. La pantalla decía "GPS
// Activo" mientras no se grababa absolutamente nada. Explica también los 81
// minutos con 0 puntos del 18/07.
//
// 75 m es tosco pero traza el recorrido de una carrera o una caminata. La
// alternativa no era "un track más preciso": era NINGÚN track.
const _kMaxAccuracyM = 75.0;

// Por encima de esto la distancia entre dos puntos seguidos no es movimiento,
// es el GPS saltando (con ±48 m de error, dos lecturas quietas pueden "separarse"
// decenas de metros e inflar los kilómetros).
const _kMaxSpeedMps = 12.0;   // 43 km/h — imposible andando o corriendo

// FIX 2: Intervalo de actualización forzada cada 10 s aunque no haya movimiento.
//         Evita quedarse sin puntos en tramos lentos o paradas breves.
const _kIntervalDuration = Duration(seconds: 10);

// FIX 3: Servicio en primer plano en Android → Android no mata el GPS en background.
//         Requiere la declaración del service en AndroidManifest.xml.
LocationSettings _buildLocationSettings() {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: _kIntervalDuration,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'GPS activo',
        notificationText: 'RitmoOptimo está registrando tu ruta',
        enableWakeLock: true,
      ),
    );
  }
  // iOS — no necesita foreground service (el sistema lo gestiona distinto)
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );
}

class GpsPoint {
  final double lat;
  final double lng;
  final double alt;
  final double speedMps;
  final double accuracy;
  final String timestamp;
  final int? hr;
  final int? cadence;   // pasos/min (carrera) o rpm (ciclismo), de BLE o podómetro
  final int? powerW;    // vatios, de potenciómetro BLE (ciclismo/carrera)

  const GpsPoint({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.speedMps,
    required this.accuracy,
    required this.timestamp,
    this.hr,
    this.cadence,
    this.powerW,
  });

  Map<String, dynamic> toJson() => {
        'lat':       lat,
        'lng':       lng,
        'alt':       alt,
        'speed_mps': speedMps,
        'accuracy':  accuracy,
        'timestamp': timestamp,
        if (hr      != null) 'hr':      hr,
        if (cadence != null) 'cadence': cadence,
        if (powerW  != null) 'power_w': powerW,
      };
}

class GpsTrack {
  final List<GpsPoint> points;
  final double totalDistanceM;
  final int durationSec;
  final String sportType;   // 'running' | 'cycling' | 'trail' | 'swimming' | 'other'

  const GpsTrack({
    required this.points,
    required this.totalDistanceM,
    required this.durationSec,
    this.sportType = 'running',
  });

  double get avgPaceSecKm {
    if (totalDistanceM <= 0 || durationSec <= 0) return 0;
    final avgSpeedMps = totalDistanceM / durationSec;
    return avgSpeedMps > 0 ? 1000 / avgSpeedMps : 0;
  }

  // Payload para POST /sessions/:id/gps-track
  Map<String, dynamic> toBackendPayload() => {
        'track_points':      points.map((p) => p.toJson()).toList(),
        'total_distance_km': totalDistanceM / 1000,
        'total_duration_sec': durationSec,
        'avg_pace_sec_km':   avgPaceSecKm,
        'sport_type':        sportType,
      };
}

class GpsService {
  StreamSubscription<Position>? _sub;
  final List<GpsPoint> _points = [];
  // Precisión de la última lectura y cuántas seguidas se han descartado: la
  // pantalla lo enseña en vez de dejar al atleta mirando un mapa vacío.
  double? _lastAccuracyM;
  int _descartados = 0;
  final _accuracyController = StreamController<double>.broadcast();
  Position? _lastPosition;
  double _totalDistanceM = 0;
  DateTime? _startTime;
  DateTime? _lastPointTime;
  int? _currentHR;
  int? _currentCadence;
  int? _currentPowerW;
  String _sportType = 'running';

  // Fix #4: buffer de últimas 5 velocidades para suavizar ritmo en intervalos cortos
  final List<double> _speedBuffer = [];

  // Distancia acumulada en tiempo real para mostrar en UI
  double get totalDistanceM => _totalDistanceM;

  // Ritmo suavizado (media móvil 5 puntos) — usar en IntervalRepWidget
  double get smoothedPaceSecKm {
    if (_speedBuffer.isEmpty) return 0;
    final avg = _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length;
    return avg > 0.3 ? 1000 / avg : 0; // 0.3 m/s = ~55 min/km — umbral mínimo
  }

  // Actualizados por el workout provider / BLE service cuando llegan datos
  void setCurrentHR(int? hr)       => _currentHR       = hr;
  void setCurrentCadence(int? cad) => _currentCadence  = cad;
  void setCurrentPower(int? watts)  => _currentPowerW   = watts;
  void setSportType(String sport)   => _sportType       = sport;

  /// Precisión (en metros) de la última lectura recibida, se haya aceptado o no.
  double? get lastAccuracyM => _lastAccuracyM;
  /// Lecturas seguidas descartadas por precisión insuficiente.
  int get descartadosSeguidos => _descartados;
  /// Emite la precisión de cada lectura, para que la UI la muestre en vivo.
  Stream<double> get accuracyStream => _accuracyController.stream;

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
    _lastPointTime = null;
    _startTime = DateTime.now();
    _speedBuffer.clear(); // Fix #4: resetear buffer al iniciar

    _sub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(
      _onPosition,
      // v7.2: sin esto, un error del stream (servicio apagado a mitad, permiso
      // revocado, excepcion del foreground service) mataba el GPS EN SILENCIO:
      // el 18/07 el atleta corrio 81 min y se grabaron 0 puntos sin ningun aviso.
      onError: (Object e) => _pointController.addError(e),
    );
  }

  void _onPosition(Position pos) {
    // La precisión de la ÚLTIMA lectura, se acepte o no: la pantalla la enseña
    // para que "no hay recorrido" deje de ser un misterio.
    _lastAccuracyM = pos.accuracy;
    _descartados = pos.accuracy > _kMaxAccuracyM ? _descartados + 1 : 0;
    if (pos.accuracy > _kMaxAccuracyM) {
      _accuracyController.add(pos.accuracy);
      return;
    }

    final now = DateTime.now();

    // Calcular distancia incremental con haversine
    if (_lastPosition != null) {
      const dist = Distance();
      final d = dist.as(
        LengthUnit.Meter,
        LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
        LatLng(pos.latitude, pos.longitude),
      );
      // Solo suma si el desplazamiento es físicamente posible: con ±48 m de
      // error dos lecturas quietas pueden "separarse" y regalar kilómetros.
      final dtSec = _lastPointTime != null
          ? now.difference(_lastPointTime!).inMilliseconds / 1000.0
          : 10.0;
      if (dtSec <= 0 || d / dtSec <= _kMaxSpeedMps) _totalDistanceM += d;
    }
    _lastPosition = pos;
    _accuracyController.add(pos.accuracy);

    // Fix #4: actualizar buffer de velocidad (últimos 5 puntos)
    final spd = pos.speed < 0 ? 0.0 : pos.speed;
    _speedBuffer.add(spd);
    if (_speedBuffer.length > 5) _speedBuffer.removeAt(0);

    // Guardar punto si han pasado al menos 5 s desde el último (evita duplicados
    // cuando coinciden el stream y el intervalo de 10 s)
    final timeSinceLast = _lastPointTime != null
        ? now.difference(_lastPointTime!).inSeconds
        : 999;
    if (timeSinceLast < 5) return;
    _lastPointTime = now;

    final point = GpsPoint(
      lat:       pos.latitude,
      lng:       pos.longitude,
      alt:       pos.altitude,
      speedMps:  pos.speed < 0 ? 0 : pos.speed,
      accuracy:  pos.accuracy,
      timestamp: pos.timestamp.toIso8601String(),
      hr:        _currentHR,
      cadence:   _currentCadence,
      powerW:    _currentPowerW,
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
      points:        List.unmodifiable(_points),
      totalDistanceM: _totalDistanceM,
      durationSec:   durationSec,
      sportType:     _sportType,
    );
  }

  void dispose() {
    _sub?.cancel();
    _pointController.close();
  }
}

final gpsServiceProvider = Provider<GpsService>((_) => GpsService());
