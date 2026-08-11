import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/skin_provider.dart';
import '../../config/skins/skin_config.dart';
import '../../core/audio/soft_chime.dart';
import '../../models/ejercicio.dart';
import '../../core/network/api_client.dart';

/// Sesión de FUERZA guiada, serie a serie.
///
/// ⚠️ POR QUÉ ES UNA PANTALLA APARTE. La de siempre está construida sobre GPS,
/// ritmo y frecuencia cardiaca: un cronómetro, los metros y el ritmo suavizado.
/// Para una sentadilla nada de eso significa nada. Lo que hace falta aquí es
/// otra cosa: qué ejercicio toca, por qué serie vas, y cuánto queda de descanso.
///
/// ⚠️ SE DISEÑA A LETRA DEL 180 % DESDE EL PRINCIPIO, no se adapta después.
/// Es la escala real del móvil de pruebas, y esta pantalla es la más difícil del
/// proyecto en ese sentido: muchos números y poco sitio. De ahí que todo vaya en
/// un scroll (un `Column` que no cabe RECORTA sin avisar, y el analizador calla),
/// que los números grandes vayan en `FittedBox`, y que no haya ninguna fila con
/// tres datos compitiendo por el ancho.
class FuerzaSessionScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final Future<void> Function(List<Map<String, dynamic>> realizado)? onFinish;

  /// De dónde sale el historial ("la última vez: 3×10 con 22 kg").
  ///
  /// Se inyecta en vez de llamar directamente al cliente para que la pantalla
  /// se pueda probar SIN red — y, sobre todo, para poder probar cómo se LEE el
  /// historial, que es lo que de verdad importa comprobar aquí.
  final Future<Map<String, dynamic>> Function(List<String> slugs)? cargarHistorial;

  const FuerzaSessionScreen({super.key, required this.session, this.onFinish,
                             this.cargarHistorial});

  @override
  ConsumerState<FuerzaSessionScreen> createState() => _FuerzaSessionScreenState();
}

class _FuerzaSessionScreenState extends ConsumerState<FuerzaSessionScreen> {
  late final List<PasoSerie> _pasos;
  int _i = 0;                     // paso actual
  bool _descansando = false;
  int _restante = 0;
  Timer? _timer;

  /// Lo que de VERDAD ha hecho, serie a serie. Va a `actual_structure`.
  /// Sin esto no hay historial ("la última vez: 3×10 con 22 kg"), que es lo que
  /// permite saber si progresa.
  final List<Map<String, dynamic>> _hecho = [];

  /// La última vez que hizo cada ejercicio. Llega después de pintar: la sesión
  /// tiene que poder empezar aunque el historial tarde o falle.
  Map<String, dynamic> _historial = const {};

  @override
  void initState() {
    super.initState();
    _pasos = PasoSerie.desdeBloques(
        BloqueFuerza.desdeEstructura(widget.session['structure']));
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    final slugs = _pasos.map((p) => p.ejercicio.slug).toSet().toList();
    if (slugs.isEmpty) return;
    final traer = widget.cargarHistorial ??
        (s) => ref.read(apiClientProvider).getExerciseHistory(s);
    final h = await traer(slugs);
    if (mounted) setState(() => _historial = h);
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  PasoSerie? get _paso => _i < _pasos.length ? _pasos[_i] : null;
  PasoSerie? get _siguiente => _i + 1 < _pasos.length ? _pasos[_i + 1] : null;
  bool get _terminada => _i >= _pasos.length;

  void _registrarYDescansar({int? reps, int? tiempoS}) {
    final p = _paso;
    if (p == null) return;
    _hecho.add({
      'slug': p.ejercicio.slug,
      'serie': p.serie,
      'ronda': p.ronda,
      'reps': reps ?? p.ejercicio.reps,
      'tiempo_s': tiempoS ?? p.ejercicio.tiempoS,
      if (p.ejercicio.cargaTipo != null)
        'carga': {'tipo': p.ejercicio.cargaTipo, 'valor': p.ejercicio.cargaValor},
      'ts': DateTime.now().toIso8601String(),
    });

    // Tras la ÚLTIMA serie no se descansa: se termina.
    if (_i + 1 >= _pasos.length) { setState(() => _i++); return; }

    setState(() { _i++; _descansando = true; _restante = p.descansoS; });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _restante--);
      if (_restante <= 0) {
        t.cancel();
        setState(() => _descansando = false);
        // El deportista no está mirando el móvil mientras descansa: el aviso
        // sonoro es lo que hace que el descanso sirva de algo.
        SoftChime.measurementDone();
      }
    });
  }

  void _saltarDescanso() {
    _timer?.cancel();
    setState(() { _descansando = false; _restante = 0; });
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        foregroundColor: skin.textPrimary,
        title: Text(widget.session['title']?.toString() ?? 'Fuerza',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      // Scroll SIEMPRE. Ver la nota de arriba sobre la letra al 180 %.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _Progreso(skin: skin, hechas: _i, total: _pasos.length),
          const SizedBox(height: 20),
          if (_terminada)
            _Final(skin: skin, hechas: _hecho.length,
                   onGuardar: () async { await widget.onFinish?.call(_hecho); })
          else if (_descansando)
            _Descanso(skin: skin, restante: _restante, siguiente: _paso,
                      onSaltar: _saltarDescanso)
          else
            _Ejercicio(skin: skin, paso: _paso!, siguiente: _siguiente,
                       ultimaVez: _historial[_paso!.ejercicio.slug] as Map<String, dynamic>?,
                       onHecha: _registrarYDescansar),
        ],
      ),
    );
  }
}

