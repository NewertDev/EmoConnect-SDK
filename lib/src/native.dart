// Bindings to the compiled EmoConnect core.
import 'dart:ffi';
import 'dart:io';

final class EmcAction extends Struct {
  @Int32()
  external int type;
  @Int32()
  external int generation;
  @Int32()
  external int id;
  @Int32()
  external int kind;
  @Int32()
  external int length;
  @Array(64)
  external Array<Uint8> bytes;
}

final class EmcEvent extends Struct {
  @Int32()
  external int type;
  @Int32()
  external int code;
  @Int64()
  external int value1;
  @Int64()
  external int value2;
}

final class EmcSample extends Struct {
  @Uint64()
  external int index;
  @Uint32()
  external int flags;
  @Uint32()
  external int reserved;
  @Double()
  external double ppg;
  @Double()
  external double ppgClean;
  @Array(3)
  external Array<Double> acceleration;
  @Array(3)
  external Array<Double> rotation;
  @Array(3)
  external Array<Double> magnetic;
}

final class EmcHeartRate extends Struct {
  @Uint64()
  external int index;
  @Double()
  external double bpm;
  @Int32()
  external int wearing;
  @Int32()
  external int moving;
  @Int32()
  external int settled;
  @Int32()
  external int reserved;
}

final class EmcDevice extends Struct {
  @Array(20)
  external Array<Uint8> deviceId;
  @Array(32)
  external Array<Uint8> firmware;
  @Int32()
  external int sampleRateHz;
  @Int32()
  external int tier;
  @Int32()
  external int licenseStatus;
  @Int32()
  external int licenseExpiryDays;
  @Int32()
  external int licenseOffline;
}

final class EmcStats extends Struct {
  @Uint64()
  external int samples;
  @Uint64()
  external int skipped;
  @Uint64()
  external int gaps;
  @Uint64()
  external int packets;
  @Uint64()
  external int discarded;
  @Uint64()
  external int droppedOutputs;
  @Uint32()
  external int reconnects;
  @Uint32()
  external int reserved;
}

final class EmcSessionHandle extends Opaque {}

typedef EmcSession = Pointer<EmcSessionHandle>;

