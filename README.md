# AppTrack

AppTrack is a Flutter-based Android network traffic monitoring application.

It uses Android's `VpnService` to observe network traffic locally and presents live connection information in a simple, user-friendly interface.

## Features

- 📡 Live network traffic monitoring
- 🔎 Search traffic by IP, country, ISP, or port
- 🌐 Display destination IP addresses and ports
- 📱 Show the application associated with network traffic
- 🌍 Display IP geolocation and ISP/organization information
- 🫧 Floating overlay (PIP-style) showing live traffic on top of any app, including the company/ISP behind each connection
- 🔄 Live traffic statistics
- 🧹 Clear live traffic entries
- 📤 Export traffic information
- 🧩 TCP, UDP, and ICMP traffic filters
- 🎮 Custom in-process TCP/IP relay for reliable per-app capture — internet access (including apps and games with non-HTTP, custom-protocol traffic) keeps working normally while monitoring
- ⚙️ Setup and monitoring controls
- 🎨 Clean Flutter UI with Android native integration

## Screenshots

### Setup

![Setup](UI/setup.jpg)

### Live Traffic

![Live Traffic](UI/trafficLog.jpg)

### Floating Overlay (PIP)

![Floating overlay](UI/pip.jpg)

## Tech Stack

- Flutter
- Dart
- Kotlin
- Android `VpnService`
- Custom userspace TCP/IP relay (packet parsing, connection handling, DNS resolution) for capture + connectivity
- Native Android integration (floating overlay window, IP/ISP lookups)
- MethodChannel / platform integration

## Project Structure

```text
lib/
├── app.dart
├── main.dart
├── models/
├── pages/
└── services/

android/
├── app/
└── ...

assets/
├── hev_config.yml
└── ...

hev-socks5-server/
└── ...

UI/
├── setup.jpg
├── trafficLog.jpg
└── pip.jpg
```

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/fsdramjan/AppTrack_FLOW_FIXED_FULL.git
cd AppTrack_FLOW_FIXED_FULL
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Run the application

Connect an Android device or start an Android emulator, then run:

```bash
flutter run
```

## Android Requirements

The application requires Android VPN functionality through `android.net.VpnService`.

When monitoring starts, Android may display a VPN permission/system confirmation dialog. This is expected behavior for applications using `VpnService`.

The floating overlay (PIP) feature additionally requires the "Display over other apps" permission, requested at runtime when first enabled.

## Notes

- This project is intended for network traffic monitoring on the user's own device.
- Some functionality depends on Android platform permissions and native components.
- Internet connectivity for monitored apps (including apps using non-standard/custom protocols, such as some games) is handled by an in-app TCP/IP relay rather than a full native tunnel library.
- Do not commit API keys, credentials, `.env` files, generated build files, or other sensitive information.

## License

Add your preferred license here.
