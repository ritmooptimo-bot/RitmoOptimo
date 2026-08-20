import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/skins/skin_config.dart';
import '../../core/network/api_client.dart';
import '../../providers/skin_provider.dart';

// ── TU RELOJ GARMIN ──────────────────────────────────────────────────
//
// Hasta hoy enlazar el Garmin era cosa del entrenador, desde el panel, pegando
// la clave del deportista. Está al revés: son los datos de salud del
// deportista, y la autorización tiene que ser suya.
//
// ⚠️ NINGÚN TEXTO DE ESTA PANTALLA ESTÁ ESCRITO AQUÍ. Los pasos, la lista de
// datos y el texto de la autorización los manda el servidor. Dos motivos:
//
//   1. La app es un APK. Corregir una palabra de una instrucción costaría
//      recompilar e instalarla en el móvil de cada deportista, e intervals.icu
//      puede mover un botón cualquier martes.
//   2. Lo que se guarda en `medical_consents.consent_text` tiene que ser
//      EXACTAMENTE lo que se le enseñó. Si la pantalla llevara su propia copia,
//      el día que una de las dos cambiara estaríamos guardando una autorización
//      que nadie leyó.
//
// ⚠️ Y la letra puede ir al 180 %: aquí no hay un solo `Row` con texto que no
// pueda encoger. Todo va en `Expanded` o `Flexible`.

/// El resumen que pinta la tarjeta de Ajustes, para que se vea el estado sin
/// tener que entrar. Esta pantalla lo invalida cada vez que cambia algo: si no,
/// Ajustes seguiría diciendo "sin conectar" después de conectarlo, y no habría
/// ningún error que mirar — solo un dato viejo, que es lo peor de encontrar.
final garminEstadoProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final d = await ref.read(apiClientProvider).getGarmin();
  return (d['estado'] as Map<String, dynamic>?) ?? const {};
});

class GarminScreen extends ConsumerStatefulWidget {
  const GarminScreen({super.key});

  @override
  ConsumerState<GarminScreen> createState() => _GarminScreenState();
}

class _GarminScreenState extends ConsumerState<GarminScreen> {
  Map<String, dynamic>? _datos;
  String? _error;
  bool _cargando = true;
  bool _trabajando = false;

  bool _autorizo = false;
  final _cuenta = TextEditingController();
  final _clave = TextEditingController();

