import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/skin_provider.dart';
import '../../core/ble/ble_service.dart';

// ── BLE Scan Screen ──────────────────────────────────────────────
// Muestra dispositivos BLE con Heart Rate Service (UUID 0x180D).
// Al seleccionar uno lo conecta y hace pop() devolviendo el device.
// "Continuar sin sensor" hace pop() con null.

class BleScanScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const BleScanScreen({super.key, required this.sessionId});

  @override
  ConsumerState<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends ConsumerState<BleScanScreen> {
  List<ScanResult> _results    = [];
  bool             _scanning   = false;
  bool             _connecting = false;
  bool             _wideMode   = false; // true = busca todos los BLE, no solo HR
  String?          _errorMsg;
  String?          _avisoBt;   // el aviso de apagar y encender el Bluetooth
  String?          _ultimaId;  // la banda de siempre, para ponerla la primera
  StreamSubscription<List<ScanResult>>? _sub;
  StreamSubscription<bool>?             _subBuscando;

  @override
  void initState() {
    super.initState();
    // El estado de "buscando" lo dice el propio Bluetooth, no un temporizador.
    // Antes era un `Future.delayed(20s)` fijo: si la búsqueda fallaba al
    // arrancar, la ruedecita seguía girando veinte segundos igualmente y luego
    // decía "Ningún sensor encontrado". Parecía que había buscado y no.
    _subBuscando = ref.read(bleServiceProvider).buscando.listen((b) {
      if (mounted) setState(() => _scanning = b);
    });
    _cargarUltima();
    _startScan();
  }

  Future<void> _cargarUltima() async {
    final u = await ref.read(bleServiceProvider).ultimaBanda();
    if (mounted && u != null) setState(() => _ultimaId = u.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subBuscando?.cancel();
    ref.read(bleServiceProvider).stopScan();
    super.dispose();
  }

  Future<void> _startScan({bool wide = false}) async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() => _errorMsg = 'Activa el Bluetooth para buscar sensores.');
      return;
    }

    setState(() {
      _wideMode = wide;
      _results  = [];
      _errorMsg = null;
      _avisoBt  = null;
    });

    await _sub?.cancel();
    final ble = ref.read(bleServiceProvider);
    final r = await ble.buscar(ampliada: wide);

    if (!mounted) return;

    // ⚠️ EL CASO QUE EXPLICA "APAGA Y ENCIENDE EL BLUETOOTH".
    // Android corta las búsquedas al pasar de cinco en treinta segundos, y lo
    // hace SIN dar error: simplemente deja de encontrar cosas. Hasta ahora la
    // pantalla decía "Ningún sensor encontrado" y quedabas tú a solas con la
    // sospecha de que se había roto la banda.
    if (!r.arrancada && r.espera > Duration.zero) {
      setState(() => _avisoBt =
          'Android ha bloqueado la búsqueda por repetirla muchas veces seguidas '
          '(deja pasar 5 cada medio minuto). Espera ${r.espera.inSeconds} s y vuelve a '
          'darle a Repetir.\n\nSi sigue sin aparecer: apaga y enciende el Bluetooth '
          'del móvil — eso reinicia el contador de Android y lo desatasca.');
      return;
    }
    if (!r.arrancada) {
      setState(() => _errorMsg =
          'No se pudo iniciar la búsqueda. Apaga y enciende el Bluetooth del móvil '
          'y vuelve a intentarlo.');
      return;
    }

    _sub = ble.resultados.listen((results) {
      if (!mounted) return;
      final lista = [...results];
      // La de siempre primero, y el resto por potencia de señal: la banda que
      // llevas puesta es la que más fuerte llega, casi siempre.
      lista.sort((a, b) {
        final aEs = a.device.remoteId.str == _ultimaId;
        final bEs = b.device.remoteId.str == _ultimaId;
        if (aEs != bEs) return aEs ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });
      setState(() => _results = lista);
    });
  }

  Future<void> _onSelect(BluetoothDevice device) async {
    setState(() { _connecting = true; _errorMsg = null; _avisoBt = null; });
    try {
      final ble = ref.read(bleServiceProvider);
      await ble.stopScan();
      final tieneFc = await ble.connect(device);

      // Conectado, sí… ¿pero a algo que dé pulsaciones? Antes esto no se
      // comprobaba: te dejaba entrar en la sesión con un altavoz conectado y
      // "Esperando dato…" hasta el final del entrenamiento.
      if (!tieneFc) {
        await ble.disconnect();
        if (!mounted) return;
        setState(() {
          _connecting = false;
          _errorMsg   = 'Ese aparato se conecta, pero no envía frecuencia cardíaca: '
                        'no es tu banda. Busca uno que salga con el corazón lleno.';
        });
        return;
      }
      if (mounted) context.pop(device);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _errorMsg   = 'No se pudo conectar. Comprueba que el sensor esté encendido y en rango.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(activeSkinProvider);

    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.backgroundSecondary,
        leading: IconButton(
          icon: Icon(Icons.close, color: skin.textPrimary),
          onPressed: () => context.pop(null),
        ),
        title: Text(
          'CONECTAR SENSOR FC',
          style: TextStyle(
              color: skin.textPrimary, letterSpacing: 2, fontSize: 14),
        ),
      ),
      body: _connecting
          ? _ConnectingView(skin: skin)
          : Column(
              children: [
                // ── Estado del scan ─────────────────────────
                _ScanStatusBar(
                  scanning: _scanning,
                  resultsCount: _results.length,
                  wideMode: _wideMode,
                  skin: skin,
                  onRetry: () => _startScan(),
                  onWide:  () => _startScan(wide: true),
                ),

                // ── Error ────────────────────────────────────
                if (_errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    child: Text(
                      _errorMsg!,
                      style: TextStyle(color: skin.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // ── El aviso del Bluetooth ───────────────────
                // No es un error de la app ni de la banda: es un tope de
                // Android. Se explica entero, porque si no la conclusión
                // natural es "esta app no funciona".
                if (_avisoBt != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: skin.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(skin.cardRadius),
                      border: Border.all(
                          color: skin.warning.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.bluetooth_disabled,
                            color: skin.warning, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _avisoBt!,
                            style: TextStyle(
                                color: skin.warning, fontSize: 13, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Lista de dispositivos ────────────────────
                Expanded(
                  child: _results.isEmpty
                      ? _EmptyView(
                          scanning: _scanning,
                          wideMode: _wideMode,
                          skin: skin,
                          onWide: () => _startScan(wide: true),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _DeviceCard(
                            result: _results[i],
                            skin: skin,
                            esLaDeSiempre:
                                _results[i].device.remoteId.str == _ultimaId,
                            onConnect: () => _onSelect(_results[i].device),
                          ),
                        ),
                ),

                // ── Continuar sin sensor ─────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: TextButton(
                    onPressed: () => context.pop(null),
                    child: Text(
                      'Continuar sin sensor de frecuencia cardíaca',
                      style: TextStyle(
                          color: skin.textMuted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────

class _ConnectingView extends StatelessWidget {
  final dynamic skin;
  const _ConnectingView({required this.skin});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: skin.accent),
            const SizedBox(height: 20),
            Text('Conectando sensor...',
                style: TextStyle(color: skin.textSecondary, fontSize: 16)),
          ],
        ),
      );
}

class _ScanStatusBar extends StatelessWidget {
  final bool scanning;
  final int resultsCount;
  final bool wideMode;
  final dynamic skin;
  final VoidCallback onRetry;
  final VoidCallback onWide;
  const _ScanStatusBar({
    required this.scanning,
    required this.resultsCount,
    required this.wideMode,
    required this.skin,
    required this.onRetry,
    required this.onWide,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: skin.backgroundSecondary,
        child: Row(
          children: [
            if (scanning)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: skin.accent, strokeWidth: 2),
              )
            else
              Icon(Icons.bluetooth_searching, color: skin.textMuted, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                scanning
                    ? wideMode
                        ? 'Buscando todos los dispositivos BLE...'
                        : 'Buscando sensores de frecuencia cardíaca...'
                    : resultsCount > 0
                        ? '$resultsCount sensor${resultsCount > 1 ? 'es' : ''} encontrado${resultsCount > 1 ? 's' : ''}'
                        : 'Ningún sensor encontrado',
                style: TextStyle(color: skin.textMuted, fontSize: 12),
              ),
            ),
            if (!scanning) ...[
              TextButton(
                onPressed: onRetry,
                child: Text('Repetir',
                    style: TextStyle(color: skin.accent, fontSize: 12)),
              ),
              if (!wideMode)
                TextButton(
                  onPressed: onWide,
                  child: Text('Ver todos',
                      style: TextStyle(color: skin.textMuted, fontSize: 12)),
                ),
            ],
          ],
        ),
      );
}

class _EmptyView extends StatelessWidget {
  final bool scanning;
  final bool wideMode;
  final dynamic skin;
  final VoidCallback onWide;
  const _EmptyView({
    required this.scanning,
    required this.wideMode,
    required this.skin,
    required this.onWide,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bluetooth_disabled,
                  size: 64, color: skin.textMuted.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                scanning
                    ? 'Buscando sensores...\nAsegúrate de que la banda esté puesta y mojada.'
                    : 'No se encontraron sensores.\nComprueba que la banda esté encendida y en rango.',
                textAlign: TextAlign.center,
                style: TextStyle(color: skin.textMuted, fontSize: 14),
              ),
              if (!scanning && !wideMode) ...[
                const SizedBox(height: 24),
                Text(
                  '¿Usas una banda Garmin?\nPrueba la búsqueda ampliada:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: skin.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onWide,
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Buscar todos los dispositivos BLE'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: skin.accent,
                    side: BorderSide(color: skin.accent.withValues(alpha: 0.5)),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _DeviceCard extends StatelessWidget {
  final ScanResult result;
  final dynamic skin;
  final bool esLaDeSiempre;
  final VoidCallback onConnect;
  const _DeviceCard(
      {required this.result,
      required this.skin,
      required this.esLaDeSiempre,
      required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Sensor sin nombre';
    final rssi = result.rssi;

    // ⚠️ ¿ESTE APARATO DA PULSACIONES, O SOLO ESTÁ AHÍ? En modo ampliado salían
    // TODOS los dispositivos BLE del vecindario —el reloj, los auriculares, la
    // tele— y todos con el mismo corazón rojo al lado, como si todos fueran
    // bandas. Así es imposible no equivocarse. Ahora el corazón lleno es solo
    // para los que anuncian frecuencia cardíaca de verdad.
    final daFc = result.advertisementData.serviceUuids
        .any((g) => g.str.toLowerCase().contains('180d'));

    // La señal, en cristiano: -60 dBm no le dice nada a nadie, pero "muy cerca"
    // sí — y es lo que distingue la banda que llevas puesta de la del vecino.
    final cerca = rssi >= -65
        ? 'muy cerca'
        : rssi >= -80 ? 'cerca' : 'lejos';

    return Container(
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(
            color: esLaDeSiempre ? skin.accent : skin.border,
            width: esLaDeSiempre ? 1.6 : 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(daFc ? Icons.favorite : Icons.bluetooth,
            color: daFc ? skin.error : skin.textMuted, size: 28),
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: skin.textPrimary, fontWeight: FontWeight.w600)),
            ),
            if (esLaDeSiempre) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: skin.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('LA TUYA',
                    style: TextStyle(
                        color: skin.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          daFc ? '$cerca  ·  envía frecuencia cardíaca'
               : '$cerca  ·  no anuncia frecuencia cardíaca',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: skin.textMuted, fontSize: 11),
        ),
        trailing: ElevatedButton(
          onPressed: onConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: skin.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          child: const Text('CONECTAR'),
        ),
      ),
    );
  }
}
