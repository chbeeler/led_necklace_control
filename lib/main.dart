import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

void main() => runApp(const NecklaceApp());

class NecklaceApp extends StatelessWidget {
  const NecklaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Necklace Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        sliderTheme: const SliderThemeData(
          showValueIndicator: ShowValueIndicator.always,
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum LedMode { off, eq, solid, pulse }

extension LedModeUi on LedMode {
  String get label => switch (this) {
        LedMode.off => 'Off',
        LedMode.eq => 'EQ',
        LedMode.solid => 'Solid',
        LedMode.pulse => 'Pulse',
      };

  int get fwValue => switch (this) {
        LedMode.off => 0,
        LedMode.eq => 1,
        LedMode.solid => 2,
        LedMode.pulse => 3,
      };

  static LedMode fromFw(int v) => switch (v) {
        0 => LedMode.off,
        1 => LedMode.eq,
        2 => LedMode.solid,
        3 => LedMode.pulse,
        _ => LedMode.eq,
      };
}

// ===================== UUIDs =====================
// Service:
const String SVC_LED = '19B10050-E8F2-537E-4F6C-D104768A1214';

// Characteristics:
const String CH_BRIGHTNESS = '19B10051-E8F2-537E-4F6C-D104768A1214';
const String CH_SENSITIVITY = '19B10052-E8F2-537E-4F6C-D104768A1214';
const String CH_MODE = '19B10053-E8F2-537E-4F6C-D104768A1214';
//const String CH_VBAT_THRES = '19B10054-E8F2-537E-4F6C-D104768A1214';
const String CH_VBAT = '19B10055-E8F2-537E-4F6C-D104768A1214';
const String CH_FILTER = '19B10100-E8F2-537E-4F6C-D104768A1214';
//const String CH_SETTINGS_STR = '19B10110-E8F2-537E-4F6C-D104768A1214';

// If your FW expects uint32 for these sliders, set this true and we send 4 bytes LE.
// If your FW expects just 1 byte, keep false (recommended for MVP).
const bool SEND_SLIDERS_AS_U32 = true;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---- Connection / device selection ----
  bool _connected = false;
  bool _busy = false;
  String _status = 'Not connected';

  // scanned devices: id -> (name, rssi)
  final Map<String, _ScanItem> _scan = {};
  String? _deviceId;
  String _deviceName = 'LED Necklace';

  // ---- Settings ----
  double _brightness = 120; // UI 0..255
  LedMode _mode = LedMode.eq;
  double _filter = 0; // 0..255
  double _sensitivity = 128; // 0..255

  // vBat threshold slider: 3.0..4.3 V (sent as V*10 as u16/u32)
  double _vbatThresV = 3.8;

  // ---- Battery ----
  double? _vbatV;
  DateTime? _vbatTime;

  // ---- Debounce timers for writes ----
  Timer? _tBright;
  Timer? _tMode;
  Timer? _tFilter;
  Timer? _tSens;
  Timer? _tVthres;

  // ---- Streams / listeners ----
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _vbatSub;

  @override
  void initState() {
    super.initState();
    _initBle();
  }

  @override
  void dispose() {
    _tBright?.cancel();
    _tMode?.cancel();
    _tFilter?.cancel();
    _tSens?.cancel();
    _tVthres?.cancel();
    _scanSub?.cancel();
    _connSub?.cancel();
    _vbatSub?.cancel();
    if (_deviceId != null) {
      // best-effort
      UniversalBle.disconnect(_deviceId!);
    }
    super.dispose();
  }

  void _setStatus(String s) => setState(() => _status = s);

  Future<void> _initBle() async {
    try {
      // Request permissions on Android; succeeds on Windows/Linux/Web as well.
      await UniversalBle.requestPermissions(withAndroidFineLocation: false);
      await UniversalBle.setLogLevel(BleLogLevel.info);
    } catch (_) {
      // still allow app to run; scan/connect might fail until permissions are granted
    }

    // Scan results
    UniversalBle.onScanResult = (BleDevice d) {
      final name = d.name ?? '';
      // Many BLE stacks hide name sometimes; keep everything, but prefer LED Necklace matches.
      final rssi = d.rssi ?? -999;
      setState(() {
        _scan[d.deviceId] = _ScanItem(name: name, rssi: rssi);
      });
    };

    // Connection changes (optional; we also use connectionStream for the selected device)
    UniversalBle.onConnectionChange = (String deviceId, bool connected, String? error) {
      if (deviceId != _deviceId) return;
      setState(() {
        _connected = connected;
        _busy = false;
        _status = connected ? 'Connected' : (error != null ? 'Disconnected: $error' : 'Disconnected');
      });
    };

    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value, int? timestamp) {
      if (deviceId != _deviceId) return;

      final cid = characteristicId.toUpperCase();
      if (cid == CH_VBAT.toUpperCase()) {
        final mv = _u16le(value);
        final v = mv / 1000.0;
        setState(() {
          _vbatV = v;
          _vbatTime = DateTime.now(); // or use timestamp if you want
        });
      }
    };
  }

