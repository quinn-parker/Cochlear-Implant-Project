# Audio Processor - Sound Viewer and Manipulator

A Python application that loads audio files, visualizes waveforms and spectrograms, applies echo effects, and saves the results. This tool is containerized with Docker for easy deployment and consistent execution across different environments.

## 🚀 Features

- **Audio Loading**: Load various audio formats (WAV, MP3, FLAC, etc.) using librosa
- **Visualization**: Generate waveform and spectrogram plots
- **Audio Effects**: Apply echo effect with configurable delay and volume
- **Output Management**: Save processed audio files and visualizations to organized output directory
- **Containerized**: Fully dockerized for consistent execution

## 📋 Prerequisites

### For Docker Usage (Recommended)
- Docker installed on your system

### For Local Development
- Python 3.10+
- System dependencies: `ffmpeg`, `libsndfile1`

## 📁 Project Structure

```
.
├── Dockerfile
├── requirements.txt
├── SoundViewerAndManipulator.py
├── your_audio_file.wav          # Your input audio file
└── output/                      # Generated output directory
    ├── original_waveform.png
    ├── original_spectrogram.png
    ├── echo_waveform.png
    └── audio_with_echo.wav
```

## 🐳 Quick Start with Docker

### 1. Prepare Your Audio File
Place your audio file in the project directory and rename it to `your_audio_file.wav`, or modify the `file_path` variable in the Python script to match your filename.

### 2. Build the Docker Image
```bash
docker build -t audio-processor .
```

### 3. Run the Container
```bash
# Create output directory on host
mkdir -p ./output

# Run container with volume mounting
docker run -v "$(pwd)/output:/output" -v "$(pwd)/your_audio_file.wav:/app/your_audio_file.wav" audio-processor
```

### 4. View Results
Check the `./output` directory for:
- `original_waveform.png` - Visualization of the original audio waveform
- `original_spectrogram.png` - Frequency domain analysis of original audio
- `echo_waveform.png` - Visualization of the processed audio with echo
- `audio_with_echo.wav` - The processed audio file with echo effect

## 📦 Requirements

Create a `requirements.txt` file with:
```txt
librosa>=0.10.0
matplotlib>=3.5.0
numpy>=1.21.0
soundfile>=0.12.0
```

## ⚙️ Configuration Options

### Echo Effect Parameters
You can modify these variables in the Python script:

```python
delay_seconds = 0.25    # Echo delay in seconds
delay_samples = int(delay_seconds * sr)
echo_volume = 0.5       # Echo volume (50% of original)
```

### Input File Path
Change the input file by modifying:
```python
file_path = 'your_audio_file.wav'
```

## 💻 Local Development Setup

### 1. Install System Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install ffmpeg libsndfile1
```

**macOS:**
```bash
brew install ffmpeg libsndfile
```

### 2. Install Python Dependencies
```bash
pip install -r requirements.txt
```

### 3. Run the Application
```bash
python SoundViewerAndManipulator.py
```

## 🐳 Docker Commands Reference

### Build Image
```bash
docker build -t audio-processor .
```

### Run with Volume Mounting
```bash
# Mount both input file and output directory
docker run \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/your_audio_file.wav:/app/your_audio_file.wav" \
  audio-processor
```

### Run Interactive Container (for debugging)
```bash
docker run -it \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/your_audio_file.wav:/app/your_audio_file.wav" \
  audio-processor bash
```

## 🎵 Supported Audio Formats

Thanks to librosa and ffmpeg, this application supports:
- WAV
- MP3
- FLAC
- M4A
- OGG
- And many other formats supported by ffmpeg

## 🔧 Troubleshooting

### Common Issues

**File Not Found Error:**
- Ensure your audio file is in the correct location
- Check that the filename in the script matches your actual file
- Verify volume mounting paths in Docker

**Permission Issues with Output Directory:**
```bash
# Fix permissions for output directory
chmod 755 ./output
```

**Container Build Failures:**
- Ensure Docker has sufficient disk space
- Try rebuilding without cache: `docker build --no-cache -t audio-processor .`

### Viewing Logs
```bash
# View container logs
docker logs <container_id>

# Run with verbose output
docker run -v "$(pwd)/output:/output" -v "$(pwd)/your_audio_file.wav:/app/your_audio_file.wav" audio-processor python -u SoundViewerAndManipulator.py
```

## 📄 Credits

-README.md was written by Quinn and Claude.ai
-Dockerfile was written by Quinn
-Python program was written by Quinn
-requirements.txt was written by Quinn
