import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

void main() => runApp(const NecklaceApp());

const Color kGold = Color.fromARGB(255, 163, 109, 28);
const Color kBg = Color(0xFF0F0F10);
const Color kSurface = Color.fromARGB(255, 35, 35, 36);
const Color kSurface2 = Color.fromARGB(255, 45, 45, 48);
const Color kText = Colors.white;

class NecklaceApp extends StatelessWidget {
  const NecklaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: kGold,
        onPrimary: Colors.black,

        secondary: kGold,
        onSecondary: Colors.black,

        background: kBg,
        onBackground: kText,

        surface: kSurface,
        onSurface: kText,

        surfaceVariant: kSurface2,
        onSurfaceVariant: Color(0xFFE6E6E6),

        outline: Color(0xFF3A3A3C),
      ),
    );

    return MaterialApp(
      title: 'Necklace Control',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: kBg,

        // Keep text white
        textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),

        iconTheme: const IconThemeData(color: kGold),

        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kText,
          iconTheme: IconThemeData(color: kGold),
        ),

        // Make Cards / Containers stay dark (no seed-tinted fills)
        // cardTheme: const CardTheme(
        //   color: kSurface,
        //   elevation: 0,
        //   margin: EdgeInsets.zero,
        // ),

        // Inputs (Dropdown/TextField) background dark
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3A3A3C)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3A3A3C)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGold, width: 1.2),
          ),
        ),

        // Sliders: gold thumb + active track, dark inactive track, no gold wash
        sliderTheme: base.sliderTheme.copyWith(
          showValueIndicator: ShowValueIndicator.always,
          activeTrackColor: kGold,
          inactiveTrackColor: const Color(0xFF2C2C2E),
          thumbColor: kGold,
          overlayColor: kGold.withOpacity(0.15),
          valueIndicatorColor: kGold,
          valueIndicatorTextStyle: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),

        // Optional: make dividers/outlines subtle
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2C2C2E),
          thickness: 1,
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum LedMode { off, eq, solid, aeq, firefly }

extension LedModeUi on LedMode {
  String get label => switch (this) {
    LedMode.off => 'Off',
    LedMode.eq => 'EQ',
    LedMode.solid => 'Solid',
    LedMode.aeq => 'AEQ',
    LedMode.firefly => 'Firefly',
  };

  int get fwValue => switch (this) {
    LedMode.off => 0,
    LedMode.eq => 1,
    LedMode.solid => 2,
    LedMode.aeq => 3,
    LedMode.firefly => 4,
  };

  static LedMode fromFw(int v) => switch (v) {
    0 => LedMode.off,
    1 => LedMode.eq,
    2 => LedMode.solid,
    3 => LedMode.aeq,
    4 => LedMode.firefly,
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
const String CH_AEQ_FILTER = '19B10130-E8F2-537E-4F6C-D104768A1214';
const String CH_NOISE_FLOOR = '19B10056-E8F2-537E-4F6C-D104768A1214';
const String CH_VOL_MIN_MAX = '19B10120-E8F2-537E-4F6C-D104768A1214';
const String CH_NFC_URI = '19B10150-E8F2-537E-4F6C-D104768A1214';
const String CH_AUDIO_TELEMETRY = '19B10160-E8F2-537E-4F6C-D104768A1214';
//const String CH_SETTINGS_STR = '19B10110-E8F2-537E-4F6C-D104768A1214';
const int SHUTDOWN_MODE_VALUE = 9;
const int NFC_URI_MAX_BYTES = 120;

double _dbfs(int value) {
  if (value <= 0) return -90;
  return (20 * math.log(value / 32768.0) / math.ln10).clamp(-90, 0);
}

class _AudioTelemetry {
  const _AudioTelemetry({
    required this.rawPeak,
    required this.rms,
    required this.envelope,
    required this.floor,
    required this.ceiling,
    required this.output,
    required this.clippedSamples,
    required this.totalSamples,
    required this.saturatedBlocks,
    required this.totalAeqBlocks,
    required this.droppedBlocks,
  });

  final int rawPeak;
  final int rms;
  final int envelope;
  final int floor;
  final int ceiling;
  final int output;
  final int clippedSamples;
  final int totalSamples;
  final int saturatedBlocks;
  final int totalAeqBlocks;
  final int droppedBlocks;

  static _AudioTelemetry? fromBytes(Uint8List value) {
    if (value.length < 20) return null;
    final data = ByteData.sublistView(value);
    return _AudioTelemetry(
      rawPeak: data.getUint16(0, Endian.little),
      rms: data.getUint16(2, Endian.little),
      envelope: data.getUint16(4, Endian.little),
      floor: data.getUint16(6, Endian.little),
      ceiling: data.getUint16(8, Endian.little),
      output: data.getUint16(10, Endian.little),
      clippedSamples: data.getUint16(12, Endian.little),
      totalSamples: data.getUint16(14, Endian.little),
      saturatedBlocks: value[16],
      totalAeqBlocks: value[17],
      droppedBlocks: data.getUint16(18, Endian.little),
    );
  }
}

class _AudioPoint {
  const _AudioPoint(this.time, this.telemetry);
  final DateTime time;
  final _AudioTelemetry telemetry;
}

// If your FW expects uint32 for these sliders, set this true and we send 4 bytes LE.
// If your FW expects just 1 byte, keep false (recommended for MVP).
const bool SEND_SLIDERS_AS_U32 = true;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // ---- Connection / device selection ----
  bool _connected = false;
  bool _busy = false;
  String _status = 'Not connected';

  // scanned devices: id -> (name, rssi)
  final Map<String, _ScanItem> _scan = {};
  String? _deviceId;
  String _deviceName = 'LED Necklace';

  // ---- Settings ----
  double _brightness = 120; // UI 0..500
  LedMode _mode = LedMode.eq;
  double _filter = 0; // 0..255
  double _aeqFilter = 0; // 0..255
  double _sensitivity = 1000; // 0..1000
  double _noise_floor = 10;
  int? _recentMinVolume;
  int? _recentMaxVolume;
  final TextEditingController _nfcUriController = TextEditingController();
  bool _nfcSupported = false;
  bool _nfcSaving = false;
  bool _audioTelemetrySupported = false;
  bool _audioDebugVisible = false;
  bool _audioFrozen = false;
  _AudioTelemetry? _audioTelemetry;
  final List<_AudioPoint> _audioPoints = [];
  int _droppedAudioBlocks = 0;

  // vBat threshold slider: 3.0..4.3 V (sent as V*10 as u16/u32)
  double _vbatThresV = 3.8;

  // ---- Battery ----
  double? _vbatV;
  DateTime? _vbatTime;

  // ---- Debounce timers for writes ----
  Timer? _tBright;
  Timer? _tMode;
  Timer? _tFilter;
  Timer? _tAeqFilter;
  Timer? _tSens;
  Timer? _tVthres;

  // ---- Streams / listeners ----
  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _vbatSub;
  StreamSubscription<Uint8List>? _audioTelemetrySub;
  void Function(void Function())? _deviceDialogSetState;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _batteryCardKey = GlobalKey();
  Timer? _batteryTimer;
  Duration? _batteryPollInterval;
  bool _batteryVisible = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateBatteryVisibility);
    _initBle();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateBatteryVisibility(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryTimer?.cancel();
    _scrollController.removeListener(_updateBatteryVisibility);
    _scrollController.dispose();
    _tBright?.cancel();
    _tMode?.cancel();
    _tFilter?.cancel();
    _tAeqFilter?.cancel();
    _tSens?.cancel();
    _tVthres?.cancel();
    _scanSub?.cancel();
    _connSub?.cancel();
    _vbatSub?.cancel();
    _audioTelemetrySub?.cancel();
    _nfcUriController.dispose();
    if (_deviceId != null) {
      // best-effort
      UniversalBle.disconnect(_deviceId!);
    }
    super.dispose();
  }

