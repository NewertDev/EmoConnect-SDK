import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'models.dart';
import 'native.dart';

/// Kinds understood by the core.
abstract final class CoreUuid {
  static const int commandService = 0;
  static const int commandWrite = 1;
  static const int commandNotify = 2;
  static const int dataService = 3;
  static const int dataNotify = 4;
  static const int infoService = 5;
  static const int infoFirmware = 6;
  static const int infoSerial = 7;
}

abstract final class CoreChannel {
  static const int data = 0;
  static const int text = 1;
}

abstract final class CoreActionType {
  static const int openLink = 1;
  static const int closeLink = 2;
  static const int startScan = 3;
  static const int stopScan = 4;
  static const int write = 5;
  static const int read = 6;
  static const int http = 7;
}

abstract final class CoreLicense {
  static const int checking = 2;
}

abstract final class CoreState {
  static const int idle = 0;
  static const int connecting = 1;
  static const int connected = 2;
  static const int searching = 3;
  static const int reconnecting = 4;
  static const int restoring = 5;
  static const int closed = 6;
}

abstract final class CoreCloseReason {
  static const int byApp = 0;
  static const int connectFailed = 1;
  static const int linkLost = 2;
  static const int deviceRestarted = 3;
}

abstract final class CoreEventType {
  static const int state = 1;
  static const int identified = 2;
  static const int stopped = 3;
  static const int heartRate = 4;
  static const int battery = 5;
  static const int gap = 6;
  static const int license = 7;
  static const int unsupportedData = 8;
  static const int recovery = 9;
  static const int store = 10;
}

class CoreAction {
  const CoreAction(this.type, this.generation, this.id, this.kind, this.bytes);

  final int type;
  final int generation;
  final int id;
  final int kind;
  final Uint8List bytes;
}

class CoreEvent {
  const CoreEvent(this.type, this.code, this.value1, this.value2);

  final int type;
  final int code;
  final int value1;
  final int value2;
}

/// Link-level facts the core knows and the Dart side must not hard-code.
class CoreLink {
  CoreLink._();

