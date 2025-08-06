from pydantic import BaseModel
from typing import Optional

class UploadResponse(BaseModel):
    job_id: str
    status: str
    pass_url: Optional[str] = None

class ErrorResponse(BaseModel):
    error: str

class StatusResponse(BaseModel):
    job_id: str
    status: str
    progress: int
    result_url: Optional[str] = None

class PassMetadata(BaseModel):
    event_name: Optional[str] = None
    venue: Optional[str] = None
    date: Optional[str] = None
    time: Optional[str] = None
    seat: Optional[str] = None
    barcode: Optional[str] = None
    logo_url: Optional[str] = None