# Audiologist DSP Configuration App

A cross-platform Flutter application for audiologists to configure DSP parameters on bone conduction hearing aids for the Cochlear Implant Project (microtia treatment).

## Features

- **Device Connection**: Scan and connect to hearing aids via Bluetooth Low Energy
- **DSP Configuration**: Adjust EQ, compression, noise reduction, and feedback cancellation
- **Frequency Response**: Visualize the combined effect of DSP settings
- **Preset Management**: Save, load, import, and export patient configurations
- **Test Signals**: Generate test tones and sweeps for fitting

## Supported Platforms

- Windows
- macOS
- iOS
- Android

## Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0.0 or later)
- For iOS: Xcode and CocoaPods
- For Android: Android Studio and Android SDK
- For Windows: Visual Studio with C++ desktop development
- For macOS: Xcode command line tools

## Getting Started

### 1. Install Flutter Dependencies

```bash
cd AudiologistApp
flutter pub get
```

### 2. Run the App

```bash
# Debug mode (any platform)
flutter run

# Specific platforms
flutter run -d windows
flutter run -d macos
flutter run -d ios
flutter run -d android
```

### 3. Build for Release

```bash
# Windows
flutter build windows

# macOS
flutter build macos

# iOS
flutter build ios

# Android
flutter build apk
flutter build appbundle  # For Play Store
```

## Project Structure

```
AudiologistApp/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── models/
│   │   └── dsp_preset.dart       # Preset data model
│   ├── screens/
│   │   ├── home_screen.dart      # Main navigation
│   │   ├── device_connection_screen.dart
│   │   ├── dsp_config_screen.dart
│   │   ├── frequency_response_screen.dart
│   │   └── presets_screen.dart
│   ├── services/
│   │   ├── device_connection_service.dart  # BLE communication
│   │   └── dsp_config_service.dart         # DSP parameter management
│   └── widgets/
│       └── parameter_slider.dart   # Reusable UI components
├── pubspec.yaml                    # Dependencies
└── README.md
```

## DSP Parameters

### Equalizer (5-Band)
| Band | Frequency | Range |
|------|-----------|-------|
| Low | 250 Hz | ±20 dB |
| Low-Mid | 500 Hz | ±20 dB |
| Mid | 1 kHz | ±20 dB |
| High-Mid | 2 kHz | ±20 dB |
| High | 4 kHz | ±20 dB |

### Wide Dynamic Range Compression (WDRC)
| Parameter | Range | Default |
|-----------|-------|---------|
| Threshold | -60 to 0 dB | -30 dB |
| Ratio | 1:1 to 10:1 | 2:1 |
| Attack | 1-100 ms | 5 ms |
| Release | 10-500 ms | 100 ms |

### Additional Processing
- Noise Reduction (0-100%)
- Feedback Cancellation with adaptive rate

## BLE Communication

The app communicates with the nRF54L15-based hearing aids via BLE. The following characteristics are used:

| Service/Characteristic | UUID | Description |
|------------------------|------|-------------|
| DSP Config Service | TBD | Main service for DSP parameters |
| Config Write | TBD | Write DSP configuration |
| Config Read | TBD | Read current configuration |
| Audio Levels | TBD | Real-time input/output levels (notify) |
| Battery | 0x180F | Battery service (standard) |

> **TODO**: Define actual UUIDs when implementing firmware

## Built-in Presets

| Preset | Description |
|--------|-------------|
| Mild Loss | Gentle high-frequency boost |
| Moderate Loss | Balanced amplification across frequencies |
| Severe Loss | Strong amplification with compression |
| High Freq Emphasis | Focus on speech clarity |
| Speech Focus | Optimized for conversation |
| Music | Minimal processing for music enjoyment |

## Development Notes

### Adding New DSP Parameters

1. Add property and setter in `DspConfigService`
2. Add field to `DspPreset` model
3. Update serialization in `toJson()`/`fromJson()`
4. Add UI control in `DspConfigScreen`

### BLE Implementation

The `DeviceConnectionService` contains placeholder code for BLE communication. To implement:

1. Uncomment flutter_blue_plus imports
2. Implement scan/connect/disconnect methods
3. Define characteristic UUIDs matching firmware
4. Implement read/write methods

## License

Part of the Cochlear Implant Project - Bone Conduction Hearing Aid for Microtia
