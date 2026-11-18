import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'ble_link.dart';
import 'core_session.dart';
import 'license_host.dart';
import 'models.dart';

/// Entry point: finds EmoConnect devices and connects to them.
///
/// Use [EmoConnect.instance]: the Bluetooth plugin underneath keeps one scan
/// callback and one notification callback per app, and this object owns
/// both. Notifications of other devices are handed to [onOtherDeviceValue].
class EmoConnect {
  EmoConnect._(this._link, this._clock, this._now, this._transport, this._store) {
    _link.values.listen(_route);
    _link.scanResults.listen(_onFound);
  }

  static EmoConnect? _instance;

  static EmoConnect get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final stopwatch = Stopwatch()..start();
    return _instance = EmoConnect._(
        UniversalBleLink(),
        () => stopwatch.elapsedMilliseconds,
        DateTime.now,
        sendWithHttpClient,
        FileLicenseStore());
  }

  /// An instance on another link, other clocks and another way to the
  /// licence server (tests).
  @visibleForTesting
  factory EmoConnect.withLink(
    BleLink link, {
    required int Function() monotonicMs,
    DateTime Function()? now,
    LicenseTransport? licenseTransport,
    LicenseStore? licenseStore,
  }) =>
      EmoConnect._(link, monotonicMs, now ?? DateTime.now,
          licenseTransport ?? sendWithHttpClient, licenseStore ?? FileLicenseStore());

  final BleLink _link;
  final int Function() _clock;
  final DateTime Function() _now;
  final LicenseTransport _transport;
  final LicenseStore _store;
  final Map<String, EmoConnectConnection> _connections =
      <String, EmoConnectConnection>{};

  // The platform has one scan; the app's scan and the scans of connections
  // that are looking for their device share it.
  final Set<Object> _scanUsers = <Object>{};
  bool _scanRunning = false;
  Future<void> _scanWork = Future<void>.value();

  final Object _appScan = Object();
  final Map<String, EmoConnectDevice> _found = <String, EmoConnectDevice>{};
  StreamController<List<EmoConnectDevice>>? _scanResults;
  Timer? _scanTimer;

  /// Notifications from devices that are not EmoConnect connections.
  void Function(String deviceId, String characteristic, Uint8List value)?
      onOtherDeviceValue;

  /// Version of the compiled core.
  static String get coreVersion => CoreLink.version;

  /// Scans for devices for [timeout] and emits the devices found so far,
  /// strongest signal first. Bluetooth permissions must be granted first
  /// (Android 12+: BLUETOOTH_SCAN and BLUETOOTH_CONNECT).
  Stream<List<EmoConnectDevice>> scan(
      {Duration timeout = const Duration(seconds: 10)}) {
    stopScan();
    _found.clear();
    final controller = StreamController<List<EmoConnectDevice>>();
    _scanResults = controller;
    _useScan(_appScan).catchError((Object error) {
      if (!controller.isClosed) controller.addError(error);
      stopScan();
    });
    _scanTimer = Timer(timeout, stopScan);
    return controller.stream;
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    final results = _scanResults;
    _scanResults = null;
    if (results == null) return;
    await _releaseScan(_appScan);
    await results.close();
  }

  /// Connects to [device] and waits until it has identified itself.
  ///
  /// [timeout] is the time one connection attempt may take. A failed
  /// attempt is repeated: up to four more times when the failures come
  /// quickly, and not after 20 seconds have passed. Then this throws.
  ///
  /// [license] is the licence of the account the device is registered to;
  /// without one the connection delivers the basic tier. The licence is
  /// checked with the licence server once the device is connected (this
  /// needs the network), and the returned connection already carries the
  /// result in [EmoConnectConnection.info]. A confirmed licence keeps
  /// working without the network for up to 30 days.
  ///
  /// With [autoReconnect] a connection lost unexpectedly is restored
  /// without the app doing anything, and a running measurement continues
  /// (see [EmoConnectConnection.state]).
  Future<EmoConnectConnection> connect(
    EmoConnectDevice device, {
    String? license,
    bool autoReconnect = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await stopScan();
    final existing = _connections[device.id];
    if (existing != null) return existing;
    final connection = EmoConnectConnection._(this, device, timeout);
    _connections[device.id] = connection;
    await connection._open(license, autoReconnect);
    return connection;
  }

  void _route(LinkValue value) {
    final connection = _connections[value.deviceId];
    if (connection != null) {
      connection._onValue(value);
    } else {
      onOtherDeviceValue?.call(value.deviceId, value.characteristic, value.value);
    }
  }

  void _onFound(FoundDevice device) {
    _connections[device.id]?._onAdvert(device);

    final results = _scanResults;
    final name = device.name;
    if (results == null || results.isClosed) return;
    if (name == null || !CoreLink.nameMatches(name)) return;
    _found[device.id] =
        EmoConnectDevice(id: device.id, name: name, rssi: device.rssi);
    final devices = _found.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    results.add(devices);
  }

  Future<void> _useScan(Object user) {
    _scanUsers.add(user);
    return _syncScan();
  }

  Future<void> _releaseScan(Object user) {
    _scanUsers.remove(user);
    return _syncScan().catchError((Object _) {});
  }

  /// Starts or stops the platform scan to match whether anyone needs it.
  Future<void> _syncScan() {
    final work = _scanWork.catchError((Object _) {}).then((_) async {
      final wanted = _scanUsers.isNotEmpty;
      if (wanted == _scanRunning) return;
      if (wanted) {
        _scanRunning = true;
        try {
          await _link.startScan(CoreLink.uuid(CoreUuid.commandService));
        } on Object {
          _scanRunning = false;
          rethrow;
        }
      } else {
        _scanRunning = false;
        try {
          await _link.stopScan();
        } on Object {
          // Bluetooth may have gone off; nothing left to stop.
        }
      }
    });
    _scanWork = work;
    return work;
  }
}

