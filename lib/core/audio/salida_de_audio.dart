/// Lo único que el guía de sesión necesita de la voz.
///
/// ⚠️ POR QUÉ EXISTE ESTE FICHERO. `SessionAudioController` dependía de
/// `AudioCueService`, que construye un `FlutterTts` y dos `AudioPlayer` en sus
/// campos. Eso hace imposible probarlo: en un test, crear la clase revienta
/// porque los plugins no están.
///
/// Y lo que hay que probar es justo lo caro de comprobar a mano — la secuencia
/// de una sesión de series entera: «serie 1 de 3», los últimos diez segundos,
/// el descanso, la serie 2… Salir a correr veintisiete minutos para ver si la
/// voz dice lo que toca no es una forma de verificar nada.
///
/// Con esta interfaz, un test puede pasar un doble que solo apunta lo que se
/// dice, y `AudioCueService` sigue siendo exactamente lo que era.
abstract class SalidaDeAudio {
  Future<void> startSession();
  Future<void> stopSession();
  Future<void> speak(String text);
  Future<void> beepShort();
  Future<void> beepLong();
  Future<void> countdown5();
}