  void _setStatus(String s) => setState(() => _status = s);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _appActive = active;
    if (!active) {
      _stopBatteryPolling();
    } else {
      _updateBatteryVisibility();
    }
  }

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
      _deviceDialogSetState?.call(() {});
    };

    // Connection changes (optional; we also use connectionStream for the selected device)
    UniversalBle.onConnectionChange =
        (String deviceId, bool connected, String? error) {
          if (deviceId != _deviceId) return;
          setState(() {
            _connected = connected;
            _busy = false;
            _status = connected
                ? 'Connected'
                : (error != null ? 'Disconnected: $error' : 'Disconnected');
          });
          if (!connected) {
            _stopBatteryPolling();
          } else {
            _updateBatteryVisibility();
          }
        };

    UniversalBle.onValueChange =
        (
          String deviceId,
          String characteristicId,
          Uint8List value,
          int? timestamp,
        ) {
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
    _showDevicePicker();

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
      _deviceDialogSetState?.call(() {});
    }
  }

  Future<void> _connectTo(String deviceId, {bool force = false}) async {
    if (_busy && !force) return;
    setState(() {
      _busy = true;
      _status = 'Connecting…';
      _deviceId = deviceId;
      _connected = false;
      _vbatV = null;
      _vbatTime = null;
      _nfcSupported = false;
      _nfcUriController.clear();
      _audioTelemetrySupported = false;
      _audioFrozen = false;
      _audioTelemetry = null;
      _audioPoints.clear();
      _droppedAudioBlocks = 0;
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

      // The NFC URI is at most 120 bytes and fits in one write with this MTU.
      try {
        await UniversalBle.requestMtu(deviceId, 128);
      } catch (_) {}

      // Audio telemetry is optional so older firmware remains compatible.
      try {
        final initial = await UniversalBle.read(
          deviceId,
          SVC_LED,
          CH_AUDIO_TELEMETRY,
        );
        _handleAudioTelemetry(initial);
        await UniversalBle.subscribeNotifications(
          deviceId,
          SVC_LED,
          CH_AUDIO_TELEMETRY,
        );
        await _audioTelemetrySub?.cancel();
        _audioTelemetrySub = UniversalBle.characteristicValueStream(
          deviceId,
          CH_AUDIO_TELEMETRY,
        ).listen(_handleAudioTelemetry);
        setState(() => _audioTelemetrySupported = true);
      } catch (_) {
        setState(() => _audioTelemetrySupported = false);
      }

      // Subscribe battery notifications if supported by your FW
      // (If you don't implement notify on the FW, this will fail silently and Refresh will still work.)
      try {
        await UniversalBle.subscribeNotifications(deviceId, SVC_LED, CH_VBAT);
        _vbatSub?.cancel();
        _vbatSub = UniversalBle.characteristicValueStream(deviceId, CH_VBAT)
            .listen((value) {
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
        _deviceName = _scan[deviceId]?.name.isNotEmpty == true
            ? _scan[deviceId]!.name
            : 'LED Necklace';
        _status = 'Connected';
      });
      _updateBatteryVisibility();
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
      try {
        await UniversalBle.unsubscribe(id, SVC_LED, CH_AUDIO_TELEMETRY);
      } catch (_) {}
      await UniversalBle.disconnect(id);
    } catch (_) {
      // ignore
    } finally {
      await _connSub?.cancel();
      await _vbatSub?.cancel();
      await _audioTelemetrySub?.cancel();
      setState(() {
        _busy = false;
        _connected = false;
        _status = 'Not connected';
      });
      _stopBatteryPolling();
    }
  }

  void _showDevicePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            _deviceDialogSetState = setModalState;
            final cs = Theme.of(context).colorScheme;
            final scanList = _scan.entries.toList()
              ..sort((a, b) {
                final an = a.value.name.toLowerCase();
                final bn = b.value.name.toLowerCase();
                return an.compareTo(bn);
              });

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Device',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _busy ? 'Scanning…' : 'Tap your necklace to connect.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_busy && _scan.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Scanning…'),
                        ],
                      ),
                    ),
                  if (scanList.isEmpty && !_busy)
                    Text(
                      'No devices found. Press Scan again.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ...scanList.take(10).map((e) {
                    final id = e.key;
                    final it = e.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(it.name.isEmpty ? '(unknown)' : it.name),
                      subtitle: Text(id),
                      trailing: Text('${it.rssi} dBm'),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _connectTo(id, force: true);
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() => _deviceDialogSetState = null);
  }

  Future<void> _readInitials(String deviceId) async {
    // These reads require the FW characteristic to be readable.
    // If not readable, ignore.
    try {
      final b = await UniversalBle.read(deviceId, SVC_LED, CH_BRIGHTNESS);
      final v = _readSliderValue(b);
      setState(() => _brightness = v.toDouble().clamp(0, 1000));
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
      final f = await UniversalBle.read(deviceId, SVC_LED, CH_AEQ_FILTER);
      final v = _readSliderValue(f);
      setState(() => _aeqFilter = v.toDouble().clamp(0, 255));
    } catch (_) {}

    try {
      final s = await UniversalBle.read(deviceId, SVC_LED, CH_SENSITIVITY);
      final v = _readSliderValue(s);
      setState(() => _sensitivity = v.toDouble().clamp(0, 1000));
    } catch (_) {}

    try {
      final s = await UniversalBle.read(deviceId, SVC_LED, CH_NOISE_FLOOR);
      final v = _readSliderValue(s);
      setState(() => _noise_floor = v.toDouble().clamp(0, 1500));
    } catch (_) {}

    try {
      final value = await UniversalBle.read(deviceId, SVC_LED, CH_NFC_URI);
      final uri = utf8.decode(value);
      setState(() {
        _nfcSupported = true;
        _nfcUriController.text = uri;
      });
    } catch (_) {
      setState(() => _nfcSupported = false);
    }
  }

  Future<void> _refreshBattery({bool showBusy = true}) async {
    final id = _deviceId;
    if (id == null || !_connected) return;
    if (_busy) return;
    if (showBusy) {
      setState(() => _busy = true);
    }
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
      if (showBusy) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _autoSetNoiseFloorFromBle() async {
    final id = _deviceId;
    if (id == null || !_connected || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Reading volume range…';
    });

    try {
      final data = await UniversalBle.read(id, SVC_LED, CH_VOL_MIN_MAX);
      final minV = _u16leAt(data, 0);
      final maxV = _u16leAt(data, 2);
      final range = maxV - minV;
      if (range <= 0) {
        setState(() {
          _recentMinVolume = minV;
          _recentMaxVolume = maxV;
          _status = 'AUTO failed: invalid min/max range';
        });
        return;
      }

      // From FW mapping:
      // led = (loudness - noiseFloor) * sensitivityF * (brightness/100)
      // For full-range mapping over current window: min->0 and max->brightness.
      // That yields:
      // noiseFloor = minV
      // sensitivityF = 100 / (maxV - minV)
      const double sensitivityScale =
          1.0 / 0.0005; //from FW (SENSITIVITY_CONV_FACTOR)
      final autoNoiseRaw = minV;
      final autoNoise = autoNoiseRaw.clamp(0, 1500);
      final rawAutoSensitivity = (100.0 / range.toDouble()) * sensitivityScale;
      debugPrint(
        'AUTO EQ: min=$minV max=$maxV range=$range rawAutoSensitivity=$rawAutoSensitivity',
      );
      final autoSensitivity = rawAutoSensitivity.round().clamp(0, 1000);
      final noiseClipped = autoNoiseRaw != autoNoise;

      setState(() {
        _recentMinVolume = minV;
        _recentMaxVolume = maxV;
        _sensitivity = autoSensitivity.toDouble();
        _noise_floor = autoNoise.toDouble();
        _status = noiseClipped ? 'AUTO EQ cliped' : 'AUTO EQ done';
      });

      await _writeSlider(
        id,
        CH_NOISE_FLOOR,
        autoNoise,
        uiFallbackByte: autoNoise,
      );
      await _writeSlider(
        id,
        CH_SENSITIVITY,
        autoSensitivity,
        uiFallbackByte: autoSensitivity,
      );
    } catch (e) {
      _setStatus('Auto noise floor failed: $e');
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

      // UI: 0..500
      final ui = _brightness.round().clamp(0, 500);

      // You wanted scaling in the app before sending:
      // Example: send 0..1020 in steps of 4 (like your FW earlier), but encoded as u32.
      // If your FW now expects plain 0..255, set scale=1 and SEND_SLIDERS_AS_U32=false.
      const int scale = 1;
      final send = (ui * scale).clamp(0, 4095);

      await _writeSlider(id, CH_BRIGHTNESS, send, uiFallbackByte: ui);
    });
  }

  void _fineAdjustBrightness(int delta) {
    final next = (_brightness + delta).clamp(0.0, 500.0).toDouble();
    if (next == _brightness) return;
    _debouncedWriteBrightness(next);
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

  void _toggleAudioDebugVisibility() {
    final visible = !_audioDebugVisible;
    setState(() => _audioDebugVisible = visible);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Audio debug ${visible ? 'enabled' : 'hidden'}'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  Future<void> _confirmAndShutdown() async {
    if (!_connected || _busy) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Shut down necklace?'),
          content: const Text(
            'After proceeding, the necklace can only be turned back on by providing USB power.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );

    if (proceed != true) return;

    final id = _deviceId;
    if (id == null || !_connected) return;
    setState(() => _status = 'Sending shutdown command...');
    await _writeU8(id, CH_MODE, SHUTDOWN_MODE_VALUE);
    setState(() => _status = 'Shutdown command sent');
  }

  void _handleAudioTelemetry(Uint8List value) {
    final telemetry = _AudioTelemetry.fromBytes(value);
    if (telemetry == null || !mounted) return;

    final now = DateTime.now();
    setState(() {
      _audioTelemetry = telemetry;
      _droppedAudioBlocks += telemetry.droppedBlocks;
      if (!_audioFrozen) {
        _audioPoints.add(_AudioPoint(now, telemetry));
        final cutoff = now.subtract(const Duration(seconds: 30));
        _audioPoints.removeWhere((point) => point.time.isBefore(cutoff));
      }
    });
  }

  void _resetAudioStatistics() {
    setState(() {
      _audioPoints.clear();
      _droppedAudioBlocks = 0;
    });
  }

  void _toggleAudioFreeze() {
    setState(() => _audioFrozen = !_audioFrozen);
  }

  Future<void> _saveNfcUri() async {
    final id = _deviceId;
    if (id == null || !_connected || !_nfcSupported || _nfcSaving) return;

    final value = _nfcUriController.text.trim();
    final parsed = Uri.tryParse(value);
    final scheme = parsed?.scheme.toLowerCase();
    final encoded = utf8.encode(value);
    if (parsed == null ||
        (scheme != 'http' && scheme != 'https') ||
        parsed.host.isEmpty) {
      _setStatus('NFC link must be a complete http:// or https:// URL');
      return;
    }
    if (encoded.length > NFC_URI_MAX_BYTES) {
      _setStatus(
        'NFC link is too long (${encoded.length}/$NFC_URI_MAX_BYTES bytes)',
      );
      return;
    }

    setState(() {
      _nfcSaving = true;
      _status = 'Saving NFC link...';
    });
    try {
      await UniversalBle.write(
        id,
        SVC_LED,
        CH_NFC_URI,
        Uint8List.fromList(encoded),
        withoutResponse: false,
      );

      // Firmware applies BLE writes from its main loop. Read back the value so
      // rejected or failed updates are never reported as saved.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final confirmedBytes = await UniversalBle.read(id, SVC_LED, CH_NFC_URI);
      final confirmed = utf8.decode(confirmedBytes);
      if (confirmed != value) {
        throw StateError('necklace kept its previous link');
      }

      setState(() {
        _nfcUriController.text = confirmed;
        _status = 'NFC link saved';
      });
    } catch (e) {
      _setStatus('NFC link write failed: $e');
    } finally {
      if (mounted) setState(() => _nfcSaving = false);
    }
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

  void _debouncedWriteAeqFilter(double v) {
    setState(() => _aeqFilter = v);
    _tAeqFilter?.cancel();
    _tAeqFilter = Timer(const Duration(milliseconds: 120), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;
      final ui = _aeqFilter.round().clamp(0, 255);
      await _writeSlider(id, CH_AEQ_FILTER, ui, uiFallbackByte: ui);
    });
  }

  void _debouncedWriteSensitivity(double v) {
    setState(() => _sensitivity = v);
    _tSens?.cancel();
    _tSens = Timer(const Duration(milliseconds: 120), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;
      final ui = _sensitivity.round().clamp(0, 1000);
      await _writeSlider(id, CH_SENSITIVITY, ui, uiFallbackByte: ui);
    });
  }

  void _debouncedWriteNoiseFloor(double v) {
    setState(() => _noise_floor = v);
    _tSens?.cancel();
    _tSens = Timer(const Duration(milliseconds: 120), () async {
      final id = _deviceId;
      if (id == null || !_connected) return;
      final ui = _noise_floor.round().clamp(0, 1500);
      await _writeSlider(id, CH_NOISE_FLOOR, ui, uiFallbackByte: ui);
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

  Future<void> _writeSlider(
    String deviceId,
    String charUuid,
    int v, {
    required int uiFallbackByte,
  }) async {
    try {
      if (SEND_SLIDERS_AS_U32) {
        final bytes = Uint8List(4);
        final bd = ByteData.sublistView(bytes);
        bd.setUint32(0, v >>> 0, Endian.little);
        await UniversalBle.write(
          deviceId,
          SVC_LED,
          charUuid,
          bytes,
          withoutResponse: false,
        );
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

  static int _u16leAt(Uint8List b, int offset) {
    if (b.length < offset + 2) return _u16le(b);
    final bd = ByteData.sublistView(b);
    return bd.getUint16(offset, Endian.little);
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

  bool _isBatteryCardVisible() {
    final cardContext = _batteryCardKey.currentContext;
    if (cardContext == null) return false;
    final cardBox = cardContext.findRenderObject();
    final rootBox = context.findRenderObject();
    if (cardBox is! RenderBox || rootBox is! RenderBox) return false;
    if (!cardBox.hasSize || !rootBox.hasSize) return false;

    final cardTopLeft = cardBox.localToGlobal(Offset.zero);
    final cardBottomRight = cardBox.localToGlobal(
      cardBox.size.bottomRight(Offset.zero),
    );
    final rootTopLeft = rootBox.localToGlobal(Offset.zero);
    final rootBottomRight = rootBox.localToGlobal(
      rootBox.size.bottomRight(Offset.zero),
    );

    return cardBottomRight.dy > rootTopLeft.dy &&
        cardTopLeft.dy < rootBottomRight.dy;
  }

  void _startBatteryPolling(Duration interval, {bool immediate = false}) {
    if (_batteryPollInterval == interval && _batteryTimer != null) return;
    _batteryTimer?.cancel();
    _batteryPollInterval = interval;
    if (immediate) {
      _refreshBattery(showBusy: false);
    }
    _batteryTimer = Timer.periodic(
      interval,
      (_) => _refreshBattery(showBusy: false),
    );
  }

  void _stopBatteryPolling() {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _batteryPollInterval = null;
  }

  void _updateBatteryVisibility() {
    if (!mounted || !_appActive) return;
    if (!_connected || _deviceId == null) {
      _stopBatteryPolling();
      return;
    }

    final visible = _isBatteryCardVisible();
    if (visible != _batteryVisible) {
      _batteryVisible = visible;
      if (visible) {
        _startBatteryPolling(const Duration(seconds: 5), immediate: true);
      } else {
        _stopBatteryPolling();
      }
    } else {
      if (visible) {
        _startBatteryPolling(const Duration(seconds: 5));
      } else {
        _stopBatteryPolling();
      }
    }
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Necklace Control'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ConnectionChip(connected: _connected, status: _status),
                  const SizedBox(width: 10),
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
                ],
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        children: [
          _HeaderCard(deviceName: _deviceName, connected: _connected),
          const SizedBox(height: 4),

          _SettingsCard(
            enabled: _connected && !_busy,
            brightness: _brightness,
            brightnessLabel: '0..500',
            onBrightnessChanged: _debouncedWriteBrightness,
            onBrightnessFineDown: () => _fineAdjustBrightness(-1),
            onBrightnessFineUp: () => _fineAdjustBrightness(1),
            mode: _mode,
            onModeChanged: _debouncedWriteMode,
            onAeqHeld: _toggleAudioDebugVisibility,
            filter: _filter,
            filterLabel: '${_filter.round()}',
            onFilterChanged: _debouncedWriteFilter,
            aeqFilter: _aeqFilter,
            aeqFilterLabel: '${_aeqFilter.round()}',
            onAeqFilterChanged: _debouncedWriteAeqFilter,
            sensitivity: _sensitivity,
            sensitivityLabel: '${_sensitivity.round()}',
            onSensitivityChanged: _debouncedWriteSensitivity,
            noise_floor: _noise_floor,
            noiseFloorLabel: '${_noise_floor.round()}',
            onNoiseFloorChanged: _debouncedWriteNoiseFloor,
            onAutoNoiseFloor: _autoSetNoiseFloorFromBle,
            recentMinVolume: _recentMinVolume,
            recentMaxVolume: _recentMaxVolume,
          ),

          if (_audioTelemetrySupported && _audioDebugVisible) ...[
            const SizedBox(height: 4),
            _AudioDebugCard(
              telemetry: _audioTelemetry,
              points: List.unmodifiable(_audioPoints),
              droppedBlocks: _droppedAudioBlocks,
              frozen: _audioFrozen,
              onReset: _resetAudioStatistics,
              onToggleFreeze: _toggleAudioFreeze,
            ),
          ],

          const SizedBox(height: 4),

          _BatteryCard(
            key: _batteryCardKey,
            enabled: _connected && !_busy,
            vbat: _vbatV,
            time: _vbatTime,
            onShutdown: _confirmAndShutdown,
          ),

          if (_nfcSupported) ...[
            const SizedBox(height: 4),
            _NfcLinkCard(
              enabled: _connected && !_busy && !_nfcSaving,
              saving: _nfcSaving,
              controller: _nfcUriController,
              onSave: _saveNfcUri,
            ),
          ],

          const SizedBox(height: 4),

          //   Container(
          //     padding: const EdgeInsets.all(12),
          //     decoration: BoxDecoration(
          //       color: cs.surfaceContainerHighest,
          //       borderRadius: BorderRadius.circular(12),
          //     ),
          //     child: Row(
          //       children: [
          //         Icon(Icons.tips_and_updates_outlined, color: cs.onSurfaceVariant),
          //         const SizedBox(width: 10),
          //         Expanded(
          //           child: Text(
          //             SEND_SLIDERS_AS_U32
          //                 ? 'Slider writes are 4-byte little-endian (u32).'
          //                 : 'Slider writes are 1-byte values (u8). Flip SEND_SLIDERS_AS_U32 if your FW expects u32.',
          //             style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          //           ),
          //         ),
          //       ],
          //     ),
          //   ),
        ],
      ),
      bottomNavigationBar: _busy
          ? LinearProgressIndicator(
              minHeight: 3,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            )
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

    const int maxChars = 18; // tweak: 16..22 works well

    String shortStatus(String s) {
      s = s.trim();
      if (s.length <= maxChars) return s;
      return '${s.substring(0, maxChars - 1)}…';
    }

    return Chip(
      label: Text(
        shortStatus(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
      avatar: Icon(
        connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
        size: 18,
        color: fg,
      ),
      backgroundColor: bg,
      side: const BorderSide(color: Colors.transparent),
      labelStyle: TextStyle(color: fg),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.deviceName, required this.connected});
  final String deviceName;
  final bool connected;

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
              child: Icon(
                Icons.auto_awesome,
                color: connected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: connected
                  ? Text(
                      deviceName,
                      style: Theme.of(context).textTheme.titleMedium,
                    )
                  : Text(
                      'Not connected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButtons extends StatefulWidget {
  const _ModeButtons({
    required this.enabled,
    required this.mode,
    required this.onModeChanged,
    required this.onAeqHeld,
  });

  final bool enabled;
  final LedMode mode;
  final ValueChanged<LedMode> onModeChanged;
  final VoidCallback onAeqHeld;

  @override
  State<_ModeButtons> createState() => _ModeButtonsState();
}

class _ModeButtonsState extends State<_ModeButtons> {
  Timer? _aeqHoldTimer;
  bool _aeqHoldTriggered = false;

  void _startAeqHold() {
    if (!widget.enabled) return;
    _aeqHoldTimer?.cancel();
    _aeqHoldTriggered = false;
    _aeqHoldTimer = Timer(const Duration(seconds: 2), () {
      _aeqHoldTriggered = true;
      widget.onAeqHeld();
    });
  }

  void _stopAeqHold() {
    _aeqHoldTimer?.cancel();
    _aeqHoldTimer = null;
  }

  @override
  void dispose() {
    _aeqHoldTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget buildButton(String label, LedMode value, {bool hiddenHold = false}) {
      final active = widget.mode == value;
      final isActive = widget.enabled && active;
      final textColor = isActive ? kText : cs.onSurfaceVariant;
      final fontWeight = isActive ? FontWeight.w800 : FontWeight.w400;

      final button = TextButton(
        onPressed: widget.enabled
            ? () {
                if (hiddenHold && _aeqHoldTriggered) {
                  _aeqHoldTriggered = false;
                  return;
                }
                widget.onModeChanged(value);
              }
            : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(cs.surfaceContainerHighest),
          foregroundColor: WidgetStateProperty.all(textColor),
          padding: WidgetStateProperty.all(
            EdgeInsets.symmetric(vertical: isActive ? 12 : 11),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: isActive ? kGold : cs.outlineVariant,
                width: isActive ? 2 : 1,
              ),
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: textColor,
            fontWeight: fontWeight,
            letterSpacing: 0.6,
          ),
        ),
      );

      return Expanded(
        child: hiddenHold
            ? Listener(
                onPointerDown: (_) => _startAeqHold(),
                onPointerUp: (_) => _stopAeqHold(),
                onPointerCancel: (_) => _stopAeqHold(),
                child: button,
              )
            : button,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LED Mode', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            buildButton('OFF', LedMode.off),
            const SizedBox(width: 8),
            buildButton('ON', LedMode.solid),
            const SizedBox(width: 8),
            buildButton('EQ', LedMode.eq),
            const SizedBox(width: 8),
            buildButton('AEQ', LedMode.aeq, hiddenHold: true),
          ],
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.enabled,
    required this.brightness,
    required this.brightnessLabel,
    required this.onBrightnessChanged,
    required this.onBrightnessFineDown,
    required this.onBrightnessFineUp,
    required this.mode,
    required this.onModeChanged,
    required this.onAeqHeld,
    required this.filter,
    required this.filterLabel,
    required this.onFilterChanged,
    required this.aeqFilter,
    required this.aeqFilterLabel,
    required this.onAeqFilterChanged,
    required this.sensitivity,
    required this.sensitivityLabel,
    required this.onSensitivityChanged,
    required this.noise_floor,
    required this.noiseFloorLabel,
    required this.onNoiseFloorChanged,
    required this.onAutoNoiseFloor,
    required this.recentMinVolume,
    required this.recentMaxVolume,
  });

  final bool enabled;

  final double brightness;
  final String brightnessLabel;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onBrightnessFineDown;
  final VoidCallback onBrightnessFineUp;

  final LedMode mode;
  final ValueChanged<LedMode> onModeChanged;
  final VoidCallback onAeqHeld;

  final double filter;
  final String filterLabel;
  final ValueChanged<double> onFilterChanged;

  final double aeqFilter;
  final String aeqFilterLabel;
  final ValueChanged<double> onAeqFilterChanged;

  final double sensitivity;
  final String sensitivityLabel;
  final ValueChanged<double> onSensitivityChanged;

  final double noise_floor;
  final String noiseFloorLabel;
  final ValueChanged<double> onNoiseFloorChanged;
  final VoidCallback onAutoNoiseFloor;
  final int? recentMinVolume;
  final int? recentMaxVolume;

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
            const SizedBox(height: 6),

            _LabeledSlider(
              title: 'Brightness',
              subtitle: brightnessLabel,
              enabled: enabled,
              value: brightness,
              min: 0,
              max: 500,
              divisions: 250,
              onChanged: enabled ? onBrightnessChanged : null,
            ),

            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: enabled ? onBrightnessFineDown : null,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(
                        cs.surfaceContainerHighest,
                      ),
                      foregroundColor: WidgetStateProperty.all(
                        cs.onSurfaceVariant,
                      ),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(vertical: 11),
                      ),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: cs.outlineVariant, width: 1),
                        ),
                      ),
                    ),
                    child: const Text('Fine -'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: enabled ? onBrightnessFineUp : null,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(
                        cs.surfaceContainerHighest,
                      ),
                      foregroundColor: WidgetStateProperty.all(
                        cs.onSurfaceVariant,
                      ),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(vertical: 11),
                      ),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: cs.outlineVariant, width: 1),
                        ),
                      ),
                    ),
                    child: const Text('Fine +'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            _ModeButtons(
              enabled: enabled,
              mode: mode,
              onModeChanged: onModeChanged,
              onAeqHeld: onAeqHeld,
            ),

            const SizedBox(height: 4),

            _LabeledSlider(
              title: 'EQ Sensitivity',
              subtitle: '0..1000 • $sensitivityLabel',
              enabled: enabled,
              value: sensitivity,
              min: 0,
              max: 1000,
              divisions: 500,
              onChanged: enabled ? onSensitivityChanged : null,
            ),

            const SizedBox(height: 4),

            _LabeledSlider(
              title: 'EQ Reaction Speed',
              subtitle: '0..255 • $filterLabel',
              enabled: enabled,
              value: filter,
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: enabled ? onFilterChanged : null,
            ),

            const SizedBox(height: 4),

            _LabeledSlider(
              title: 'EQ Noise Floor',
              subtitle: '0..1500 • $noiseFloorLabel',
              enabled: enabled,
              value: noise_floor,
              min: 0,
              max: 1500,
              divisions: 750,
              onChanged: enabled ? onNoiseFloorChanged : null,
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: Text(
                    recentMinVolume == null && recentMaxVolume == null
                        ? 'Min/Max: —'
                        : 'Min/Max: ${recentMinVolume ?? 0} / ${recentMaxVolume ?? 0}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: enabled ? onAutoNoiseFloor : null,
                      child: const Text('AUTO'),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            _LabeledSlider(
              title: 'AEQ Filter',
              subtitle: '0..255 • $aeqFilterLabel',
              enabled: enabled,
              value: aeqFilter,
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: enabled ? onAeqFilterChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioDebugCard extends StatelessWidget {
  const _AudioDebugCard({
    required this.telemetry,
    required this.points,
    required this.droppedBlocks,
    required this.frozen,
    required this.onReset,
    required this.onToggleFreeze,
  });

  final _AudioTelemetry? telemetry;
  final List<_AudioPoint> points;
  final int droppedBlocks;
  final bool frozen;
  final VoidCallback onReset;
  final VoidCallback onToggleFreeze;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = points.isEmpty ? DateTime.now() : points.last.time;
    final cutoff = now.subtract(const Duration(seconds: 10));
    final recent = points.where((point) => !point.time.isBefore(cutoff));

    int peak = 0;
    int clippedSamples = 0;
    int totalSamples = 0;
    int saturatedBlocks = 0;
    int totalAeqBlocks = 0;
    for (final point in recent) {
      final value = point.telemetry;
      if (value.rawPeak > peak) peak = value.rawPeak;
      clippedSamples += value.clippedSamples;
      totalSamples += value.totalSamples;
      saturatedBlocks += value.saturatedBlocks;
      totalAeqBlocks += value.totalAeqBlocks;
    }

    final clipPercent = totalSamples == 0
        ? 0.0
        : clippedSamples * 100.0 / totalSamples;
    final saturationPercent = totalAeqBlocks == 0
        ? null
        : saturatedBlocks * 100.0 / totalAeqBlocks;
    final current = telemetry;

    Widget metric(String label, String value, {bool warning = false}) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: warning ? Colors.redAccent : cs.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: warning ? Colors.redAccent : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Audio Debug',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onToggleFreeze,
                  icon: Icon(frozen ? Icons.play_arrow : Icons.pause),
                  label: Text(frozen ? 'Resume' : 'Freeze'),
                ),
                TextButton(onPressed: onReset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 2.15,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                metric(
                  'Peak hold (10 s)',
                  peak == 0 ? '—' : '${_dbfs(peak).toStringAsFixed(1)} dBFS',
                  warning: peak >= 29204,
                ),
                metric(
                  'Mic clipping (10 s)',
                  '${clipPercent.toStringAsFixed(3)}%',
                  warning: clippedSamples > 0,
                ),
                metric(
                  'AEQ saturation (10 s)',
                  saturationPercent == null
                      ? '—'
                      : '${saturationPercent.toStringAsFixed(1)}%',
                  warning: saturationPercent != null && saturationPercent > 10,
                ),
                metric(
                  'Dropped blocks',
                  '$droppedBlocks',
                  warning: droppedBlocks > 0,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 170,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: CustomPaint(
                painter: _AudioChartPainter(points: points, frozen: frozen),
              ),
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _ChartLegend(color: Colors.redAccent, label: 'Peak dBFS'),
                _ChartLegend(color: Colors.lightBlueAccent, label: 'RMS dBFS'),
                _ChartLegend(color: kGold, label: 'AEQ output'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              current == null
                  ? 'Waiting for audio telemetry…'
                  : 'RMS ${_dbfs(current.rms).toStringAsFixed(1)} dBFS  •  '
                        'AEQ ${(current.output * 100 / 32767).clamp(0, 100).toStringAsFixed(0)}%  •  '
                        'Floor ${_dbfs(current.floor).toStringAsFixed(1)} dBFS  •  '
                        'Ceiling ${_dbfs(current.ceiling).toStringAsFixed(1)} dBFS',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _AudioChartPainter extends CustomPainter {
  const _AudioChartPainter({required this.points, required this.frozen});
  final List<_AudioPoint> points;
  final bool frozen;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;

    final end = points.last.time;
    final start = end.subtract(const Duration(seconds: 30));
    final durationMs = const Duration(seconds: 30).inMilliseconds.toDouble();

    double xFor(DateTime time) =>
        ((time.difference(start).inMilliseconds / durationMs) * size.width)
            .clamp(0, size.width);
    double dbY(int value) =>
        size.height * (1 - ((_dbfs(value).clamp(-60, 0) + 60) / 60));
    double outputY(int value) =>
        size.height * (1 - (value / 32767).clamp(0.0, 1.0));

    Path pathFor(double Function(_AudioTelemetry value) yFor) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        final x = xFor(point.time);
        final y = yFor(point.telemetry);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    void drawSeries(Path path, Color color, double width) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    drawSeries(pathFor((value) => dbY(value.rawPeak)), Colors.redAccent, 1.4);
    drawSeries(pathFor((value) => dbY(value.rms)), Colors.lightBlueAccent, 1.4);
    drawSeries(pathFor((value) => outputY(value.output)), kGold, 2);

    if (frozen) {
      final label = TextPainter(
        text: const TextSpan(
          text: 'FROZEN',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(size.width - label.width - 4, 4));
    }
  }

  @override
  bool shouldRepaint(covariant _AudioChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.frozen != frozen;
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({
    super.key,
    required this.enabled,
    required this.vbat,
    required this.time,
    required this.onShutdown,
  });
  final bool enabled;
  final double? vbat;
  final DateTime? time;
  final VoidCallback onShutdown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    double pctFromV(double v) => ((v - 3.7) / (4.2 - 3.7)).clamp(0.0, 1.0);

    final v = vbat;
    final pct = v == null ? null : pctFromV(v);
    final timeStr = time == null
        ? '—'
        : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Power', style: Theme.of(context).textTheme.titleMedium),
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
                            Icon(
                              Icons.battery_full,
                              color: cs.onSurfaceVariant,
                            ),
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
                  onPressed: enabled ? onShutdown : null,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Shut down'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NfcLinkCard extends StatelessWidget {
  const _NfcLinkCard({
    required this.enabled,
    required this.saving,
    required this.controller,
    required this.onSave,
  });

  final bool enabled;
  final bool saving;
  final TextEditingController controller;
  final VoidCallback onSave;

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
            Text('NFC Link', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This is the link opened when a phone scans the necklace.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
                helperText: 'HTTP(S), up to 120 UTF-8 bytes',
              ),
              onSubmitted: enabled ? (_) => onSave() : null,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: enabled ? onSave : null,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.nfc),
                label: Text(saving ? 'Saving...' : 'Save link'),
              ),
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
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: cs.surfaceContainerHighest,
            ),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                (divisions == 13
                    ? value.toStringAsFixed(1)
                    : value.round().toString()),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: enabled ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          //const SizedBox(height: 4),
          //Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: divisions == 13
                ? value.toStringAsFixed(1)
                : value.round().toString(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
