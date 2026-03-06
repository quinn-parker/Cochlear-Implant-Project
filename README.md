# Bone Conduction Hearing Aid

A complete bone conduction hearing aid system for microtia treatment, consisting of embedded DSP firmware (nRF54L15) and a cross-platform clinical fitting application (Flutter/Dart).

## Project Structure

```
.
├── app/                        # Flutter GUI (Audiologist Fitting Tool)
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── models/             # Data models
│   │   │   ├── audiogram.dart          # Patient audiogram (air/bone, L/R)
│   │   │   ├── channel_config.dart     # 12-channel WDRC config (binary serialization)
│   │   │   └── hearing_aid_profile.dart # .haprofile root model
│   │   ├── services/           # Business logic
│   │   │   ├── autofit_service.dart        # NAL-NL2 gain prescription
│   │   │   ├── device_connection_service.dart # BLE + serial connection mgmt
│   │   │   ├── dsp_config_service.dart     # Profile state & device comms
│   │   │   ├── protocol_service.dart       # Binary protocol framing
│   │   │   └── transport.dart              # BLE / serial transport layer
│   │   └── screens/            # UI screens
│   │       ├── home_screen.dart            # 5-tab navigation
│   │       ├── device_connection_screen.dart
│   │       ├── audiogram_screen.dart       # Audiogram entry + auto-fit
│   │       ├── dsp_config_screen.dart      # 12-channel gain/compression
│   │       ├── frequency_response_screen.dart # I/O plots, audiogram overlay
│   │       └── presets_screen.dart         # Profile save/load/export
│   └── pubspec.yaml
│
├── firmware/                   # nRF54L15 Embedded Firmware (Zephyr RTOS)
│   ├── src/
│   │   ├── hearing_aid_dsp.c   # 12-band WDRC DSP + runtime config protocol
│   │   ├── ble_service.c       # BLE GATT service for config over wireless
│   │   ├── fft_waveform_v1.c   # FFT spectrum analyzer (alt build)
│   │   └── main.c              # PDM microphone test (alt build)
│   ├── boards/
│   │   └── nrf54l15dk_nrf54l15_cpuapp.overlay
│   ├── tools/
│   │   ├── hearing_aid_serial.py   # Python serial test tool
│   │   └── requirements.txt
│   ├── CMakeLists.txt
│   └── prj.conf
│
├── tools/                      # Development & Testing Utilities
│   ├── audio_testing/          # Python audio visualization (Docker)
│   └── testbench_software/     # Teensy-based hardware testbench
│
├── hardware/                   # Hardware Documentation
│   ├── schematics/
│   └── IMXRT1060RM_rev3_annotations.pdf
│
├── setup.sh                    # One-command dependency installer
└── README.md
```

## Quick Start

### 1. Install Dependencies

```bash
./setup.sh
```

This installs system packages, Flutter SDK, Python dependencies, and checks for the nRF Connect SDK.

### 2. Run the Flutter GUI

```bash
cd app
flutter pub get
flutter run -d linux
```

Other platforms: `-d windows`, `-d macos`, `-d chrome`, `-d android`, `-d ios`.

### 3. Build and Flash Firmware

Requires [nRF Connect SDK](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-SDK) v2.5.0+.

```bash
cd firmware
west build -b nrf54l15dk/nrf54l15/cpuapp
west flash
```

Alternative firmware builds:

```bash
# FFT spectrum analyzer
west build -b nrf54l15dk/nrf54l15/cpuapp -- -DBUILD_APP=fft_analyzer

# PDM microphone test
west build -b nrf54l15dk/nrf54l15/cpuapp -- -DBUILD_APP=pdm_test
```

---

## Architecture

### DSP Pipeline (Firmware)

The firmware processes audio through a real-time pipeline at 16 kHz / 256-point FFT:

```
PDM Mic → FFT → Noise Reduction → 12-Band WDRC → HF Emphasis → IFFT → AGC → Output
                (Wiener + spectral    (per-band     (configurable     (overlap-add)
                 subtraction)          gain, ratio,   start freq,
                                       threshold,     max dB)
                                       MPO limiter)
```

### 12-Channel WDRC Bands

Approximately 1/3-octave spacing in the speech-critical range:

