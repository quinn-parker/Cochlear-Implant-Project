# nRF54L15 Firmware - Cochlear Implant Project

Firmware for the nRF54L15 for the Cochlear Implant Project (bone conduction hearing aid for microtia).

## Applications

This project contains two applications:

### 1. FFT Waveform Analyzer v1.0 (Default)

Real-time FFT spectrum analyzer that processes waveforms (songs with noise) and displays frequency analysis on the console.

**Features:**
- Waveform upload via UART or built-in test waveform generator
- 256-point FFT using Cooley-Tukey Radix-2 algorithm
- Hanning window for reduced spectral leakage
- ASCII spectrum visualization with dB scale
- Peak frequency detection and display
- Supports 16kHz sample rate with 62.5 Hz frequency resolution

### 2. PDM Microphone Test

Original skeleton firmware for testing PDM microphone input.

**Features:**
- PDM peripheral initialization for digital MEMS microphone
- Double-buffered audio capture
- ASCII waveform visualization
- Audio statistics (min, max, RMS levels)

## Hardware Requirements

- **MCU**: nRF54L15-DK or custom board with nRF54L15
- **Microphone**: Infineon IM69D129F Digital PDM MEMS Microphone

### IM69D129F Specifications

| Parameter       | Value                    |
|-----------------|--------------------------|
| SNR             | 69 dB (A-weighted)       |
| AOP             | 128 dB SPL               |
| Sensitivity     | -36 dBFS @ 94 dB SPL     |
| PDM Clock Range | 1.0 MHz - 3.25 MHz       |
| Supply Voltage  | 1.62V - 3.6V             |
| Current         | ~650 µA active           |

### Wiring

| IM69D129F Pin | nRF54L15 Pin | Description              |
|---------------|--------------|--------------------------|
| CLK           | P1.10        | PDM clock (1.28 MHz)     |
| DATA          | P1.11        | PDM data output          |
| VDD           | 1.8V         | Power supply             |
| GND           | GND          | Ground                   |
| L/R           | GND or VDD   | Channel select (see below)|

### L/R Pin Configuration

The IM69D129F L/R pin determines which clock edge the data is valid on:

| L/R Pin | Data Valid On | Config in main.c           |
|---------|---------------|----------------------------|
| GND     | Falling edge  | `#define IM69D129_LR_HIGH 0` |
| VDD     | Rising edge   | `#define IM69D129_LR_HIGH 1` |

> **Note**: Adjust pin definitions in `src/main.c` if using different GPIO pins.

## Software Requirements

- nRF Connect SDK v2.5.0 or later
- Zephyr RTOS (included with nRF Connect SDK)
- West build tool
- A serial terminal (minicom, PuTTY, screen, or VS Code Serial Monitor)

## Building

### Building FFT Waveform Analyzer (Default)

```bash
# Set up environment (if not already done)
source ~/ncs/zephyr/zephyr-env.sh

# Navigate to project directory
cd nRF54L15

# Build FFT Waveform Analyzer for nRF54L15-DK
west build -b nrf54l15dk/nrf54l15/cpuapp

# Flash to device
west flash
```

### Building PDM Microphone Test

```bash
# Build with BUILD_FFT_ANALYZER=OFF to build PDM test instead
west build -b nrf54l15dk/nrf54l15/cpuapp -- -DBUILD_FFT_ANALYZER=OFF
```

### VS Code with nRF Connect Extension

1. Open the `nRF54L15` folder in VS Code
2. Click "Add Build Configuration" in the nRF Connect extension
3. Select board: `nrf54l15dk/nrf54l15/cpuapp`
4. (Optional) Add CMake argument `-DBUILD_FFT_ANALYZER=OFF` for PDM test
5. Click "Build"
6. Click "Flash"

## Usage

### FFT Waveform Analyzer

1. Connect the nRF54L15-DK to your computer via USB
2. Open a serial terminal at **115200 baud**:
   ```bash
   # Linux/macOS
   screen /dev/ttyACM0 115200
   
   # Or using minicom
   minicom -D /dev/ttyACM0 -b 115200
   ```
3. Reset the board - the analyzer will auto-generate a test waveform and display the FFT

#### Commands

| Key | Action |
|-----|--------|
| `T` | Generate test waveform (simulated song with noise) |
| `U` | Upload waveform via UART |
| `F` | Run FFT analysis on current waveform |
| `H` | Show help menu |

#### Test Waveform

The built-in test waveform simulates a musical chord with added noise:
- **Frequencies**: C4 (262Hz), E4 (330Hz), G4 (392Hz), C5 (523Hz), 1kHz, 2kHz
- **Noise**: Random noise at ~30% amplitude
- **Duration**: 256 samples at 16kHz (16ms)

#### Uploading Custom Waveforms

To upload your own waveform (song with noise):

1. Send the character `U` to initiate upload
2. Send 2-byte length (little-endian, in bytes = samples × 2)
3. Send waveform data as 16-bit signed samples (little-endian)

**Python upload example:**
```python
import serial
import struct
import numpy as np

# Open serial connection
ser = serial.Serial('/dev/ttyACM0', 115200, timeout=1)

# Your waveform (song with noise) as int16 array
waveform = np.array([...], dtype=np.int16)

# Send upload command
ser.write(b'U')

# Send length (2 bytes, little-endian)
ser.write(struct.pack('<H', len(waveform) * 2))

# Send waveform data
ser.write(waveform.tobytes())

ser.close()
```