  Future<void> _startScan() async {
    _setStatus('Requesting permissions…');
    await UniversalBle.requestPermissions(withAndroidFineLocation: false);
    _setStatus('Permission result: ok');

    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Scanning…';
      _scan.clear();
    });

    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          // Filtering by service is nice when it works, but some platforms omit it in advertisements.
          // Keeping it null is often more reliable; you can enable it later:
          withServices: [SVC_LED],
        ),
      );

      // Auto-stop after 4 seconds
      await Future<void>.delayed(const Duration(seconds: 4));
    } catch (e) {
      _setStatus('Scan failed: $e');
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      setState(() {
        _busy = false;
        _status = 'Select a device';
      });
    }
  }

  Future<void> _connectTo(String deviceId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Connecting…';
      _deviceId = deviceId;
      _connected = false;
      _vbatV = null;
      _vbatTime = null;
    });

    try {
      // Stop scan before connect (recommended).
      try {
        await UniversalBle.stopScan();
      } catch (_) {}

      await UniversalBle.connect(deviceId);

      // Track connection state
      _connSub?.cancel();
      _connSub = UniversalBle.connectionStream(deviceId).listen((c) {
        setState(() {
          _connected = c;
          _status = c ? 'Connected' : 'Disconnected';
        });
      });

      // Discover services (required before read/write)
      await UniversalBle.discoverServices(deviceId);

      // Subscribe battery notifications if supported by your FW
      // (If you don't implement notify on the FW, this will fail silently and Refresh will still work.)
      try {
        await UniversalBle.subscribeNotifications(deviceId, SVC_LED, CH_VBAT);
        _vbatSub?.cancel();
        _vbatSub = UniversalBle.characteristicValueStream(deviceId, CH_VBAT).listen((value) {
          final mv = _u16le(value);
          setState(() {
            _vbatV = mv / 1000.0;
            _vbatTime = DateTime.now();
          });
        });
      } catch (_) {}

      // Optional: read initial values (best-effort)
      await _readInitials(deviceId);

      setState(() {
        _busy = false;
        _connected = true;
        _deviceName = _scan[deviceId]?.name.isNotEmpty == true ? _scan[deviceId]!.name : 'LED Necklace';
        _status = 'Connected';
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _connected = false;
        _status = 'Connect failed: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    final id = _deviceId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _status = 'Disconnecting…';
    });

    try {
      try {
        await UniversalBle.unsubscribe(id, SVC_LED, CH_VBAT);
      } catch (_) {}
      await UniversalBle.disconnect(id);
    } catch (_) {
      // ignore
    } finally {
      await _connSub?.cancel();
      await _vbatSub?.cancel();
      setState(() {
        _busy = false;
        _connected = false;
        _status = 'Not connected';
      });
    }
  }

  Future<void> _readInitials(String deviceId) async {
    // These reads require the FW characteristic to be readable.
    // If not readable, ignore.
    try {
      final b = await UniversalBle.read(deviceId, SVC_LED, CH_BRIGHTNESS);
      final v = _readSliderValue(b);
      setState(() => _brightness = v.toDouble().clamp(0, 255));
    } catch (_) {}

    try {
      final m = await UniversalBle.read(deviceId, SVC_LED, CH_MODE);
      final v = _u8(m);
      setState(() => _mode = LedModeUi.fromFw(v));
    } catch (_) {}

    try {
      final f = await UniversalBle.read(deviceId, SVC_LED, CH_FILTER);
      final v = _readSliderValue(f);
      setState(() => _filter = v.toDouble().clamp(0, 255));
    } catch (_) {}

    try {
      final s = await UniversalBle.read(deviceId, SVC_LED, CH_SENSITIVITY);
      final v = _readSliderValue(s);
      setState(() => _sensitivity = v.toDouble().clamp(0, 255));
    } catch (_) {}
  }

  Future<void> _refreshBattery() async {
    final id = _deviceId;
    if (id == null || !_connected) return;
    setState(() => _busy = true);
    try {
      final v = await UniversalBle.read(id, SVC_LED, CH_VBAT);
      final mv = _u16le(v);
      setState(() {
        _vbatV = mv / 1000.0;
        _vbatTime = DateTime.now();
      });
    } catch (e) {
      _setStatus('Battery read failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ---------- Write helpers (debounced) ----------
  void _debouncedWriteBrightness(double v) {
    setState(() => _brightness = v);
    _tBright?.cancel();
    _tBright = Timer(const Duration(milliseconds: 120), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;

      // UI: 0..255
      final ui = _brightness.round().clamp(0, 255);

      // You wanted scaling in the app before sending:
      // Example: send 0..1020 in steps of 4 (like your FW earlier), but encoded as u32.
      // If your FW now expects plain 0..255, set scale=1 and SEND_SLIDERS_AS_U32=false.
      const int scale = 4;
      final send = (ui * scale).clamp(0, 4095);

      await _writeSlider(id, CH_BRIGHTNESS, send, uiFallbackByte: ui);
    });
  }

  void _debouncedWriteMode(LedMode m) {
    setState(() => _mode = m);
    _tMode?.cancel();
    _tMode = Timer(const Duration(milliseconds: 80), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;
      await _writeU8(id, CH_MODE, _mode.fwValue);
    });
  }

  void _debouncedWriteFilter(double v) {
    setState(() => _filter = v);
    _tFilter?.cancel();
    _tFilter = Timer(const Duration(milliseconds: 120), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;
      final ui = _filter.round().clamp(0, 255);
      await _writeSlider(id, CH_FILTER, ui, uiFallbackByte: ui);
    });
  }

  void _debouncedWriteSensitivity(double v) {
    setState(() => _sensitivity = v);
    _tSens?.cancel();
    _tSens = Timer(const Duration(milliseconds: 120), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;
      final ui = _sensitivity.round().clamp(0, 255);
      await _writeSlider(id, CH_SENSITIVITY, ui, uiFallbackByte: ui);
    });
  }

  Future<void> _writeU8(String deviceId, String charUuid, int v) async {
    try {
      await UniversalBle.write(
        deviceId,
        SVC_LED,
        charUuid,
        Uint8List.fromList([v & 0xFF]),
        withoutResponse: false,
      );
    } catch (e) {
      _setStatus('Write failed: $e');
    }
  }

  Future<void> _writeU16(String deviceId, String charUuid, int v) async {
    final bytes = Uint8List(2);
    final bd = ByteData.sublistView(bytes);
    bd.setUint16(0, v & 0xFFFF, Endian.little);
    try {
      await UniversalBle.write(
        deviceId,
        SVC_LED,
        charUuid,
        bytes,
        withoutResponse: false,
      );
    } catch (e) {
      _setStatus('Write failed: $e');
    }
  }

  Future<void> _writeSlider(String deviceId, String charUuid, int v, {required int uiFallbackByte}) async {
    try {
      if (SEND_SLIDERS_AS_U32) {
        final bytes = Uint8List(4);
        final bd = ByteData.sublistView(bytes);
        bd.setUint32(0, v >>> 0, Endian.little);
        await UniversalBle.write(deviceId, SVC_LED, charUuid, bytes, withoutResponse: false);
      } else {
        // 1-byte payload (recommended MVP)
        await UniversalBle.write(
          deviceId,
          SVC_LED,
          charUuid,
          Uint8List.fromList([uiFallbackByte & 0xFF]),
          withoutResponse: false,
        );
      }
    } catch (e) {
      _setStatus('Write failed: $e');
    }
  }

  // ---------- Read helpers ----------
  static int _u8(Uint8List b) => b.isEmpty ? 0 : b[0];

  static int _u16le(Uint8List b) {
    if (b.length < 2) return b.isEmpty ? 0 : b[0];
    final bd = ByteData.sublistView(b);
    return bd.getUint16(0, Endian.little);
  }

  static int _u32le(Uint8List b) {
    if (b.length < 4) return _u16le(b);
    final bd = ByteData.sublistView(b);
    return bd.getUint32(0, Endian.little);
  }

  static int _readSliderValue(Uint8List b) {
    if (SEND_SLIDERS_AS_U32) return _u32le(b);
    return _u8(b);
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final scanList = _scan.entries.toList()
      ..sort((a, b) {
        final an = a.value.name.toLowerCase();
        final bn = b.value.name.toLowerCase();
        final aHit = an.contains('led necklace') ? 0 : 1;
        final bHit = bn.contains('led necklace') ? 0 : 1;
        if (aHit != bHit) return aHit - bHit;
        return b.value.rssi.compareTo(a.value.rssi);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Necklace Control'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ConnectionChip(connected: _connected, status: _status),
          ),
          if (!_connected)
            FilledButton.icon(
              onPressed: _busy ? null : _startScan,
              icon: const Icon(Icons.search),
              label: const Text('Scan'),
            )
          else
            OutlinedButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _HeaderCard(deviceName: _deviceName, connected: _connected, status: _status),
          const SizedBox(height: 14),

          if (!_connected) ...[
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Devices', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_busy && _scan.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Scanning…'),
                          ],
                        ),
                      ),
                    if (scanList.isEmpty && !_busy)
                      Text('Press Scan, then tap your necklace.', style: TextStyle(color: cs.onSurfaceVariant)),
                    ...scanList.take(8).map((e) {
                      final id = e.key;
                      final it = e.value;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(it.name.isEmpty ? '(unknown)' : it.name),
                        subtitle: Text(id),
                        trailing: Text('${it.rssi} dBm'),
                        onTap: _busy ? null : () => _connectTo(id),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          _SettingsCard(
            enabled: _connected && !_busy,
            brightness: _brightness,
            brightnessLabel: '0..255 • sending scaled value',
            onBrightnessChanged: _debouncedWriteBrightness,
            mode: _mode,
            onModeChanged: _debouncedWriteMode,
            filter: _filter,
            filterLabel: '${_filter.round()}',
            onFilterChanged: _debouncedWriteFilter,
            sensitivity: _sensitivity,
            sensitivityLabel: '${_sensitivity.round()}',
            onSensitivityChanged: _debouncedWriteSensitivity,
          ),

          const SizedBox(height: 14),

          _BatteryCard(
            enabled: _connected && !_busy,
            vbat: _vbatV,
            time: _vbatTime,
            onRefresh: _refreshBattery,
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates_outlined, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    SEND_SLIDERS_AS_U32
                        ? 'Slider writes are 4-byte little-endian (u32).'
                        : 'Slider writes are 1-byte values (u8). Flip SEND_SLIDERS_AS_U32 if your FW expects u32.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _busy
          ? LinearProgressIndicator(minHeight: 3, color: cs.primary, backgroundColor: cs.surfaceContainerHighest)
          : const SizedBox(height: 3),
    );
  }
}