/// A connected device.
class EmoConnectConnection {
  EmoConnectConnection._(this._owner, this.device, this._timeout)
      : _link = _owner._link,
        _core = CoreSession(_owner._clock);

  static const Duration _reconnectTimeout = Duration(seconds: 10);
  static const Duration _stopTimeout = Duration(seconds: 3);
  static const Duration _requestTimeout = Duration(seconds: 8);
  static const Duration _pollInterval = Duration(milliseconds: 100);

  final EmoConnect _owner;
  final BleLink _link;
  final Duration _timeout;
  final CoreSession _core;

  /// The device this connection belongs to.
  final EmoConnectDevice device;

  final StreamController<List<PpgSample>> _samples =
      StreamController<List<PpgSample>>.broadcast();
  final StreamController<HeartRate> _heartRate =
      StreamController<HeartRate>.broadcast();
  final StreamController<int> _battery = StreamController<int>.broadcast();
  final StreamController<StreamNotice> _notices =
      StreamController<StreamNotice>.broadcast();
  final StreamController<EmoConnectState> _state =
      StreamController<EmoConnectState>.broadcast();
  final StreamController<String> _diagnostics =
      StreamController<String>.broadcast();

  final Object _connectScan = Object();
  final Completer<void> _identified = Completer<void>();
  final Completer<void> _closedSignal = Completer<void>();
  Completer<int>? _stopped;
  Completer<void>? _licenseChecked;

  late final String _commandService;
  late final String _commandWrite;
  late final String _commandNotify;
  late final String _dataService;
  late final String _dataNotify;
  late final String _infoService;
  late final String _infoFirmware;
  late final String _infoSerial;

  StreamSubscription<bool>? _linkState;
  Timer? _pollTimer;
  bool _writeWithResponse = true;
  int _generation = 0;
  int _openSerial = 0;
  bool _firstOpen = true;
  bool _linkOpen = false;
  bool _scanning = false;
  bool _pumping = false;
  bool _closed = false;
  bool _measuring = false;
  bool _processed = false;
  int _lastSampleCount = 0;
  EmoConnectInfo? _info;
  EmoConnectState? _publicState;
  int? _lastBattery;
  DisconnectReason? _disconnectReason;

