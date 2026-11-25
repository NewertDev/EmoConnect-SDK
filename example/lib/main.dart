// EmoConnect SDK example: scan, connect, measure, draw and save.
import 'dart:async';
import 'dart:io';

import 'package:emoconnect_sdk/emoconnect_sdk.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// The SDK entry point used by this app.
EmoConnect sdk = EmoConnect.instance;

/// Called with `start <brightness>` and `stop` when a measurement begins and
/// ends. Unused in this app.
void Function(String event)? measurementHook;

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EmoConnect SDK 예제',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _chartSamples = 500; // 10 seconds

  final TextEditingController _license = TextEditingController();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<String> _log = [];

  List<EmoConnectDevice> _devices = [];
  bool _scanning = false;
  bool _busy = false;
  bool _autoReconnect = true;
  bool _saveCsv = false;
  PpgBrightness _brightness = PpgBrightness.medium;

  EmoConnectConnection? _connection;
  EmoConnectState? _state;
  HeartRate? _heartRate;
  int? _battery;
  PpgSample? _latest;

  final List<double> _ppg = [];
  final List<double> _clean = [];
  final List<double> _accX = [];
  final List<double> _accY = [];
  final List<double> _accZ = [];

  IOSink? _csv;
  String? _csvPath;

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _csv?.close();
    _connection?.disconnect();
    _license.dispose();
    super.dispose();
  }

  void _note(String text) {
    if (!mounted) return;
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _log.insert(0, '$time  $text');
      if (_log.length > 60) _log.removeLast();
    });
  }

  Future<bool> _permissions() async {
    // Android asks at run time. iOS and macOS ask by themselves the first
    // time Bluetooth is used (the scan permissions below are Android only;
    // on iOS permission_handler reports them as permanently denied).
    if (!Platform.isAndroid) return true;
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scan = results[Permission.bluetoothScan];
    final connect = results[Permission.bluetoothConnect];
    final ok = (scan == null || scan.isGranted || scan.isLimited) &&
        (connect == null || connect.isGranted || connect.isLimited);
    if (!ok) _note('블루투스 권한이 없습니다.');
    return ok;
  }

  Future<void> _scan() async {
    if (!await _permissions()) return;
    setState(() {
      _devices = [];
      _scanning = true;
    });
    sdk.scan(timeout: const Duration(seconds: 8)).listen(
      (devices) {
        if (mounted) setState(() => _devices = devices);
      },
      onError: (Object error) => _note('검색 오류: $error'),
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _connect(EmoConnectDevice device) async {
    setState(() => _busy = true);
    try {
      final license = _license.text.trim();
      final connection = await sdk.connect(
        device,
        license: license.isEmpty ? null : license,
        autoReconnect: _autoReconnect,
      );
      _listen(connection);
      setState(() {
        _connection = connection;
        _state = EmoConnectState.connected;
        _devices = [];
      });
      final info = connection.info;
      _note('연결됨: ${device.name}, '
          '등급 ${info.tier.name}, 라이선스 ${info.licenseStatus.name}');
    } on Object catch (error) {
      _note('연결 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _listen(EmoConnectConnection connection) {
    _subscriptions.addAll([
      connection.samples.listen(_onSamples),
      connection.heartRate.listen((rate) {
        if (mounted) setState(() => _heartRate = rate);
      }),
      connection.battery.listen((percent) {
        if (mounted) setState(() => _battery = percent);
      }),
      connection.state.listen((state) {
        if (mounted) setState(() => _state = state);
        switch (state) {
          case EmoConnectState.connected:
            _note('연결됨');
          case EmoConnectState.reconnecting:
            _note('연결이 끊겨 다시 연결하는 중');
          case EmoConnectState.disconnected:
            _note('연결 종료 (${connection.disconnectReason?.name})');
            _closed();
        }
      }),
      connection.notices.listen((notice) {
        switch (notice.kind) {
          case StreamNoticeKind.gap:
            _note('데이터 없음: ${(notice.samples / 50).toStringAsFixed(1)}초 건너뜀');
          case StreamNoticeKind.unsupportedData:
            _note('이 SDK가 읽지 못하는 형식의 데이터를 보내는 기기입니다.');
          case StreamNoticeKind.licenseChanged:
            _note('라이선스: ${connection.info.licenseStatus.name}, '
                '등급 ${connection.info.tier.name}');
        }
      }),
      connection.diagnostics.listen((step) => _note('· $step')),
    ]);
  }

  void _onSamples(List<PpgSample> samples) {
    for (final s in samples) {
      _push(_ppg, s.ppg);
      _push(_clean, s.clean ?? double.nan);
      _push(_accX, s.acceleration[0]);
      _push(_accY, s.acceleration[1]);
      _push(_accZ, s.acceleration[2]);
      _csv?.writeln([
        s.index,
        (s.index / 50).toStringAsFixed(2),
        s.ppg.toStringAsFixed(3),
        s.clean?.toStringAsFixed(4) ?? '',
        for (final v in s.acceleration) v.toStringAsFixed(3),
        for (final v in s.rotation) v.toStringAsFixed(4),
        for (final v in s.magnetic) v.toStringAsFixed(3),
        _heartRate?.bpm.toStringAsFixed(1) ?? '',
      ].join(','));
    }
    if (mounted) setState(() => _latest = samples.last);
  }

  void _push(List<double> buffer, double value) {
    buffer.add(value);
    if (buffer.length > _chartSamples) buffer.removeAt(0);
  }

  Future<void> _start() async {
    final connection = _connection;
    if (connection == null) return;
    try {
      for (final buffer in [_ppg, _clean, _accX, _accY, _accZ]) {
        buffer.clear();
      }
      _heartRate = null;
      if (_saveCsv) await _openCsv();
      measurementHook?.call('start ${_brightness.index}');
      await connection.start(brightness: _brightness);
      _note('측정 시작');
    } on Object catch (error) {
      _note('시작 실패: $error');
    }
  }

  Future<void> _stop() async {
    final connection = _connection;
    if (connection == null) return;
    try {
      measurementHook?.call('stop');
      final result = await connection.stop();
      _note('측정 정지: ${result.sampleCount}개 샘플'
          '${result.confirmed ? '' : ' (정지 확인 안 됨)'}');
    } on Object catch (error) {
      _note('정지 실패: $error');
    }
    await _closeCsv();
    if (mounted) setState(() {});
  }

  Future<void> _disconnect() async {
    await _connection?.disconnect();
  }

  void _closed() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _closeCsv();
    if (!mounted) return;
    setState(() {
      _connection = null;
      _heartRate = null;
      _battery = null;
      _latest = null;
      // The next connection starts with empty charts.
      for (final buffer in [_ppg, _clean, _accX, _accY, _accZ]) {
        buffer.clear();
      }
    });
  }

  Future<void> _openCsv() async {
    final folder = Platform.isAndroid
        ? (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final file = File('${folder.path}${Platform.pathSeparator}emoconnect_$stamp.csv');
    _csv = file.openWrite()
      ..writeln('index,time_s,ppg,ppg_clean,acc_x_ms2,acc_y_ms2,acc_z_ms2,'
          'rot_x_rads,rot_y_rads,rot_z_rads,mag_x_ut,mag_y_ut,mag_z_ut,heart_rate_bpm');
    _csvPath = file.path;
    _note('저장: ${file.path}');
  }

  Future<void> _closeCsv() async {
    final csv = _csv;
    _csv = null;
    await csv?.close();
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connection;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EmoConnect SDK 예제'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('코어 ${EmoConnect.coreVersion}')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (connection == null) ..._connectSection() else ..._deviceSection(connection),
            const SizedBox(height: 12),
            Text('기록', style: Theme.of(context).textTheme.titleSmall),
            for (final line in _log)
              Text(line, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  List<Widget> _connectSection() => [
        TextField(
          controller: _license,
          decoration: const InputDecoration(
            labelText: '라이선스 (없으면 기본 등급)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('끊기면 자동으로 다시 연결'),
          value: _autoReconnect,
          onChanged: (v) => setState(() => _autoReconnect = v),
        ),
        FilledButton.icon(
          onPressed: _scanning || _busy ? null : _scan,
          icon: const Icon(Icons.search),
          label: Text(_scanning ? '검색 중...' : '기기 검색'),
        ),
        for (final device in _devices)
          Card(
            child: ListTile(
              title: Text(device.name),
              subtitle: Text('${device.id}   ${device.rssi ?? '-'} dBm'),
              trailing: const Icon(Icons.bluetooth),
              onTap: _busy ? null : () => _connect(device),
            ),
          ),
        if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      ];

  List<Widget> _deviceSection(EmoConnectConnection connection) {
    final info = connection.info;
    final pro = info.tier == EmoConnectTier.pro;
    final rate = _heartRate;
    final latest = _latest;
    final measuring = connection.isMeasuring;
    final connected = _state == EmoConnectState.connected;
    final expiry = info.licenseExpiry;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(connection.device.name, style: Theme.of(context).textTheme.titleMedium),
              Text('기기 ID ${info.deviceId.isEmpty ? '(응답 없음)' : info.deviceId}'),
              Text('등급 ${pro ? 'Pro' : '기본'}   라이선스 ${info.licenseStatus.name}'
                  '${info.licenseOffline ? ' (오프라인)' : ''}'
                  '${expiry == null ? '' : ' (~${expiry.toIso8601String().substring(0, 10)})'}'),
              Text('상태 ${_state?.name ?? '-'}   배터리 ${_battery == null ? '-' : '$_battery%'}'),
            ],
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<PpgBrightness>(
            value: _brightness,
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _brightness = value);
              if (measuring) {
                try {
                  await connection.setBrightness(value);
                } on Object catch (error) {
                  _note('밝기 변경 실패: $error');
                }
              }
            },
            items: const [
              DropdownMenuItem(value: PpgBrightness.low, child: Text('밝기 낮음')),
              DropdownMenuItem(value: PpgBrightness.medium, child: Text('밝기 보통')),
              DropdownMenuItem(value: PpgBrightness.high, child: Text('밝기 높음')),
            ],
          ),
          FilterChip(
            label: const Text('CSV 저장'),
            selected: _saveCsv,
            onSelected: measuring ? null : (v) => setState(() => _saveCsv = v),
          ),
          FilledButton(
            onPressed: measuring || !connected ? null : _start,
            child: const Text('측정 시작'),
          ),
          OutlinedButton(
            onPressed: measuring ? _stop : null,
            child: const Text('정지'),
          ),
          TextButton(onPressed: _disconnect, child: const Text('연결 해제')),
        ],
      ),
      if (_csvPath != null) Text('저장 파일: $_csvPath', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      if (pro)
        Text(
          rate == null
              ? '심박 -'
              : '심박 ${rate.bpm.toStringAsFixed(0)} bpm   '
                  '${rate.wearing ? '착용' : '미착용'}   '
                  '${rate.moving ? '움직임 있음' : '안정'}   '
                  '${rate.settled ? '' : '(준비 중)'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      _chart('PPG (기기 측정값)', [_ppg], const [Colors.teal]),
      if (pro) _chart('PPG (정제, -1~1)', [_clean], const [Colors.deepOrange]),
      _chart('가속도 x y z (m/s²)', [_accX, _accY, _accZ],
          const [Colors.red, Colors.green, Colors.blue]),
      if (latest != null)
        Text(
          '회전 ${_triple(latest.rotation, 3)} rad/s   지자기 ${_triple(latest.magnetic, 1)} µT',
          style: const TextStyle(fontSize: 12),
        ),
    ];
  }

  static String _triple(List<double> v, int digits) =>
      '${v[0].toStringAsFixed(digits)}, ${v[1].toStringAsFixed(digits)}, ${v[2].toStringAsFixed(digits)}';

  Widget _chart(String title, List<List<double>> series, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: CustomPaint(
                painter: _LinePainter(
                  [for (final s in series) List<double>.of(s)],
                  colors,
                  _chartSamples,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the last values of each series, scaled to their common range.
class _LinePainter extends CustomPainter {
  _LinePainter(this.series, this.colors, this.capacity);

  final List<List<double>> series;
  final List<Color> colors;
  final int capacity;

  @override
  void paint(Canvas canvas, Size size) {
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (final values in series) {
      for (final v in values) {
        if (!v.isFinite) continue;
        if (v < low) low = v;
        if (v > high) high = v;
      }
    }
    if (!low.isFinite || !high.isFinite) return;
    if (high - low < 1e-9) {
      high += 1;
      low -= 1;
    }
    final range = high - low;
    for (var k = 0; k < series.length; k++) {
      final values = series[k];
      final paint = Paint()
        ..color = colors[k]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      final path = Path();
      var drawing = false;
      final offset = capacity - values.length;
      for (var i = 0; i < values.length; i++) {
        final v = values[i];
        if (!v.isFinite) {
          drawing = false;
          continue;
        }
        final x = (offset + i) / (capacity - 1) * size.width;
        final y = size.height - (v - low) / range * (size.height - 8) - 4;
        if (drawing) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          drawing = true;
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
