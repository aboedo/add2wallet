from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Header
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import uuid
import os
import shutil
from pathlib import Path

from app.models.responses import UploadResponse, ErrorResponse, StatusResponse
from app.services.pdf_validator import PDFValidator
from app.services.pass_generator import pass_generator

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
    
    # Generate Apple Wallet pass immediately
    try:
        pkpass_data = pass_generator.create_pass_from_pdf_data(contents, file.filename)
        
        # Save the pass file
        pass_path = UPLOAD_DIR / f"{job_id}.pkpass"
        with open(pass_path, "wb") as f:
            f.write(pkpass_data)
        
        # Store job information
        jobs[job_id] = {
            "user_id": user_id,
            "status": "completed",
            "progress": 100,
            "file_path": str(file_path),
            "pass_path": str(pass_path),
            "filename": file.filename
        }
        
        return UploadResponse(job_id=job_id, status="completed")
        
    except Exception as e:
        # If pass generation fails, mark job as failed
        jobs[job_id] = {
            "user_id": user_id,
            "status": "failed",
            "progress": 0,
            "file_path": str(file_path),
            "filename": file.filename,
            "error": str(e)
        }
        
        return UploadResponse(job_id=job_id, status="failed")

@app.get("/status/{job_id}", response_model=StatusResponse)
async def get_status(
    job_id: str,
    authorization: Optional[str] = Header(None)
):
    """Check the processing status of a PDF conversion job."""
    
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    
    # Job status is already set during upload
    
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
    
    # Return the actual .pkpass file
    pass_path = Path(job["pass_path"])
    if not pass_path.exists():
        raise HTTPException(status_code=404, detail="Pass file not found")
    
    with open(pass_path, "rb") as f:
        pass_data = f.read()
    
    return Response(
        content=pass_data,
        media_type="application/vnd.apple.pkpass",
        headers={
            "Content-Disposition": f"attachment; filename=\"{job['filename'].replace('.pdf', '.pkpass')}\""
        }
    )

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
        # Clean up PDF file
        file_path = Path(job["file_path"])
        if file_path.exists():
            file_path.unlink()
        
        # Clean up pass file
        if "pass_path" in job:
            pass_path = Path(job["pass_path"])
            if pass_path.exists():
                pass_path.unlink()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)