  // Where setting the link up stood and what went wrong, for the message
  // of a failed connect().
  String _openStep = '';
  Object? _openError;

  /// What the device reported about itself, and the licence state.
  EmoConnectInfo get info => _info!;

  /// PPG and motion, 50 samples a second, delivered once a second.
  Stream<List<PpgSample>> get samples => _samples.stream;

  /// Heart rate, wearing and motion state, once a second (pro tier).
  Stream<HeartRate> get heartRate => _heartRate.stream;

  /// Battery level in percent, when it changes.
  Stream<int> get battery => _battery.stream;

  /// Gaps in the data and other things worth knowing.
  Stream<StreamNotice> get notices => _notices.stream;

  Stream<EmoConnectState> get state => _state.stream;

  /// Steps of the reconnect logic, as short words, for troubleshooting logs.
  Stream<String> get diagnostics => _diagnostics.stream;

  /// Last battery level, null until the device reported one.
  int? get lastBattery => _lastBattery;

  bool get isMeasuring => _measuring;

  /// Why the connection ended, null while it is open.
  DisconnectReason? get disconnectReason => _disconnectReason;

  StreamStats get stats => _core.stats();

  Future<void> _open(String? license, bool autoReconnect) async {
    _commandService = CoreLink.uuid(CoreUuid.commandService);
    _commandWrite = CoreLink.uuid(CoreUuid.commandWrite);
    _commandNotify = CoreLink.uuid(CoreUuid.commandNotify);
    _dataService = CoreLink.uuid(CoreUuid.dataService);
    _dataNotify = CoreLink.uuid(CoreUuid.dataNotify);
    _infoService = CoreLink.uuid(CoreUuid.infoService);
    _infoFirmware = CoreLink.uuid(CoreUuid.infoFirmware);
    _infoSerial = CoreLink.uuid(CoreUuid.infoSerial);

    _linkState = _link.connection(device.id).listen((connected) {
      if (connected || _closed || !_linkOpen) return;
      _linkOpen = false;
      _core.onLinkLost(_generation);
      _pump();
    });

    _core.setName(device.name);
    try {
      _core.setRecord(await _owner._store.read(_storeKey));
    } on Object {
      // Nothing kept, or no place to keep it: the server decides alone.
    }
    if (_closed) return;
    final now = _owner._now();
    _core.poll(now);
    if (license != null && license.isNotEmpty) _giveLicense(license);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _core.poll(_owner._now());
      _pump();
    });
    _core.connect(autoReconnect);
    _pump();

    try {
      // The core ends the attempts itself. The last one starts within 21
      // seconds, may take [_timeout] to open the link, and the device's
      // answer follows within about 12 seconds; this only guards against a
      // link that never reports back.
      await _identified.future.timeout(_timeout + const Duration(seconds: 45));
    } on TimeoutException {
      _link.disconnect(device.id).catchError((Object _) {});
      _finish(CoreCloseReason.connectFailed);
      throw const EmoConnectException('The device did not answer.');
    }
    await _licenseAnswer();
  }

  /// Gives the connection a licence (null removes it) and waits for the
  /// licence server's answer. Returns the resulting state, which is also in
  /// [info]. The tier changes with the next second of data.
  ///
  /// Calling it again with the same licence asks the server again, for
  /// example after [LicenseStatus.unverified] when the network is back.
  Future<LicenseStatus> setLicense(String? license) async {
    _checkOpen();
    final status = _giveLicense(license);
    _pump();
    await _licenseAnswer();
    return _info?.licenseStatus ?? status;
  }

  LicenseStatus _giveLicense(String? license) {
    final code = _core.setLicense(
        license, _owner._now().millisecondsSinceEpoch ~/ 1000);
    final waiting = _licenseChecked;
    if (code == CoreLicense.checking) {
      if (waiting == null || waiting.isCompleted) _licenseChecked = Completer<void>();
    } else if (waiting != null && !waiting.isCompleted) {
      waiting.complete();
    }
    return CoreSession.licenseStatus(code);
  }

  /// Waits until the licence check under way has ended. The request itself
  /// is given up after [_requestTimeout], so this cannot wait for long.
  Future<void> _licenseAnswer() async {
    final waiting = _licenseChecked;
    if (waiting == null || waiting.isCompleted) return;
    try {
      await waiting.future.timeout(_requestTimeout + const Duration(seconds: 4));
    } on TimeoutException {
      // The state stays "checking"; the answer may still come.
    }
  }

  /// The name the licence record of this device is kept under.
  String get _storeKey {
    final name = device.name.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return name.isNotEmpty ? name : device.id.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  }

  /// Starts a measurement. The data streams begin about a second later.
  Future<void> start({PpgBrightness brightness = PpgBrightness.medium}) async {
    _checkOpen();
    if (_measuring) throw const EmoConnectException('Already measuring.');
    _core.poll(_owner._now());
    if (!_core.start(brightness.index)) {
      throw const EmoConnectException('The device is not connected.');
    }
    _measuring = true;
    _pump();
  }

  /// Stops the measurement. Waits until the data still on its way is out.
  Future<StopResult> stop() async {
    _checkOpen();
    if (!_measuring) {
      return StopResult(sampleCount: _lastSampleCount, confirmed: true);
    }
    final stopped = _stopped = Completer<int>();
    if (!_core.stop()) {
      _stopped = null;
      _measuring = false;
      return StopResult(sampleCount: _lastSampleCount, confirmed: false);
    }
    _pump();
    try {
      _lastSampleCount = await stopped.future.timeout(_stopTimeout);
      return StopResult(sampleCount: _lastSampleCount, confirmed: true);
    } on TimeoutException {
      return StopResult(sampleCount: _lastSampleCount, confirmed: false);
    } finally {
      _stopped = null;
      _measuring = false;
    }
  }

  /// Changes the brightness of the PPG light.
  Future<void> setBrightness(PpgBrightness brightness) async {
    _checkOpen();
    if (!_core.setBrightness(brightness.index)) {
      throw const EmoConnectException('The device is not connected.');
    }
    _pump();
  }

  /// Stops a measurement if needed and disconnects. The device is not
  /// reconnected afterwards.
  Future<void> disconnect() async {
    if (_closed) return;
    if (_measuring) {
      try {
        await stop();
      } on Object {
        // Disconnecting anyway.
      }
    }
    if (_closed) return;
    _core.disconnect();
    _pump();
    try {
      await _closedSignal.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _link.disconnect(device.id).catchError((Object _) {});
      _finish(CoreCloseReason.byApp);
    }
  }

  void _checkOpen() {
    if (_closed) throw const EmoConnectException('The connection is closed.');
  }

  // ---- what the core asks for ---------------------------------------------

  void _pump() {
    if (_pumping || _closed) return;
    _pumping = true;
    try {
      for (var round = 0; round < 8 && !_closed; round++) {
        final actions = _core.takeActions();
        final events = _core.takeEvents();
        if (actions.isEmpty && events.isEmpty) break;
        actions.forEach(_execute);
        events.forEach(_handle);
      }
      if (_closed) return;
      final samples = _core.takeSamples(processed: _processed);
      if (samples.isNotEmpty) _samples.add(samples);
    } finally {
      _pumping = false;
    }
  }

  void _execute(CoreAction action) {
    switch (action.type) {
      case CoreActionType.openLink:
        _openLink(action.generation);
      case CoreActionType.closeLink:
        _openSerial++;
        _linkOpen = false;
        _link.disconnect(device.id).catchError((Object _) {});
      case CoreActionType.startScan:
        _scanning = true;
        _owner._useScan(this).catchError((Object _) {
          if (_closed || !_scanning) return;
          _scanning = false;
          _core.onScanEnded();
          _pump();
        });
      case CoreActionType.stopScan:
        _scanning = false;
        _owner._releaseScan(this);
      case CoreActionType.write:
        _link
            .write(device.id, _commandService, _commandWrite, action.bytes,
                _writeWithResponse)
            .then((_) => true, onError: (Object _) => false)
            .then((ok) {
          if (_closed) return;
          _core.onWriteDone(action.id, ok);
          _pump();
        });
      case CoreActionType.read:
        final characteristic =
            action.kind == 0 ? _infoFirmware : _infoSerial;
        _link
            .read(device.id, _infoService, characteristic)
            .then<Uint8List?>((value) => value, onError: (Object _) => null)
            .then((value) {
          if (_closed) return;
          _core.onRead(action.generation, action.kind, value);
          _pump();
        });
      case CoreActionType.http:
        _send(action.id, action.kind == 1 ? 'PUT' : 'POST');
    }
  }

  /// Sends the request the core wrote and hands the answer back.
  void _send(int id, String method) {
    final address = _core.httpText(id, 0);
    final body = _core.httpText(id, 1);
    final Future<LicenseResponse?> answer = (address == null || body == null)
        ? Future<LicenseResponse?>.value()
        : Future<LicenseResponse>.sync(
                () => _owner._transport(method, address, body))
            .timeout(_requestTimeout)
            .then<LicenseResponse?>((r) => r, onError: (Object _) => null);
    answer.then((response) {
      if (_closed) return;
      _core.onHttp(id, response?.status ?? -1, response?.body);
      _pump();
    });
  }

  /// Connects and sets the link up: services, MTU, notifications.
  Future<void> _openLink(int generation) async {
    final serial = ++_openSerial;
    _generation = generation;
    _linkOpen = false;
    final timeout = _firstOpen ? _timeout : _reconnectTimeout;
    _firstOpen = false;
    bool current() => serial == _openSerial && !_closed;

    Future<void> setUp() async {
      _openStep = 'connecting';
      await _link.connect(device.id, timeout);
      if (!current()) return;
      _openStep = 'reading the services';
      final services = await _link.services(device.id);
      LinkService? command;
      LinkService? data;
      for (final service in services) {
        if (service.uuid == _commandService) command = service;
        if (service.uuid == _dataService) data = service;
      }
      if (command == null ||
          data == null ||
          !command.characteristics.containsKey(_commandWrite) ||
          !command.characteristics.containsKey(_commandNotify) ||
          !data.characteristics.containsKey(_dataNotify)) {
        throw const EmoConnectException('Not an EmoConnect device.');
      }
      _writeWithResponse = command.characteristics[_commandWrite] ?? true;
      _openStep = 'setting the link up';
      try {
        await _link.requestMtu(device.id, CoreLink.preferredMtu);
      } on Object {
        // Not supported everywhere (Linux, iOS negotiate on their own).
      }
      await _link.notify(device.id, _dataService, _dataNotify);
      await _link.notify(device.id, _commandService, _commandNotify);
      _openStep = 'waiting for the device to answer';
    }

    // Windows finds a device it is asked to connect to much sooner while a
    // scan is running; without one the attempt often ends before the
    // connection is made.
    final scanWhileConnecting = Platform.isWindows;
    if (scanWhileConnecting) {
      _owner._useScan(_connectScan).catchError((Object _) {});
    }
    try {
      try {
        await setUp().timeout(timeout + const Duration(seconds: 20));
      } finally {
        if (scanWhileConnecting) _owner._releaseScan(_connectScan);
      }
      if (!current()) return;
      _linkOpen = true;
      _core.onLinkOpened(generation);
    } on Object catch (error) {
      if (!current()) return;
      _openError = error;
      try {
        await _link.disconnect(device.id);
      } on Object {
        // Already gone.
      }
      if (!current()) return;
      _core.onLinkFailed(generation);
    }
    _pump();
  }

  void _onValue(LinkValue value) {
    if (_closed || !_linkOpen) return;
    final int channel;
    if (value.characteristic == _dataNotify) {
      channel = CoreChannel.data;
    } else if (value.characteristic == _commandNotify) {
      channel = CoreChannel.text;
    } else {
      return;
    }
    _core.feed(_generation, channel, value.value);
    _pump();
  }

  void _onAdvert(FoundDevice found) {
    if (_closed || !_scanning) return;
    _core.onAdvert(found.manufacturerData, found.rssi ?? 0);
    _pump();
  }

  // ---- what the core reports ----------------------------------------------

  void _handle(CoreEvent event) {
    switch (event.type) {
      case CoreEventType.state:
        switch (event.code) {
          case CoreState.connected:
            _publish(EmoConnectState.connected);
          case CoreState.searching:
          case CoreState.reconnecting:
          case CoreState.restoring:
            _publish(EmoConnectState.reconnecting);
          case CoreState.closed:
            _finish(event.value1);
        }
      case CoreEventType.identified:
        _info = _core.info();
        if (!_identified.isCompleted) _identified.complete();
      case CoreEventType.stopped:
        final stopped = _stopped;
        if (stopped != null && !stopped.isCompleted) {
          stopped.complete(event.value1);
        } else {
          _lastSampleCount = event.value1;
        }
      case CoreEventType.heartRate:
        final rate = _core.heartRate();
        if (rate != null) _heartRate.add(rate);
      case CoreEventType.battery:
        _lastBattery = event.value1;
        _battery.add(event.value1);
      case CoreEventType.gap:
        _notices.add(StreamNotice(StreamNoticeKind.gap, event.value1));
      case CoreEventType.license:
        _processed = event.value1 == 1;
        _info = _core.info() ?? _info;
        _notices.add(const StreamNotice(StreamNoticeKind.licenseChanged));
        final waiting = _licenseChecked;
        if (event.code != CoreLicense.checking &&
            waiting != null &&
            !waiting.isCompleted) {
          waiting.complete();
        }
      case CoreEventType.store:
        final record = _core.takeRecord();
        _owner._store
            .write(_storeKey, record.isEmpty ? null : record)
            .catchError((Object _) {});
      case CoreEventType.unsupportedData:
        _notices.add(const StreamNotice(StreamNoticeKind.unsupportedData));
      case CoreEventType.recovery:
        if (event.code > 0 && event.code < _recoverySteps.length) {
          _diagnostics.add(_recoverySteps[event.code]);
        }
    }
  }

  static const List<String> _recoverySteps = <String>[
    '',
    'connectionLost',
    'scanStarted',
    'scanRestarted',
    'scanError',
    'deviceSeen',
    'reconnectStarted',
    'reconnectFailed',
    'linkReady',
    'sessionIdRead',
    'measurementRestored',
    'firstData',
    'recovered',
    'restoreRepeated',
    'linkRenewed',
    'deviceRestarted',
    'disconnectedByApp',
    'stopNotConfirmed',
    'lateEventIgnored',
  ];

  void _publish(EmoConnectState state) {
    if (_publicState == state || !_identified.isCompleted) return;
    _publicState = state;
    _state.add(state);
  }

  void _finish(int reason) {
    if (_closed) return;
    _closed = true;
    _owner._connections.remove(device.id);
    _pollTimer?.cancel();
    _linkState?.cancel();
    if (_scanning) {
      _scanning = false;
      _owner._releaseScan(this);
    }
    _measuring = false;
    _disconnectReason = switch (reason) {
      CoreCloseReason.linkLost => DisconnectReason.connectionLost,
      CoreCloseReason.deviceRestarted => DisconnectReason.deviceRestarted,
      _ => DisconnectReason.byApp,
    };

    final wasIdentified = _identified.isCompleted;
    if (!wasIdentified) {
      final error = _openError;
      _identified.completeError(EmoConnectException(
          'Could not connect to the device (while $_openStep'
          '${error == null ? '' : ': $error'}).'));
      // Whoever awaits connect() gets the error; nobody else listens.
      _identified.future.catchError((Object _) {});
    }
    final stopped = _stopped;
    if (stopped != null && !stopped.isCompleted) stopped.complete(_lastSampleCount);
    if (wasIdentified) {
      _publicState = EmoConnectState.disconnected;
      _state.add(EmoConnectState.disconnected);
    }
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    final waiting = _licenseChecked;
    if (waiting != null && !waiting.isCompleted) waiting.complete();

    _core.dispose();
    for (final controller in <StreamController<Object?>>[
      _samples, _heartRate, _battery, _notices, _state, _diagnostics
    ]) {
      controller.close();
    }
  }
}
