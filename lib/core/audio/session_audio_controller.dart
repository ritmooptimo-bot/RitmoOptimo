import 'audio_cue_service.dart';
import 'medidor_bloques.dart';
import '../utils/zona_fc.dart';
import '../session/aviso_zona.dart';
import 'salida_de_audio.dart';

// Tipos de bloque que se interpretan como intervalos/series
const _kIntervalTypes = {'intervals', 'series', 'interval', 'fartlek', 'repeticiones', 'hiit'};

// ── BlockInfo: normaliza las distintas convenciones de clave del JSON ────────

class BlockInfo {
  final int    index;
  final String label;
  final String type;
  final int    durationSeconds; // 0 = solo avance manual
  final int?   zone;
  /// La zona TAL CUAL viene del plan ("R1+", "z2"). `zone` es solo su número,
  /// y con la escala del entrenador (R0…R3+) un número no la representa.
  final String? zoneLabel;
  final String? targetPace;    // "4:30" formato mm:ss
  final String? description;
  final bool   isInterval;
  final int?   repCount;
  final int?   repDurationSeconds;
  final int?   repDistanceM;
  final int    recoverySeconds;

  /// ⚠️ De qué escala habla `zone`. Sin esto, un bloque `R1` de Raúl —que es
  /// PERCEPCIÓN, «sin reloj ni pulsómetro»— se trataría como si fuera la zona 1
  /// de frecuencia cardiaca, y le avisaríamos por pulsaciones en una sesión que
  /// por método no se mide con ellas. Ver migración 090.
  final String zoneEscala;

  const BlockInfo({
    required this.index,
    required this.label,
    required this.type,
    required this.durationSeconds,
    this.zone,
    this.zoneLabel,
    this.targetPace,
    this.description,
    this.isInterval       = false,
    this.repCount,
    this.repDurationSeconds,
    this.repDistanceM,
    this.recoverySeconds  = 90,
    this.zoneEscala       = 'desconocida',
  });