  /// Lo que se le enseña justo después de conectar: cuántas noches han entrado.
  String? _recienConectado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cuenta.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final d = await ref.read(apiClientProvider).getGarmin();
      if (!mounted) return;
      setState(() { _datos = d; _cargando = false; });
      // Que Ajustes no se quede con el estado de antes.
      ref.invalidate(garminEstadoProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _mensaje(e); _cargando = false; });
    }
  }

  /// El error del servidor, si lo trae; si no, algo que se entienda.
  String _mensaje(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['error'] is String) return d['error'] as String;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return 'No hay conexión. Inténtalo cuando vuelvas a tener cobertura.';
      }
    }
    return 'Algo ha ido mal. Vuelve a intentarlo en un momento.';
  }

  Future<void> _conectar() async {
    setState(() { _trabajando = true; _error = null; });
    try {
      final r = await ref.read(apiClientProvider).conectarGarmin(
        cuenta: _cuenta.text.trim(),
        apiKey: _clave.text.trim(),
        autorizo: _autorizo,
      );
      if (!mounted) return;
      final b = r['bienestar'] as Map<String, dynamic>?;
      final n = (b?['total'] as num?)?.toInt() ?? 0;
      setState(() {
        _datos = {...?_datos, 'estado': r['estado']};
        _recienConectado = n > 0
            ? 'Hemos recibido $n ${n == 1 ? 'noche' : 'noches'} de tu reloj.'
            : 'Reloj conectado. Los datos irán entrando solos.';
        _clave.clear();
        _trabajando = false;
      });
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _mensaje(e); _trabajando = false; });
    }
  }

  Future<void> _buscarHistorial() async {
    setState(() { _trabajando = true; _error = null; });
    try {
      final r = await ref.read(apiClientProvider).traerHistorialGarmin();
      if (!mounted) return;
      final b = r['bienestar'] as Map<String, dynamic>?;
      final nuevos = (b?['nuevos'] as num?)?.toInt() ?? 0;
      setState(() {
        _datos = {...?_datos, 'estado': r['estado']};
        _recienConectado = nuevos > 0
            ? 'Han entrado $nuevos ${nuevos == 1 ? 'noche nueva' : 'noches nuevas'}.'
            : 'De momento no hay nada nuevo. En cuanto aparezca, entra solo.';
        _trabajando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _mensaje(e); _trabajando = false; });
    }
  }

  Future<void> _desconectar() async {
    // ⚠️ Se pregunta SIEMPRE qué pasa con los datos ya recibidos, y no hay
    // opción marcada por defecto: borrar el historial de salud de alguien no
    // puede ser el resultado de darle rápido a un botón.
    final skin = ref.read(activeSkinProvider);
    final borrar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: skin.backgroundCard,
        title: Text('Desconectar el reloj',
            style: TextStyle(color: skin.textPrimary, fontSize: 18)),
        content: Text(
          'Dejarás de recibir el sueño, el HRV y el pulso en reposo de tu Garmin.\n\n'
          '¿Qué hacemos con lo que ya nos habías dado?',
          style: TextStyle(color: skin.textSecondary, height: 1.4),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            // ⚠️ Con go_router se cierra con el context del builder. Usar el de
            // la pantalla deja la app en negro.
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancelar', style: TextStyle(color: skin.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Guardar mi historial',
                style: TextStyle(color: skin.accent, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Borrarlo todo',
                style: TextStyle(color: skin.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (borrar == null || !mounted) return;

    setState(() { _trabajando = true; _error = null; });
    try {
      await ref.read(apiClientProvider).desconectarGarmin(borrarDatos: borrar);
      if (!mounted) return;
      setState(() { _recienConectado = null; _autorizo = false; _trabajando = false; });
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = _mensaje(e); _trabajando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        iconTheme: IconThemeData(color: skin.textPrimary),
        title: Text('Tu reloj Garmin',
            style: TextStyle(color: skin.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w700)),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: skin.accent))
          : RefreshIndicator(
              onRefresh: _cargar,
              color: skin.accent,
              backgroundColor: skin.backgroundCard,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: _cuerpo(skin),
              ),
            ),
    );
  }

  List<Widget> _cuerpo(SkinConfig skin) {
    final estado = (_datos?['estado'] as Map<String, dynamic>?) ?? const {};
    final vinculado = estado['vinculado'] == true;
    return [
      if (_error != null) ...[_Aviso(texto: _error!, tono: skin.error, skin: skin),
                             const SizedBox(height: 16)],
      if (_recienConectado != null) ...[
        _Aviso(texto: _recienConectado!, tono: skin.success, skin: skin,
               icono: Icons.check_circle_outline),
        const SizedBox(height: 16),
      ],
      ...(vinculado ? _conectado(skin, estado) : _porConectar(skin)),
      const SizedBox(height: 32),
    ];
  }

  // ── YA ESTÁ CONECTADO ───────────────────────────────────────────────
  List<Widget> _conectado(SkinConfig skin, Map<String, dynamic> e) {
    final noches = (e['noches'] as num?)?.toInt() ?? 0;
    final desde = e['desde'] as String?;
    final historiaCorta = e['historiaCorta'] == true;

    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: skin.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.success.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.watch_outlined, color: skin.success, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Tu Garmin está conectado',
                    style: TextStyle(color: skin.textPrimary, fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              noches > 0
                  ? '$noches ${noches == 1 ? 'noche recibida' : 'noches recibidas'}'
                    '${desde != null ? ', desde el ${_enLetra(desde)}' : ''}.'
                  : 'Todavía no ha entrado ninguna noche. Suele tardar unas horas.',
              style: TextStyle(color: skin.textSecondary, height: 1.4),
            ),
            if (e['cuenta'] != null) ...[
              const SizedBox(height: 6),
              Text('Cuenta ${e['cuenta']}',
                  style: TextStyle(color: skin.textMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),

      // ⚠️ EL PASO QUE NADIE ADIVINA. intervals.icu solo trae lo nuevo: la
      // historia hay que pedirla, y hasta que no se pide no existe. Sin este
      // aviso el deportista ve dos semanas y cree que eso es todo lo que hay.
      if (historiaCorta) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: skin.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(skin.cardRadius),
            border: Border.all(color: skin.warning.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.history, color: skin.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Te falta tu historia',
                      style: TextStyle(color: skin.textPrimary,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'intervals.icu solo trae lo nuevo. Entra y pide la descarga de '
                'tus datos antiguos de Garmin: cuantas más noches tengamos, '
                'mejor sabremos cómo estás de verdad.',
                style: TextStyle(color: skin.textSecondary, height: 1.4, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],

      _Boton(
        texto: historiaCorta ? 'Ya los he pedido — búscalos' : 'Buscar mi historial ahora',
        icono: Icons.refresh,
        skin: skin,
        cargando: _trabajando,
        onPressed: _trabajando ? null : _buscarHistorial,
      ),
      const SizedBox(height: 10),
      Text(
        'No hace falta que lo hagas: se revisa solo una vez al día. Esto es por '
        'si acabas de pedirlos y quieres verlos ya.',
        style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.4),
      ),

      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: skin.error,
            side: BorderSide(color: skin.error.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(skin.cardRadius),
            ),
          ),
          onPressed: _trabajando ? null : _desconectar,
          child: const Text('Desconectar el reloj',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    ];
  }

  // ── TODAVÍA NO ─────────────────────────────────────────────────────
  List<Widget> _porConectar(SkinConfig skin) {
    final entra = (_datos?['entra'] as List?) ?? const [];
    final sale = (_datos?['sale'] as List?) ?? const [];
    final pasos = (_datos?['pasos'] as List?) ?? const [];
    final cons = (_datos?['consentimiento'] as Map<String, dynamic>?) ?? const {};

    return [
      // ── Por qué merece la pena ────────────────────────────────
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.watch_outlined, color: skin.accent, size: 32),
            const SizedBox(height: 12),
            Text('Conecta tu Garmin',
                style: TextStyle(color: skin.textPrimary, fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Tu reloj te mide toda la noche. Si nos dejas verlo, tu '
              'entrenamiento deja de ajustarse a lo que tocaba en el papel y '
              'empieza a ajustarse a cómo has descansado de verdad.',
              style: TextStyle(color: skin.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      _Titulo('Qué recibimos de tu reloj', skin),
      const SizedBox(height: 10),
      ...entra.map((x) => _Fila(dato: x as Map<String, dynamic>, skin: skin,
                               color: skin.accent)),

      if (sale.isNotEmpty) ...[
        const SizedBox(height: 20),
        _Titulo('Y qué te llega a ti', skin),
        const SizedBox(height: 10),
        ...sale.map((x) => _Fila(dato: x as Map<String, dynamic>, skin: skin,
                                 color: skin.success)),
      ],

      const SizedBox(height: 28),
      _Titulo('Cómo se hace', skin),
      const SizedBox(height: 12),
      ...pasos.map((x) => _Paso(paso: x as Map<String, dynamic>, skin: skin)),

      const SizedBox(height: 28),
      _Titulo('Tu autorización', skin),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: skin.backgroundCard,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          border: Border.all(color: skin.border),
        ),
        child: Text(
          (cons['texto'] as String?) ?? '',
          style: TextStyle(color: skin.textSecondary, fontSize: 13, height: 1.55),
        ),
      ),
      const SizedBox(height: 8),
      // El interruptor va SEPARADO del texto y arranca apagado: la autorización
      // se da a propósito, no por inercia de ir bajando por la pantalla.
      Row(
        children: [
          Switch(
            value: _autorizo,
            activeThumbColor: skin.accent,
            onChanged: (v) => setState(() => _autorizo = v),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _autorizo = !_autorizo),
              child: Text('Lo he leído y autorizo',
                  style: TextStyle(color: skin.textPrimary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),

      const SizedBox(height: 24),
      _Titulo('Tus datos de intervals.icu', skin),
      const SizedBox(height: 12),
      _Campo(
        controlador: _cuenta,
        etiqueta: 'Athlete ID',
        pista: 'i123456',
        skin: skin,
        alEscribir: (_) => setState(() {}),
        // Solo la i y números: así el error se ve al teclear y no después de
        // haber esperado a que responda el servidor.
        formatos: [FilteringTextInputFormatter.allow(RegExp(r'[i0-9]'))],
      ),
      const SizedBox(height: 12),
      _Campo(
        controlador: _clave,
        etiqueta: 'API Key',
        pista: 'la clave larga de Developer Settings',
        skin: skin,
        alEscribir: (_) => setState(() {}),
        oculto: true,
      ),
      const SizedBox(height: 20),

      _Boton(
        texto: 'Conectar mi reloj',
        icono: Icons.link,
        skin: skin,
        cargando: _trabajando,
        // Sin autorización el botón no se puede pulsar, y se ve que no se
        // puede: es más honesto que dejarlo vivo y soltar un error después.
        onPressed: (_autorizo && !_trabajando &&
                    _cuenta.text.trim().isNotEmpty && _clave.text.trim().isNotEmpty)
            ? _conectar
            : null,
      ),
      const SizedBox(height: 10),
      Text('Tu clave se guarda cifrada y no se enseña nunca, ni a tu entrenador.',
          style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.4)),
    ];
  }

  /// '2025-08-04' → '4 de agosto de 2025'. Sin depender de nada de fuera.
  String _enLetra(String iso) {
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
                   'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final p = iso.split('-');
    if (p.length != 3) return iso;
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (m == null || d == null || m < 1 || m > 12) return iso;
    return '$d de ${meses[m - 1]} de ${p[0]}';
  }
}

// ── Piezas ───────────────────────────────────────────────────────────

class _Titulo extends StatelessWidget {
  final String texto;
  final SkinConfig skin;
  const _Titulo(this.texto, this.skin);

  @override
  Widget build(BuildContext context) => Text(texto.toUpperCase(),
      style: TextStyle(color: skin.textMuted, fontSize: 12,
          fontWeight: FontWeight.w700, letterSpacing: 0.5));
}

class _Fila extends StatelessWidget {
  final Map<String, dynamic> dato;
  final SkinConfig skin;
  final Color color;
  const _Fila({required this.dato, required this.skin, required this.color});

  static const _iconos = {
    'sleep': Icons.bedtime_outlined,
    'hrv': Icons.monitor_heart_outlined,
    'heart': Icons.favorite_outline,
    'activity': Icons.directions_run,
    'watch': Icons.watch_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconos[dato['icono']] ?? Icons.check_circle_outline,
              color: color, size: 20),
          const SizedBox(width: 12),
          // Expanded: con la letra al 180 % un texto que no puede encoger se
          // recorta sin avisar de nada.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${dato['titulo']}',
                    style: TextStyle(color: skin.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${dato['detalle']}',
                    style: TextStyle(color: skin.textMuted, fontSize: 13,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  final Map<String, dynamic> paso;
  final SkinConfig skin;
  const _Paso({required this.paso, required this.skin});

  @override
  Widget build(BuildContext context) {
    final clave = paso['clave'] == true;
    final color = clave ? skin.warning : skin.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: clave ? skin.warning.withValues(alpha: 0.08) : skin.backgroundCard,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(
            color: clave ? skin.warning.withValues(alpha: 0.4) : skin.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text('${paso['n']}',
                style: TextStyle(color: color, fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${paso['titulo']}',
                    style: TextStyle(color: skin.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${paso['detalle']}',
                    style: TextStyle(color: skin.textSecondary, fontSize: 13,
                        height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  final TextEditingController controlador;
  final String etiqueta;
  final String pista;
  final SkinConfig skin;
  final bool oculto;
  final List<TextInputFormatter>? formatos;
  /// ⚠️ OBLIGATORIO, y por eso no tiene valor por defecto. El botón de conectar
  /// se activa según lo que haya escrito en los campos, y un `TextField` NO
  /// repinta la pantalla al teclear: sin esto el botón se quedaba apagado con
  /// los dos campos llenos, sin ningún error y sin nada que mirar.
  final ValueChanged<String> alEscribir;

  const _Campo({
    required this.controlador, required this.etiqueta,
    required this.pista, required this.skin, required this.alEscribir,
    this.oculto = false, this.formatos,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controlador,
      obscureText: oculto,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: formatos,
      onChanged: alEscribir,
      style: TextStyle(color: skin.textPrimary),
      decoration: InputDecoration(
        labelText: etiqueta,
        hintText: pista,
        labelStyle: TextStyle(color: skin.textMuted),
        hintStyle: TextStyle(color: skin.textMuted.withValues(alpha: 0.6)),
        filled: true,
        fillColor: skin.backgroundCard,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
          borderSide: BorderSide(color: skin.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
          borderSide: BorderSide(color: skin.accent, width: 2),
        ),
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  final String texto;
  final IconData icono;
  final SkinConfig skin;
  final bool cargando;
  final VoidCallback? onPressed;

  const _Boton({
    required this.texto, required this.icono, required this.skin,
    required this.cargando, required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: skin.accent,
          foregroundColor: skin.background,
          disabledBackgroundColor: skin.border,
          disabledForegroundColor: skin.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(skin.cardRadius),
          ),
        ),
        onPressed: onPressed,
        child: cargando
            ? SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: skin.background))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icono, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(texto,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final Color tono;
  final SkinConfig skin;
  final IconData icono;

  const _Aviso({
    required this.texto, required this.tono, required this.skin,
    this.icono = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tono.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(color: tono.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: tono, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: TextStyle(color: skin.textPrimary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
