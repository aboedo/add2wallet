#!/usr/bin/env python3
"""Development server runner for Add2Wallet backend."""

import uvicorn
from app.main import app

if __name__ == "__main__":
    print("Starting Add2Wallet backend server...")
    print("API will be available at:")
    print("  - Local: http://localhost:8000")
    print("  - Network: http://192.168.68.66:8000")
    print("  - Documentation: http://192.168.68.66:8000/docs")
    print("Press CTRL+C to stop the server")
    print("-" * 50)
    
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info",
        access_log=True
    )