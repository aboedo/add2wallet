#!/usr/bin/env python3
"""
Dependency checker for Railway deployment
"""

def check_dependencies():
    print("🔍 Checking dependencies...")
    
    # Basic imports
    try:
        import fastapi
        print("✅ FastAPI:", fastapi.__version__)
    except ImportError as e:
        print("❌ FastAPI:", e)
    
    try:
        import uvicorn
        print("✅ Uvicorn available")
    except ImportError as e:
        print("❌ Uvicorn:", e)
    
    # OpenAI
    try:
        import openai
        print("✅ OpenAI:", openai.__version__)
    except ImportError as e:
        print("❌ OpenAI:", e)
    
    # PDF processing
    try:
        import PyPDF2
        print("✅ PyPDF2 available")
    except ImportError as e:
        print("❌ PyPDF2:", e)
    
    try:
        import fitz
        print("✅ PyMuPDF available")
    except ImportError as e:
        print("❌ PyMuPDF:", e)
    
    # Image processing
    try:
        from PIL import Image
        print("✅ Pillow available")
    except ImportError as e:
        print("❌ Pillow:", e)
    
    # Binary dependencies (the problematic ones)
    try:
        import cv2
        print("✅ OpenCV:", cv2.__version__)
    except ImportError as e:
        print("❌ OpenCV:", e)
    
    try:
        import numpy as np
        print("✅ NumPy:", np.__version__)
    except ImportError as e:
        print("❌ NumPy:", e)
    
    try:
        from pyzbar import pyzbar
        print("✅ pyzbar available")
    except ImportError as e:
        print("❌ pyzbar:", e)
    
    try:
        from pdf2image import convert_from_bytes
        print("✅ pdf2image available")
    except ImportError as e:
        print("❌ pdf2image:", e)
    
    # Cryptography
    try:
        import cryptography
        print("✅ Cryptography:", cryptography.__version__)
    except ImportError as e:
        print("❌ Cryptography:", e)

if __name__ == "__main__":
    check_dependencies()