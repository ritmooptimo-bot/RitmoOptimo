/// EL AVISO DE ZONA: decirle que se ha salido, sin volverse un pesado.
///
/// ⚠️ LO DIFÍCIL NO ES DETECTAR QUE SE HA SALIDO. Eso es una comparación. Lo
/// difícil es avisar **las veces justas**: un aviso cada tres segundos se aprende
/// a ignorar en dos minutos, y a partir de ahí la función está muerta aunque
/// funcione. Por eso los topes van EN CÓDIGO y no en un ajuste que nadie toca.
///
/// Tres frenos, y cada uno tapa un agujero distinto:
///
///   1. PERSISTENCIA — hay que estar fuera varios segundos seguidos. Un pico al
///      subir una cuesta o al esquivar un coche no es salirse de zona.
///   2. ESPERA entre avisos — tras hablar, se calla un rato aunque siga fuera.
///      Ya lo ha oído; repetirlo no añade información.
///   3. TOPE por sesión — pasado ese número no se vuelve a avisar. Si alguien va
///      fuera de zona todo el rato, el problema no se arregla hablándole doce
///      veces: se arregla en el plan, y eso lo verá su entrenador.
///
/// ⚠️ Y DOS REGLAS QUE NO SON DE COMODIDAD, SON DE HONESTIDAD:
///
///   · SIN LECTURA FRESCA NO HAY AVISO. Si la banda se ha soltado, la app no
///     sabe a qué va. Decirle «aprieta» con un número muerto es peor que
///     callarse — ya costó 40 minutos de sesión con el mismo 126.
///   · EN ESCALA DE PERCEPCIÓN NO SE AVISA NUNCA. La escala R de Raúl es «sin
///     reloj ni pulsómetro» por decisión metodológica: avisar por pulsaciones
///     en un bloque R1 sería entrenar contra su método.
library;

enum EstadoZona {
  /// Dentro del rango pedido.
  dentro,

  /// Por encima del techo del rango.
  porEncima,

  /// Por debajo del suelo del rango.
  porDebajo,

  /// No hay lectura utilizable de la banda. NO es "está en cero": es "no se sabe".
  sinDato,

  /// Este bloque no se mide por pulsaciones (percepción, ritmo, o sin objetivo).
  noAplica,
}

/// Un rango de pulsaciones. `hasta == null` = sin techo (la última zona).
class RangoFc {
  final int desde;
  final int? hasta;
  final String nombre;

  const RangoFc({required this.desde, this.hasta, this.nombre = ''});

  bool contiene(int bpm) => bpm >= desde && (hasta == null || bpm <= hasta!);

  /// "107-125 ppm" · "160+ ppm"
  String get texto => hasta == null ? '$desde+ ppm' : '$desde-$hasta ppm';
}

/// El resultado de un tick: en qué estado va y, si toca, qué decirle.
class ResultadoAviso {
  final EstadoZona estado;

  /// Lo que hay que decir en voz alta. `null` = no toca hablar ahora.
  final String? decir;

  /// true la primera vez que se detecta que ha salido (para vibrar).
  final bool vibrar;

  const ResultadoAviso(this.estado, {this.decir, this.vibrar = false});
}

class AvisoZona {
  /// Segundos seguidos fuera antes de abrir la boca.
  static const int persistenciaSeg = 20;

  /// Silencio obligatorio entre dos avisos.
  static const int esperaSeg = 90;

  /// Tope por sesión. Pasado esto, se calla para siempre.
  static const int maximoAvisos = 4;

  final RangoFc? objetivo;
  final String escala;

  int _fueraDesde = -1;      // segundo en que empezó a estar fuera
  int _ultimoAviso = -9999;  // segundo del último aviso dado
  int _avisosDados = 0;
  EstadoZona _ultimoEstado = EstadoZona.sinDato;
  bool _yaVibro = false;

  AvisoZona({this.objetivo, this.escala = 'desconocida'});

  int get avisosDados => _avisosDados;
  EstadoZona get estado => _ultimoEstado;

  /// ¿Este bloque se puede vigilar por pulsaciones?
  bool get aplica => escala == 'fc' && objetivo != null;

  /// Un segundo de sesión.
  ///
  /// [bpm] null significa **no se sabe** (banda suelta o lectura caducada), no
  /// cero. Quien llame no debe rellenarlo con el último valor conocido.
  ResultadoAviso tick(int segundo, int? bpm) {
    if (!aplica) {
      _ultimoEstado = EstadoZona.noAplica;
      return const ResultadoAviso(EstadoZona.noAplica);
    }

    if (bpm == null || bpm <= 0) {
      // Sin dato se reinicia la cuenta: no se acumulan segundos "fuera" de algo
      // que no se ha medido.
      _fueraDesde = -1;
      _yaVibro = false;
      _ultimoEstado = EstadoZona.sinDato;
      return const ResultadoAviso(EstadoZona.sinDato);
    }

    final r = objetivo!;
    final estado = r.contiene(bpm)
        ? EstadoZona.dentro
        : (bpm > (r.hasta ?? bpm) ? EstadoZona.porEncima : EstadoZona.porDebajo);
    _ultimoEstado = estado;

    if (estado == EstadoZona.dentro) {
      _fueraDesde = -1;
      _yaVibro = false;
      return const ResultadoAviso(EstadoZona.dentro);
    }

    // Ha salido. ¿Desde cuándo?
    if (_fueraDesde < 0) _fueraDesde = segundo;
    final llevaFuera = segundo - _fueraDesde;

    // Freno 1: todavía no lleva fuera el tiempo suficiente.
    if (llevaFuera < persistenciaSeg) return ResultadoAviso(estado);

    // La vibración va la PRIMERA vez, aunque toque callarse: es discreta y no
    // interrumpe la música. La voz tiene más frenos que la vibración.
    final vibrar = !_yaVibro;
    if (vibrar) _yaVibro = true;

    // Freno 3: el tope de la sesión.
    if (_avisosDados >= maximoAvisos) return ResultadoAviso(estado, vibrar: vibrar);

    // Freno 2: la espera entre avisos.
    if (segundo - _ultimoAviso < esperaSeg) return ResultadoAviso(estado, vibrar: vibrar);

    _ultimoAviso = segundo;
    _avisosDados++;
    return ResultadoAviso(estado, vibrar: vibrar, decir: _frase(estado, bpm, r));
  }

  /// Qué se le dice.
  ///
  /// Corto y con el número: quien corre con auriculares no retiene una frase
  /// larga. Y siempre con el rango, porque «vas alto» sin decir alto respecto a
  /// qué obliga a mirar el móvil, que es justo lo que se quiere evitar.
  String _frase(EstadoZona estado, int bpm, RangoFc r) {
    final zona = r.nombre.isEmpty ? '' : ' de ${r.nombre}';
    return estado == EstadoZona.porEncima
        ? 'Vas a $bpm. Afloja: el objetivo$zona es ${r.texto}.'
        : 'Vas a $bpm. Puedes apretar: el objetivo$zona es ${r.texto}.';
  }

  /// Al cambiar de bloque cambia el objetivo, pero el TOPE de la sesión no se
  /// reinicia: si se reiniciara, una sesión de seis bloques podría dar
  /// veinticuatro avisos y volveríamos al problema de origen.
  AvisoZona paraBloque({RangoFc? objetivo, String escala = 'desconocida'}) {
    final nuevo = AvisoZona(objetivo: objetivo, escala: escala);
    nuevo._avisosDados = _avisosDados;
    nuevo._ultimoAviso = _ultimoAviso;
    return nuevo;
  }
}