  static BlockInfo fromMap(int index, Map<String, dynamic> b) {
    // ⚠️ EL ORDEN DE ESTA CADENA TENÍA EL FALLO. Antes era
    // `b['block'] ?? b['blockType'] ?? b['tipo'] ?? b['type']`, o sea que
    // cogía PRIMERO el nombre humano del bloque — "Parte principal",
    // "Series 4 x 6 min" — y solo miraba `type` si no había nombre, cosa que
    // no pasa nunca.
    //
    // Y como `isInterval` exige coincidencia EXACTA con la lista de tipos, un
    // bloque llamado "Series 4 x 6 min" no casaba con 'series' y la app lo
    // trataba como carrera continua. Resultado: toda la guía de repeticiones
    // —la cuenta atrás, los pitidos, "serie 3 de 6", saltar descanso— llevaba
    // meses escrita y sin dispararse jamás.
    //
    // El tipo canónico va PRIMERO; el nombre humano es para leerlo, no para
    // decidir con él.
    final typeRaw = (b['type'] ?? b['blockType'] ?? b['tipo'] ?? b['block'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final nombreBloque = (b['block'] ?? '').toString().trim();
    final desc    = (b['descripcion'] ?? b['description'] ?? b['desc'] ?? '').toString().trim();
    final durMin  = _parseDouble(b['min'] ?? b['durationMin'] ?? b['duracion_min'] ??
                                 b['duration_min'] ?? b['dur_min']) ?? 0.0;
    final zoneRaw = b['zone'] ?? b['zona_fc'] ?? b['hr_zone'] ?? b['zona'];
    final escala  = (b['zone_escala'] ?? 'desconocida').toString();
    final paceRaw = b['ritmo_objetivo'] ?? b['target_pace'] ?? b['pace'];
    // Y si el bloque TRAE repeticiones utilizables, es una serie diga lo que diga
    // su etiqueta: el dato es la prueba. Así una serie sigue guiándose aunque
    // alguien escriba el tipo de otra manera.
    final traeReps = (_parseInt(b['reps'] ?? b['repeticiones'] ?? b['num_reps']) ?? 0) >= 2 &&
        ((_parseDouble(b['rep_duration_min'] ?? b['rep_time_min']) ?? 0) > 0 ||
         (_parseInt(b['rep_distance_m'] ?? b['distancia_rep']) ?? 0) > 0);
    final isInt   = _kIntervalTypes.contains(typeRaw) || traeReps;

    int? repCount;
    int? repDurSec;
    int? repDistM;
    int  recSec = 90;

    if (isInt) {
      repCount  = _parseInt(b['reps'] ?? b['repeticiones'] ?? b['num_reps'] ?? b['series']);
      final rm  = _parseDouble(b['rep_duration_min'] ?? b['rep_time_min'] ??
                               b['tiempo_rep']       ?? b['tiempo_serie']);
      repDurSec = rm != null ? (rm * 60).round() : null;
      repDistM  = _parseInt(b['rep_distance_m'] ?? b['distancia_rep'] ?? b['distancia_serie_m']);
      recSec    = _parseInt(b['recovery_seconds'] ?? b['descanso_segundos'] ??
                            b['recuperacion_seg']) ??
                  ((_parseDouble(b['recovery_min'] ?? b['descanso_min']) ?? 1.5) * 60).round();
    }

    return BlockInfo(
      index:              index,
      // Para LEER manda el nombre que escribió el entrenador ("Series 4 x 6 min"),
      // que dice mucho más que "Intervalos". El tipo solo se usa para decidir.
      label:              desc.isNotEmpty ? desc
                          : (nombreBloque.isNotEmpty ? nombreBloque : _buildLabel(typeRaw, desc)),
      type:               typeRaw,
      durationSeconds:    durMin > 0 ? (durMin * 60).round() : 0,
      zone:               zonaFcNumero(zoneRaw),
      zoneLabel:          zoneRaw?.toString(),
      targetPace:         paceRaw?.toString(),
      description:        desc.isNotEmpty ? desc : null,
      isInterval:         isInt,
      repCount:           repCount,
      repDurationSeconds: repDurSec,
      repDistanceM:       repDistM,
      recoverySeconds:    recSec,
      zoneEscala:         escala,
    );
  }

  /// ⚠️ ANTES ESTO SE CALLABA LA ZONA. Si el bloque traía ritmo objetivo,
  /// devolvía el ritmo Y PUNTO; y si no lo traía, decía "en zona N" solo cuando
  /// la zona era un número de FC. Con un plan entero en la escala R —que es la
  /// del entrenador— `zonaFcNumero("R2")` devuelve null a propósito, así que la
  /// frase salía VACÍA: 27 minutos de series sin oír una sola referencia.
  ///
  /// Ahora se acumulan las dos cosas, y la zona se dice TAL COMO LA ESCRIBIÓ EL
  /// ENTRENADOR. Repetir su etiqueta no es traducir nada: R2 es R2.
  String get targetDescription {
    final partes = <String>[];

    if (targetPace != null && targetPace!.isNotEmpty) {
      // El ritmo objetivo llega del plan como "5:30". Tal cual, el motor de voz
      // lo lee como una HORA. Se dice en palabras.
      partes.add('a ritmo de ${_paceEnPalabras(targetPace!)} por kilómetro');
    }

    // ⚠️ `zone` solo trae número cuando la etiqueta ES de frecuencia cardiaca
    // (`zonaFcNumero` devuelve null para R1, R2…). Así que ese null es
    // justamente la señal de "esto es escala del entrenador".
    //
    // Y el orden importa: pedir `zoneEscala == 'fc'` aquí hacía que un bloque
    // escrito "z1" pero sin declarar la escala dijera «en z1» —que el motor de
    // voz lee «en zeta uno»— en vez de «en zona 1».
    final etiqueta = (zoneLabel ?? '').trim();
    if (zone != null) {
      partes.add('en zona $zone');
    } else if (etiqueta.isNotEmpty) {
      partes.add('en $etiqueta');
    }

    return partes.join(', ');
  }

  /// "5:30" → "5 minutos 30 segundos" · "5:00" → "5 minutos justos"
  static String _paceEnPalabras(String pace) {
    final p = pace.split(':');
    if (p.length != 2) return pace;
    final m = int.tryParse(p[0].trim()), s = int.tryParse(p[1].trim());
    if (m == null || s == null) return pace;
    final min = '$m ${m == 1 ? "minuto" : "minutos"}';
    if (s == 0) return '$min justos';
    return '$min $s ${s == 1 ? "segundo" : "segundos"}';
  }

  static String _buildLabel(String type, String desc) {
    if (desc.isNotEmpty) return desc;
    switch (type) {
      case 'warmup':      return 'Calentamiento';
      case 'cooldown':    return 'Enfriamiento';
      case 'steady':      return 'Carrera continua';
      case 'endurance':   return 'Fondo';
      case 'intervals':   return 'Intervalos';
      case 'series':      return 'Series';
      case 'fartlek':     return 'Fartlek';
      case 'hiit':        return 'HIIT';
      case 'rest':        return 'Descanso';
      case 'strength':    return 'Fuerza';
      default: return type.isNotEmpty
          ? type[0].toUpperCase() + type.substring(1)
          : 'Bloque';
    }
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

// ── Estado UI exportado al widget ─────────────────────────────────────────

class SessionBlockUIState {
  final int    blockNumber;
  final int    totalBlocks;
  final String blockLabel;
  final int?   blockRemainingSeconds; // null = sin auto-avance
  final int?   blockDurationSeconds;
  final bool   isInterval;
  // Intervalos
  final int    currentRep;
  final int    totalReps;
  final bool   isResting;
  final int?   restRemainingSeconds;
  final int?   repElapsedSeconds;
  final int?   repDurationSeconds;
  final int?   repDistanceM;

  const SessionBlockUIState({
    required this.blockNumber,
    required this.totalBlocks,
    required this.blockLabel,
    this.blockRemainingSeconds,
    this.blockDurationSeconds,
    this.isInterval       = false,
    this.currentRep       = 0,
    this.totalReps        = 0,
    this.isResting        = false,
    this.restRemainingSeconds,
    this.repElapsedSeconds,
    this.repDurationSeconds,
    this.repDistanceM,
  });
}

// ── Fases internas ─────────────────────────────────────────────────────────

enum _Phase {
  idle,
  preCountdown,
  blockActive,
  blockWarning,
  blockBeeps,
  intervalRest,
  intervalRestBeeps,
  intervalRepActive,
  sessionDone,
}

// ── SessionAudioController ─────────────────────────────────────────────────

class SessionAudioController {
  final SalidaDeAudio _audio;
  final List<BlockInfo> blocks;

  _Phase _phase        = _Phase.idle;
  bool   _busy         = false;
  bool   _skipRequest  = false;

  int _blockIdx         = 0;
  int _blockStartElapsed = 0;

  // Intervalos
  int _currentRep        = 0;
  int _restStartElapsed  = 0;
  int _repStartElapsed   = 0;
  int _repStartDistM     = 0;
  List<ResultadoRepeticion> _repResults = [];

  // Las pulsaciones DE ESTA repetición. Se reinician en cada serie: la media
  // del bloque entero no sirve para ver si la tercera se fue de vueltas.
  int  _repFcSuma  = 0;
  int  _repFcCuenta = 0;
  int? _repFcMax;

  // Deduplicación: evita re-disparar el mismo cue en el mismo segundo
  final Set<String> _fired = {};

  // Aviso por kilómetro: "Kilómetro 3. Ritmo 5:42..." (petición del usuario)
  int _lastKmAnnounced   = 0;
  int _lastKmElapsedSec  = 0;
  // Segundo en que arrancó de verdad (tras la cuenta atrás): la media se mide
  // desde ahí, no desde que se pulsó "empezar".
  int _inicioCarreraSec  = 0;

  // ── MEDIDAS POR BLOQUE ────────────────────────────────────────────────
  // Cada bloque lleva su propia cuenta de kilómetros, ritmo y pulso, y arranca
  // de cero aunque la sesión lleve ya media hora encima. Pedido por David:
  // "para que el deportista sepa cómo ha realizado el bloque concreto".
  MedidorBloque? _medidor;
  final List<ResultadoBloque> _resultados = [];
  int _ultimaDistanciaM = 0;

  /// Lo que ha dado cada bloque. La pantalla lo envía al terminar la sesión.
  List<ResultadoBloque> get resultadosDeBloques => List.unmodifiable(_resultados);

  /// Las zonas de FC del deportista, en pulsaciones. `null` = no se han podido
  /// cargar (sin red, o sin FC máxima): entonces no se avisa de nada, que es lo
  /// correcto — no se inventa un rango.
  final List<RangoFc>? zonasFc;

  /// Las zonas del ENTRENADOR (R0…R3+) en pulsaciones, estimadas por FC de
  /// reserva. Es lo que permite decirle algo en un plan escrito entero en R,
  /// que es como escribe el suyo. null = no se han podido calcular.
  final List<RangoFc>? zonasEntrenador;

  /// Qué pulsaciones son un "R1" PARA ESTE deportista (mig. 092). Manda sobre
  /// el modelo genérico de zonas: la escala del entrenador no se traduce con una
  /// fórmula, se mide en él.
  final List<RangoFc>? equivalencia;

  /// Vibración corta al salirse. Se inyecta para poder probarlo sin plugin.
  final void Function()? onVibrar;

  AvisoZona _aviso = AvisoZona();

  SessionAudioController({
    required SalidaDeAudio audio,
    required List<dynamic>   rawBlocks,
    this.zonasFc,
    this.zonasEntrenador,
    this.equivalencia,
    this.onVibrar,
  })  : _audio = audio,
        blocks = List.generate(
          rawBlocks.length,
          (i) => BlockInfo.fromMap(i, (rawBlocks[i] as Map<String, dynamic>?) ?? {}),
        );

  // ── API pública ─────────────────────────────────────────────────────────

  Future<void> onSessionStart() async {
    _phase = _Phase.preCountdown;
    await _audio.startSession();
    await _audio.speak('Preparado. Comenzamos en 10 segundos.');
  }

  /// Llamar cada segundo desde el timer existente. Fire-and-forget.
  void onTick(int elapsed, {int distanceM = 0, int? hr}) {
    // El medidor se alimenta SIEMPRE, aunque el controlador esté ocupado
    // hablando: si se saltara los ticks de los cues, el bloque perdería metros.
    _ultimaDistanciaM = distanceM;

    // El pulso de la repetición en curso. Va aquí y no en el tick de la serie
    // porque el tick solo corre en algunas fases, y una lectura perdida es un
    // dato menos para decidir si la dosis fue la buena.
    if (hr != null && hr > 0 && _phase == _Phase.intervalRepActive) {
      _repFcSuma += hr;
      _repFcCuenta++;
      if (_repFcMax == null || hr > _repFcMax!) _repFcMax = hr;
    }
    _medidor?.anota(elapsedSeg: elapsed, metrosTotales: distanceM, fc: hr);

    // ⚠️ EL AVISO DE ZONA VA FUERA DEL `_busy`, y a propósito: si el controlador
    // está hablando de otra cosa, el aviso NO se pierde — se queda pendiente y
    // sale cuando pueda. Perderlo sería peor que retrasarlo.
    _vigilarZona(elapsed, hr);

    if (_busy) return;
    _doTick(elapsed, distanceM: distanceM);
  }

  /// El objetivo de FC del bloque en curso, si es que se mide por pulsaciones.
  ///
  /// ⚠️ Devuelve null en cuanto la escala NO es de FC. Un bloque `R1` de Raúl es
  /// percepción («sin reloj ni pulsómetro»): darle un rango de pulsaciones sería
  /// inventarse una equivalencia que él no ha establecido.
  RangoFc? _objetivoDelBloque([BlockInfo? cual]) {
    if (cual == null && (_blockIdx < 0 || _blockIdx >= blocks.length)) return null;
    final b = cual ?? blocks[_blockIdx];
    if (b.zoneLabel == null || b.zoneEscala == 'desconocida') return null;

    // 1) La EQUIVALENCIA de este deportista manda sobre todo: dice qué
    //    pulsaciones son un "R1" para ÉL. No hay fórmula que lo sustituya —
    //    R1 no es Z1: en los datos reales sale al 79 % de la máxima, o sea Z3.
    final eq = equivalencia?.where(
      (x) => x.nombre.toUpperCase() == b.zoneLabel!.toUpperCase().trim());
    if (eq != null && eq.isNotEmpty) return eq.first;

    // 2) Y si no la hay, LAS ZONAS DEL PROPIO ENTRENADOR en pulsaciones.
    //
    // ⚠️ AQUÍ ANTES SE CALLABA, y por un motivo que era bueno: traducir una
    // etiqueta de percepción con una fórmula genérica sería inventarle una
    // equivalencia que él no ha establecido. Pero el resultado real fue peor:
    // este deportista tiene TODO su plan en R1/R2 y no tiene equivalencia
    // propia, así que corrió 27 minutos de series sin una sola referencia de
    // pulsaciones y sin que la app pudiera avisarle de nada.
    //
    // Estas no salen de una fórmula genérica: salen de las fracciones de FC de
    // reserva de SUS PROPIAS zonas (R2 = 0,80-0,88 de la reserva), aplicadas a
    // la máxima y el reposo MEDIDOS de este deportista. Aun así son una
    // ESTIMACIÓN mientras no haya un test de campo, y por eso viajan marcadas:
    // la app lo dice en voz alta al anunciar el bloque. Un rango estimado
    // presentado como una orden sería peor que el silencio; dicho como lo que
    // es, es mejor.
    final zr = zonasEntrenador?.where(
      (x) => x.nombre.toUpperCase() == b.zoneLabel!.toUpperCase().trim());
    if (zr != null && zr.isNotEmpty) return zr.first;

    // 3) Y en último lugar, el modelo genérico z1-z5, solo si el bloque ya
    //    venía en escala de FC.
    if (b.zoneEscala != 'fc' || b.zone == null || zonasFc == null) return null;
    final z = zonasFc!.where((x) => x.nombre.startsWith('Z${b.zone}'));
    return z.isEmpty ? null : z.first;
  }

  /// El rango de pulsaciones del bloque, dicho en voz alta.
  ///
  /// ⚠️ SE DICE UNA VEZ, AL EMPEZAR, y con su procedencia si es estimado. Los
  /// avisos de después van cortos —quien corre con auriculares no retiene una
  /// frase larga— así que la advertencia de "esto es una aproximación" tiene
  /// que caber aquí o no cabrá en ningún sitio. Y tiene que estar: un rango
  /// calculado presentado como su umbral medido es un dato sin procedencia.
  String _fraseObjetivoFc(BlockInfo b) {
    final r = _objetivoDelBloque(b);
    if (r == null) return '';
    final rango = r.hasta == null
        ? 'a partir de ${r.desde}'
        : 'entre ${r.desde} y ${r.hasta}';
    final coletilla = r.esEstimacion ? ', estimadas' : '';
    return ' Pulsaciones: $rango$coletilla.';
  }

  void _vigilarZona(int elapsed, int? hr) {
    final objetivo = _objetivoDelBloque();
    if (objetivo?.nombre != _aviso.objetivo?.nombre) {
      // Bloque nuevo → objetivo nuevo, pero el TOPE de avisos NO se reinicia.
      _aviso = _aviso.paraBloque(objetivo: objetivo, escala: 'fc');
    }
    final r = _aviso.tick(elapsed, hr);
    if (r.vibrar) onVibrar?.call();
    if (r.decir != null) _audio.speak(r.decir!);
  }

  /// Solicita avanzar al siguiente bloque (o finalizar la rep actual).
  void requestSkip() => _skipRequest = true;

  bool get isSessionDone => _phase == _Phase.sessionDone;

  BlockInfo? get currentBlock =>
      _blockIdx < blocks.length ? blocks[_blockIdx] : null;

  SessionBlockUIState getUIState(int elapsed) {
    final block = _blockIdx < blocks.length ? blocks[_blockIdx] : null;
    if (block == null) {
      return SessionBlockUIState(
        blockNumber: blocks.length,
        totalBlocks: blocks.length,
        blockLabel: 'Sesión completada',
      );
    }
    final blockElapsed = elapsed - _blockStartElapsed;
    int? remaining;
    if (block.durationSeconds > 0) {
      remaining = (block.durationSeconds - blockElapsed).clamp(0, block.durationSeconds);
    }

    if (block.isInterval) {
      final isResting = _phase == _Phase.intervalRest || _phase == _Phase.intervalRestBeeps;
      int? restRem;
      if (isResting) {
        final restElapsed = elapsed - _restStartElapsed;
        restRem = (block.recoverySeconds - restElapsed).clamp(0, block.recoverySeconds);
      }
      final repElapsed = _phase == _Phase.intervalRepActive ? elapsed - _repStartElapsed : null;

      return SessionBlockUIState(
        blockNumber:           _blockIdx + 1,
        totalBlocks:           blocks.length,
        blockLabel:            block.label,
        blockRemainingSeconds: remaining,
        blockDurationSeconds:  block.durationSeconds > 0 ? block.durationSeconds : null,
        isInterval:            true,
        currentRep:            _currentRep,
        totalReps:             block.repCount ?? 0,
        isResting:             isResting,
        restRemainingSeconds:  restRem,
        repElapsedSeconds:     repElapsed,
        repDurationSeconds:    block.repDurationSeconds,
        repDistanceM:          block.repDistanceM,
      );
    }

    return SessionBlockUIState(
      blockNumber:           _blockIdx + 1,
      totalBlocks:           blocks.length,
      blockLabel:            block.label,
      blockRemainingSeconds: remaining,
      blockDurationSeconds:  block.durationSeconds > 0 ? block.durationSeconds : null,
    );
  }

  // ── Lógica interna ──────────────────────────────────────────────────────

  Future<void> _doTick(int elapsed, {int distanceM = 0}) async {
    _busy = true;
    try {
      if (_skipRequest) {
        _skipRequest = false;
        await _handleSkip(elapsed, distanceM: distanceM);
        return;
      }

      // Aviso por kilómetro (en cualquier fase de carrera, sin pisar los pitidos)
      await _maybeAnnounceKm(elapsed, distanceM);

      switch (_phase) {
        case _Phase.preCountdown:
          await _tickPreCountdown(elapsed);
        case _Phase.blockActive:
        case _Phase.blockWarning:
          await _tickBlockActive(elapsed);
        case _Phase.blockBeeps:
          // ⚠️ BUG cazado en la primera sesión real (04/08): esta fase era un
          // callejón sin salida ("el siguiente tick lo detecta"… pero este case
          // hacía break y NUNCA se re-evaluaba el bloque) → tras los pitidos
          // del bloque 2 no llegaba ni el "completado", ni el bloque 3, ni la
          // finalización. Ahora el tick sigue vigilando el fin del bloque.
          final b = blocks[_blockIdx];
          if (b.durationSeconds > 0 &&
              elapsed - _blockStartElapsed >= b.durationSeconds) {
            await _endBlock(elapsed);
          }
        case _Phase.intervalRest:
        case _Phase.intervalRestBeeps:
          await _tickIntervalRest(elapsed, distanceM: distanceM);
        case _Phase.intervalRepActive:
          await _tickIntervalRep(elapsed, distanceM: distanceM);
        default:
          break;
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleSkip(int elapsed, {int distanceM = 0}) async {
    if (_phase == _Phase.intervalRepActive) {
      await _endIntervalRep(elapsed, distanceM: distanceM, manual: true);
    } else if (_phase == _Phase.intervalRest || _phase == _Phase.intervalRestBeeps) {
      // Saltar el descanso — ir directamente a la rep o al siguiente bloque
      final block = blocks[_blockIdx];
      final totalReps = block.repCount ?? 1;
      if (_currentRep >= totalReps) {
        await _endBlock(elapsed);
      } else {
        await _startIntervalRep(elapsed, distanceM: distanceM);
      }
    } else {
      await _endBlock(elapsed);
    }
  }

  Future<void> _tickPreCountdown(int elapsed) async {
    if (elapsed >= 10) {
      await _startBlock(0, elapsed);
      return;
    }
    // Beeps en 7, 8, 9 (cuenta atrás 3-2-1)
    final key = 'countdown_$elapsed';
    if (elapsed >= 7 && _fire(key)) {
      await _audio.beepShort();
    }
  }

  Future<void> _tickBlockActive(int elapsed) async {
    final block = blocks[_blockIdx];
    if (block.durationSeconds <= 0) return; // solo avance manual

    final remaining = block.durationSeconds - (elapsed - _blockStartElapsed);

    if (remaining <= 0) {
      await _endBlock(elapsed);
      return;
    }

    // Aviso 30 segundos antes
    if (remaining == 30 && _fire('warn_${_blockIdx}')) {
      _phase = _Phase.blockWarning;
      final nextIdx = _blockIdx + 1;
      final nextDesc = nextIdx < blocks.length
          ? 'comienza el bloque ${nextIdx + 1}, ${blocks[nextIdx].label}'
          : 'finaliza la sesión';
      await _audio.speak(
        'En 30 segundos finaliza el bloque ${_blockIdx + 1} y $nextDesc.',
      );
    }

    // Pitidos 5 segundos antes
    if (remaining == 5 && _fire('beeps_${_blockIdx}')) {
      _phase = _Phase.blockBeeps;
      await _audio.countdown5();
      // Tras los pitidos el bloque habrá terminado; el siguiente tick lo detecta
    }
  }

  Future<void> _tickIntervalRest(int elapsed, {int distanceM = 0}) async {
    final block      = blocks[_blockIdx];
    final restElapsed = elapsed - _restStartElapsed;
    final remaining   = block.recoverySeconds - restElapsed;

    // A falta de 10 s se avisa de QUÉ viene: no es lo mismo prepararse para
    // otra serie que para el final del bloque.
    final totalReps = block.repCount ?? 1;
    if (block.recoverySeconds >= 30 && remaining == 10 &&
        _fire('rest_aviso10_${_blockIdx}_$_currentRep')) {
      await _audio.speak(_currentRep >= totalReps
          ? 'En 10 segundos terminamos el bloque.'
          : 'En 10 segundos, serie ${_currentRep + 1} de $totalReps.');
    }

    if (remaining <= 5 && _fire('rest_beeps_${_blockIdx}_$_currentRep')) {
      _phase = _Phase.intervalRestBeeps;
      await _audio.countdown5();
    }

    if (remaining <= 0) {
      final totalReps = block.repCount ?? 1;
      if (_currentRep >= totalReps) {
        await _endBlock(elapsed);
      } else {
        await _startIntervalRep(elapsed, distanceM: distanceM);
      }
    }
  }

  Future<void> _tickIntervalRep(int elapsed, {int distanceM = 0}) async {
    final block      = blocks[_blockIdx];
    final repElapsed = elapsed - _repStartElapsed;
    final targetSec  = block.repDurationSeconds;
    final targetDist = block.repDistanceM;

    // Pitidos en los últimos 5 s si el objetivo es por tiempo
    if (targetSec != null) {
      final remaining = targetSec - repElapsed;
      // Aviso HABLADO a falta de 10 s, y solo en repeticiones que dan para
      // ello: en una de treinta segundos, avisar a los diez es hablar encima
      // del esfuerzo. Ahí bastan los pitidos.
      if (targetSec >= 60 && remaining == 10 &&
          _fire('rep_aviso10_${_blockIdx}_$_currentRep')) {
        await _audio.speak('Últimos 10 segundos.');
      }
      if (remaining == 5 && _fire('rep_beeps_${_blockIdx}_$_currentRep')) {
        await _audio.countdown5();
      }
      if (remaining <= 0) {
        await _endIntervalRep(elapsed, distanceM: distanceM);
        return;
      }
    }

    // Fin por distancia
    if (targetDist != null) {
      final repDist = distanceM - _repStartDistM;
      if (repDist >= targetDist && _fire('rep_dist_${_blockIdx}_$_currentRep')) {
        await _endIntervalRep(elapsed, distanceM: distanceM);
      }
    }
  }

  // ── Transiciones ────────────────────────────────────────────────────────

  Future<void> _startBlock(int idx, int elapsed) async {
    if (idx >= blocks.length) {
      await _endSession(elapsed);
      return;
    }
    _blockIdx          = idx;
    _blockStartElapsed = elapsed;
    _phase             = _Phase.blockActive;

    // Empieza a medir ESTE bloque: de aquí en adelante sus kilómetros y su
    // ritmo se cuentan desde cero, aunque la sesión lleve ya varios km.
    _medidor = MedidorBloque(
      indice:            idx,
      etiqueta:          blocks[idx].label,
      zona:              blocks[idx].zoneLabel,
      elapsedSeg:        elapsed,
      metrosTotales:     _ultimaDistanciaM,
      segundosPrevistos: blocks[idx].durationSeconds,
    );
    // El ritmo del km 1 se mide desde que EMPIEZA a correr (no desde la cuenta atrás)
    if (idx == 0) { _lastKmElapsedSec = elapsed; _inicioCarreraSec = elapsed; }

    final block = blocks[idx];
    final n     = idx + 1;
    final dur   = block.durationSeconds > 0
        ? 'Duración: ${_fmtMin(block.durationSeconds)}. '
        : '';
    final tgt   = block.targetDescription;
    final tgtTxt = tgt.isNotEmpty ? '${tgt[0].toUpperCase()}${tgt.substring(1)}.' : '';

    if (block.isInterval) {
      _currentRep  = 0;
      _repResults  = [];
      final reps   = block.repCount != null ? '${block.repCount} series' : 'series';
      final repTgt = block.repDurationSeconds != null
          ? 'de ${_fmtSec(block.repDurationSeconds!)}'
          : block.repDistanceM != null
              ? 'de ${block.repDistanceM} metros'
              : '';
      final rec    = 'Recuperación: ${block.recoverySeconds} segundos.';
      await _audio.speak(
        'Bloque $n, ${block.label}. $reps $repTgt. $tgtTxt${_fraseObjetivoFc(block)} $rec',
      );
      await Future.delayed(const Duration(milliseconds: 1800));
      // ⚠️ ANTES ESTO ARRANCABA EL BLOQUE CON UN DESCANSO
      // (`_startIntervalRest(announce: false)`), así que el deportista se
      // quedaba parado los 90 segundos de la recuperación ANTES de la primera
      // serie, en silencio y sin saber por qué. Y el bloque duraba un descanso
      // de más: 3 x 8 con 90 s son 27 minutos, no 28 y medio.
      //
      // Un bloque de series empieza CORRIENDO. El descanso va entre
      // repeticiones, que es lo que significa "entre".
      // ⚠️ CON LA DISTANCIA YA RECORRIDA. Sin esto, `_repStartDistM` se queda
      // en 0 y la primera serie mide desde el principio de la sesión: salía
      // "ritmo 1:55" en una serie corrida a 5:33, y encima con el veredicto
      // "algo rápido, controla en la siguiente". Un dato inventado con consejo
      // encima es peor que no decir nada.
      await _startIntervalRep(elapsed, distanceM: _ultimaDistanciaM);
    } else {
      await _audio.speak('Bloque $n, ${block.label}. $dur$tgtTxt${_fraseObjetivoFc(block)}');
    }
  }

  Future<void> _endBlock(int elapsed) async {
    final blockElapsed = elapsed - _blockStartElapsed;
    await _audio.beepLong();

    // Se cierran las medidas de ESTE bloque antes de hablar: lo que se cuenta
    // es lo que se guarda, no dos cifras calculadas por caminos distintos.
    // ⚠️ LAS REPETICIONES VIAJAN CON EL BLOQUE. Antes se medían, se decían en
    // voz alta («serie 2 completada, ritmo 4:35») y se tiraban: al entrenador
    // le llegaba solo el agregado, y con una media no se puede saber si la
    // primera fue perfecta y las dos últimas un desastre.
    final resultado = _medidor?.cerrar(
      repeticiones: blocks[_blockIdx].isInterval ? List.of(_repResults) : const []);
    if (resultado != null) _resultados.add(resultado);
    _medidor = null;

    if (blocks[_blockIdx].isInterval && _repResults.isNotEmpty) {
      final block    = blocks[_blockIdx];
      final avgPace  = _avgRepPace();
      final repsDone = _repResults.length;
      final total    = block.repCount ?? repsDone;
      String summary = 'Bloque ${_blockIdx + 1} completado. $repsDone de $total series realizadas.';
      if (avgPace != null) {
        summary += ' Ritmo medio: ${_fmtPace(avgPace.round())} por kilómetro.';
        if (block.targetPace != null) {
          final diff = avgPace - _paceToSec(block.targetPace!);
          if (diff.abs() <= 5)      summary += ' Excelente precisión.';
          else if (diff < -5)       summary += ' Tendencia algo rápida.';
          else if (diff <= 15)      summary += ' Ligeramente por encima del objetivo.';
          else                      summary += ' Por encima del objetivo. Ajusta en la próxima sesión.';
        }
      }
      await _audio.speak(summary);
    } else if (resultado != null) {
      // El resumen del bloque con SUS números: kilómetros, ritmo, pulso y si
      // estuvo dentro de lo que pedía el entrenador. Antes solo decía el tiempo.
      final objetivo = blocks[_blockIdx].targetPace;
      await _audio.speak(veredictoBloque(
        resultado,
        ritmoObjetivoSegKm: (objetivo != null && objetivo.isNotEmpty)
            ? _paceToSec(objetivo)
            : null,
      ));
    } else {
      await _audio.speak(
        'Bloque ${_blockIdx + 1} completado. Tiempo: ${_fmtSec(blockElapsed)}.',
      );
    }

    await Future.delayed(const Duration(milliseconds: 1800));
    await _startBlock(_blockIdx + 1, elapsed);
  }

  Future<void> _startIntervalRest(int elapsed, {bool announce = true}) async {
    _phase             = _Phase.intervalRest;
    _restStartElapsed  = elapsed;
    if (announce) {
      final block = blocks[_blockIdx];
      await _audio.speak('Descansa ${block.recoverySeconds} segundos.');
    }
  }

  Future<void> _startIntervalRep(int elapsed, {int distanceM = 0}) async {
    _phase           = _Phase.intervalRepActive;
    _currentRep++;
    _repStartElapsed = elapsed;
    _repStartDistM   = distanceM;
    _repFcSuma = 0; _repFcCuenta = 0; _repFcMax = null;
    final block      = blocks[_blockIdx];
    final total      = block.repCount ?? '?';
    await _audio.beepLong();

    // El objetivo (ritmo o pulsaciones) se repite EN CADA serie cuando hay
    // tiempo de decirlo: en una repetición de ocho minutos, oírlo al empezar es
    // justo lo que hace falta para no salir demasiado rápido. En series muy
    // cortas se dice solo en la primera — meter una frase larga en un sprint de
    // treinta segundos es robarle el arranque.
    final tgt   = block.targetDescription;
    final largo = (block.repDurationSeconds ?? 0) >= 120;
    final decirObjetivo = tgt.isNotEmpty && (largo || _currentRep == 1);

    final tgtFrase = decirObjetivo && tgt.isNotEmpty
        ? '${tgt[0].toUpperCase()}${tgt.substring(1)}. ' : '';
    await _audio.speak('Serie $_currentRep de $total. $tgtFrase¡Ya!');
  }

  Future<void> _endIntervalRep(int elapsed, {int distanceM = 0, bool manual = false}) async {
    await _audio.beepLong();
    final block      = blocks[_blockIdx];
    final repElapsed = elapsed - _repStartElapsed;
    final repDist    = distanceM - _repStartDistM;

    String summary = 'Serie $_currentRep completada.';
    int? achievedPace;

    if (repDist > 0 && repElapsed > 0) {
      achievedPace = (repElapsed * 1000 / repDist).round();
      summary += ' Ritmo: ${_fmtPace(achievedPace)} por kilómetro.';
      if (block.targetPace != null) {
        final diff = achievedPace - _paceToSec(block.targetPace!);
        if (diff.abs() <= 5)      summary += ' Perfecto.';
        else if (diff < -5)       summary += ' Algo rápido, controla en la siguiente.';
        else if (diff <= 15)      summary += ' Ligeramente por encima del objetivo.';
        else                      summary += ' Por encima del tiempo objetivo, ajusta el esfuerzo.';
      }
    } else {
      summary += ' Tiempo: ${_fmtSec(repElapsed)}.';
    }

    _repResults.add(ResultadoRepeticion(
      numero:            _currentRep,
      deReps:            block.repCount ?? _currentRep,
      segundosPrevistos: block.repDurationSeconds ?? 0,
      segundosReales:    repElapsed,
      metros:            repDist > 0 ? repDist : 0,
      ritmoSegKm:        achievedPace,
      fcMedia:           _repFcCuenta > 0 ? (_repFcSuma / _repFcCuenta).round() : null,
      fcMax:             _repFcMax,
    ));
    await _audio.speak(summary);
    await Future.delayed(const Duration(milliseconds: 1500));

    final totalReps = block.repCount ?? 1;
    if (_currentRep >= totalReps) {
      await _endBlock(elapsed);
    } else {
      await _startIntervalRest(elapsed);
    }
  }

  Future<void> _endSession(int elapsed) async {
    _phase = _Phase.sessionDone;
    await _audio.beepLong();
    await Future.delayed(const Duration(milliseconds: 600));
    await _audio.speak('Sesión completada. ¡Excelente trabajo! Revisa tus datos en la pantalla de resumen.');
    await _audio.stopSession();
  }

  // ── Aviso por kilómetro ─────────────────────────────────────────────────
  // En cada km completo: número, ritmo del ÚLTIMO km y tiempo total. Se calla
  // durante pitidos/cuenta atrás/fin para no pisar los cues críticos (ese km
  // se anuncia al siguiente tick en fase normal — el _lastKm no avanza hasta
  // que de verdad se dice).
  Future<void> _maybeAnnounceKm(int elapsed, int distanceM) async {
    if (distanceM <= 0) return;
    final km = distanceM ~/ 1000;
    if (km <= _lastKmAnnounced) return;
    if (_phase == _Phase.preCountdown ||
        _phase == _Phase.blockBeeps ||
        _phase == _Phase.intervalRestBeeps ||
        _phase == _Phase.sessionDone) {
      return;
    }
    final paceSec = (elapsed - _lastKmElapsedSec).clamp(60, 3600);
    _lastKmAnnounced  = km;
    _lastKmElapsedSec = elapsed;

    // Media acumulada desde que empezó a correr, como da el Garmin. Se calcula
    // sobre la distancia REAL recorrida, no sobre los km redondos, para que no
    // mienta cuando el aviso llega con unos metros de retraso.
    final segCorriendo = elapsed - _inicioCarreraSec;
    final kmReales     = distanceM / 1000.0;
    final media = kmReales > 0.1 ? (segCorriendo / kmReales).round() : null;
    final frasesMedia = media != null
        ? ' Media: ${_fmtPace(media.clamp(60, 3600))}.'
        : '';

    await _audio.speak(
      'Kilómetro $km. Último kilómetro en ${_fmtPace(paceSec)}.$frasesMedia '
      'Tiempo total: ${_fmtSec(elapsed)}.',
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  bool _fire(String key) {
    if (_fired.contains(key)) return false;
    _fired.add(key);
    return true;
  }

  // ⚠️ AQUÍ NO SE ESCRIBEN NÚMEROS CON DOS PUNTOS.
  //
  // Todo lo de este fichero se LOCUTA. "7:41" el motor de voz lo lee como una
  // HORA: el atleta oía "ritmo, siete pm" en vez de "siete cuarenta y uno el
  // kilómetro". Pasaba con el ritmo, con los tiempos de bloque y con el tiempo
  // total — con todo lo que llevara dos puntos.
  //
  // Los números para la PANTALLA van en otro sitio; estos son solo para hablar.

  /// "45 minutos 20 segundos" · "3 minutos" · "40 segundos"
  static String _fmtSec(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    if (m == 0) return '$s ${s == 1 ? "segundo" : "segundos"}';
    final min = '$m ${m == 1 ? "minuto" : "minutos"}';
    if (s == 0) return min;
    return '$min $s ${s == 1 ? "segundo" : "segundos"}';
  }

  static String _fmtMin(int totalSec) {
    final m = totalSec ~/ 60;
    return '$m ${m == 1 ? "minuto" : "minutos"}';
  }

  /// "7 minutos 41 segundos" · "7 minutos justos"
  static String _fmtPace(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    if (s == 0) return '$m ${m == 1 ? "minuto" : "minutos"} justos';
    return '$m ${m == 1 ? "minuto" : "minutos"} $s ${s == 1 ? "segundo" : "segundos"}';
  }

  static int _paceToSec(String pace) {
    final parts = pace.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  double? _avgRepPace() {
    final paces = _repResults.where((r) => r.ritmoSegKm != null).map((r) => r.ritmoSegKm!).toList();
    if (paces.isEmpty) return null;
    return paces.reduce((a, b) => a + b) / paces.length;
  }
}


