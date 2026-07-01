import 'audio_cue_service.dart';

// Tipos de bloque que se interpretan como intervalos/series
const _kIntervalTypes = {'intervals', 'series', 'interval', 'fartlek', 'repeticiones', 'hiit'};

// ── BlockInfo: normaliza las distintas convenciones de clave del JSON ────────

class BlockInfo {
  final int    index;
  final String label;
  final String type;
  final int    durationSeconds; // 0 = solo avance manual
  final int?   zone;
  final String? targetPace;    // "4:30" formato mm:ss
  final String? description;
  final bool   isInterval;
  final int?   repCount;
  final int?   repDurationSeconds;
  final int?   repDistanceM;
  final int    recoverySeconds;

  const BlockInfo({
    required this.index,
    required this.label,
    required this.type,
    required this.durationSeconds,
    this.zone,
    this.targetPace,
    this.description,
    this.isInterval       = false,
    this.repCount,
    this.repDurationSeconds,
    this.repDistanceM,
    this.recoverySeconds  = 90,
  });

  static BlockInfo fromMap(int index, Map<String, dynamic> b) {
    final typeRaw = (b['block'] ?? b['blockType'] ?? b['tipo'] ?? b['type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final desc    = (b['descripcion'] ?? b['description'] ?? b['desc'] ?? '').toString().trim();
    final durMin  = _parseDouble(b['min'] ?? b['durationMin'] ?? b['duracion_min'] ??
                                 b['duration_min'] ?? b['dur_min']) ?? 0.0;
    final zoneRaw = b['zone'] ?? b['zona_fc'] ?? b['hr_zone'] ?? b['zona'];
    final paceRaw = b['ritmo_objetivo'] ?? b['target_pace'] ?? b['pace'];
    final isInt   = _kIntervalTypes.contains(typeRaw);

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
      label:              _buildLabel(typeRaw, desc),
      type:               typeRaw,
      durationSeconds:    durMin > 0 ? (durMin * 60).round() : 0,
      zone:               zoneRaw != null ? int.tryParse(zoneRaw.toString()) : null,
      targetPace:         paceRaw?.toString(),
      description:        desc.isNotEmpty ? desc : null,
      isInterval:         isInt,
      repCount:           repCount,
      repDurationSeconds: repDurSec,
      repDistanceM:       repDistM,
      recoverySeconds:    recSec,
    );
  }

  String get targetDescription {
    if (targetPace != null && targetPace!.isNotEmpty) return 'a ritmo $targetPace por kilómetro';
    if (zone != null) return 'en zona $zone';
    return '';
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
  final AudioCueService _audio;
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
  List<_RepResult> _repResults = [];

  // Deduplicación: evita re-disparar el mismo cue en el mismo segundo
  final Set<String> _fired = {};

  SessionAudioController({
    required AudioCueService audio,
    required List<dynamic>   rawBlocks,
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
  void onTick(int elapsed, {int distanceM = 0}) {
    if (_busy) return;
    _doTick(elapsed, distanceM: distanceM);
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

      switch (_phase) {
        case _Phase.preCountdown:
          await _tickPreCountdown(elapsed);
        case _Phase.blockActive:
        case _Phase.blockWarning:
          await _tickBlockActive(elapsed);
        case _Phase.blockBeeps:
          break; // countdown5() maneja su propio timing
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
          ? 'de ${_fmtSec(block.repDurationSeconds!)} minutos'
          : block.repDistanceM != null
              ? 'de ${block.repDistanceM} metros'
              : '';
      final rec    = 'Recuperación: ${block.recoverySeconds} segundos.';
      await _audio.speak(
        'Bloque $n, ${block.label}. $reps $repTgt. $tgtTxt $rec',
      );
      await Future.delayed(const Duration(milliseconds: 1800));
      await _startIntervalRest(elapsed, announce: false);
    } else {
      await _audio.speak('Bloque $n, ${block.label}. $dur$tgtTxt');
    }
  }

  Future<void> _endBlock(int elapsed) async {
    final blockElapsed = elapsed - _blockStartElapsed;
    await _audio.beepLong();

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
    final total      = blocks[_blockIdx].repCount ?? '?';
    await _audio.beepLong();
    await _audio.speak('Serie $_currentRep de $total. ¡Ya!');
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

    _repResults.add(_RepResult(elapsedSec: repElapsed, paceSecKm: achievedPace));
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

  // ── Helpers ─────────────────────────────────────────────────────────────

  bool _fire(String key) {
    if (_fired.contains(key)) return false;
    _fired.add(key);
    return true;
  }

  static String _fmtSec(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _fmtMin(int totalSec) {
    final m = totalSec ~/ 60;
    return '$m ${m == 1 ? "minuto" : "minutos"}';
  }

  static String _fmtPace(int secPerKm) {
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static int _paceToSec(String pace) {
    final parts = pace.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  double? _avgRepPace() {
    final paces = _repResults.where((r) => r.paceSecKm != null).map((r) => r.paceSecKm!).toList();
    if (paces.isEmpty) return null;
    return paces.reduce((a, b) => a + b) / paces.length;
  }
}

class _RepResult {
  final int elapsedSec;
  final int? paceSecKm;
  const _RepResult({required this.elapsedSec, this.paceSecKm});
}
