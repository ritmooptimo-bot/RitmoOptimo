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
  StreamSubscription<List<ScanResult>>? _sub;

  static const _scanSeconds = 20; // sincronizado con BleService.scan()

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _sub?.cancel();
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
      _scanning  = true;
      _wideMode  = wide;
      _results   = [];
      _errorMsg  = null;
    });

    _sub?.cancel();
    final ble = ref.read(bleServiceProvider);

    if (wide) {
      // Modo amplio: todos los dispositivos BLE, el usuario elige cuál es su banda
      FlutterBluePlus.startScan(timeout: const Duration(seconds: _scanSeconds));
      _sub = FlutterBluePlus.scanResults.listen(
        (results) => setState(() => _results = results),
      );
    } else {
      _sub = ble.scan().listen(
        (results) => setState(() => _results = results),
      );
    }

    // Sincronizado con el timeout del scan
    Future.delayed(const Duration(seconds: _scanSeconds), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _onSelect(BluetoothDevice device) async {
    setState(() { _connecting = true; _errorMsg = null; });
    try {
      final ble = ref.read(bleServiceProvider);
      await ble.stopScan();
      await ble.connect(device);
      if (mounted) context.pop(device);
    } catch (e) {
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
  final VoidCallback onConnect;
  const _DeviceCard(
      {required this.result, required this.skin, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Sensor sin nombre';
    final rssi = result.rssi;

    return Container(
      decoration: BoxDecoration(
        color: skin.backgroundCard,
        borderRadius: BorderRadius.circular(skin.cardRadius),
        border: Border.all(color: skin.border),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(Icons.favorite, color: skin.error, size: 28),
        title: Text(name,
            style: TextStyle(
                color: skin.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${rssi} dBm  ·  ${result.device.remoteId.str.length >= 8 ? result.device.remoteId.str.substring(0, 8) : result.device.remoteId.str}...',
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