| Channel | Center Freq | FFT Bins | Region |
|---------|------------|----------|--------|
| 0 | 200 Hz | 1–4 | Low vowels |
| 1 | 315 Hz | 4–6 | F1 formant |
| 2 | 500 Hz | 6–10 | Primary speech |
| 3 | 800 Hz | 10–14 | Transition |
| 4 | 1000 Hz | 14–20 | Speech fundamental |
| 5 | 1500 Hz | 20–28 | F2 onset |
| 6 | 2000 Hz | 28–36 | Speech intelligibility |
| 7 | 3000 Hz | 36–52 | Consonants (/s/, /f/) |
| 8 | 4000 Hz | 52–68 | HF consonants |
| 9 | 5000 Hz | 68–84 | Sibilance |
| 10 | 6000 Hz | 84–104 | HF detail |
| 11 | 7500 Hz | 104–128 | Upper bandwidth |

Each channel has independent: **gain** (-20 to +60 dB), **compression threshold** (-60 to 0 dB), **ratio** (1:1 to 10:1), **attack** (1–100 ms), **release** (10–500 ms), **MPO** (80–130 dB SPL).

---

## Communication Protocol

The app and firmware share a binary protocol that works identically over **UART** (115200 baud) and **BLE** (custom GATT service).

### Frame Format

```
[command : 1 byte] [payload_length : 2 bytes LE] [payload : N bytes] [checksum : 1 byte XOR]
```

### Commands

| Cmd | Byte | Direction | Payload | Description |
|-----|------|-----------|---------|-------------|
| `W` | 0x57 | Host → Device | 12 × 24B channel configs (288B) + checksum | Write full config |
| `w` | 0x77 | Host → Device | 1B index + 24B channel + checksum | Write single channel |
| `G` | 0x47 | Host → Device | 20B global config + checksum | Write master/NR/HF |
| `R` | 0x52 | Host → Device | (empty) | Request config readback |
| `r` | 0x72 | Device → Host | 288B channels + 20B global + checksum | Config response |
| `S` | 0x53 | Host → Device | (empty) | Request device status |
| `s` | 0x73 | Device → Host | 14B status struct + checksum | Status response |
| `A` | 0x41 | Device → Host | 1B echoed command | ACK (success) |
| `N` | 0x4E | Device → Host | 1B command + 1B error | NACK (failure) |
| `P` | 0x50 | Host → Device | 2B length + 16-bit samples | Process audio |

### Channel Config Wire Format (24 bytes, packed, little-endian floats)

| Offset | Type | Field |
|--------|------|-------|
| 0 | float32 | gain_db |
| 4 | float32 | threshold_db |
| 8 | float32 | ratio |
| 12 | float32 | attack_ms |
| 16 | float32 | release_ms |
| 20 | float32 | mpo_db_spl |

### BLE Service

| Characteristic | UUID | Properties |
|----------------|------|------------|
| Service | `12345678-1234-5678-1234-56789abcdef0` | — |
| Config Write | `...def1` | Write, Write Without Response |
| Config Notify | `...def2` | Notify |

BLE device name: `BoneCond HA`. MTU negotiated to 512 bytes.

---

## Audiology Profile Format (`.haprofile`)

Patient configurations are saved as JSON files with the `.haprofile` extension:

```json
{
  "version": "1.0",
  "metadata": {
    "patientName": "Jane Doe",
    "patientId": "P-2026-001",
    "audiologistName": "Dr. Smith",
    "clinicName": "City Hearing Center",
    "dateCreated": "2026-03-01T10:30:00Z",
    "dateModified": "2026-03-01T11:45:00Z",
    "notes": "First fitting, mild-moderate sloping loss"
  },
  "audiogram": {
    "left":  { "air": { "250": 20, ... , "8000": 65 }, "bone": { ... } },
    "right": { "air": { "250": 15, ... , "8000": 55 }, "bone": { ... } }
  },
  "channels": [
    { "index": 0, "centerFreqHz": 200, "gainDb": 6.0, "thresholdDb": -40.0,
      "ratio": 1.5, "attackMs": 5.0, "releaseMs": 50.0, "mpoDbSpl": 110.0 },
    ...
  ],
  "master": { "volumeDb": 0.0, "mute": false },
  "noiseReduction": { "enabled": true, "strengthPercent": 50.0 },
  "highFreqEmphasis": { "enabled": true, "startFreqHz": 1500.0,
                         "maxEmphasisDb": 12.0, "slopeDbPerOctave": 3.0 }
}
```

---

## Flutter App Screens

The GUI has 5 tabs:

### 1. Devices
Connect to the hearing aid via **Bluetooth LE** (scan, discover, pair) or **USB Serial** (port selection). Displays firmware version, channel count, and sample rate once connected.

