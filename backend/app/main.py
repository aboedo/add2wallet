from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Header
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import uuid
import os
import shutil
import asyncio
from pathlib import Path
from dotenv import load_dotenv

from app.models.responses import UploadResponse, ErrorResponse, StatusResponse
from app.services.pdf_validator import PDFValidator
from app.services.pass_generator import pass_generator
from app.services.ai_service import ai_service

# Load environment variables
load_dotenv()

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
    
    # Initialize job in processing state
    jobs[job_id] = {
        "user_id": user_id,
        "status": "processing",
        "progress": 10,
        "file_path": str(file_path),
        "filename": file.filename
    }
    
    # Process PDF with AI and generate Apple Wallet pass
    try:
        # Step 1: Extract text from PDF for AI analysis
        from app.services.pass_generator import PassGenerator
        temp_generator = PassGenerator()
        pdf_text = temp_generator._extract_pdf_text(contents)
        
        # Update progress
        jobs[job_id]["progress"] = 30
        
        # Step 2: AI analysis of PDF content
        ai_metadata = None
        try:
            ai_metadata = await ai_service.analyze_pdf_content(pdf_text, file.filename)
            jobs[job_id]["progress"] = 70
            jobs[job_id]["ai_metadata"] = ai_metadata
            print(f"✅ AI analysis completed for {file.filename}")
        except Exception as ai_error:
            print(f"⚠️ AI analysis failed, using fallback: {ai_error}")
            # Continue with basic extraction
            jobs[job_id]["progress"] = 50
        
        # Step 3: Generate enhanced pass(es) with AI metadata and barcode extraction
        pkpass_files, detected_barcodes, ticket_info = pass_generator.create_pass_from_pdf_data(
            contents, 
            file.filename,
            ai_metadata
        )
        
        # Save pass files
        pass_paths = []
        for i, pkpass_data in enumerate(pkpass_files):
            if len(pkpass_files) > 1:
                pass_path = UPLOAD_DIR / f"{job_id}_ticket_{i+1}.pkpass"
            else:
                pass_path = UPLOAD_DIR / f"{job_id}.pkpass"
            
            with open(pass_path, "wb") as f:
                f.write(pkpass_data)
            pass_paths.append(str(pass_path))
        
        # Update job information with completion
        jobs[job_id].update({
            "status": "completed",
            "progress": 100,
            "pass_paths": pass_paths,
            "detected_barcodes": detected_barcodes,
            "barcode_count": len(detected_barcodes),
            "ticket_count": len(pkpass_files),
            "ticket_info": ticket_info,
            # Keep backwards compatibility
            "pass_path": pass_paths[0] if pass_paths else None
        })
        
        return UploadResponse(
            job_id=job_id, 
            status="completed", 
            pass_url=f"/pass/{job_id}",
            ai_metadata=ai_metadata
        )
        
    except Exception as e:
        # If pass generation fails, mark job as failed
        jobs[job_id].update({
            "status": "failed",
            "progress": 0,
            "error": str(e)
        })
        print(f"❌ Pass generation failed: {e}")
        
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
        result_url=f"/pass/{job_id}" if job["status"] == "completed" else None,
        ai_metadata=job.get("ai_metadata")
    )

@app.get("/pass/{job_id}")
async def download_pass(
    job_id: str,
    ticket_number: Optional[int] = None,
    authorization: Optional[str] = Header(None)
):
    """Download the generated Apple Wallet pass(es)."""
    
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    if job["status"] != "completed":
        raise HTTPException(status_code=400, detail="Pass is not ready yet")
    
    # Handle multiple passes
    pass_paths = job.get("pass_paths", [job.get("pass_path")]) if job.get("pass_path") else []
    ticket_count = job.get("ticket_count", 1)
    
    if not pass_paths:
        raise HTTPException(status_code=404, detail="No pass files found")
    
    # If specific ticket requested
    if ticket_number is not None:
        if ticket_number < 1 or ticket_number > len(pass_paths):
            raise HTTPException(status_code=400, detail=f"Invalid ticket number. Available: 1-{len(pass_paths)}")
        
        pass_path = Path(pass_paths[ticket_number - 1])
        filename_suffix = f"_ticket_{ticket_number}" if ticket_count > 1 else ""
    else:
        # Return first pass (backwards compatibility)
        pass_path = Path(pass_paths[0])
        filename_suffix = "_ticket_1" if ticket_count > 1 else ""
    
    if not pass_path.exists():
        raise HTTPException(status_code=404, detail="Pass file not found")
    
    with open(pass_path, "rb") as f:
        pass_data = f.read()
    
    base_filename = job['filename'].replace('.pdf', '')
    return Response(
        content=pass_data,
        media_type="application/vnd.apple.pkpass",
        headers={
            "Content-Disposition": f"attachment; filename=\"{base_filename}{filename_suffix}.pkpass\""
        }
    )

@app.get("/tickets/{job_id}")
async def list_tickets(
    job_id: str,
    authorization: Optional[str] = Header(None)
):
    """List all tickets for a specific job."""
    
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    ticket_info = job.get("ticket_info", [])
    ticket_count = job.get("ticket_count", 1)
    
    return {
        "job_id": job_id,
        "ticket_count": ticket_count,
        "barcode_count": job.get("barcode_count", 0),
        "tickets": [
            {
                "ticket_number": ticket["ticket_number"],
                "title": ticket["title"],
                "description": ticket["description"],
                "download_url": f"/pass/{job_id}?ticket_number={ticket['ticket_number']}",
                "has_barcode": ticket["barcode"] is not None,
                "barcode_type": ticket["barcode"]["type"] if ticket["barcode"] else None
            }
            for ticket in ticket_info
        ]
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
                "status": job["status"],
                "ticket_count": job.get("ticket_count", 1),
                "barcode_count": job.get("barcode_count", 0)
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