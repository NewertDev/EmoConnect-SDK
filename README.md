# EmoConnect SDK (Flutter) 0.2.0

EmoConnect 기기에 연결해 PPG, 움직임(가속도·회전·지자기), 배터리 상태를 받는 Flutter 패키지입니다.
라이선스가 있으면 정제된 PPG 파형과 심박, 착용·움직임 상태도 함께 받습니다.

- 기기 검색, 연결, 통신, 신호 처리는 SDK가 합니다. 앱은 함수를 호출하고 데이터를 받기만 하면 됩니다.
- 데이터 **저장은 앱이 합니다.** SDK는 스트림만 제공합니다.
- 측정 중에 연결이 끊기면 SDK가 기기를 다시 찾아 연결하고 측정을 이어 갑니다.

| 플랫폼 | 지원 |
|---|---|
| Android | 7.0 (API 24) 이상, arm64-v8a / armeabi-v7a / x86_64 |
| iOS | 15.0 이상 (기기 arm64, 시뮬레이터 arm64 / x86_64) |
| macOS | 12.0 이상, Apple Silicon / Intel |
| Windows | 10 이상, x64 |
| Linux | 준비 중 (다음 버전) |

지원 기기: 이름이 `EmoConnect`로 시작하는 기기 (펌웨어 v1.0 계열).

매뉴얼(PDF): [한국어](doc/EmoConnect_SDK_Manual_ko.pdf) · [English](doc/EmoConnect_SDK_Manual_en.pdf)

## 설치

`pubspec.yaml`에 추가하고 `flutter pub get`을 실행합니다. `ref`로 버전을 고정합니다
(버전 목록: 저장소의 Tags, 변경 내용: `CHANGELOG.md`).

```yaml
dependencies:
  emoconnect_sdk:
    git:
      url: https://github.com/NewertDev/EmoConnect-SDK.git
      ref: v0.2.0
```

zip으로 받았다면 `emoconnect_sdk` 폴더를 프로젝트 옆에 두고 경로로 추가합니다.

```yaml
dependencies:
  emoconnect_sdk:
    path: ../emoconnect_sdk
```

## 빠른 시작

```dart
import 'package:emoconnect_sdk/emoconnect_sdk.dart';

final sdk = EmoConnect.instance;

// 1. 검색: 찾은 기기 목록이 갱신될 때마다 들어옵니다 (기본 10초).
final devices = await sdk.scan(timeout: const Duration(seconds: 5))
    .firstWhere((list) => list.isNotEmpty);

// 2. 연결 (라이선스가 있으면 함께 넘깁니다)
final device = await sdk.connect(devices.first, license: myLicense);
print('${device.info.firmwareVersion}, ${device.info.tier}');

// 3. 데이터 받기 (저장은 앱에서)
device.samples.listen((samples) {
  for (final s in samples) {
    // s.index: 0부터 1초에 50씩. 시간(초) = s.index / 50
    // s.ppg: 기기가 측정한 PPG
    // s.clean: 정제 PPG (-1~1). Pro 등급이 아니면 null
    // s.acceleration, s.rotation, s.magnetic: 각 x, y, z
  }
});
device.heartRate.listen((hr) { /* Pro 등급: 1초마다 hr.bpm, hr.wearing, hr.moving */ });
device.battery.listen((percent) { /* 배터리 % */ });

// 4. 측정 시작
await device.start(brightness: PpgBrightness.medium);

// 5. 정지와 연결 해제
final result = await device.stop();
await device.disconnect();
```

전체 예제는 `example/`에 있습니다(검색, 연결, 측정, 그래프, CSV 저장).

## 제공 데이터

