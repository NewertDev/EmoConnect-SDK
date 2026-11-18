import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// A peripheral seen while scanning, as the link layer reports it.
class FoundDevice {
  const FoundDevice(this.id, this.name, this.rssi, this.manufacturerData);

  final String id;
  final String? name;
  final int? rssi;

  /// Manufacturer data as advertised (company id first), empty when absent.
  final Uint8List manufacturerData;
}

/// A characteristic notification.
class LinkValue {
  const LinkValue(this.deviceId, this.characteristic, this.value);

  final String deviceId;
  final String characteristic;
  final Uint8List value;
}

class LinkService {
  const LinkService(this.uuid, this.characteristics);

  final String uuid;

  /// Characteristic UUID -> can be written with a response.
  final Map<String, bool> characteristics;
}

/// The BLE operations the SDK needs; universal_ble in an app, a fake in
/// tests.
abstract class BleLink {
  Stream<FoundDevice> get scanResults;
  Stream<LinkValue> get values;
  Stream<bool> connection(String deviceId);

  /// Scans for peripherals; [service] narrows the scan where the platform
  /// needs that to keep scanning with the screen off.
  Future<void> startScan(String service);
  Future<void> stopScan();
  Future<void> connect(String deviceId, Duration timeout);
  Future<void> disconnect(String deviceId);
  Future<List<LinkService>> services(String deviceId);
  Future<void> requestMtu(String deviceId, int mtu);
  Future<void> notify(String deviceId, String service, String characteristic);
  Future<Uint8List> read(String deviceId, String service, String characteristic);
  Future<void> write(String deviceId, String service, String characteristic,
      Uint8List value, bool withResponse);
}

/// [BleLink] on universal_ble. universal_ble keeps one scan and one value
/// callback per app; this link owns them while the SDK is in use (values of
/// other devices reach `EmoConnect.onOtherDeviceValue`).
class UniversalBleLink implements BleLink {
  UniversalBleLink() {
    UniversalBle.onScanResult = (device) {
      final data = device.manufacturerDataList;
      _scan.add(FoundDevice(
        device.deviceId,
        device.name,
        device.rssi,
        data.isEmpty ? Uint8List(0) : data.first.toUint8List(),
      ));
    };
    UniversalBle.onValueChange = (deviceId, characteristic, value) {
      _values.add(LinkValue(deviceId, _normal(characteristic), value));
    };
  }

  final StreamController<FoundDevice> _scan =
      StreamController<FoundDevice>.broadcast(sync: true);
  final StreamController<LinkValue> _values =
      StreamController<LinkValue>.broadcast(sync: true);

  static String _normal(String uuid) => BleUuidParser.string(uuid).toLowerCase();

  @override
  Stream<FoundDevice> get scanResults => _scan.stream;

  @override
  Stream<LinkValue> get values => _values.stream;

  @override
  Stream<bool> connection(String deviceId) =>
      UniversalBle.connectionStream(deviceId).map((u) => u.isConnected);

  @override
  Future<void> startScan(String service) => UniversalBle.startScan(
        // Android only keeps a scan alive with the screen off when it has a
        // filter. Elsewhere a filter could hide the part of the
        // advertisement that carries the name.
        scanFilter:
            Platform.isAndroid ? ScanFilter(withServices: [service]) : null,
      );

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId, Duration timeout) =>
      UniversalBle.connect(deviceId, connectionTimeout: timeout);

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Future<List<LinkService>> services(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);
    return <LinkService>[
      for (final service in services)
        LinkService(_normal(service.uuid), <String, bool>{
          for (final c in service.characteristics)
            _normal(c.uuid): c.properties.contains(CharacteristicProperty.write),
        }),
    ];
  }

  @override
  Future<void> requestMtu(String deviceId, int mtu) async {
    await UniversalBle.requestMtu(deviceId, mtu);
  }

  @override
  Future<void> notify(String deviceId, String service, String characteristic) =>
      UniversalBle.setNotifiable(
          deviceId, service, characteristic, BleInputProperty.notification);

  @override
  Future<Uint8List> read(
          String deviceId, String service, String characteristic) =>
      UniversalBle.readValue(deviceId, service, characteristic);

  @override
  Future<void> write(String deviceId, String service, String characteristic,
          Uint8List value, bool withResponse) =>
      UniversalBle.writeValue(
          deviceId,
          service,
          characteristic,
          value,
          withResponse
              ? BleOutputProperty.withResponse
              : BleOutputProperty.withoutResponse);
}
