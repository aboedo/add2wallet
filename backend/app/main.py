from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import uuid
import os
import shutil
from pathlib import Path

from app.models.responses import UploadResponse, ErrorResponse, StatusResponse
from app.services.pdf_validator import PDFValidator

app = FastAPI(title="Add2Wallet API", version="1.0.0")

# Configure CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create upload directory
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

# In-memory job storage (will be replaced with database in production)
jobs = {}

@app.get("/")
async def root():
    return {"message": "Add2Wallet API is running", "version": "1.0.0"}

@app.post("/upload", response_model=UploadResponse)
async def upload_pdf(
    file: UploadFile = File(...),
    user_id: str = Form(...),
    session_token: str = Form(...),
    x_api_key: Optional[str] = Header(None)
):
    """Upload a PDF file for processing into an Apple Wallet pass."""
    
    # Basic authentication check for development
    if x_api_key != "development-api-key":
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    # Validate file type
    if not file.filename.endswith('.pdf'):
        raise HTTPException(status_code=400, detail="Only PDF files are allowed")
    
    # Validate file size (10MB limit)
    contents = await file.read()
    if len(contents) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File size exceeds 10MB limit")
    
    # Validate PDF structure
    validator = PDFValidator()
    is_valid, error_message = validator.validate(contents)
    if not is_valid:
        raise HTTPException(status_code=400, detail=f"Invalid PDF: {error_message}")
    
    # Generate job ID
    job_id = str(uuid.uuid4())
    
    # Save file temporarily
    file_path = UPLOAD_DIR / f"{job_id}.pdf"
    with open(file_path, "wb") as f:
        f.write(contents)
    
    # Store job information
    jobs[job_id] = {
        "user_id": user_id,
        "status": "processing",
        "progress": 0,
        "file_path": str(file_path),
        "filename": file.filename
    }
    
    return UploadResponse(job_id=job_id, status="processing")

@app.get("/status/{job_id}", response_model=StatusResponse)
async def get_status(
    job_id: str,
    authorization: Optional[str] = Header(None)
):
    """Check the processing status of a PDF conversion job."""
    
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    
    # Simulate processing completion for now
    if job["progress"] == 0:
        job["progress"] = 100
        job["status"] = "completed"
    
    return StatusResponse(
        job_id=job_id,
        status=job["status"],
        progress=job["progress"],
        result_url=f"/pass/{job_id}" if job["status"] == "completed" else None
    )

@app.get("/pass/{job_id}")
async def download_pass(
    job_id: str,
    authorization: Optional[str] = Header(None)
):
    """Download the generated Apple Wallet pass."""
    
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    if job["status"] != "completed":
        raise HTTPException(status_code=400, detail="Pass is not ready yet")
    
    # For now, return a placeholder response
    return {
        "message": "Pass generation will be implemented in Phase 4",
        "job_id": job_id,
        "filename": job["filename"]
    }

@app.get("/passes")
async def list_passes(
    authorization: Optional[str] = Header(None)
):
    """List all passes for the authenticated user."""
    
    # For now, return all jobs (in production, filter by user)
    return {
        "passes": [
            {
                "job_id": job_id,
                "filename": job["filename"],
                "status": job["status"]
            }
            for job_id, job in jobs.items()
        ]
    }

@app.on_event("shutdown")
async def shutdown_event():
    """Clean up temporary files on shutdown."""
    for job in jobs.values():
        file_path = Path(job["file_path"])
        if file_path.exists():
            file_path.unlink()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)