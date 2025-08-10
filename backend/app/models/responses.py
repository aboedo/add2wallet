from pydantic import BaseModel
from typing import Optional, List, Dict, Any

class UploadResponse(BaseModel):
    job_id: str
    status: str
    pass_url: Optional[str] = None
    ai_metadata: Optional[Dict[str, Any]] = None
    ticket_count: Optional[int] = None
    warnings: Optional[List[str]] = None

class ErrorResponse(BaseModel):
    error: str

class StatusResponse(BaseModel):
    job_id: str
    status: str
    progress: int
    result_url: Optional[str] = None
    ai_metadata: Optional[Dict[str, Any]] = None
    warnings: Optional[List[str]] = None

class PassMetadata(BaseModel):
    event_name: Optional[str] = None
    venue: Optional[str] = None
    date: Optional[str] = None
    time: Optional[str] = None
    seat: Optional[str] = None
    barcode: Optional[str] = None
    logo_url: Optional[str] = None

class EnhancedPassMetadata(BaseModel):
    # Basic Information
    event_type: Optional[str] = None
    event_name: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    
    # Date and Time
    date: Optional[str] = None
    time: Optional[str] = None
    duration: Optional[str] = None
    
    # Location Information
    venue_name: Optional[str] = None
    venue_address: Optional[str] = None
    city: Optional[str] = None
    state_country: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    
    # Event Details
    organizer: Optional[str] = None
    performer_artist: Optional[str] = None
    seat_info: Optional[str] = None
    barcode_data: Optional[str] = None
    price: Optional[str] = None
    confirmation_number: Optional[str] = None
    gate_info: Optional[str] = None
    
    # Enriched Information
    event_description: Optional[str] = None
    venue_type: Optional[str] = None
    capacity: Optional[str] = None
    website: Optional[str] = None
    phone: Optional[str] = None
    nearby_landmarks: Optional[List[str]] = None
    public_transport: Optional[str] = None
    parking_info: Optional[str] = None
    
    # Additional Details
    age_restriction: Optional[str] = None
    dress_code: Optional[str] = None
    weather_considerations: Optional[str] = None
    amenities: Optional[List[str]] = None
    accessibility: Optional[str] = None
    
    # Processing Information
    ai_processed: Optional[bool] = False
    confidence_score: Optional[int] = None
    processing_timestamp: Optional[str] = None
    model_used: Optional[str] = None
    enrichment_completed: Optional[bool] = False
    
    # Pass Colors (added by pass generator)
    background_color: Optional[str] = None
    foreground_color: Optional[str] = None
    label_color: Optional[str] = None