// ── Cuánto llevas ──────────────────────────────────────────────────────
class _Progreso extends StatelessWidget {
  final SkinConfig skin; final int hechas; final int total;
  const _Progreso({required this.skin, required this.hechas, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : hechas / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('SERIE ${hechas < total ? hechas + 1 : total} DE $total',
          style: TextStyle(color: skin.accent, fontSize: 11,
              letterSpacing: 1.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct, minHeight: 6,
          backgroundColor: skin.textMuted.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation(skin.accent),
        ),
      ),
    ]);
  }
}

// ── El ejercicio que toca ──────────────────────────────────────────────
class _Ejercicio extends StatelessWidget {
  final SkinConfig skin;
  final PasoSerie paso;
  final PasoSerie? siguiente;
  final Map<String, dynamic>? ultimaVez;
  final void Function({int? reps, int? tiempoS}) onHecha;

  const _Ejercicio({required this.skin, required this.paso,
                    required this.siguiente, required this.onHecha,
                    this.ultimaVez});

  /// "La última vez: 3×10 · 22 kg · hace 6 días"
  ///
  /// Sin fecha no vale: "3×10 con 22 kg" de hace tres meses no es una
  /// referencia, es un recuerdo — y compararse con ella induce a error.
  String? get _resumenUltimaVez {
    final u = ultimaVez;
    if (u == null) return null;
    final series = u['series'];
    final cuanto = u['reps'] != null ? '$series×${u['reps']}'
                 : u['tiempo_s'] != null ? '$series×${u['tiempo_s']}s'
                 : '$series series';
    final c = u['carga'] as Map?;
    final carga = c == null || c['tipo'] == 'peso_corporal' ? null
                : c['tipo'] == 'kg'    ? '${c['valor']} kg'
                : c['tipo'] == 'rir'   ? 'RIR ${c['valor']}'
                : c['tipo'] == 'rpe'   ? 'RPE ${c['valor']}/10'
                : c['tipo'] == 'banda' ? 'banda ${c['valor']}'
                : '${c['valor']}';
    final d = u['hace_dias'] as int?;
    final cuando = d == null ? null
                 : d <= 0 ? 'hoy' : d == 1 ? 'ayer' : 'hace $d días';
    return [cuanto, carga, cuando].whereType<String>().join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final e = paso.ejercicio;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(paso.bloque.toUpperCase(),
          style: TextStyle(color: skin.textMuted, fontSize: 11, letterSpacing: 1.2)),
      const SizedBox(height: 6),
      Text(e.nombre,
          style: TextStyle(color: skin.textPrimary, fontSize: 26,
              fontWeight: FontWeight.w800, height: 1.15)),
      const SizedBox(height: 14),

      // Serie y ronda. En columna a propósito: dos datos en una fila con la
      // letra al 180 % se recortan sin avisar.
      Text(
        paso.deRondas > 1
            ? 'Serie ${paso.serie} de ${paso.deSeries}  ·  Ronda ${paso.ronda} de ${paso.deRondas}'
            : 'Serie ${paso.serie} de ${paso.deSeries}',
        style: TextStyle(color: skin.textSecondary, fontSize: 15,
            fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 18),

      // El objetivo, en grande: es lo único que tiene que leer de un vistazo
      // entre serie y serie.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: skin.accent.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(e.objetivo,
                maxLines: 1,
                style: TextStyle(color: skin.textPrimary, fontSize: 36,
                    fontWeight: FontWeight.w800,
                    fontFamily: skin.fontFamilyMono)),
          ),
          if (e.carga != null) ...[
            const SizedBox(height: 6),
            Text(e.carga!,
                style: TextStyle(color: skin.accent, fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
      ),

      // ⚠️ EL HISTORIAL ES LO QUE MÁS ENGANCHA de una app de fuerza, y no es
      // decoración: sin él el deportista no sabe si progresa. Levantar 22 kg no
      // significa nada; levantar 22 donde la semana pasada levantaste 20, sí.
      // Va justo debajo del objetivo, que es donde se compara.
      if (_resumenUltimaVez != null) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.history, size: 16, color: skin.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text('La última vez: ${_resumenUltimaVez!}',
              style: TextStyle(color: skin.textMuted, fontSize: 13))),
        ]),
      ],

      if ((e.nota ?? '').isNotEmpty) ...[
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: skin.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(e.nota!,
              style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.35))),
        ]),
      ],

      const SizedBox(height: 26),
      SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton(
          onPressed: () => onHecha(),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('SERIE HECHA', maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
        ),
      ),

      if (siguiente != null) ...[
        const SizedBox(height: 18),
        Text('Después: ${siguiente!.ejercicio.nombre}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: skin.textMuted, fontSize: 13)),
      ],
    ]);
  }
}

