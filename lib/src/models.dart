import 'dart:typed_data';

/// A device found while scanning.
class EmoConnectDevice {
  const EmoConnectDevice({required this.id, required this.name, this.rssi});

  /// Platform identifier (MAC address on Android, Windows and Linux; a UUID
  /// on iOS).
  final String id;

  /// Advertised name, for example "EmoConnect v1.0(A1B2)".
  final String name;

  /// Signal strength in dBm, when the platform reports it.
  final int? rssi;

  @override
  String toString() => '$name [$id]';
}

/// What a licence unlocks.
enum EmoConnectTier {
  /// Device values as measured: PPG, motion, battery.
  basic,

  /// Additionally the processed PPG waveform, the heart rate and the
  /// wearing and motion state.
  pro,
}

enum LicenseStatus {
  /// No licence was given.
  none,

  /// The licence is confirmed for this device: by the licence server, or,
  /// when the server could not be reached, by an earlier confirmation kept
  /// on this device ([EmoConnectInfo.licenseOffline]).
  active,

  /// The licence is being checked.
  checking,

  /// The licence server does not accept this licence for this device.
  refused,

  /// The licence has ended.
  expired,

  /// The licence server could not be reached and no earlier confirmation is
  /// kept on this device. Call [EmoConnectConnection.setLicense] again when
  /// the network is back.
  unverified,

  /// The text is not a licence.
  malformed,
}

/// What the device reported about itself, and the licence state.
class EmoConnectInfo {
  const EmoConnectInfo({
    required this.deviceId,
    required this.firmwareVersion,
    required this.sampleRateHz,
    required this.tier,
    required this.licenseStatus,
    this.licenseExpiry,
    this.licenseOffline = false,
  });

  /// The device's own id (16 hex characters; the advertised name ends with
  /// its last 4, the code a licence is registered for). Empty when the
  /// device did not answer.
  final String deviceId;

  final String firmwareVersion;

  /// Samples per second of the [EmoConnectConnection.samples] stream.
  final int sampleRateHz;

  final EmoConnectTier tier;
  final LicenseStatus licenseStatus;

  /// The day the pro tier is confirmed until (UTC midnight; the pro tier
  /// ends when that day begins): the end of the licence as the server gave
  /// it, or, with [licenseOffline], the end of the offline period. Null
  /// without a confirmed licence.
  final DateTime? licenseExpiry;

  /// True when the licence server could not be reached and the pro tier
  /// rests on an earlier confirmation, which lasts 30 days at most.
  final bool licenseOffline;
}

/// One sample: PPG and motion sensors at the same moment.
class PpgSample {
  const PpgSample({
    required this.index,
    required this.ppg,
    required this.clean,
    required this.acceleration,
    required this.rotation,
    required this.magnetic,
    required this.afterGap,
  });

  /// Position in the measurement, 50 per second: time in seconds is
  /// index / 50. Jumps where no data arrived for a while ([afterGap]).
  final int index;

  /// PPG as measured by the device (green light, arbitrary units, 0 while
  /// the sensor sees nothing).
  final double ppg;

  /// Processed PPG waveform for display, within -1..1; null without the pro
  /// tier. NaN while the signal is flat (for example off the skin).
  final double? clean;

  /// Acceleration x, y, z in m/s².
  final Float64List acceleration;

  /// Rotation rate x, y, z in rad/s.
  final Float64List rotation;

  /// Magnetic field x, y, z in µT.
  final Float64List magnetic;

  /// First sample after a stretch without data.
  final bool afterGap;
}

/// Heart rate and signal state, once a second (pro tier).
class HeartRate {
  const HeartRate({
    required this.index,
    required this.bpm,
    required this.wearing,
    required this.moving,
    required this.settled,
  });

  /// Sample index the values belong to (the end of the second).
  final int index;

  /// Beats per minute; 0 while it cannot be measured.
  final double bpm;

  /// False when the sensor is not on skin.
  final bool wearing;

  /// True while movement disturbs the signal.
  final bool moving;

  /// False during the first seconds of a measurement and after the device
  /// was taken off: the heart rate is not computed yet.
  final bool settled;
}

enum PpgBrightness { low, medium, high }

enum EmoConnectState {
  connected,

  /// The connection was lost; the SDK is looking for the device and will
  /// restore the measurement when it is back.
  reconnecting,

  /// Final: the connection object is closed. See
  /// [EmoConnectConnection.disconnectReason].
  disconnected,
}

enum DisconnectReason {
  /// [EmoConnectConnection.disconnect] was called.
  byApp,

  /// The connection was lost and auto reconnect was off.
  connectionLost,

  /// The device was restarted while disconnected. Its measurement is gone;
  /// connect again to start a new one.
  deviceRestarted,
}

enum StreamNoticeKind {
  /// No data arrived for a while; the sample index jumped by
  /// [StreamNotice.samples].
  gap,

  /// The device sends data this SDK version does not read (another
  /// firmware line).
  unsupportedData,

  /// The licence state changed (see [EmoConnectConnection.info]).
  licenseChanged,
}

class StreamNotice {
  const StreamNotice(this.kind, [this.samples = 0]);

  final StreamNoticeKind kind;
  final int samples;
}

class StopResult {
  const StopResult({required this.sampleCount, required this.confirmed});

  /// Samples delivered in this measurement.
  final int sampleCount;

  /// False when the end of the measurement was not confirmed in time.
  final bool confirmed;
}

class StreamStats {
  const StreamStats({
    required this.samples,
    required this.skipped,
    required this.gaps,
    required this.reconnects,
  });

  /// Samples delivered since connecting.
  final int samples;

  /// Samples skipped in gaps.
  final int skipped;
  final int gaps;

  /// Times the connection was lost and restored.
  final int reconnects;
}

class EmoConnectException implements Exception {
  const EmoConnectException(this.message);

  final String message;

  @override
  String toString() => 'EmoConnectException: $message';
}
