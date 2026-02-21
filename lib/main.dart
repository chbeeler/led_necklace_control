import 'dart:async';
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
        textTheme: base.textTheme.apply(
          bodyColor: kText,
          displayColor: kText,
        ),

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

enum LedMode { off, eq, solid, test }

extension LedModeUi on LedMode {
  String get label => switch (this) {
        LedMode.off => 'Off',
        LedMode.eq => 'EQ',
        LedMode.solid => 'Solid',
        LedMode.test => 'TST',
      };

  int get fwValue => switch (this) {
        LedMode.off => 0,
        LedMode.eq => 1,
        LedMode.solid => 2,
        LedMode.test => 3,
      };

  static LedMode fromFw(int v) => switch (v) {
        0 => LedMode.off,
        1 => LedMode.eq,
        2 => LedMode.solid,
        3 => LedMode.test,
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
const String CH_NOISE_FLOOR = '19B10056-E8F2-537E-4F6C-D104768A1214';
const String CH_VOL_MIN_MAX = '19B10120-E8F2-537E-4F6C-D104768A1214';
//const String CH_SETTINGS_STR = '19B10110-E8F2-537E-4F6C-D104768A1214';

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
  double _sensitivity = 1000; // 0..1000
  double _noise_floor = 10;
  int? _recentMinVolume;
  int? _recentMaxVolume;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBatteryVisibility());
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
    UniversalBle.onConnectionChange = (String deviceId, bool connected, String? error) {
      if (deviceId != _deviceId) return;
      setState(() {
        _connected = connected;
        _busy = false;
        _status = connected ? 'Connected' : (error != null ? 'Disconnected: $error' : 'Disconnected');
      });
      if (!connected) {
        _stopBatteryPolling();
      } else {
        _updateBatteryVisibility();
      }
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
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Device', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    _busy ? 'Scanning…' : 'Tap your necklace to connect.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
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
                    Text('No devices found. Press Scan again.', style: TextStyle(color: cs.onSurfaceVariant)),
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
      final s = await UniversalBle.read(deviceId, SVC_LED, CH_SENSITIVITY);
      final v = _readSliderValue(s);
      setState(() => _sensitivity = v.toDouble().clamp(0, 1000));
    } catch (_) {}

    try {
      final s = await UniversalBle.read(deviceId, SVC_LED, CH_NOISE_FLOOR);
      final v = _readSliderValue(s);
      setState(() => _noise_floor = v.toDouble().clamp(0, 1000));
    } catch (_) {}
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

      final autoNoise = (minV * 0.9).round().clamp(0, 1000);

      setState(() {
        _recentMinVolume = minV;
        _recentMaxVolume = maxV;
        _noise_floor = autoNoise.toDouble();
        _status = 'Noise floor set from min volume';
      });

      await _writeSlider(id, CH_NOISE_FLOOR, autoNoise, uiFallbackByte: autoNoise);
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
      final ui = _noise_floor.round().clamp(0, 1000);
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
    final cardBottomRight = cardBox.localToGlobal(cardBox.size.bottomRight(Offset.zero));
    final rootTopLeft = rootBox.localToGlobal(Offset.zero);
    final rootBottomRight = rootBox.localToGlobal(rootBox.size.bottomRight(Offset.zero));

    return cardBottomRight.dy > rootTopLeft.dy && cardTopLeft.dy < rootBottomRight.dy;
  }

  void _startBatteryPolling(Duration interval, {bool immediate = false}) {
    if (_batteryPollInterval == interval && _batteryTimer != null) return;
    _batteryTimer?.cancel();
    _batteryPollInterval = interval;
    if (immediate) {
      _refreshBattery(showBusy: false);
    }
    _batteryTimer = Timer.periodic(interval, (_) => _refreshBattery(showBusy: false));
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
            mode: _mode,
            onModeChanged: _debouncedWriteMode,
            filter: _filter,
            filterLabel: '${_filter.round()}',
            onFilterChanged: _debouncedWriteFilter,
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

          const SizedBox(height: 4),

          _BatteryCard(
            key: _batteryCardKey,
            enabled: _connected && !_busy,
            vbat: _vbatV,
            time: _vbatTime,
            onRefresh: _refreshBattery,
          ),

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
              child: Icon(Icons.auto_awesome, color: connected ? cs.onPrimary : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: connected
                  ? Text(deviceName, style: Theme.of(context).textTheme.titleMedium)
                  : Text(
                      'Not connected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButtons extends StatelessWidget {
  const _ModeButtons({required this.enabled, required this.mode, required this.onModeChanged});

  final bool enabled;
  final LedMode mode;
  final ValueChanged<LedMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget buildButton(String label, LedMode value) {
      final active = mode == value;
      final isActive = enabled && active;
      final textColor = isActive ? kText : cs.onSurfaceVariant;
      final fontWeight = isActive ? FontWeight.w800 : FontWeight.w400;

      return Expanded(
        child: TextButton(
          onPressed: enabled ? () => onModeChanged(value) : null,
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
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mode', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            buildButton('OFF', LedMode.off),
            const SizedBox(width: 8),
            buildButton('ON', LedMode.solid),
            const SizedBox(width: 8),
            buildButton('EQ', LedMode.eq),
            const SizedBox(width: 8),
            buildButton('TST', LedMode.test),
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
    required this.mode,
    required this.onModeChanged,
    required this.filter,
    required this.filterLabel,
    required this.onFilterChanged,
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

  final LedMode mode;
  final ValueChanged<LedMode> onModeChanged;

  final double filter;
  final String filterLabel;
  final ValueChanged<double> onFilterChanged;

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

            const SizedBox(height: 4),

            _ModeButtons(
              enabled: enabled,
              mode: mode,
              onModeChanged: onModeChanged,
            ),

            const SizedBox(height: 4),

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

            const SizedBox(height: 4),

            _LabeledSlider(
              title: 'Sensitivity',
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
              title: 'Noise Floor',
              subtitle: '0..1000 • $noiseFloorLabel',
              enabled: enabled,
              value: noise_floor,
              min: 0,
              max: 1000,
              divisions: 500,
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
          ],
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({
    super.key,
    required this.enabled,
    required this.vbat,
    required this.time,
    required this.onRefresh,
  });
  final bool enabled;
  final double? vbat;
  final DateTime? time;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    double pctFromV(double v) => ((v - 3.7) / (4.2 - 3.7)).clamp(0.0, 1.0);

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
      padding: const EdgeInsets.fromLTRB(12,8,12,4),
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
          //const SizedBox(height: 4),
          //Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
