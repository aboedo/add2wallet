from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Header
from fastapi.responses import Response, RedirectResponse, JSONResponse
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
from app.services.revenuecat_service import revenuecat_service
from app.services.v2.orchestrator import create_passes_v2

# Load environment variables
load_dotenv()

app = FastAPI(title="Add2Wallet API", version="1.0.0")


def sanitize_metadata(raw: dict | None) -> dict | None:
    """Strip fields that don't match the iOS EnhancedPassMetadata Codable model.

    The AI enrichment pipeline adds arbitrary keys with unpredictable types
    (e.g. ``upcoming_events`` as a string instead of an array).  This causes
    ``JSONDecoder`` in the iOS app to fail with "data couldn't be read".

    We whitelist only the fields the Swift model declares and coerce known
    list-typed fields so a stray string doesn't blow up decoding.
    """
    if raw is None:
        return None

    ALLOWED = {
        "event_type", "event_name", "title", "description",
        "date", "time", "duration",
        "venue_name", "venue_address", "city", "state_country",
        "latitude", "longitude",
        "organizer", "performer_artist", "seat_info", "barcode_data",
        "price", "confirmation_number", "gate_info",
        "event_description", "venue_type", "capacity", "website", "phone",
        "nearby_landmarks", "public_transport", "parking_info",
        "age_restriction", "dress_code", "weather_considerations",
        "amenities", "accessibility",
        "ai_processed", "confidence_score", "processing_timestamp",
        "model_used", "enrichment_completed",
        "background_color", "foreground_color", "label_color",
        "multiple_events", "upcoming_events", "venue_place_id",
        "performer_names", "exhibit_name", "has_assigned_seating",
        "event_urls",
    }

    LIST_FIELDS = {"nearby_landmarks", "amenities", "upcoming_events", "performer_names"}

    clean: dict = {}
    for key, value in raw.items():
        if key not in ALLOWED:
            continue
        # Coerce list-typed fields: if it's not a list, drop it
        if key in LIST_FIELDS and not isinstance(value, list):
            clean[key] = None
            continue
        clean[key] = value
    return clean

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

@app.get("/share/{token}")
async def handle_universal_link_sharing(token: str):
    """Handle Universal Link sharing from iOS Share Extension"""
    
    # Validate token format (UUID)
    try:
        uuid.UUID(token)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid sharing token")
    
    # This endpoint is designed to work with Universal Links
    # When accessed via browser, it should redirect to the iOS app with the token
    # When accessed by the iOS app directly, it can return metadata
    
    # Check if this is coming from an iOS device
    user_agent = "unknown"
    
    # For iOS devices, redirect to the custom URL scheme as a fallback
    # This creates a seamless flow: Universal Link -> App opens -> App handles token
    ios_app_url = f"add2wallet://share/{token}"
    
    # For web browsers, return a simple page with app store link and instructions
    return RedirectResponse(
        url=ios_app_url,
        status_code=302
    )

@app.get("/share/{token}/metadata")
async def get_sharing_metadata(token: str):
    """Get metadata for a shared PDF token"""
    
    # Validate token format (UUID)
    try:
        uuid.UUID(token)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid sharing token")
    
    # This endpoint could be used by the iOS app to get metadata about
    # the shared PDF before processing, but for now we'll keep the
    # file-based approach that's already implemented
    
    return JSONResponse({
        "token": token,
        "status": "valid",
        "message": "Open the Add2Wallet app to process this PDF"
    })

@app.get("/.well-known/apple-app-site-association")
async def apple_app_site_association():
    """Serve the apple-app-site-association file for Universal Links"""
    
    association_file_path = Path(__file__).parent.parent / "apple-app-site-association"
    
    if not association_file_path.exists():
        raise HTTPException(status_code=404, detail="Association file not found")
    
    with open(association_file_path, "r") as f:
        content = f.read()
    
    return Response(
        content=content,
        media_type="application/json",
        headers={"Content-Type": "application/json"}
    )

@app.get("/healthz")
async def healthz():
    """Lightweight health check for Railway / load balancer probes."""
    return {"status": "ok"}

