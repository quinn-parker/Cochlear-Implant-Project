# testbench.py
import serial
import time
import numpy as np
import matplotlib.pyplot as plt
import soundfile as sf
import struct
import sys

# --- Configuration ---
SERIAL_PORT = 'COM3'  # Change this to your Teensy's serial port (e.g., '/dev/ttyACM0' on Linux)
BAUD_RATE = 115200
CHUNK_SIZE = 256  # How many samples to send at a time

def run_test(ser, audio_data, algorithm_command):
    """Sends audio data to the Teensy and retrieves the processed result."""
    print(f"--- Running Test for: {algorithm_command} ---")
    
    # 1. Send the command to select the algorithm
    print(f"Sending command: {algorithm_command}")
    ser.write(f"{algorithm_command}\n".encode())
    time.sleep(0.1) # Give Teensy time to process command

    # 2. Stream audio data to Teensy and get results
    num_samples = len(audio_data)
    processed_data = np.zeros_like(audio_data)
    
    print(f"Streaming {num_samples} samples in chunks of {CHUNK_SIZE}...")
    for i in range(0, num_samples, CHUNK_SIZE):
        chunk = audio_data[i:i+CHUNK_SIZE]
        
        # Pack the 16-bit integer samples into bytes (little-endian)
        byte_chunk = struct.pack(f'<{len(chunk)}h', *chunk)
        ser.write(byte_chunk)
        
        # Wait for and read the processed data back
        bytes_to_read = len(chunk) * 2 # 2 bytes per sample
        response_bytes = ser.read(bytes_to_read)
        
        if len(response_bytes) == bytes_to_read:
            processed_chunk = struct.unpack(f'<{len(chunk)}h', response_bytes)
            processed_data[i:i+CHUNK_SIZE] = processed_chunk
        else:
            print(f"Warning: Expected {bytes_to_read} bytes, got {len(response_bytes)}")

    print("--- Test Complete ---")
    return processed_data

def plot_results(original, processed, samplerate):
    """Plots the waveform and frequency spectrum of original vs. processed audio."""
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))
    
    # Plot Waveform
    time_axis = np.arange(len(original)) / samplerate
    ax1.plot(time_axis, original, label='Original', alpha=0.7)
    ax1.plot(time_axis, processed, label='Processed', alpha=0.7)
    ax1.set_title('Waveform Comparison')
    ax1.set_xlabel('Time (s)')
    ax1.set_ylabel('Amplitude')
    ax1.legend()
    ax1.grid(True)
    
    # Plot Frequency Spectrum (FFT)
    n = len(original)
    original_fft = np.fft.fft(original)
    processed_fft = np.fft.fft(processed)
    freq_axis = np.fft.fftfreq(n, d=1/samplerate)
    
    ax2.plot(freq_axis[:n//2], np.abs(original_fft)[:n//2], label='Original', alpha=0.7)
    ax2.plot(freq_axis[:n//2], np.abs(processed_fft)[:n//2], label='Processed', alpha=0.7)
    ax2.set_title('Frequency Spectrum Comparison')
    ax2.set_xlabel('Frequency (Hz)')
    ax2.set_ylabel('Magnitude')
    ax2.legend()
    ax2.grid(True)
    
    plt.tight_layout()
    plt.show()

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python testbench.py <path_to_wav_file> <algorithm>")
        print("Available algorithms: PASSTHROUGH, WDRC, NOISE_REDUCTION, FREQ_SHAPING")
        sys.exit(1)

    wav_file_path = sys.argv[1]
    algorithm = sys.argv[2].upper()

    # Load audio file (ensure it's mono 16-bit)
    audio, sr = sf.read(wav_file_path, dtype='int16')
    print(f"Loaded '{wav_file_path}' - Samplerate: {sr}, Samples: {len(audio)}")
    if audio.ndim > 1:
        print("Audio is not mono. Converting to mono.")
        audio = audio.mean(axis=1).astype(np.int16)

    # Establish Serial Connection
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2)
        time.sleep(2) # Wait for serial connection to establish
        print(f"Connected to Teensy on {SERIAL_PORT}")
    except serial.SerialException as e:
        print(f"Error: Could not open serial port {SERIAL_PORT}. {e}")
        sys.exit(1)
        
    # Run the test and get processed audio
    processed_audio = run_test(ser, audio, algorithm)
    
    # Clean up
    ser.close()
    
    # Visualize the results
    plot_results(audio, processed_audio, sr)