// ── Descanso ───────────────────────────────────────────────────────────
class _Descanso extends StatelessWidget {
  final SkinConfig skin; final int restante;
  final PasoSerie? siguiente; final VoidCallback onSaltar;
  const _Descanso({required this.skin, required this.restante,
                   required this.siguiente, required this.onSaltar});

  @override
  Widget build(BuildContext context) {
    final m = restante ~/ 60, s = restante % 60;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('DESCANSO',
          style: TextStyle(color: skin.warning, fontSize: 12,
              letterSpacing: 2, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '$s s',
            maxLines: 1,
            style: TextStyle(color: skin.textPrimary, fontSize: 64,
                fontWeight: FontWeight.w800, fontFamily: skin.fontFamilyMono)),
      ),
      const SizedBox(height: 20),
      if (siguiente != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: skin.backgroundCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AHORA VIENE',
                style: TextStyle(color: skin.textMuted, fontSize: 10, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Text(siguiente!.ejercicio.nombre,
                style: TextStyle(color: skin.textPrimary, fontSize: 19,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text([siguiente!.ejercicio.objetivo, siguiente!.ejercicio.carga]
                    .whereType<String>().join('  ·  '),
                style: TextStyle(color: skin.textSecondary, fontSize: 14)),
          ]),
        ),
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity, height: 52,
        child: OutlinedButton(
          onPressed: onSaltar,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('ESTOY LISTO', maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ),
        ),
      ),
    ]);
  }
}

// ── Final ──────────────────────────────────────────────────────────────
class _Final extends StatelessWidget {
  final SkinConfig skin; final int hechas; final Future<void> Function() onGuardar;
  const _Final({required this.skin, required this.hechas, required this.onGuardar});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.check_circle, color: skin.success, size: 60),
      const SizedBox(height: 14),
      Text('Sesión completada',
          style: TextStyle(color: skin.textPrimary, fontSize: 24,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('$hechas series registradas. Queda anotado para tu entrenador y para '
           'saber por dónde seguir la próxima vez.',
          style: TextStyle(color: skin.textSecondary, fontSize: 14, height: 1.4)),
      const SizedBox(height: 26),
      SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton(
          onPressed: onGuardar,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('GUARDAR', maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
        ),
      ),
    ]);
  }
}