@app.get("/health")
async def health_check():
    """Health check endpoint to test basic functionality"""
    health_status = {
        "status": "healthy",
        "timestamp": "2025-08-07T18:28:00Z",
        "services": {}
    }
    
    # Test AI service
    try:
        ai_status = "enabled" if ai_service.ai_enabled else "disabled"
        health_status["services"]["ai"] = ai_status
    except Exception as e:
        health_status["services"]["ai"] = f"error: {str(e)}"
    
    # Test pass generator
    try:
        from app.services.pass_generator import PassGenerator
        generator = PassGenerator()
        health_status["services"]["pass_generator"] = "initialized"
        health_status["services"]["signing"] = "enabled" if generator.signing_enabled else "disabled"
    except Exception as e:
        health_status["services"]["pass_generator"] = f"error: {str(e)}"
    
    # Test barcode extractor
    try:
        from app.services.barcode_extractor import barcode_extractor
        health_status["services"]["barcode_extractor"] = "initialized"
    except Exception as e:
        health_status["services"]["barcode_extractor"] = f"error: {str(e)}"
    
    return health_status

@app.post("/upload", response_model=UploadResponse)
async def upload_pdf(
    file: UploadFile = File(...),
    user_id: str = Form(...),
    session_token: str = Form(...),
    is_retry: bool = Form(False),
    is_demo: bool = Form(False),
    x_api_key: Optional[str] = Header(None)
):
    """Upload a PDF file for processing into an Apple Wallet pass."""
    
    # Basic authentication check
    expected_api_key = os.getenv("API_KEY", "development-api-key")
    if x_api_key != expected_api_key:
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
        print(f"🔄 Starting processing for {file.filename}")
        
        # Step 1: Extract text from PDF for AI analysis
        try:
            from app.services.pass_generator import PassGenerator
            temp_generator = PassGenerator()
            pdf_text = temp_generator._extract_pdf_text(contents)
            print(f"📝 PDF text extracted: {len(pdf_text)} characters")
        except Exception as e:
            print(f"❌ Error extracting PDF text: {e}")
            raise HTTPException(status_code=400, detail=f"Failed to extract PDF text: {str(e)}")
        
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
        try:
            pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
                contents, 
                file.filename,
                ai_metadata
            )
            print(f"🎫 Generated {len(pkpass_files)} pass files")
            if warnings:
                print(f"⚠️ Warnings generated: {warnings}")
        except Exception as e:
            print(f"❌ Error generating passes: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to generate passes: {str(e)}")
        
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
        
        # Deduct 1 PASS from user's RevenueCat balance (unless this is a retry or demo)
        if is_demo:
            print(f"🎮 Demo mode: Skipping PASS deduction for user {user_id}")
            deduction_success = True
        else:
            print(f"🔄 Attempting to deduct PASS for user: {user_id}, is_retry: {is_retry}")
            deduction_success = revenuecat_service.deduct_pass(user_id, is_retry)
            if deduction_success:
                print(f"✅ PASS deduction successful for user {user_id}")
            else:
                print(f"⚠️ PASS deduction failed for user {user_id}, but continuing with pass generation")
        
        # Update job information with completion
        jobs[job_id].update({
            "status": "completed",
            "progress": 100,
            "pass_paths": pass_paths,
            "detected_barcodes": detected_barcodes,
            "barcode_count": len(detected_barcodes),
            "ticket_count": len(pkpass_files),
            "ticket_info": ticket_info,
            "warnings": warnings,
            # Keep backwards compatibility
            "pass_path": pass_paths[0] if pass_paths else None
        })
        
        # Use enhanced metadata with colors from ticket_info for the upload response
        # For multi-pass documents, use base metadata without ticket-specific numbering
        enhanced_metadata = ai_metadata  # fallback to original
        if ticket_info and len(ticket_info) > 0:
            first_ticket = ticket_info[0]
            if "metadata" in first_ticket and first_ticket["metadata"]:
                enhanced_metadata = first_ticket["metadata"].copy()
                # Remove ticket-specific numbering from title for upload response
                if len(ticket_info) > 1 and enhanced_metadata.get("title"):
                    title = enhanced_metadata["title"]
                    # Remove "(#N)" pattern from title
                    import re
                    clean_title = re.sub(r'\s*\(#\d+\)\s*$', '', title)
                    enhanced_metadata["title"] = clean_title
                print(f"🎨 Using enhanced metadata with colors for upload response")
        
        return UploadResponse(
            job_id=job_id, 
            status="completed", 
            pass_url=f"/pass/{job_id}",
            ai_metadata=sanitize_metadata(enhanced_metadata),
            ticket_count=len(pkpass_files),
            warnings=warnings if warnings else None
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

@app.post("/upload/v2", response_model=UploadResponse)
async def upload_pdf_v2(
    file: UploadFile = File(...),
    user_id: str = Form(...),
    session_token: str = Form(...),
    is_retry: bool = Form(False),
    is_demo: bool = Form(False),
    x_api_key: Optional[str] = Header(None)
):
    """Upload a PDF for processing using the v2 pipeline.

    Same contract as /upload but uses the rewritten pass generation pipeline:
    single LLM call, Pydantic-validated pass.json, cleaner barcode handling.
    """
    # Auth
    expected_api_key = os.getenv("API_KEY", "development-api-key")
    if x_api_key != expected_api_key:
        raise HTTPException(status_code=401, detail="Invalid API key")

    # Validate file
    if not file.filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are allowed")

    contents = await file.read()
    if len(contents) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File size exceeds 10MB limit")

    validator = PDFValidator()
    is_valid, error_message = validator.validate(contents)
    if not is_valid:
        raise HTTPException(status_code=400, detail=f"Invalid PDF: {error_message}")

    job_id = str(uuid.uuid4())
    file_path = UPLOAD_DIR / f"{job_id}.pdf"
    with open(file_path, "wb") as f:
        f.write(contents)

    jobs[job_id] = {
        "user_id": user_id,
        "status": "processing",
        "progress": 10,
        "file_path": str(file_path),
        "filename": file.filename,
        "pipeline": "v2",
    }

    try:
        print(f"🔄 [v2] Starting processing for {file.filename}")
        jobs[job_id]["progress"] = 30

        pkpass_files, detected_barcodes, ticket_info, warnings = create_passes_v2(
            contents, file.filename
        )
        print(f"🎫 [v2] Generated {len(pkpass_files)} pass file(s)")

        pass_paths = []
        for i, pkpass_data in enumerate(pkpass_files):
            if len(pkpass_files) > 1:
                pass_path = UPLOAD_DIR / f"{job_id}_ticket_{i + 1}.pkpass"
            else:
                pass_path = UPLOAD_DIR / f"{job_id}.pkpass"
            with open(pass_path, "wb") as f:
                f.write(pkpass_data)
            pass_paths.append(str(pass_path))

        # Deduct pass credit
        if is_demo:
            print(f"🎮 Demo mode: skipping PASS deduction for {user_id}")
        else:
            deduction_success = revenuecat_service.deduct_pass(user_id, is_retry)
            if not deduction_success:
                print(f"⚠️ PASS deduction failed for {user_id}, continuing anyway")

        jobs[job_id].update({
            "status": "completed",
            "progress": 100,
            "pass_paths": pass_paths,
            "pass_path": pass_paths[0] if pass_paths else None,
            "detected_barcodes": detected_barcodes,
            "barcode_count": len(detected_barcodes),
            "ticket_count": len(pkpass_files),
            "ticket_info": ticket_info,
            "warnings": warnings,
        })

        # Build ai_metadata from ticket_info for response (backwards compat)
        enhanced_metadata = None
        if ticket_info:
            enhanced_metadata = ticket_info[0].get("metadata")

        return UploadResponse(
            job_id=job_id,
            status="completed",
            pass_url=f"/pass/{job_id}",
            ai_metadata=sanitize_metadata(enhanced_metadata),
            ticket_count=len(pkpass_files),
            warnings=warnings if warnings else None,
        )

    except Exception as exc:
        jobs[job_id].update({"status": "failed", "progress": 0, "error": str(exc)})
        print(f"❌ [v2] Pass generation failed: {exc}")
        import traceback; traceback.print_exc()
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
    
    # For completed jobs, use the enhanced metadata from ticket_info (includes colors)
    # For in-progress jobs, use the original ai_metadata
    metadata_to_return = job.get("ai_metadata")  # default
    
    if job["status"] == "completed" and "ticket_info" in job and job["ticket_info"]:
        # Use the enhanced metadata from the first ticket (includes colors)
        first_ticket = job["ticket_info"][0]
        if "metadata" in first_ticket and first_ticket["metadata"]:
            metadata_to_return = first_ticket["metadata"]
            print(f"🎨 Using enhanced metadata with colors for job {job_id}")
        else:
            print(f"⚠️ No enhanced metadata found in ticket_info for job {job_id}")
    
    return StatusResponse(
        job_id=job_id,
        status=job["status"],
        progress=job["progress"],
        result_url=f"/pass/{job_id}" if job["status"] == "completed" else None,
        ai_metadata=sanitize_metadata(metadata_to_return),
        warnings=job.get("warnings")
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