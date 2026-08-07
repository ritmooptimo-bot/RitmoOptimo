// ============================================================
//  CADA BLOQUE, CON SUS PROPIAS MEDIDAS
//
//  Pedido por David tras su sesión del 07/08:
//
//    "El bloque 1 debe tomar sus medidas independientes de los demás, y así
//     cada bloque toma sus medidas, sus kilómetros… para que el deportista sepa
//     cómo ha realizado el bloque concreto. Eso sí, también se obtiene el
//     cómputo total de la sesión. Como lo hace Garmin."
//
//  La app conocía los bloques y los anunciaba por voz, pero solo medía el TOTAL
//  de la sesión: al terminar los 10 minutos de calentamiento no había forma de
//  decirle cuántos kilómetros habían sido ni a qué ritmo.
//
//  Esto vive aparte, sin dependencias de GPS ni de audio, para poder probarlo
//  con números a mano. Lo único que necesita es que alguien le vaya diciendo
//  cuánto lleva la sesión, cuánta distancia y a qué pulsaciones.
// ============================================================

/// Lo que ha dado un bloque cuando se cierra.
class ResultadoBloque {
  final int indice;            // 0-based
  final String etiqueta;       // "Calentamiento"
  final String? zona;          // "R1+"
  final int segundosPrevistos;
  final int segundosReales;
  final int metros;
  final int? fcMedia;
  final int? fcMax;

  const ResultadoBloque({
    required this.indice,
    required this.etiqueta,
    required this.segundosPrevistos,
    required this.segundosReales,
    required this.metros,
    this.zona,
    this.fcMedia,
    this.fcMax,
  });

  /// Ritmo medio del bloque en segundos por km. Null si no dio para medirlo.
  ///
  /// Se exige un mínimo de 100 metros: con menos, el ritmo es ruido del GPS
  /// disfrazado de dato. Un bloque de fuerza en el salón daría "2:30/km".
  int? get ritmoSegPorKm {
    if (metros < 100 || segundosReales <= 0) return null;
    final r = (segundosReales / (metros / 1000)).round();
    return (r >= 120 && r <= 1800) ? r : null;
  }

  double get km => metros / 1000;

  /// Para enviarlo al backend (`POST /sessions/:id/actual-structure`).
  Map<String, dynamic> toJson() => {
        'block': etiqueta,
        'zone': zona,
        'min': (segundosReales / 60).round(),
        'min_previstos': (segundosPrevistos / 60).round(),
        'distance_m': metros,
        'pace_sec_km': ritmoSegPorKm,
        'hr_avg': fcMedia,
        'hr_max': fcMax,
      };
}

/// Va tomando las medidas de UN bloque mientras se corre.
///
/// Se crea al abrir el bloque y se cierra al terminarlo. Guarda de dónde partía
/// la sesión para restarlo: así el bloque 2 empieza en cero aunque la sesión
/// lleve ya 4 kilómetros — que es justo lo que pedía David.
class MedidorBloque {
  final int indice;
  final String etiqueta;
  final String? zona;
  final int segundosPrevistos;

  final int _elapsedAlEmpezar;
  final int _metrosAlEmpezar;

  int _fcSuma = 0;
  int _fcCuenta = 0;
  int? _fcMax;
  int _ultimoElapsed;
  int _ultimosMetros;

  MedidorBloque({
    required this.indice,
    required this.etiqueta,
    required int elapsedSeg,
    required int metrosTotales,
    this.zona,
    this.segundosPrevistos = 0,
  })  : _elapsedAlEmpezar = elapsedSeg,
        _metrosAlEmpezar = metrosTotales,
        _ultimoElapsed = elapsedSeg,
        _ultimosMetros = metrosTotales;

  /// Segundos que lleva ESTE bloque.
  int get segundos => (_ultimoElapsed - _elapsedAlEmpezar).clamp(0, 1 << 30);

  /// Metros de ESTE bloque. Nunca negativos: si el GPS corrige hacia atrás
  /// —pasa, y más en zonas con mala cobertura— no puede restar distancia ya
  /// recorrida.
  int get metros => (_ultimosMetros - _metrosAlEmpezar).clamp(0, 1 << 30);

  /// Se llama en cada tick de la sesión.
  void anota({required int elapsedSeg, required int metrosTotales, int? fc}) {
    _ultimoElapsed = elapsedSeg;
    if (metrosTotales > _ultimosMetros) _ultimosMetros = metrosTotales;
    if (fc != null && fc >= 30 && fc <= 220) {
      _fcSuma += fc;
      _fcCuenta++;
      if (_fcMax == null || fc > _fcMax!) _fcMax = fc;
    }
  }

  ResultadoBloque cerrar() => ResultadoBloque(
        indice: indice,
        etiqueta: etiqueta,
        zona: zona,
        segundosPrevistos: segundosPrevistos,
        segundosReales: segundos,
        metros: metros,
        fcMedia: _fcCuenta > 0 ? (_fcSuma / _fcCuenta).round() : null,
        fcMax: _fcMax,
      );
}

/// "5:42" a partir de segundos por km.
String ritmoTexto(int segPorKm) =>
    '${segPorKm ~/ 60}:${(segPorKm % 60).toString().padLeft(2, '0')}';

/// Cómo se cuenta un ritmo EN VOZ ALTA.
///
/// ⚠️ NUNCA "5:42": el motor de voz lo lee como una hora ("las cinco cuarenta y
/// dos"). Ya pasó con el aviso de kilómetro y David lo reportó: "indica 7
/// minutos como horario". Todo número hablado va en palabras.
String ritmoHablado(int segPorKm) {
  final m = segPorKm ~/ 60;
  final s = segPorKm % 60;
  if (s == 0) return '$m minutos por kilómetro';
  return '$m minutos y $s segundos por kilómetro';
}

/// El veredicto del bloque: qué se le dice al cerrarlo.
///
/// Es lo que pedía: "cuando termina, lo ha realizado en X y ha estado dentro de
/// lo que indica el entrenador". Si no hay ritmo objetivo, se cuenta lo hecho
/// sin juzgar — inventarse un veredicto sin referencia sería peor que callarse.
String veredictoBloque(ResultadoBloque r, {int? ritmoObjetivoSegKm}) {
  final partes = <String>['Bloque ${r.indice + 1} completado'];

  if (r.metros >= 100) {
    final km = r.km;
    final kmTxt = km >= 1
        ? '${km.toStringAsFixed(2).replaceAll('.', ' coma ')} kilómetros'
        : '${r.metros} metros';
    partes.add(kmTxt);
  }

  final ritmo = r.ritmoSegPorKm;
  if (ritmo != null) {
    partes.add('a ${ritmoHablado(ritmo)}');

    if (ritmoObjetivoSegKm != null) {
      final diff = ritmo - ritmoObjetivoSegKm;   // positivo = más lento
      if (diff.abs() <= 10) {
        partes.add('justo en el ritmo que pedía tu entrenador');
      } else if (diff < 0) {
        partes.add('${diff.abs()} segundos más rápido de lo previsto');
      } else {
        partes.add('$diff segundos más lento de lo previsto');
      }
    }
  }

  if (r.fcMedia != null) partes.add('pulso medio ${r.fcMedia}');

  return '${partes.join('. ')}.';
}
