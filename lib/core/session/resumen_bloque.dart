import '../utils/zona_fc.dart';

/// Qué se va a hacer en un bloque, en una línea.
///
/// ⚠️ POR QUÉ ESTÁ AQUÍ Y NO DENTRO DE LA TARJETA. La tarjeta del plan enseñaba
/// solo etiqueta, minutos y zona: en una sesión de series se leía
/// «Series 3 x 8 min · 27 min · R2» y ni una palabra de cuántas repeticiones,
/// cuánto dura cada una ni cuánto se recupera. En una de fuerza, «Fuerza
/// general · 25 min · R1» y ningún ejercicio. El dato viajaba en el bloque
/// desde el backend y no se pintaba.
///
/// Vive fuera del widget para poder PROBARLO. Hoy han aparecido tres cosas
/// escritas, completas y que no se ejecutaban nunca —la guía de repeticiones,
/// el aviso de zona y la pantalla de fuerza entera—, y todas tenían en común
/// que no había forma de comprobarlas sin salir a correr.

String _mmss(num seg) {
  final s = seg.round();
  if (s < 60) return '$s s';
  final m = s ~/ 60, r = s % 60;
  return r == 0 ? "$m'" : "$m' $r\"";
}

/// «3 × 8' · recupera 1' 30" en R1», o null si el bloque no es una serie.
String? resumenSerieDe(Map<String, dynamic> b) {
  final reps = int.tryParse('${b['reps'] ?? b['repetitions'] ?? ''}') ?? 0;
  if (reps < 2) return null;

  final repMin = num.tryParse('${b['rep_duration_min'] ?? ''}');
  final dist = int.tryParse('${b['rep_distance_m'] ?? ''}');
  final trabajo = repMin != null && repMin > 0
      ? _mmss(repMin * 60)
      : (dist != null && dist > 0 ? '$dist m' : null);
  // ⚠️ Media serie no se enseña: anunciar «6 series» sin decir de cuánto es
  // peor que no anunciar nada — el deportista no sabe qué hacer con eso.
  if (trabajo == null) return null;

  final rec = int.tryParse('${b['recovery_seconds'] ?? ''}') ?? 0;
  final zonaRec = b['recovery_zone'];
  final recTxt = rec > 0
      ? ' · recupera ${_mmss(rec)}'
          '${zonaRec != null ? ' en ${etiquetaZonaFc(zonaRec) ?? zonaRec}' : ''}'
      : '';
  return '$reps × $trabajo$recTxt';
}

/// Una línea por ejercicio: «Sentadilla goblet — 3×10 · RIR 4 · desc 60s».
///
/// Vacía si el bloque no lleva ejercicios (una sesión de carrera, sin ir más
/// lejos), que es lo que permite usar esto en cualquier bloque sin preguntar.
List<String> lineasEjercicios(Map<String, dynamic> b) {
  final ej = b['ejercicios'];
  if (ej is! List) return const [];

  return ej.whereType<Map>().map((e) {
    // El nombre es lo primero: nadie entrena un slug. Si el backend no lo
    // enriqueció, se cae al slug antes que dejarlo en blanco.
    final nombre = (e['nombre'] ?? e['slug'] ?? '').toString();
    final series = e['series'] ?? 1;
    final cuanto = e['reps'] != null
        ? '$series×${e['reps']}'
        : (e['tiempo_s'] != null ? '$series×${e['tiempo_s']}s' : '$series series');

    // ⚠️ La carga SIEMPRE con su tipo: un 20 en kilos y un 2 de RIR no son la
    // misma escala, y esa confusión ya ha costado tres veces en esta casa.
    final carga = e['carga'] is Map ? e['carga'] as Map : null;
    final cargaTxt =
        carga == null || carga['tipo'] == null || carga['tipo'] == 'peso_corporal'
            ? ''
            : carga['tipo'] == 'kg'
                ? ' · ${carga['valor']} kg'
                : ' · ${carga['tipo'].toString().toUpperCase()} ${carga['valor'] ?? ''}';

    final desc = e['descanso_s'] != null ? ' · desc ${e['descanso_s']}s' : '';
    final lado = e['unilateral'] == true ? ' (por lado)' : '';
    return '$nombre — $cuanto$lado$cargaTxt$desc';
  }).toList();
}

/// «3 rondas · 90s entre rondas», o null si no es un circuito.
String? resumenRondas(Map<String, dynamic> b) {
  final rondas = int.tryParse('${b['rondas'] ?? ''}') ?? 0;
  if (rondas < 2) return null;
  final entre = int.tryParse('${b['descanso_entre_rondas_s'] ?? ''}') ?? 0;
  return '$rondas rondas${entre > 0 ? ' · ${entre}s entre rondas' : ''}';
}
