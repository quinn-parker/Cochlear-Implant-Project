#!/usr/bin/env python3
"""
Hearing Aid DSP Serial Interface
Cochlear Implant Project - nRF54L15

This script interfaces with the nRF54L15 Hearing Aid DSP processor via serial.
It can:
- Send noisy audio files for processing
- Receive cleaned/processed audio
- Generate test signals with configurable noise
- Compare input vs output signals

Serial Protocol:
    Input:  'P' + 2-byte length (LE) + 16-bit samples (LE)
    Output: 'R' + 2-byte length (LE) + 16-bit samples (LE)

Usage:
    python hearing_aid_serial.py --port /dev/ttyACM0 --input noisy.wav --output clean.wav
    python hearing_aid_serial.py --port COM3 --test  # Generate and process test signal
"""

import argparse
import struct
import time
import sys
import os
import numpy as np

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("Error: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)

try:
    import scipy.io.wavfile as wavfile
    from scipy import signal as scipy_signal
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False
    print("Warning: scipy not installed. WAV file support limited.")
    print("Install with: pip install scipy")


SAMPLE_RATE = 16000
MAX_SAMPLES = 2048


def list_serial_ports():
    """List available serial ports."""
    ports = serial.tools.list_ports.comports()
    print("\nAvailable serial ports:")
    for port in ports:
        print(f"  {port.device}: {port.description}")
    if not ports:
        print("  No serial ports found!")
    print()


def generate_noisy_speech_signal(duration_sec=0.5, noise_level=0.3):
    """
    Generate a test signal simulating speech with noise.
    
    Args:
        duration_sec: Duration in seconds
        noise_level: Noise amplitude relative to signal (0.0-1.0)
    
    Returns:
        numpy array of int16 samples
    """
    num_samples = int(SAMPLE_RATE * duration_sec)
    if num_samples > MAX_SAMPLES:
        num_samples = MAX_SAMPLES
    
    t = np.arange(num_samples) / SAMPLE_RATE
    
    speech_freqs = [300, 500, 800, 1200, 2000, 3000]
    speech_amps = [0.3, 0.5, 0.4, 0.3, 0.2, 0.1]
    
    signal = np.zeros(num_samples)
    
    envelope = np.sin(np.pi * np.arange(num_samples) / num_samples) ** 2
    
    for freq, amp in zip(speech_freqs, speech_amps):
        freq_mod = 1.0 + 0.03 * np.sin(2 * np.pi * 4 * t)
        signal += amp * np.sin(2 * np.pi * freq * freq_mod * t)
    
    signal *= envelope
    
    white_noise = np.random.randn(num_samples) * noise_level
    
    b, a = scipy_signal.butter(4, 4000 / (SAMPLE_RATE / 2), btype='low') if HAS_SCIPY else (None, None)
    if b is not None:
        pink_noise = scipy_signal.filtfilt(b, a, np.random.randn(num_samples)) * noise_level * 0.5
    else:
        pink_noise = np.zeros(num_samples)
    
    noisy_signal = signal + white_noise + pink_noise
    
    max_val = np.max(np.abs(noisy_signal))
    if max_val > 0:
        noisy_signal = noisy_signal / max_val * 0.8
    
    return (noisy_signal * 32767).astype(np.int16)


def generate_pure_noise(duration_sec=0.5):
    """Generate pure noise for noise estimation testing."""
    num_samples = int(SAMPLE_RATE * duration_sec)
    if num_samples > MAX_SAMPLES:
        num_samples = MAX_SAMPLES
    
    noise = np.random.randn(num_samples)
    
    if HAS_SCIPY:
        b, a = scipy_signal.butter(4, [100 / (SAMPLE_RATE / 2), 6000 / (SAMPLE_RATE / 2)], btype='band')
        noise = scipy_signal.filtfilt(b, a, noise)
    
    noise = noise / np.max(np.abs(noise)) * 0.5
    return (noise * 32767).astype(np.int16)


def load_wav_file(filename):
    """Load a WAV file and convert to 16kHz mono int16."""
    if not HAS_SCIPY:
        print("Error: scipy required for WAV file support")
        return None
    
    try:
        rate, data = wavfile.read(filename)
    except Exception as e:
        print(f"Error reading WAV file: {e}")
        return None
    
    if len(data.shape) > 1:
        data = data.mean(axis=1)
    
    if rate != SAMPLE_RATE:
        num_samples = int(len(data) * SAMPLE_RATE / rate)
        data = scipy_signal.resample(data, num_samples)
        print(f"Resampled from {rate}Hz to {SAMPLE_RATE}Hz")
    
    if data.dtype != np.int16:
        if np.issubdtype(data.dtype, np.floating):
            data = (data * 32767).astype(np.int16)
        else:
            data = data.astype(np.int16)
    
    if len(data) > MAX_SAMPLES:
        print(f"Warning: Truncating from {len(data)} to {MAX_SAMPLES} samples")
        data = data[:MAX_SAMPLES]
    
    return data


def save_wav_file(filename, data):
    """Save samples as a WAV file."""
    if not HAS_SCIPY:
        print("Error: scipy required for WAV file support")
        return False
    
    try:
        wavfile.write(filename, SAMPLE_RATE, data.astype(np.int16))
        print(f"Saved: {filename}")
        return True
    except Exception as e:
        print(f"Error saving WAV file: {e}")
        return False


def send_audio_for_processing(ser, samples):
    """
    Send audio samples to nRF54L15 for processing.
    
    Args:
        ser: Serial port object
        samples: numpy array of int16 samples
    
    Returns:
        numpy array of processed int16 samples, or None on error
    """
    if len(samples) > MAX_SAMPLES:
        print(f"Warning: Truncating to {MAX_SAMPLES} samples")
        samples = samples[:MAX_SAMPLES]
    
    num_bytes = len(samples) * 2
    
    print(f"Sending {len(samples)} samples ({num_bytes} bytes)...")
    
    ser.reset_input_buffer()
    
    ser.write(b'P')
    ser.write(struct.pack('<H', num_bytes))
    
    sample_bytes = samples.astype('<i2').tobytes()
    ser.write(sample_bytes)
    
    print("Data sent. Waiting for processed response...")
    
    start_time = time.time()
    timeout = 10.0
    
    while time.time() - start_time < timeout:
        if ser.in_waiting > 0:
            header = ser.read(1)
            if header == b'R':
                break
        time.sleep(0.01)
    else:
        print("Error: Timeout waiting for response")
        return None
    
    len_bytes = ser.read(2)
    if len(len_bytes) < 2:
        print("Error: Failed to read response length")
        return None
    
    response_bytes = struct.unpack('<H', len_bytes)[0]
    response_samples = response_bytes // 2
    
    print(f"Receiving {response_samples} processed samples...")
    
    data = b''
    while len(data) < response_bytes:
        remaining = response_bytes - len(data)
        chunk = ser.read(min(remaining, 1024))
        if not chunk:
            if time.time() - start_time > timeout:
                print("Error: Timeout receiving data")
                return None
            time.sleep(0.01)
            continue
        data += chunk
    
    processed = np.frombuffer(data, dtype='<i2')
    print(f"Received {len(processed)} samples")
    
    return processed


def send_command(ser, cmd):
    """Send a single-character command."""
    ser.write(cmd.encode())
    time.sleep(0.1)
    response = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
    return response


def interactive_mode(ser):
    """Interactive terminal mode."""
    print("\n=== Interactive Mode ===")
    print("Commands: P=Process, T=Test, S=Status, C=Compression, H=Help, Q=Quit")
    print()
    
    while True:
        try:
            cmd = input("> ").strip().upper()
            
            if not cmd:
                continue
            
            if cmd == 'Q':
                break
            
            if cmd == 'T':
                print("\nGenerating test signal...")
                
                ser.write(b'T')
                
                time.sleep(3)
                
                while ser.in_waiting > 0:
                    print(ser.read(ser.in_waiting).decode('utf-8', errors='ignore'), end='')
                
                print("\nWaiting for processed data...")
                time.sleep(2)
                
                if ser.in_waiting > 0:
                    header = ser.read(1)
                    if header == b'R':
                        len_bytes = ser.read(2)
                        if len(len_bytes) == 2:
                            response_bytes = struct.unpack('<H', len_bytes)[0]
                            data = ser.read(response_bytes)
                            processed = np.frombuffer(data, dtype='<i2')
                            print(f"Received {len(processed)} processed samples")
                            
                            save = input("Save to WAV? (y/n): ").strip().lower()
                            if save == 'y':
                                save_wav_file("test_processed.wav", processed)
            else:
                response = send_command(ser, cmd)
                print(response)
                
        except KeyboardInterrupt:
            print("\nExiting...")
            break


def calculate_snr(original, processed):
    """Calculate Signal-to-Noise Ratio improvement estimate."""
    min_len = min(len(original), len(processed))
    original = original[:min_len].astype(float)
    processed = processed[:min_len].astype(float)
    
    orig_power = np.mean(original ** 2)
    proc_power = np.mean(processed ** 2)
    
    diff_power = np.mean((original - processed) ** 2)
    
    if diff_power > 0:
        snr_improvement = 10 * np.log10(proc_power / diff_power)
    else:
        snr_improvement = float('inf')
    
    return snr_improvement


def main():
    parser = argparse.ArgumentParser(
        description='Hearing Aid DSP Serial Interface for nRF54L15',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  List ports:    python hearing_aid_serial.py --list
  Process file:  python hearing_aid_serial.py -p /dev/ttyACM0 -i noisy.wav -o clean.wav
  Test mode:     python hearing_aid_serial.py -p /dev/ttyACM0 --test
  Interactive:   python hearing_aid_serial.py -p /dev/ttyACM0 --interactive
        """
    )
    
    parser.add_argument('-p', '--port', type=str, help='Serial port (e.g., /dev/ttyACM0, COM3)')
    parser.add_argument('-b', '--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('-i', '--input', type=str, help='Input WAV file')
    parser.add_argument('-o', '--output', type=str, help='Output WAV file')
    parser.add_argument('--test', action='store_true', help='Generate and process test signal')
    parser.add_argument('--noise-level', type=float, default=0.3, help='Noise level for test (0.0-1.0)')
    parser.add_argument('--interactive', action='store_true', help='Interactive terminal mode')
    parser.add_argument('--list', action='store_true', help='List available serial ports')
    parser.add_argument('--save-input', type=str, help='Save generated input to WAV')
    
    args = parser.parse_args()
    
    if args.list:
        list_serial_ports()
        return
    
    if not args.port:
        print("Error: Serial port required. Use --list to see available ports.")
        parser.print_help()
        return
    
    print(f"Opening serial port {args.port} at {args.baud} baud...")
    
    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
        time.sleep(2)
        ser.reset_input_buffer()
        print("Connected!")
    except Exception as e:
        print(f"Error opening serial port: {e}")
        return
    
    try:
        if args.interactive:
            interactive_mode(ser)
            return
        
        if args.test:
            print("\n=== Test Mode ===")
            print(f"Generating noisy test signal (noise level: {args.noise_level})...")
            
            input_samples = generate_noisy_speech_signal(
                duration_sec=0.5, 
                noise_level=args.noise_level
            )
            
            if args.save_input:
                save_wav_file(args.save_input, input_samples)
            
            processed = send_audio_for_processing(ser, input_samples)
            
            if processed is not None:
                output_file = args.output or "test_processed.wav"
                save_wav_file(output_file, processed)
                
                input_file = args.save_input or "test_input.wav"
                if not args.save_input:
                    save_wav_file(input_file, input_samples)
                
                print(f"\nResults:")
                print(f"  Input samples:  {len(input_samples)}")
                print(f"  Output samples: {len(processed)}")
                print(f"  Input RMS:  {np.sqrt(np.mean(input_samples.astype(float)**2)):.1f}")
                print(f"  Output RMS: {np.sqrt(np.mean(processed.astype(float)**2)):.1f}")
                
            return
        
        if args.input:
            print(f"\n=== Processing {args.input} ===")
            
            input_samples = load_wav_file(args.input)
            if input_samples is None:
                return
            
            print(f"Loaded {len(input_samples)} samples")
            
            processed = send_audio_for_processing(ser, input_samples)
            
            if processed is not None:
                output_file = args.output or args.input.replace('.wav', '_processed.wav')
                save_wav_file(output_file, processed)
                
                print(f"\nProcessing complete!")
                print(f"  Input:  {args.input}")
                print(f"  Output: {output_file}")
            
            return
        
        print("\nNo action specified. Use --test, --input, or --interactive")
        parser.print_help()
        
    finally:
        ser.close()
        print("\nSerial port closed.")


if __name__ == '__main__':
    main()