#### FFT Output

The analyzer displays:
- **Top Frequency Components**: Ranked list of detected frequencies with magnitude bars
- **Full Spectrum Visualization**: ASCII art spectrum (0 to 8kHz)
- **Raw FFT Data**: First 32 frequency bins with real/imaginary components

Example output:
```
╔════════════════════════════════════════════════════════════════════╗
║           FFT SPECTRUM ANALYZER v1.0 - nRF54L15                    ║
╠════════════════════════════════════════════════════════════════════╣
║  Sample Rate: 16000 Hz  |  FFT Size:  256  |  Resolution: 62.5 Hz  ║
╚════════════════════════════════════════════════════════════════════╝

Top Frequency Components:

  Freq (Hz)   Bin   Magnitude   dB     Spectrum Bar
  ─────────   ───   ─────────   ────   ──────────────────────────────
    1000.0     16      4523.2    0.0   [██████████████████████████████]
     262.5      4      3892.1   -1.3   [█████████████████████████     ]
     312.5      5      2156.7   -6.4   [████████████████              ]
    2000.0     32      1823.4   -7.9   [██████████████                ]
    ...
```

---

### PDM Microphone Test

The PDM microphone test displays:
- ASCII waveform visualization (updates every 100ms)
- Audio statistics (min, max, average, RMS)
- Level meter
- Raw sample values

Example output:
```
=== PDM Microphone Waveform Test ===
Sample Rate: 16000 Hz | Buffer: 256 samples

Stats: Min= -1234  Max=  1456  Avg=    12  RMS=  890

Waveform (downsampled 8x):
+----------------------------------------------------------------+
|                    ####                                         |
|                   ###### ##                                     |
|                  ############ #                                 |
|                 ###############                                 |
|         ###### ##################                               |
|        ########################### ##                           |
|       ###############################                           |
|      ##################################                         |
|     ####################################                        |
|    ######################################                       |
|   ########################################                      |
|  ##########################################                     |
| ############################################                    |
|##############################################                   |
|################################################                 |
|##################################################               |
+----------------------------------------------------------------+

Level: [====================            ] 890
```

## Configuration

### FFT Waveform Analyzer Parameters (`src/fft_waveform_v1.c`)

| Parameter           | Default | Description                           |
|---------------------|---------|---------------------------------------|
| `FFT_SIZE`          | 256     | FFT size (must be power of 2)        |
| `SAMPLE_RATE_HZ`    | 16000   | Sample rate for frequency calc (Hz)  |
| `MAX_WAVEFORM_SIZE` | 1024    | Maximum waveform storage (samples)   |
| `SPECTRUM_WIDTH`    | 64      | ASCII spectrum display width         |
| `SPECTRUM_HEIGHT`   | 20      | ASCII spectrum display height        |

### PDM Microphone Test Parameters (`src/main.c`)

| Parameter             | Default | Description                        |
|-----------------------|---------|-------------------------------------|
| `PDM_CLK_PIN`         | P1.10   | PDM clock output pin               |
| `PDM_DATA_PIN`        | P1.11   | PDM data input pin                 |
| `SAMPLE_RATE_HZ`      | 16000   | Audio sample rate in Hz            |
| `AUDIO_BUFFER_SAMPLES`| 256     | Samples per buffer                 |
| `WAVEFORM_WIDTH`      | 64      | ASCII waveform display width       |
| `DISPLAY_INTERVAL_MS` | 100     | Waveform update rate               |

## Troubleshooting

### No audio data / flat waveform
- Check PDM_CLK and PDM_DATA pin connections
- Verify IM69D129F power supply (1.8V recommended, supports 1.62V - 3.6V)
- Ensure mic GND is connected
- **Check L/R pin configuration**: 
  - If L/R is tied to GND, set `IM69D129_LR_HIGH 0` in main.c
  - If L/R is tied to VDD, set `IM69D129_LR_HIGH 1` in main.c
- Verify clock frequency is within 1.0 - 3.25 MHz range (default: 1.28 MHz)

### Build errors
- Ensure nRF Connect SDK is properly installed
- Check that you're using SDK v2.5.0 or later (nRF54L15 support)
- Run `west update` to ensure all modules are up to date

### PDM init failed
- The nRF54L15 may require specific pin configurations
- Check the device tree overlay matches your hardware

## Next Steps

After verifying microphone input works:
1. Implement DSP processing (filtering, noise reduction)
2. Add audio output via I2S to MAX98502
3. Optimize for low latency (<10ms)
4. Add power management integration with nPM1300

## Project Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌────────────┐
│  PDM MEMS   │────▶│   nRF54L15   │────▶│  MAX98502   │────▶│ Transducer │
│ Microphone  │     │  (DSP/MCU)   │     │  Class D    │     │   (Bone    │
│             │     │              │     │  Amplifier  │     │ Conduction)│
└─────────────┘     └──────────────┘     └─────────────┘     └────────────┘
                           │
                           │
                    ┌──────▼──────┐
                    │   nPM1300   │
                    │    PMIC     │
                    └─────────────┘
```

## License

SPDX-License-Identifier: Apache-2.0