/// The library's functions, resolved once.
class CoreLibrary {
  CoreLibrary._(DynamicLibrary l)
      : version = l.lookupFunction<Uint32 Function(), int Function()>('emc_version'),
        uuid = l.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Int32),
            int Function(int, Pointer<Uint8>, int)>('emc_uuid'),
        nameMatches = l.lookupFunction<Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)>('emc_name_matches'),
        preferredMtu =
            l.lookupFunction<Int32 Function(), int Function()>('emc_preferred_mtu'),
        create = l.lookupFunction<EmcSession Function(), EmcSession Function()>(
            'emc_session_create'),
        destroy = l.lookupFunction<Void Function(EmcSession),
            void Function(EmcSession)>('emc_session_destroy'),
        setName = l.lookupFunction<Void Function(EmcSession, Pointer<Uint8>),
            void Function(EmcSession, Pointer<Uint8>)>('emc_set_name'),
        setRecord = l.lookupFunction<Void Function(EmcSession, Pointer<Uint8>, Int32),
            void Function(EmcSession, Pointer<Uint8>, int)>('emc_set_record'),
        takeRecord = l.lookupFunction<Int32 Function(EmcSession, Pointer<Uint8>, Int32),
            int Function(EmcSession, Pointer<Uint8>, int)>('emc_take_record'),
        onHttp = l.lookupFunction<
            Void Function(EmcSession, Int64, Int32, Int32, Pointer<Uint8>, Int32),
            void Function(EmcSession, int, int, int, Pointer<Uint8>, int)>('emc_on_http'),
        httpText = l.lookupFunction<
            Int32 Function(EmcSession, Int32, Int32, Pointer<Uint8>, Int32),
            int Function(EmcSession, int, int, Pointer<Uint8>, int)>('emc_http_text'),
        setLicense = l.lookupFunction<
            Int32 Function(EmcSession, Pointer<Uint8>, Int64),
            int Function(EmcSession, Pointer<Uint8>, int)>('emc_set_license'),
        connect = l.lookupFunction<Void Function(EmcSession, Int64, Int32),
            void Function(EmcSession, int, int)>('emc_connect'),
        disconnect = l.lookupFunction<Void Function(EmcSession, Int64),
            void Function(EmcSession, int)>('emc_disconnect'),
        start = l.lookupFunction<Int32 Function(EmcSession, Int64, Int32),
            int Function(EmcSession, int, int)>('emc_start'),
        stop = l.lookupFunction<Int32 Function(EmcSession, Int64),
            int Function(EmcSession, int)>('emc_stop'),
        setBrightness = l.lookupFunction<Int32 Function(EmcSession, Int64, Int32),
            int Function(EmcSession, int, int)>('emc_set_brightness'),
        onLinkOpened = l.lookupFunction<Void Function(EmcSession, Int64, Int32),
            void Function(EmcSession, int, int)>('emc_on_link_opened'),
        onLinkFailed = l.lookupFunction<Void Function(EmcSession, Int64, Int32),
            void Function(EmcSession, int, int)>('emc_on_link_failed'),
        onLinkLost = l.lookupFunction<Void Function(EmcSession, Int64, Int32),
            void Function(EmcSession, int, int)>('emc_on_link_lost'),
        onAdvert = l.lookupFunction<
            Void Function(EmcSession, Int64, Pointer<Uint8>, Int32, Int32),
            void Function(EmcSession, int, Pointer<Uint8>, int, int)>('emc_on_advert'),
        onScanEnded = l.lookupFunction<Void Function(EmcSession, Int64),
            void Function(EmcSession, int)>('emc_on_scan_ended'),
        onRead = l.lookupFunction<
            Void Function(EmcSession, Int64, Int32, Int32, Pointer<Uint8>, Int32),
            void Function(EmcSession, int, int, int, Pointer<Uint8>, int)>('emc_on_read'),
        onWriteDone = l.lookupFunction<Void Function(EmcSession, Int64, Int32, Int32),
            void Function(EmcSession, int, int, int)>('emc_on_write_done'),
        feed = l.lookupFunction<
            Void Function(EmcSession, Int64, Int32, Int32, Pointer<Uint8>, Int32),
            void Function(EmcSession, int, int, int, Pointer<Uint8>, int)>('emc_feed'),
        poll = l.lookupFunction<Void Function(EmcSession, Int64, Int64, Int32),
            void Function(EmcSession, int, int, int)>('emc_poll'),
        nextAction = l.lookupFunction<Int32 Function(EmcSession, Pointer<EmcAction>),
            int Function(EmcSession, Pointer<EmcAction>)>('emc_next_action'),
        nextEvent = l.lookupFunction<Int32 Function(EmcSession, Pointer<EmcEvent>),
            int Function(EmcSession, Pointer<EmcEvent>)>('emc_next_event'),
        readSamples = l.lookupFunction<
            Int32 Function(EmcSession, Pointer<EmcSample>, Int32),
            int Function(EmcSession, Pointer<EmcSample>, int)>('emc_read_samples'),
        heartRate = l.lookupFunction<Int32 Function(EmcSession, Pointer<EmcHeartRate>),
            int Function(EmcSession, Pointer<EmcHeartRate>)>('emc_heart_rate'),
        deviceInfo = l.lookupFunction<Int32 Function(EmcSession, Pointer<EmcDevice>),
            int Function(EmcSession, Pointer<EmcDevice>)>('emc_device_info'),
        stats = l.lookupFunction<Void Function(EmcSession, Pointer<EmcStats>),
            void Function(EmcSession, Pointer<EmcStats>)>('emc_get_stats');

  /// Where the library is loaded from; tests point it at a local build.
  static String? overridePath;

  static CoreLibrary? _instance;

  static CoreLibrary get instance => _instance ??= CoreLibrary._(_open());

  static DynamicLibrary _open() {
    final path = overridePath;
    if (path != null) return DynamicLibrary.open(path);
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libemoconnect_core.so');
    }
    if (Platform.isWindows) return DynamicLibrary.open('emoconnect_core.dll');
    if (Platform.isIOS) {
      return DynamicLibrary.open('EmoConnectCore.framework/EmoConnectCore');
    }
    throw UnsupportedError(
        'EmoConnect SDK does not support ${Platform.operatingSystem}.');
  }

  final int Function() version;
  final int Function(int, Pointer<Uint8>, int) uuid;
  final int Function(Pointer<Uint8>) nameMatches;
  final int Function() preferredMtu;
  final EmcSession Function() create;
  final void Function(EmcSession) destroy;
  final void Function(EmcSession, Pointer<Uint8>) setName;
  final void Function(EmcSession, Pointer<Uint8>, int) setRecord;
  final int Function(EmcSession, Pointer<Uint8>, int) takeRecord;
  final void Function(EmcSession, int, int, int, Pointer<Uint8>, int) onHttp;
  final int Function(EmcSession, int, int, Pointer<Uint8>, int) httpText;
  final int Function(EmcSession, Pointer<Uint8>, int) setLicense;
  final void Function(EmcSession, int, int) connect;
  final void Function(EmcSession, int) disconnect;
  final int Function(EmcSession, int, int) start;
  final int Function(EmcSession, int) stop;
  final int Function(EmcSession, int, int) setBrightness;
  final void Function(EmcSession, int, int) onLinkOpened;
  final void Function(EmcSession, int, int) onLinkFailed;
  final void Function(EmcSession, int, int) onLinkLost;
  final void Function(EmcSession, int, Pointer<Uint8>, int, int) onAdvert;
  final void Function(EmcSession, int) onScanEnded;
  final void Function(EmcSession, int, int, int, Pointer<Uint8>, int) onRead;
  final void Function(EmcSession, int, int, int) onWriteDone;
  final void Function(EmcSession, int, int, int, Pointer<Uint8>, int) feed;
  final void Function(EmcSession, int, int, int) poll;
  final int Function(EmcSession, Pointer<EmcAction>) nextAction;
  final int Function(EmcSession, Pointer<EmcEvent>) nextEvent;
  final int Function(EmcSession, Pointer<EmcSample>, int) readSamples;
  final int Function(EmcSession, Pointer<EmcHeartRate>) heartRate;
  final int Function(EmcSession, Pointer<EmcDevice>) deviceInfo;
  final void Function(EmcSession, Pointer<EmcStats>) stats;
}