| 스트림 | 내용 | 주기 | 등급 |
|---|---|---|---|
| `samples` | `List<PpgSample>`: PPG, 가속도, 회전, 지자기 | 1초마다 50개 | 기본 |
| `samples`의 `clean` | 정제 PPG 파형 (-1~1) | 위와 같음 | Pro |
| `heartRate` | `HeartRate`: 심박(bpm), 착용 여부, 움직임 여부, 준비 완료 여부 | 1초 | Pro |
| `battery` | 배터리 잔량 (%) | 변할 때 | 기본 |
| `notices` | 데이터가 없던 구간(`gap`), 라이선스 변경, 읽지 못하는 형식의 기기 | 발생할 때 | 기본 |
| `state` | `connected` / `reconnecting` / `disconnected` | 변할 때 | 기본 |

단위와 값의 뜻:

- **`ppg`**: 녹색광 PPG. 기기 안에서 한 번 다듬어진 값이며 단위는 없습니다(0~65535). 센서가 피부에서 떨어지면 0입니다.
- **`clean`**: 화면 표시용으로 정제한 파형입니다. 추세를 없애고 최근 2초 범위에 맞춰 -1~1로 맞춘 값이라
  **진폭 정보는 없습니다.** 진폭이나 파형 모양을 분석하려면 `ppg`를 쓰세요.
  측정 시작 후 2초 동안은 0이고, 신호가 변하지 않는 동안(예: 미착용)은 `NaN`입니다.
- **`acceleration`**: m/s². **`rotation`**: rad/s. **`magnetic`**: µT.
- **`heartRate.bpm`**: 측정할 수 없을 때는 0입니다. 착용하고 움직임이 없는 상태로 약 10초가 지나야 값이 나오기
  시작합니다(`settled`가 true).

시간축:

- 샘플은 초당 50개 격자에 놓입니다. 기기가 실제로 보내는 샘플 수는 펌웨어에 따라 초당 50개보다 적을 수 있고,
  SDK가 받은 샘플을 매끄럽게 이어 초당 50개로 맞춥니다. 받은 그대로의 원시 샘플열이 아닙니다.
- 데이터는 1초 단위로 묶여 전달되므로 실제 측정 시점보다 1초 남짓 늦습니다. `clean`은 같은 묶음의 `ppg`보다
  1초 더 늦은 구간의 파형입니다.
- 데이터가 1초 넘게 오지 않으면(연결 끊김 등) 그 시간만큼 `index`가 건너뜁니다. 다시 이어진 첫 샘플은
  `afterGap`이 true이고, `notices`에 건너뛴 샘플 수가 옵니다.

## 등급과 라이선스

| 등급 | 받는 것 |
|---|---|
| 기본 (라이선스 없음) | `ppg`, 가속도·회전·지자기, 배터리 |
| Pro | 위에 더해 `clean`, `heartRate`. 기기 화면의 심박 표시 |

- 라이선스는 Biosignal DataHub 계정에 발급된 값입니다(`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` 형식의 문자열).
  기기 이름의 괄호 안 코드(예: `EmoConnect v1.0(A1B2)`의 `A1B2`)와 함께 라이선스 서버에서 확인됩니다.
- `sdk.connect(device, license: value)`로 넘기거나, 연결 후 `await device.setLicense(value)`로 넣습니다.
  SDK가 라이선스 서버에 확인하므로 **인터넷 연결이 필요**하고, `connect()`는 확인 결과까지 받은 뒤에
  돌아옵니다(서버가 답하지 않으면 최대 약 8초 기다린 뒤 `unverified`로 돌아옴).
- 상태는 `device.info.licenseStatus`로 확인합니다.

  | 상태 | 뜻 |
  |---|---|
  | `active` | 확인됨. Pro 등급 |
  | `refused` | 서버가 이 라이선스·기기 조합을 받아 주지 않음 |
  | `expired` | 라이선스 기간이 끝남 |
  | `unverified` | 서버에 닿지 못했고 이 기기에 저장된 이전 확인도 없음. 네트워크가 되면 `setLicense`를 다시 호출 |
  | `malformed` | 라이선스 형식이 아닌 문자열 |
  | `checking` | 확인 중 |
  | `none` | 라이선스를 주지 않음 |

