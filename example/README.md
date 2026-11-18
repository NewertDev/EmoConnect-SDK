# EmoConnect SDK 예제

EmoConnect 기기를 검색해 연결하고, 측정값을 그래프로 그리고 CSV로 저장하는 앱입니다.

```
flutter pub get
flutter run
```

- 라이선스 토큰을 입력하고 연결하면 정제 PPG와 심박이 함께 나옵니다. 비워 두면 기본 등급(기기 측정값)으로 동작합니다.
- CSV 파일은 앱 문서 폴더(Android는 앱 전용 외부 저장소)에 `emoconnect_<날짜_시각>.csv`로 저장됩니다.
- 사용법은 `lib/main.dart` 한 파일에 있습니다.