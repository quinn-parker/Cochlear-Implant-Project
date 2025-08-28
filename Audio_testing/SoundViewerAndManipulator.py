import librosa
import librosa.display
import matplotlib.pyplot as plt
import numpy as np
import soundfile as sf
import os

# Create an output directory if it doesn't exist
output_dir = '/output'
if not os.path.exists(output_dir):
    # In a container, this directory will be a mounted volume
    # For local testing, it will be created in your project root
    os.makedirs(output_dir)

def plot_waveform(y, sr, title="Waveform", output_filename="waveform.png"):
    """Plots the waveform and saves it to the output directory."""
    plt.figure(figsize=(12, 4))
    librosa.display.waveshow(y, sr=sr)
    plt.title(title)
    plt.xlabel("Time (s)")
    plt.ylabel("Amplitude")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, output_filename))
    plt.close() # Close plot to free memory

def plot_spectrogram(y, sr, title="Spectrogram", output_filename="spectrogram.png"):
    """Plots the spectrogram and saves it to the output directory."""
    D = librosa.stft(y)
    S_db = librosa.amplitude_to_db(np.abs(D), ref=np.max)
    plt.figure(figsize=(12, 4))
    librosa.display.specshow(S_db, sr=sr, x_axis='time', y_axis='log')
    plt.colorbar(format='%+2.0f dB')
    plt.title(title)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, output_filename))
    plt.close()

# --- 1. Load the Audio File ---
# This file must be in the same directory as the script.
file_path = 'your_audio_file.wav'

try:
    y, sr = librosa.load(file_path, sr=None) # Load with original sampling rate
    print(f"Audio loaded successfully from: {file_path}")
except Exception as e:
    print(f"Error loading file: {e}")
    exit()

# --- 2. View the Original Signal ---
print("Generating plots for original signal...")
plot_waveform(y, sr, "Original Waveform", "original_waveform.png")
plot_spectrogram(y, sr, "Original Spectrogram", "original_spectrogram.png")

# --- 3. Manipulate the Audio Signal (Add Echo) ---
print("Applying echo effect...")
delay_seconds = 0.25
delay_samples = int(delay_seconds * sr)
y_echo = np.copy(y)
y_delayed = np.zeros_like(y)
y_delayed[delay_samples:] = y[:-delay_samples] * 0.5 # Echo is at 50% volume
y_echo += y_delayed
y_echo = y_echo / np.max(np.abs(y_echo)) # Normalize to prevent clipping

# --- 4. View the Manipulated Signal ---
print("Generating plot for manipulated signal...")
plot_waveform(y_echo, sr, "Waveform with Echo", "echo_waveform.png")

# --- 5. Save the Manipulated Audio ---
output_filename = os.path.join(output_dir, 'audio_with_echo.wav')
try:
    sf.write(output_filename, y_echo, sr)
    print(f"\n✅ Successfully saved manipulated audio and plots to the 'output' directory!")
except Exception as e:
    print(f"\nError saving file: {e}")