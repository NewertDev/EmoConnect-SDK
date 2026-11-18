/// EmoConnect SDK: connect to an EmoConnect device and receive its PPG and
/// motion data, the battery level and, with a licence, the processed PPG
/// waveform and the heart rate.
///
/// ```dart
/// final sdk = EmoConnect.instance;
/// final devices = await sdk.scan().first;
/// final device = await sdk.connect(devices.first);
/// device.samples.listen((samples) { /* save or show */ });
/// await device.start();
/// ...
/// await device.stop();
/// await device.disconnect();
/// ```
library;

export 'src/emoconnect.dart' show EmoConnect, EmoConnectConnection;
export 'src/models.dart';