- **오프라인 사용**: 한 번 확인되면 그 결과를 이 기기(폰·PC)에 보관해, 이후 인터넷이 안 될 때도 최대 30일
  (라이선스가 그 전에 끝나면 그날까지) Pro 등급으로 동작합니다. 이때 `device.info.licenseOffline`이 true입니다.
  보관한 것은 그 라이선스와 그 기기에만 쓰입니다.
- `device.info.licenseExpiry`: Pro 등급이 확인된 기한입니다(서버가 알려 준 라이선스 종료일, 오프라인이면
  오프라인 기한). 그날이 되면 Pro 등급이 끝납니다.
- Android에서는 이 패키지가 `INTERNET` 권한을 앱에 추가합니다.

## 연결이 끊겼을 때

`connect(..., autoReconnect: true)`(기본값)이면 예기치 않게 끊겼을 때 SDK가 처리합니다.

1. `state`에 `reconnecting`이 옵니다. 연결 객체와 스트림은 그대로 유지됩니다.
2. SDK가 기기를 다시 찾아 연결하고, 측정 중이었다면 측정을 이어 갑니다. `state`에 `connected`가 옵니다.
3. 끊겨 있던 시간만큼 `index`가 건너뜁니다(`notices`의 `gap`).

- 기기가 그사이 **재시작**되었으면(리셋, 전원 꺼짐) 이전 측정은 기기에서 사라진 상태입니다. 이때는 다시
  연결하지 않고 `state`에 `disconnected`가 오며, `device.disconnectReason`이 `deviceRestarted`입니다.
  `connect()`로 새로 연결해 측정을 다시 시작하세요.
- `disconnect()`를 부르면 기기의 측정을 멈추고 끊으며, 다시 연결하지 않습니다.
- `autoReconnect: false`이면 끊기는 즉시 `disconnected`(`connectionLost`)가 오고 연결 객체가 닫힙니다.
- 재연결 과정의 단계는 `device.diagnostics`(짧은 단어 스트림)로 볼 수 있습니다. 문제를 알려 주실 때 이 기록을
  함께 주시면 도움이 됩니다.

## 플랫폼별 준비

### Android

`android/app/src/main/AndroidManifest.xml`에 권한을 넣고, 검색 전에 실행 중 권한을 요청하세요
(예: `permission_handler` 패키지, 예제 앱 참고).

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

화면이 꺼진 상태에서도 측정과 재연결이 이어지게 하려면 앱에서 포그라운드 서비스
(`connectedDevice` 유형)를 실행해야 합니다. SDK는 서비스를 띄우지 않습니다.

### iOS

`ios/Runner/Info.plist`에 블루투스 사용 문구를 넣습니다.

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>EmoConnect 기기와 연결하는 데 블루투스를 사용합니다.</string>
```

배포 대상은 15.0 이상이어야 합니다. `ios/Podfile`의 `platform :ios, '15.0'`과 Xcode 프로젝트의
iOS Deployment Target을 15.0 이상으로 맞춥니다.

- 블루투스 권한은 앱이 처음 검색할 때 iOS가 직접 묻습니다. `permission_handler`의 `bluetoothScan`,
  `bluetoothConnect`는 Android 전용이라 iOS에서는 항상 거절로 나오므로, iOS에서는 요청하지 마세요.
- 기기에 따라 연결할 때 iOS가 블루투스 페어링 요청 창을 띄울 수 있습니다. 창이 떠 있는 동안에도 측정은 됩니다.
- 앱이 백그라운드로 가면 iOS가 앱을 멈출 수 있습니다. 백그라운드에서도 측정을 이어 가려면
  `Info.plist`의 `UIBackgroundModes`에 `bluetooth-central`을 넣는 등 앱에서 준비해야 합니다.

### macOS

`macos/Runner/DebugProfile.entitlements`와 `macos/Runner/Release.entitlements` 두 파일에 블루투스와
네트워크(라이선스 확인) 권한을 넣습니다.

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

`macos/Runner/Info.plist`에 블루투스 사용 문구를 넣습니다.

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>EmoConnect 기기와 연결하는 데 블루투스를 사용합니다.</string>
```

