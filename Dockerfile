FROM python:3.11-slim

# Install system dependencies required for OpenCV, pyzbar, pdf2image
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libgomp1 \
    libzbar0 \
    libzbar-dev \
    poppler-utils \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgtk-3-0 \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Set OpenCV to headless mode to avoid GUI dependencies
ENV OPENCV_HEADLESS=1

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create uploads directory with proper permissions
RUN mkdir -p uploads && chmod 755 uploads

# Default port for Railway (will be overridden by PORT env var)
EXPOSE 8000

# Copy and make start script executable
COPY start.sh .
RUN chmod +x start.sh

# Use startup script
CMD ["./start.sh"]