#!/usr/bin/env python3
"""Development server runner for Add2Wallet backend."""

import uvicorn
from app.main import app

if __name__ == "__main__":
    print("Starting Add2Wallet backend server...")
    print("API will be available at: http://localhost:8000")
    print("Documentation at: http://localhost:8000/docs")
    print("Press CTRL+C to stop the server")
    
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )