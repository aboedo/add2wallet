#!/bin/bash
set -e

echo "🚀 Starting Add2Wallet backend on Railway..."

# Create uploads directory if it doesn't exist
mkdir -p uploads
chmod 755 uploads

# Set default port if not provided
export PORT=${PORT:-8000}

echo "📡 Starting server on port $PORT"

# Test critical imports before starting
echo "🔍 Testing critical imports..."
python3 -c "import cv2; print('✅ OpenCV imported successfully')" || exit 1
python3 -c "import pyzbar.pyzbar; print('✅ pyzbar imported successfully')" || exit 1
python3 -c "import fitz; print('✅ PyMuPDF imported successfully')" || exit 1
python3 -c "import numpy; print('✅ numpy imported successfully')" || exit 1

echo "✅ All critical imports successful"

# Start the FastAPI server with uvicorn
exec uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 1