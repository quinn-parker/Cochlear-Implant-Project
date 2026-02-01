# nRF54L15 PDM Microphone Waveform Test

Skeleton firmware for testing PDM microphone input on the nRF54L15 for the Cochlear Implant Project (bone conduction hearing aid for microtia).

## Overview

This application:
1. Initializes the PDM peripheral to read from a digital MEMS microphone
2. Captures audio samples into double-buffered memory
3. Displays an ASCII waveform visualization over serial console
4. Reports audio statistics (min, max, RMS levels)

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

### Option 1: Command Line

```bash
# Set up environment (if not already done)
source ~/ncs/zephyr/zephyr-env.sh

# Navigate to project directory
cd nRF54L15

# Build for nRF54L15-DK
west build -b nrf54l15dk/nrf54l15/cpuapp

# Flash to device
west flash
```

### Option 2: VS Code with nRF Connect Extension

1. Open the `nRF54L15` folder in VS Code
2. Click "Add Build Configuration" in the nRF Connect extension
3. Select board: `nrf54l15dk/nrf54l15/cpuapp`
4. Click "Build"
5. Click "Flash"

## Usage

1. Connect the nRF54L15-DK to your computer via USB
2. Open a serial terminal at **115200 baud**:
   ```bash
   # Linux/macOS
   screen /dev/ttyACM0 115200
   
   # Or using minicom
   minicom -D /dev/ttyACM0 -b 115200
   ```
3. Reset the board - you should see the waveform display updating

### Serial Output

The application displays:
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

Key parameters in `src/main.c`:

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
