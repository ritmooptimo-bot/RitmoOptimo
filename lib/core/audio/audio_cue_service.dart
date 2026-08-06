import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de audio para sesiones guiadas.
/// Genera beeps WAV en memoria (sin archivos de asset).
/// Fix #2: keepalive silencioso en loop para iOS background.
class AudioCueService {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _keepalivePlayer = AudioPlayer();

  // WAV generados una sola vez al init
  late final Uint8List _shortBeep;
  late final Uint8List _longBeep;
  late final Uint8List _silence;

  bool _initialized = false;
  bool _sessionActive = false;

  Future<void> init() async {
    if (_initialized) return;

    await _tts.setLanguage('es-ES');
    // v7.2.1: el atleta reporto que la voz hablaba demasiado rapido (antes 0.85)
    await _tts.setSpeechRate(0.42);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await aplicarVozGuardada();

    _shortBeep = buildBeepWav(frequency: 880, durationMs: 90);
    _longBeep  = buildBeepWav(frequency: 660, durationMs: 600);
    _silence   = _buildSilenceWav(durationMs: 2000);

    _initialized = true;
  }

  // ── VOZ: hombre o mujer ───────────────────────────────────────
  //
  // En Android los motores de voz NO dicen el sexo de cada voz: solo dan
  // nombres como "es-es-x-eef-local". Así que no se puede etiquetar con
  // certeza cuál es de hombre y cuál de mujer, y no vamos a adivinarlo y
  // ponerle un cartel que puede estar mal.
  //
  // Lo que sí se puede es dejar que el atleta las ESCUCHE y elija. La pantalla
  // de ajustes las lista con un botón de prueba; aquí solo se guarda y aplica
  // la que eligió.
  static const _clavePrefVoz = 'voz_tts_nombre';
  static const _clavePrefIdioma = 'voz_tts_idioma';

  /// Voces en español USABLES de este móvil.
  ///
  /// ⚠️ Se descartan las que el motor marca como `notInstalled`. Estaban en la
  /// lista y NO SUENAN: por eso el botón de escuchar "no hacía nada" — el
  /// atleta pulsaba una voz que no está descargada en el teléfono. Ofrecer algo
  /// que no funciona es peor que no ofrecerlo.
  ///
  /// Devuelve, por voz: `name`, `locale`, `necesitaRed` y `zona`
  /// ('espana' | 'latam'). El sexo NO va: Android no lo dice. Su clase Voice
  /// solo expone nombre, idioma, calidad, latencia y si requiere red — no hay
  /// campo de género, así que ponerlo sería inventárselo.
  Future<List<Map<String, String>>> vocesDisponibles() async {
    try {
      final crudas = await _tts.getVoices;
      if (crudas is! List) return [];

      final fuera = <Map<String, String>>[];
      for (final v in crudas) {
        if (v is! Map) continue;
        final locale = '${v['locale'] ?? ''}';
        if (!locale.toLowerCase().startsWith('es')) continue;

        final features = '${v['features'] ?? ''}';
        if (features.contains('notInstalled')) continue;   // no sonaría

        final name = '${v['name'] ?? ''}';
        if (name.isEmpty) continue;
        // Las "…-language" son el alias genérico del idioma, no una voz
        // concreta: aparecen duplicando a otra y confunden.
        if (name.toLowerCase().endsWith('-language')) continue;

        fuera.add({
          'name': name,
          'locale': locale,
          'necesitaRed': '${v['network_required'] ?? 0}' == '1' ? 'si' : 'no',
          'zona': locale.toLowerCase().startsWith('es-es') ? 'espana' : 'latam',
        });
      }

      // España primero (es el atleta que tenemos), y dentro, las que funcionan
      // sin internet antes que las que lo necesitan: en mitad de una carrera
      // puede no haber cobertura.
      fuera.sort((a, b) {
        final z = (a['zona'] == 'espana' ? 0 : 1) - (b['zona'] == 'espana' ? 0 : 1);
        if (z != 0) return z;
        final r = (a['necesitaRed'] == 'no' ? 0 : 1) - (b['necesitaRed'] == 'no' ? 0 : 1);
        if (r != 0) return r;
        return a['name']!.compareTo(b['name']!);
      });
      return fuera;
    } catch (e) {
      // ignore: avoid_print
      print('TTSVOZ ERROR listando: $e');
      return [];   // motor sin lista de voces → se queda la del sistema
    }
  }

  /// setVoice SOLO admite name+locale. Nuestros mapas llevan además `zona` y
  /// `necesitaRed` para pintar la lista; pasarlos tal cual haría que el motor
  /// rechazara la voz.
  static Map<String, String> _soloIdentidad(Map<String, String> v) =>
      {'name': v['name'] ?? '', 'locale': v['locale'] ?? 'es-ES'};

  /// Prueba una voz sin guardarla (el botón ▶). Devuelve true si sonó.
  Future<bool> probarVoz(Map<String, String> voz, String frase) async {
    try {
      await init();               // sin esto, a la primera el motor no está listo
      await _tts.stop();
      await _tts.setVoice(_soloIdentidad(voz));
      final r = await _tts.speak(frase);
      // speak devuelve 1 cuando el motor acepta el encargo.
      return r == 1 || r == true;
    } catch (e) {
      // ANTES SE TRAGABA EL ERROR EN SILENCIO y por eso el ▶ "no hacía nada"
      // sin dejar rastro por ningún lado. Ahora se ve y se avisa en pantalla.
      // ignore: avoid_print
      print('TTSVOZ ERROR probando ${voz['name']}: $e');
      return false;
    }
  }

