# 1. Use an official Python runtime as a parent image
FROM python:3.10-slim

# 2. Set the working directory inside the container
WORKDIR /app

# 3. Install system dependencies required by librosa
# ffmpeg is for handling various audio formats, libsndfile1 for WAV/FLAC
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# 4. Copy the requirements file and install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 5. Copy the rest of the application code into the container
COPY . .

# 6. Define the command to run the application
CMD ["python", "SoundViewerAndManipulator.py"]