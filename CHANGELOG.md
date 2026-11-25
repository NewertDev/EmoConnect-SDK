## 0.2.0

- iOS (15.0 and later) and macOS (12.0 and later, Apple Silicon and Intel).
- iOS and macOS: when Bluetooth is switched off during a connection the SDK
  now notices the lost link and starts reconnecting, and searches again once
  Bluetooth is back (the system reports only the adapter state there).
- Example app: iOS no longer asks for the Android-only Bluetooth
  permissions (they were always refused there and blocked the scan); iOS
  deployment target 15.0; macOS runner added.

## 0.1.0

- First release: scan, connect, start/stop; PPG, motion and battery
  streams; with a licence the processed PPG waveform, the heart rate and
  the wearing and motion state.
- The licence is the value issued for the Biosignal DataHub account. It is
  checked with the licence server when connecting and keeps working without
  the network for up to 30 days.
- A lost connection is restored automatically and a running measurement
  continues.
- Android and Windows. Linux and iOS follow in the next version.