  Future<void> guardarVoz(Map<String, String> voz) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_clavePrefVoz, voz['name'] ?? '');
    await p.setString(_clavePrefIdioma, voz['locale'] ?? 'es-ES');
    await aplicarVozGuardada();
  }

  bool _aplicandoVoz = false;
  Future<void> aplicarVozGuardada() async {
    // init() llama aquí y esto llamaba a init(): sin este cerrojo se quedaban
    // dando vueltas el uno al otro.
    if (_aplicandoVoz) return;
    _aplicandoVoz = true;
    try {
      final p = await SharedPreferences.getInstance();
      final nombre = p.getString(_clavePrefVoz);
      if (nombre == null || nombre.isEmpty) return;   // la del sistema
      await _tts.setVoice({
        'name': nombre,
        'locale': p.getString(_clavePrefIdioma) ?? 'es-ES',
      });
    } catch (_) {/* voz desinstalada → se queda la del sistema */}
    finally { _aplicandoVoz = false; }
  }

  // ── Session lifecycle ─────────────────────────────────────────

  Future<void> startSession() async {
    await init();
    _sessionActive = true;
    if (Platform.isIOS) {
      // Fix #2: reproducir silencio en loop para mantener iOS activo entre anuncios
      await _keepalivePlayer.setReleaseMode(ReleaseMode.loop);
      await _keepalivePlayer.play(BytesSource(_silence), volume: 0.001);
    }
  }

  Future<void> stopSession() async {
    _sessionActive = false;
    await _keepalivePlayer.stop();
    await _tts.stop();
  }

  // ── Audio primitives ──────────────────────────────────────────

  Future<void> speak(String text) async {
    if (!_sessionActive) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> beepShort() async {
    if (!_sessionActive) return;
    await _beepPlayer.play(BytesSource(_shortBeep), volume: 1.0);
  }

  Future<void> beepLong() async {
    if (!_sessionActive) return;
    await _beepPlayer.play(BytesSource(_longBeep), volume: 1.0);
  }

  /// 4 pitidos cortos (1/s) + 1 largo — para los últimos 5 segundos de bloque.
  Future<void> countdown5() async {
    for (int i = 0; i < 4; i++) {
      await _beepPlayer.play(BytesSource(_shortBeep), volume: 1.0);
      await Future.delayed(const Duration(milliseconds: 950));
    }
    await _beepPlayer.play(BytesSource(_longBeep), volume: 1.0);
  }

  void dispose() {
    _tts.stop();
    _beepPlayer.dispose();
    _keepalivePlayer.dispose();
  }

  // ── WAV generation (no archivos de asset necesarios) ─────────

  /// Genera un WAV PCM de 16-bit mono con una onda senoidal (beep puro).
  /// Público: también lo usa SoftChime (aviso de fin de medición de bienestar).
  static Uint8List buildBeepWav({
    required int frequency,
    required int durationMs,
    int sampleRate = 22050,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize   = numSamples * 2;
    final bd         = ByteData(44 + dataSize);
    _writeWavHeader(bd, dataSize, sampleRate);

    const pi = math.pi;
    final fadeLen = (sampleRate * 0.010).round(); // 10 ms fade in/out
    for (int i = 0; i < numSamples; i++) {
      double amp = 1.0;
      if (i < fadeLen)                     amp = i / fadeLen;
      else if (i > numSamples - fadeLen)   amp = (numSamples - i) / fadeLen;
      final v = (32767 * amp * math.sin(2 * pi * frequency * i / sampleRate))
          .round()
          .clamp(-32768, 32767);
      bd.setInt16(44 + i * 2, v, Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  /// Genera un WAV PCM de silencio total (datos = ceros).
  static Uint8List _buildSilenceWav({
    required int durationMs,
    int sampleRate = 22050,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize   = numSamples * 2;
    final bd         = ByteData(44 + dataSize);
    _writeWavHeader(bd, dataSize, sampleRate);
    // Todos los bytes de datos ya son 0 = silencio
    return bd.buffer.asUint8List();
  }

  static void _writeWavHeader(ByteData bd, int dataSize, int sampleRate) {
    // RIFF
    bd.setUint8(0, 0x52); bd.setUint8(1, 0x49); bd.setUint8(2, 0x46); bd.setUint8(3, 0x46);
    bd.setUint32(4, 36 + dataSize, Endian.little);
    bd.setUint8(8, 0x57); bd.setUint8(9, 0x41); bd.setUint8(10, 0x56); bd.setUint8(11, 0x45);
    // fmt
    bd.setUint8(12, 0x66); bd.setUint8(13, 0x6D); bd.setUint8(14, 0x74); bd.setUint8(15, 0x20);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1,  Endian.little); // PCM
    bd.setUint16(22, 1,  Endian.little); // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2,  Endian.little);
    bd.setUint16(34, 16, Endian.little);
    // data
    bd.setUint8(36, 0x64); bd.setUint8(37, 0x61); bd.setUint8(38, 0x74); bd.setUint8(39, 0x61);
    bd.setUint32(40, dataSize, Endian.little);
  }
}
