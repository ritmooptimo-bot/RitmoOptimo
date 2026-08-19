// ============================================================
//  EL COMPROBADOR: lo que ve el deportista TIENE que ser el plan.
//
//  ⚠️ DE DÓNDE SALE. El 19/08 el plan decía que la serie del viernes iba en
//  **R2** —entre VT1 y VT2, 155-164 ppm en David— y la app la pintaba
//  **«Z2 FC»**, que son 116-134. Treinta pulsaciones menos.
//
//  El deportista habría hecho su sesión de umbral a ritmo de rodaje suave
//  creyendo que iba bien, y el entrenador habría visto en su plan una sesión que
//  no es la que se ejecutó. Sin un solo error por ninguna parte.
//
//  La causa: `zonaFcNumero` sacaba el dígito de CUALQUIER etiqueta con una
//  expresión regular, así que «R2» daba 2 y de ahí «Z2 FC». Las dos escalas
//  comparten el dígito y NO son intercambiables: la R está anclada en umbrales
//  ventilatorios y es percepción; Z1-Z5 es porcentaje de FC máxima.
//
//  ─── QUÉ COMPRUEBA ───
//
//  Recorre las sesiones REALES del plan (volcadas de producción con
//  `backend/scripts/volcar_plan_para_app.mjs`) y exige que lo que la app enseña
//  sea lo mismo que dice el plan: la zona, los minutos, las repeticiones y los
//  ejercicios. Un test con datos inventados no habría cazado esto, porque el
//  fallo estaba en traducir una escala a otra.
//
//  Para refrescar el patrón:
//     cd backend && node scripts/volcar_plan_para_app.mjs
// ============================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmooptimo_mobile/core/session/resumen_bloque.dart';
import 'package:ritmooptimo_mobile/core/utils/zona_fc.dart';

void main() {
  final fichero = File('test/fixtures/plan_real.json');
  final datos = jsonDecode(fichero.readAsStringSync()) as Map<String, dynamic>;
  final sesiones = (datos['sesiones'] as List).cast<Map<String, dynamic>>();

  test('hay plan que comprobar', () {
    expect(sesiones, isNotEmpty,
        reason: 'sin patrón no se comprueba nada: regenera plan_real.json');
  });

  for (final s in sesiones) {
    final bloques = (s['planned_structure'] as List).cast<Map<String, dynamic>>();
    final nombre = '${s['fecha']} ${s['session_type']} "${s['title']}"';

    group(nombre, () {
      test('la ZONA que ve el deportista es la del plan, sin traducir', () {
        for (final b in bloques) {
          final zona = b['zone'];
          if (zona == null) continue;
          final escala = b['zone_escala'] as String?;
          final pintado = etiquetaZonaFc(zona, escala: escala);

          if (escala == 'percepcion') {
            // R2 se enseña como R2. NUNCA como Z2.
            expect(pintado, zona.toString().toUpperCase(),
                reason: 'el plan dice $zona y la app pinta $pintado '
                    'en "${b['block']}" — son escalas distintas');
            expect(pintado, isNot(startsWith('Z')),
                reason: '$zona es percepción: convertirla a Z cambia el esfuerzo');

            // ⚠️ Y TAMBIÉN SIN PASARLE LA ESCALA. El fallo real no fue que la
            // función tradujera mal cuando se le decía la escala: fue que quien
            // pintaba NO SE LA PASABA. Si la función no es segura por defecto,
            // basta que una pantalla nueva se olvide del parámetro para que
            // vuelva el «Z2 FC» sobre un bloque en R2.
            expect(etiquetaZonaFc(zona), isNot(startsWith('Z')),
                reason: 'sin escala, $zona se convierte en ${etiquetaZonaFc(zona)} '
                    '— la función tiene que ser segura por sí sola');
          } else {
            // En la escala de FC sí se etiqueta como tal, pero con SU número.
            expect(pintado, contains(RegExp(r'[1-7]')));
            final n = RegExp(r'[1-7]').firstMatch(zona.toString())?.group(0);
            if (n != null) {
              expect(pintado, contains(n),
                  reason: 'el plan dice $zona y la app pinta $pintado');
            }
          }
        }
      });

      test('las REPETICIONES que ve son las del plan', () {
        for (final b in bloques) {
          final reps = int.tryParse('${b['reps'] ?? ''}') ?? 0;
          final resumen = resumenSerieDe(b);
          if (reps >= 2 && (b['rep_duration_min'] != null || b['rep_distance_m'] != null)) {
            expect(resumen, isNotNull,
                reason: '"${b['block']}" tiene $reps repeticiones y la app no las enseña');
            expect(resumen, contains('$reps ×'),
                reason: 'el plan dice $reps y la app enseña «$resumen»');
            final rec = int.tryParse('${b['recovery_seconds'] ?? ''}') ?? 0;
            if (rec > 0) {
              expect(resumen, contains('recupera'),
                  reason: 'hay ${rec}s de recuperación y no se dicen');
            }
          } else {
            expect(resumen, isNull,
                reason: '"${b['block']}" no es una serie y la app enseña «$resumen»');
          }
        }
      });

      test('los EJERCICIOS que ve son los del plan, y con su nombre', () {
        for (final b in bloques) {
          final ej = (b['ejercicios'] as List?) ?? const [];
          final lineas = lineasEjercicios(b);
          expect(lineas.length, ej.length,
                reason: '"${b['block']}" tiene ${ej.length} ejercicios y se enseñan ${lineas.length}');

          for (var i = 0; i < ej.length; i++) {
            final e = ej[i] as Map<String, dynamic>;
            // ⚠️ El nombre, no el slug: nadie entrena un `movilidad_cadera_90_90`.
            final esperado = (e['nombre'] ?? e['slug']).toString();
            expect(lineas[i], startsWith(esperado));
            // Series y repeticiones/segundos, tal cual los pide el plan.
            if (e['reps'] != null) {
              expect(lineas[i], contains("${e['series']}×${e['reps']}"));
            } else if (e['tiempo_s'] != null) {
              expect(lineas[i], contains("${e['series']}×${e['tiempo_s']}s"));
            }
            // Y la carga con SU tipo.
            final carga = e['carga'] as Map?;
            if (carga != null && carga['tipo'] == 'kg') {
              expect(lineas[i], contains('${carga['valor']} kg'));
            }
          }
        }
      });

      test('los MINUTOS de los bloques suman lo que dice la sesión', () {
        final suma = bloques.fold<num>(
            0, (a, b) => a + (num.tryParse('${b['min'] ?? 0}') ?? 0));
        final total = num.tryParse('${s['duration_target_min']}') ?? 0;
        if (total > 0) {
          expect((suma - total).abs() <= 1, isTrue,
              reason: 'los bloques suman $suma y la sesión dice $total');
        }
      });
    });
  }
}