### 2. Audiogram
Enter patient hearing thresholds at 250, 500, 1k, 2k, 3k, 4k, 6k, 8k Hz. Standard audiogram chart with inverted Y-axis (dB HL). Supports:
- Left / Right ear tabs
- Air and bone conduction
- Pure-tone average (PTA) calculation with severity classification
- **Auto-Fit** button — runs a simplified NAL-NL2 prescription to compute initial gain, compression ratio, threshold, and MPO for all 12 channels

### 3. DSP Config
- **Frequency response graph** at top showing 3 gain curves: soft (50 dB), medium (65 dB), loud (80 dB) input levels
- **12 channel strips** — each with a gain slider; expandable for threshold, ratio, attack, release, MPO
- **Master volume** with mute toggle
- **Upload / Read / Reset** buttons for device communication

### 4. Visualization
- **I/O function plot** for any selected channel — shows compression knee, ratio slope, and MPO ceiling
- **Gain curve with audiogram overlay** — see whether prescribed gain compensates for hearing loss at each frequency
- **Global controls** for noise reduction (on/off + strength) and high-frequency emphasis (on/off + max dB)

### 5. Profiles
- Save / load `.haprofile` files to app storage
- Built-in presets: Mild Loss, Moderate Loss, Severe Loss, High-Frequency Loss
- Import / export via system file picker
- Edit patient metadata (name, ID, audiologist, notes)

---

## Auto-Fit Prescription

The auto-fit engine implements a simplified [NAL-NL2](https://www.nal.gov.au/project/nal-nl2/) prescription algorithm:

1. **Interpolates** the patient's audiogram to the 12 channel center frequencies
2. **Computes PTA** (pure-tone average of 500, 1000, 2000 Hz)
3. **Prescribes per-channel gain** using: `gain = X(f) + 0.31 × HL(f) + corrections`
4. **Derives compression ratio** from hearing loss severity (mild → 1.3:1, moderate → 2:1, severe → 3:1)
5. **Sets compression threshold** inversely proportional to hearing loss
6. **Estimates MPO** from uncomfortable loudness level approximation
7. Supports **bilateral correction** (-3 dB) and **new user acclimatization** (-5 dB)

The audiologist can then fine-tune every parameter manually after the initial prescription.

---

## Hardware

| Component | Part | Purpose |
|-----------|------|---------|
| MCU | nRF54L15-DK | ARM Cortex-M33 + BLE 5.4 radio |
| Microphone | Infineon IM69D129F | Digital MEMS, 69 dB SNR, PDM output |
| Amplifier | MAX98502 | Class D, bone conduction transducer driver |
| PMIC | nPM1300 | Power management |
| Transducer | Bone conduction | Vibrates skull bone for sound conduction |

---

## Development

### Firmware Testing (without hardware)

```bash
# Send test commands via Python serial tool
cd firmware/tools
pip install -r requirements.txt
python3 hearing_aid_serial.py --port /dev/ttyACM0 --test
```

### Flutter App (without device)

The app runs in debug mode with simulated BLE devices when no real hardware is detected. All UI screens, audiogram entry, auto-fit, profile save/load, and visualization work without a connected device.

### Audio Testing

```bash
cd tools/audio_testing
docker build -t audio-test .
docker run -v $(pwd):/data audio-test
```

### Testbench (Teensy)

The Teensy-based testbench (`tools/testbench_software/`) allows testing DSP algorithms independently:
- `teensyFirmware.ino` — Arduino sketch supporting PASSTHROUGH, WDRC, NOISE_REDUCTION, FREQ_SHAPING modes
- `testbench.py` — Python test harness that streams audio through the Teensy at 115200 baud

---

## Dependencies

### Flutter App (`app/pubspec.yaml`)

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_blue_plus | ^1.31.0 | BLE communication |
| fl_chart | ^0.66.0 | Audiogram and frequency response charts |
| provider | ^6.1.1 | State management |
| shared_preferences | ^2.2.2 | Local settings storage |
| file_picker | ^6.1.1 | Profile import/export |
| path_provider | ^2.1.2 | App documents directory |

### Firmware (`firmware/prj.conf`)

- Zephyr RTOS (nRF Connect SDK v2.5.0+)
- Bluetooth LE peripheral stack
- PDM/DMIC audio driver
- FPU + Newlib C library
- UART interrupt-driven I/O

### Python Tools

- `numpy`, `pyserial`, `scipy` — serial tool
- `librosa`, `matplotlib`, `soundfile`, `numpy` — audio testing