  static String uuid(int kind) {
    final library = CoreLibrary.instance;
    final buffer = calloc<Uint8>(64);
    try {
      final length = library.uuid(kind, buffer, 64);
      if (length <= 0) throw StateError('core has no UUID $kind');
      return String.fromCharCodes(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }

  static bool nameMatches(String name) {
    final library = CoreLibrary.instance;
    final buffer = _text(name);
    try {
      return library.nameMatches(buffer) == 1;
    } finally {
      calloc.free(buffer);
    }
  }

  static int get preferredMtu => CoreLibrary.instance.preferredMtu();

  static String get version {
    final v = CoreLibrary.instance.version();
    return '${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }

  static Pointer<Uint8> _text(String text) {
    final bytes = text.codeUnits;
    final buffer = calloc<Uint8>(bytes.length + 1);
    buffer.asTypedList(bytes.length).setAll(0, bytes.map((c) => c & 0xFF));
    buffer[bytes.length] = 0;
    return buffer;
  }
}

/// One native session: link events and bytes in, actions, events and data
/// out. Every call takes the time from [clock].
class CoreSession {
  CoreSession(this.clock) : _library = CoreLibrary.instance {
    _handle = _library.create();
    if (_handle == nullptr) throw StateError('core session not created');
  }

  /// Monotonic milliseconds.
  final int Function() clock;

  static const int _sampleCapacity = 256;

  final CoreLibrary _library;
  late final Pointer<EmcSessionHandle> _handle;
  final Pointer<EmcSample> _samples = calloc<EmcSample>(_sampleCapacity);
  final Pointer<EmcAction> _action = calloc<EmcAction>();
  final Pointer<EmcEvent> _event = calloc<EmcEvent>();
  Pointer<Uint8> _input = calloc<Uint8>(512);
  int _inputCapacity = 512;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// The advertised name of the device.
  void setName(String name) {
    if (_disposed) return;
    final buffer = CoreLink._text(name);
    try {
      _library.setName(_handle, buffer);
    } finally {
      calloc.free(buffer);
    }
  }

  /// What the core asked to keep in an earlier session, if anything.
  void setRecord(Uint8List? record) {
    if (_disposed) return;
    final bytes = record ?? Uint8List(0);
    _copy(bytes);
    _library.setRecord(_handle, _input, bytes.length);
  }

  /// What the core wants kept now (empty: nothing).
  Uint8List takeRecord() {
    if (_disposed) return Uint8List(0);
    final buffer = calloc<Uint8>(64);
    try {
      final length = _library.takeRecord(_handle, buffer, 64);
      return length > 0
          ? Uint8List.fromList(buffer.asTypedList(length))
          : Uint8List(0);
    } finally {
      calloc.free(buffer);
    }
  }

  int setLicense(String? license, int unixSeconds) {
    if (_disposed) return 0;
    final buffer = CoreLink._text(license ?? '');
    try {
      return _library.setLicense(_handle, buffer, unixSeconds);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Address ([part] 0) or body (1) of the request the core asked for.
  String? httpText(int id, int part) {
    if (_disposed) return null;
    final buffer = calloc<Uint8>(1024);
    try {
      final length = _library.httpText(_handle, id, part, buffer, 1024);
      if (length < 0) return null;
      return String.fromCharCodes(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }

  /// [status] -1 and [body] null when no answer came.
  void onHttp(int id, int status, Uint8List? body) {
    if (_disposed) return;
    final bytes = body ?? Uint8List(0);
    _copy(bytes);
    _library.onHttp(_handle, clock(), id, status, _input, bytes.length);
  }

  void connect(bool autoReconnect) {
    if (!_disposed) _library.connect(_handle, clock(), autoReconnect ? 1 : 0);
  }

  void disconnect() {
    if (!_disposed) _library.disconnect(_handle, clock());
  }

  bool start(int brightness) =>
      !_disposed && _library.start(_handle, clock(), brightness) == 0;

  bool stop() => !_disposed && _library.stop(_handle, clock()) == 0;

  bool setBrightness(int brightness) =>
      !_disposed && _library.setBrightness(_handle, clock(), brightness) == 0;

  void onLinkOpened(int generation) {
    if (!_disposed) _library.onLinkOpened(_handle, clock(), generation);
  }

  void onLinkFailed(int generation) {
    if (!_disposed) _library.onLinkFailed(_handle, clock(), generation);
  }

  void onLinkLost(int generation) {
    if (!_disposed) _library.onLinkLost(_handle, clock(), generation);
  }

  void onAdvert(Uint8List manufacturerData, int rssi) {
    if (_disposed) return;
    _copy(manufacturerData);
    _library.onAdvert(
        _handle, clock(), _input, manufacturerData.length, rssi);
  }

  void onScanEnded() {
    if (!_disposed) _library.onScanEnded(_handle, clock());
  }

  void onRead(int generation, int kind, Uint8List? bytes) {
    if (_disposed) return;
    if (bytes == null) {
      _library.onRead(_handle, clock(), generation, kind, nullptr, -1);
      return;
    }
    _copy(bytes);
    _library.onRead(_handle, clock(), generation, kind, _input, bytes.length);
  }

  void onWriteDone(int id, bool ok) {
    if (!_disposed) _library.onWriteDone(_handle, clock(), id, ok ? 1 : 0);
  }

  void feed(int generation, int channel, Uint8List bytes) {
    if (_disposed || bytes.isEmpty) return;
    _copy(bytes);
    _library.feed(_handle, clock(), generation, channel, _input, bytes.length);
  }

  void poll(DateTime wallClock) {
    if (_disposed) return;
    _library.poll(_handle, clock(), wallClock.millisecondsSinceEpoch ~/ 1000,
        wallClock.timeZoneOffset.inMinutes);
  }

  void _copy(Uint8List bytes) {
    if (bytes.length > _inputCapacity) {
      calloc.free(_input);
      _inputCapacity = bytes.length;
      _input = calloc<Uint8>(_inputCapacity);
    }
    if (bytes.isNotEmpty) _input.asTypedList(bytes.length).setAll(0, bytes);
  }

  List<CoreAction> takeActions() {
    final actions = <CoreAction>[];
    while (!_disposed && _library.nextAction(_handle, _action) == 1) {
      final a = _action.ref;
      final bytes = Uint8List(a.length);
      for (var i = 0; i < a.length; i++) {
        bytes[i] = a.bytes[i];
      }
      actions.add(CoreAction(a.type, a.generation, a.id, a.kind, bytes));
    }
    return actions;
  }

  List<CoreEvent> takeEvents() {
    final events = <CoreEvent>[];
    while (!_disposed && _library.nextEvent(_handle, _event) == 1) {
      final e = _event.ref;
      events.add(CoreEvent(e.type, e.code, e.value1, e.value2));
    }
    return events;
  }

  /// [processed] tells whether the processed waveform is part of the
  /// current tier (otherwise the samples carry none).
  List<PpgSample> takeSamples({required bool processed}) {
    final out = <PpgSample>[];
    while (!_disposed) {
      final n = _library.readSamples(_handle, _samples, _sampleCapacity);
      for (var i = 0; i < n; i++) {
        final s = _samples[i];
        out.add(PpgSample(
          index: s.index,
          ppg: s.ppg,
          clean: processed ? s.ppgClean : null,
          acceleration: Float64List.fromList(
              [s.acceleration[0], s.acceleration[1], s.acceleration[2]]),
          rotation: Float64List.fromList(
              [s.rotation[0], s.rotation[1], s.rotation[2]]),
          magnetic: Float64List.fromList(
              [s.magnetic[0], s.magnetic[1], s.magnetic[2]]),
          afterGap: (s.flags & 1) != 0,
        ));
      }
      if (n < _sampleCapacity) break;
    }
    return out;
  }

  HeartRate? heartRate() {
    if (_disposed) return null;
    final state = calloc<EmcHeartRate>();
    try {
      if (_library.heartRate(_handle, state) != 1) return null;
      final s = state.ref;
      return HeartRate(
        index: s.index,
        bpm: s.bpm,
        wearing: s.wearing != 0,
        moving: s.moving != 0,
        settled: s.settled != 0,
      );
    } finally {
      calloc.free(state);
    }
  }

  EmoConnectInfo? info() {
    if (_disposed) return null;
    final device = calloc<EmcDevice>();
    try {
      if (_library.deviceInfo(_handle, device) != 1) return null;
      final d = device.ref;
      String text(Array<Uint8> chars, int capacity) {
        final codes = <int>[];
        for (var i = 0; i < capacity && chars[i] != 0; i++) {
          codes.add(chars[i]);
        }
        return String.fromCharCodes(codes);
      }

      return EmoConnectInfo(
        deviceId: text(d.deviceId, 20),
        firmwareVersion: text(d.firmware, 32),
        sampleRateHz: d.sampleRateHz,
        tier: d.tier == 1 ? EmoConnectTier.pro : EmoConnectTier.basic,
        licenseStatus: licenseStatus(d.licenseStatus),
        licenseExpiry: d.licenseExpiryDays > 0
            ? DateTime.fromMillisecondsSinceEpoch(
                d.licenseExpiryDays * 86400000,
                isUtc: true)
            : null,
        licenseOffline: d.licenseOffline != 0,
      );
    } finally {
      calloc.free(device);
    }
  }

  static LicenseStatus licenseStatus(int code) => switch (code) {
        1 => LicenseStatus.active,
        2 => LicenseStatus.checking,
        3 => LicenseStatus.refused,
        4 => LicenseStatus.expired,
        5 => LicenseStatus.unverified,
        6 => LicenseStatus.malformed,
        _ => LicenseStatus.none,
      };

  StreamStats stats() {
    if (_disposed) {
      return const StreamStats(samples: 0, skipped: 0, gaps: 0, reconnects: 0);
    }
    final stats = calloc<EmcStats>();
    try {
      _library.stats(_handle, stats);
      final s = stats.ref;
      return StreamStats(
          samples: s.samples,
          skipped: s.skipped,
          gaps: s.gaps,
          reconnects: s.reconnects);
    } finally {
      calloc.free(stats);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _library.destroy(_handle);
    calloc.free(_samples);
    calloc.free(_action);
    calloc.free(_event);
    calloc.free(_input);
  }
}
