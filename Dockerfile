# NOTE: Railway deploys this service with its root directory set to `backend/`,
# so it builds backend/Dockerfile — not this file. This root Dockerfile is kept
# only as a working fallback for a root-context build, and it must stay in sync
# with backend/Dockerfile (system deps) and backend/requirements.txt (Python
# deps). It builds the backend from the backend/ subdirectory.
FROM python:3.11-slim

# System dependencies for OpenCV (headless), pyzbar, zxing-cpp, pdf2image
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libglib2.0-dev \
    libgomp1 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libzbar0 \
    libzbar-dev \
    poppler-utils \
    g++ \
    cmake \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV OPENCV_HEADLESS=1

# Install Python deps first for better layer caching
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the backend application code (app/, start.sh, certificates/, …)
COPY backend/ .

# Create uploads directory with proper permissions
RUN mkdir -p uploads && chmod 755 uploads

# Default port for Railway (overridden by PORT env var)
EXPOSE 8000

RUN chmod +x start.sh

CMD ["./start.sh"]
