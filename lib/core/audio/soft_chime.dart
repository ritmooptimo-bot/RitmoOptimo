import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'audio_cue_service.dart';

/// Aviso de "medición completada" para las tomas de FC/HRV de bienestar.
/// El deportista suele cerrar los ojos para relajarse durante la toma: dos
/// notas suaves ascendentes + una vibración corta le avisan de que terminó.
/// Independiente del audio de sesiones guiadas (no toca su ciclo de vida).
class SoftChime {
  SoftChime._();
  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _nota1, _nota2;

  static Future<void> measurementDone() async {
    try {
      _nota1 ??= AudioCueService.buildBeepWav(frequency: 587, durationMs: 180);
      _nota2 ??= AudioCueService.buildBeepWav(frequency: 784, durationMs: 340);
      HapticFeedback.mediumImpact();
      await _player.play(BytesSource(_nota1!), volume: 0.5);
      await Future.delayed(const Duration(milliseconds: 220));
      await _player.play(BytesSource(_nota2!), volume: 0.5);
    } catch (_) {
      // El aviso jamás debe romper la medición.
    }
  }
}