배포 대상은 12.0 이상이어야 합니다. 이전 Flutter로 만든 프로젝트는 10.15로 되어 있을 수 있으니
`macos/Podfile`의 `platform :osx, '12.0'`과 Xcode 프로젝트의 macOS Deployment Target을 12.0 이상으로 맞춥니다.
블루투스 권한은 앱이 처음 검색할 때 macOS가 직접 묻습니다.

### Linux (다음 버전)

BlueZ가 실행 중이어야 합니다(`systemctl status bluetooth`). 사용자 계정이 블루투스를
쓸 수 있어야 합니다(배포판에 따라 `bluetooth` 그룹).

### Windows

추가 설정이 없습니다. 블루투스 LE를 지원하는 어댑터가 필요합니다.

## 알아 둘 점

- SDK는 Bluetooth 플러그인 `universal_ble`을 사용하며, 이 플러그인의 검색·알림 콜백을
  SDK가 차지합니다. 앱에서 다른 BLE 기기도 다룬다면 그 기기의 알림은
  `EmoConnect.instance.onOtherDeviceValue`로 받으세요.
- 같은 기기에 다른 BLE 라이브러리로 동시에 연결하지 마세요.
- 기기 한 대에 연결 하나입니다. 여러 대는 기기마다 `connect()`를 호출합니다.
- `connect()`는 연결 시도가 실패하면 스스로 다시 시도합니다(금방 실패한 경우 네 번까지, 시작한 지
  20초가 지나면 더 시도하지 않음). 그래도 안 되면 예외를 냅니다. `timeout`은 한 번의 시도에 주는
  시간입니다. 연결에는 보통 2~6초가 걸립니다. Windows에서는 블루투스 어댑터에 따라 10초 넘게 걸리거나
  실패할 수 있습니다. 실패하면 다시 `connect()`를 호출하세요.
- 연결할 때 SDK는 기기에 남아 있을 수 있는 이전 측정을 멈춥니다. 측정은 `start()`로 시작합니다.
- 측정 중에는 기기 화면의 시각을 SDK가 맞춥니다. Pro 등급에서는 심박도 기기 화면에 표시됩니다.
- 다른 계열의 펌웨어를 쓰는 기기는 연결은 되지만 데이터를 읽지 못하며, `notices`에
  `unsupportedData`가 옵니다.

## 이전 버전에서 옮기기

2024년에 배포된 샘플 앱과 `newert_vitaltrack` 패키지를 쓰던 앱은 다음과 같이 바꿉니다.

| 예전 방식 | 새 SDK |
|---|---|
| 샘플의 `BleController`를 복사해 검색·연결 | `EmoConnect.instance.scan()`, `connect()` |
| 측정 명령 문자열을 직접 전송 | `start(brightness: ...)`, `stop()` |
| 수신 큐를 1초 타이머로 비우고 50개로 보간 | `samples` 스트림 (이미 초당 50개) |
| 배터리 큐 | `battery` 스트림 |
| 기기 화면의 시각·심박을 앱이 전송 | SDK가 처리 |
| `flutter_reactive_ble` | `universal_ble` (SDK가 포함). 권한 설정은 위 "플랫폼별 준비" 참고 |

값의 차이: 가속도·회전·지자기의 값과 단위는 같습니다. `ppg`는 예전과 같은 기기 값이지만, 초당 50개로 맞추는
방식이 직선 보간에서 매끄러운 곡선 보간으로 바뀌어 샘플 사이 값이 조금 다르고 한 샘플만큼 늦습니다.

## 라이선스

Newert의 독점 소프트웨어입니다. `LICENSE`를 확인하세요.
