#!/bin/bash
set -e

echo "🚀 Starting Add2Wallet backend on Railway..."

# Create uploads directory if it doesn't exist
mkdir -p uploads
chmod 755 uploads

# Set default port if not provided
export PORT=${PORT:-8000}

echo "📡 Starting server on port $PORT"

# Start the FastAPI server with uvicorn
exec uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 1