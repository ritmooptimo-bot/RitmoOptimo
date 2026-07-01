import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _shortBeep = _buildBeepWav(frequency: 880, durationMs: 90);
    _longBeep  = _buildBeepWav(frequency: 660, durationMs: 600);
    _silence   = _buildSilenceWav(durationMs: 2000);

    _initialized = true;
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
  static Uint8List _buildBeepWav({
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
