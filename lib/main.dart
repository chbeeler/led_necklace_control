import 'package:flutter/material.dart';

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
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---- Connection state (hook to universal_ble later) ----
  bool _connected = false;
  String _deviceName = 'LED Necklace';
  String _status = 'Not connected';

  // ---- Settings state (MVP) ----
  double _brightness = 120; // UI 0..255
  LedMode _mode = LedMode.eq;
  double _filter = 0; // 0..255 (your FW maps this to alpha)
  double _sensitivity = 128; // 0..255 (placeholder)

  // ---- Battery state ----
  double? _vbat; // volts, null = unknown
  DateTime? _vbatTime;

  bool _busy = false;

  // TODO: Replace with actual BLE connect logic
  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _status = 'Connecting…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    setState(() {
      _connected = true;
      _busy = false;
      _status = 'Connected';
      _deviceName = 'LED Necklace';
    });
  }

  // TODO: Replace with actual BLE disconnect logic
  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _status = 'Disconnecting…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    setState(() {
      _connected = false;
      _busy = false;
      _status = 'Not connected';
    });
  }

  // TODO: Replace with BLE read/notify subscription
  Future<void> _refreshBattery() async {
    if (!_connected) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    setState(() {
      _vbat = 4.01; // placeholder
      _vbatTime = DateTime.now();
      _busy = false;
    });
  }

  // When you wire BLE:
  // brightnessToSend = (_brightness * 4).round() or whatever you want
  int get _brightnessToSend => (_brightness.round() * 4).clamp(0, 1023);
  int get _filterToSend => _filter.round().clamp(0, 255);
  int get _sensitivityToSend => _sensitivity.round().clamp(0, 255);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Necklace Control'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ConnectionChip(connected: _connected, status: _status),
          ),
          if (!_connected)
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
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
          _HeaderCard(
            deviceName: _deviceName,
            connected: _connected,
            status: _status,
          ),
          const SizedBox(height: 14),

          _SettingsCard(
            enabled: _connected && !_busy,
            brightness: _brightness,
            brightnessLabel: '${_brightness.round()}  → send $_brightnessToSend',
            onBrightnessChanged: (v) => setState(() => _brightness = v),

            mode: _mode,
            onModeChanged: (m) => setState(() => _mode = m),

            filter: _filter,
            filterLabel: '${_filter.round()}',
            onFilterChanged: (v) => setState(() => _filter = v),

            sensitivity: _sensitivity,
            sensitivityLabel: '${_sensitivity.round()}',
            onSensitivityChanged: (v) => setState(() => _sensitivity = v),
          ),

          const SizedBox(height: 14),

          _BatteryCard(
            enabled: _connected && !_busy,
            vbat: _vbat,
            time: _vbatTime,
            onRefresh: _refreshBattery,
          ),

          const SizedBox(height: 14),

          _FooterHint(
            text: _connected
                ? 'Tip: debounce slider writes (e.g. 80–150 ms) once BLE is wired.'
                : 'Connect to start controlling the necklace.',
          ),
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
  const _HeaderCard({
    required this.deviceName,
    required this.connected,
    required this.status,
  });

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
              child: Icon(
                Icons.auto_awesome,
                color: connected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deviceName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    connected ? 'Ready to control' : 'Not connected',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
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
                      items: LedMode.values
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m.label),
                              ))
                          .toList(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
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
                  child: Text(
                    'FW: ${mode.fwValue}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _LabeledSlider(
              title: 'Filter',
              subtitle: '0..255 (maps to LP alpha in FW) • $filterLabel',
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
  const _BatteryCard({
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

    double pctFromV(double v) {
      // rough LiPo mapping: 3.3V ~ empty, 4.2V ~ full
      final p = ((v - 3.3) / (4.2 - 3.3)).clamp(0.0, 1.0);
      return p;
    }

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
                    child: Row(
                      children: [
                        Icon(Icons.battery_full, color: cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v == null ? 'Unknown' : '${v.toStringAsFixed(3)} V',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Last update: $timeStr',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (pct != null)
                          SizedBox(
                            width: 90,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 10,
                                backgroundColor: cs.outlineVariant,
                              ),
                            ),
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

class _FooterHint extends StatelessWidget {
  const _FooterHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
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
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.labelLarge),
              ),
              Text(
                value.round().toString(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: enabled ? cs.primary : cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