// ===================== UI Widgets =====================
class _ScanItem {
  final String name;
  final int rssi;
  _ScanItem({required this.name, required this.rssi});
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.connected, required this.status});
  final bool connected;
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = connected ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = connected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Chip(
      label: Text(status),
      avatar: Icon(
        connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
        size: 18,
        color: fg,
      ),
      backgroundColor: bg,
      side: BorderSide(color: Colors.transparent),
      labelStyle: TextStyle(color: fg),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.deviceName, required this.connected, required this.status});
  final String deviceName;
  final bool connected;
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: connected ? cs.primary : cs.outlineVariant,
              child: Icon(Icons.auto_awesome, color: connected ? cs.onPrimary : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deviceName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    connected ? 'Ready to control' : 'Scan and connect',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(
              status,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: connected ? cs.primary : cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.enabled,
    required this.brightness,
    required this.brightnessLabel,
    required this.onBrightnessChanged,
    required this.mode,
    required this.onModeChanged,
    required this.filter,
    required this.filterLabel,
    required this.onFilterChanged,
    required this.sensitivity,
    required this.sensitivityLabel,
    required this.onSensitivityChanged,
  });

  final bool enabled;

  final double brightness;
  final String brightnessLabel;
  final ValueChanged<double> onBrightnessChanged;

  final LedMode mode;
  final ValueChanged<LedMode> onModeChanged;

  final double filter;
  final String filterLabel;
  final ValueChanged<double> onFilterChanged;

  final double sensitivity;
  final String sensitivityLabel;
  final ValueChanged<double> onSensitivityChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Controls', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),

            _LabeledSlider(
              title: 'Brightness',
              subtitle: brightnessLabel,
              enabled: enabled,
              value: brightness,
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: enabled ? onBrightnessChanged : null,
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _FieldShell(
                    title: 'Mode',
                    child: DropdownButtonFormField<LedMode>(
                      value: mode,
                      onChanged: enabled ? (v) => onModeChanged(v!) : null,
                      items: LedMode.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label))).toList(),
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('FW: ${mode.fwValue}', style: Theme.of(context).textTheme.labelLarge),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _LabeledSlider(
              title: 'Filter',
              subtitle: '0..255 • $filterLabel',
              enabled: enabled,
              value: filter,
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: enabled ? onFilterChanged : null,
            ),

            const SizedBox(height: 8),

            _LabeledSlider(
              title: 'Sensitivity',
              subtitle: '0..255 • $sensitivityLabel',
              enabled: enabled,
              value: sensitivity,
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: enabled ? onSensitivityChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.enabled, required this.vbat, required this.time, required this.onRefresh});
  final bool enabled;
  final double? vbat;
  final DateTime? time;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    double pctFromV(double v) => ((v - 3.3) / (4.2 - 3.3)).clamp(0.0, 1.0);

    final v = vbat;
    final pct = v == null ? null : pctFromV(v);
    final timeStr = time == null ? '—' : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Battery', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.battery_full, color: cs.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: pct ?? 0.0,
                                  minHeight: 10,
                                  backgroundColor: cs.outlineVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          v == null ? 'Unknown' : '${v.toStringAsFixed(3)} V',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: enabled ? onRefresh : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: cs.surfaceContainerHighest),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
              Text(
                (divisions == 13 ? value.toStringAsFixed(1) : value.round().toString()),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: enabled ? cs.primary : cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: divisions == 13 ? value.toStringAsFixed(1) : value.round().toString(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
