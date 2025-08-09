import pytest
from fastapi.testclient import TestClient
from app.main import app
import io
from PyPDF2 import PdfWriter

client = TestClient(app)

def create_test_pdf():
    """Create a simple test PDF in memory."""
    pdf_writer = PdfWriter()
    pdf_writer.add_blank_page(width=200, height=200)
    
    pdf_bytes = io.BytesIO()
    pdf_writer.write(pdf_bytes)
    pdf_bytes.seek(0)
    return pdf_bytes.getvalue()

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["message"] == "Add2Wallet API is running"

def test_upload_pdf_success():
    pdf_content = create_test_pdf()
    
    files = {"file": ("test.pdf", pdf_content, "application/pdf")}
    data = {
        "user_id": "test-user",
        "session_token": "test-token"
    }
    headers = {"X-API-Key": "development-api-key"}
    
    response = client.post("/upload", files=files, data=data, headers=headers)
    
    assert response.status_code == 200
    json_response = response.json()
    assert "job_id" in json_response
    assert json_response["status"] == "processing"

def test_upload_aztec_pdf_integration():
    """Test uploading the actual Aztec PDF through the API."""
    import os
    
    # Ensure API key is set for test
    os.environ["API_KEY"] = "development-api-key"
    
    # Path to the test Aztec PDF
    test_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "test_files", "pass_with_aztec_code.pdf")
    
    if not os.path.exists(test_file):
        pytest.skip(f"Aztec test file not found: {test_file}")
    
    # Read the test PDF
    with open(test_file, 'rb') as f:
        pdf_content = f.read()
    
    files = {"file": ("pass_with_aztec_code.pdf", pdf_content, "application/pdf")}
    data = {
        "user_id": "test-user-aztec",
        "session_token": "test-token-aztec"
    }
    headers = {"X-API-Key": "development-api-key"}
    
    response = client.post("/upload", files=files, data=data, headers=headers)
    
    assert response.status_code == 200
    json_response = response.json()
    assert "job_id" in json_response
    assert json_response["status"] in ["processing", "completed"]
    
    # If completed immediately, check ticket count
    if json_response["status"] == "completed":
        assert "ticket_count" in json_response
        # Should find at least 1 ticket (ideally 3 for the 3 Aztec codes)
        assert json_response["ticket_count"] >= 1
        
        print(f"✅ Aztec upload test: Found {json_response['ticket_count']} ticket(s)")
        
        # Test downloading the tickets
        job_id = json_response["job_id"]
        tickets_response = client.get(f"/tickets/{job_id}", headers=headers)
        assert tickets_response.status_code == 200
        
        tickets_data = tickets_response.json()
        assert "tickets" in tickets_data
        assert len(tickets_data["tickets"]) == json_response["ticket_count"]
        
        # Verify each ticket has barcode info
        for ticket in tickets_data["tickets"]:
            assert "has_barcode" in ticket
            if ticket["has_barcode"]:
                assert "barcode_type" in ticket
                print(f"  Ticket: {ticket.get('title', 'N/A')} - {ticket.get('barcode_type', 'N/A')}")

def test_upload_pdf_invalid_api_key():
    pdf_content = create_test_pdf()
    
    files = {"file": ("test.pdf", pdf_content, "application/pdf")}
    data = {
        "user_id": "test-user",
        "session_token": "test-token"
    }
    headers = {"X-API-Key": "invalid-key"}
    
    response = client.post("/upload", files=files, data=data, headers=headers)
    
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid API key"

def test_upload_non_pdf_file():
    files = {"file": ("test.txt", b"Not a PDF", "text/plain")}
    data = {
        "user_id": "test-user",
        "session_token": "test-token"
    }
    headers = {"X-API-Key": "development-api-key"}
    
    response = client.post("/upload", files=files, data=data, headers=headers)
    
    assert response.status_code == 400
    assert "Only PDF files are allowed" in response.json()["detail"]

def test_get_status():
    # First upload a PDF
    pdf_content = create_test_pdf()
    files = {"file": ("test.pdf", pdf_content, "application/pdf")}
    data = {
        "user_id": "test-user",
        "session_token": "test-token"
    }
    headers = {"X-API-Key": "development-api-key"}
    
    upload_response = client.post("/upload", files=files, data=data, headers=headers)
    job_id = upload_response.json()["job_id"]
    
    # Check status
    status_response = client.get(f"/status/{job_id}")
    assert status_response.status_code == 200
    
    status_data = status_response.json()
    assert status_data["job_id"] == job_id
    assert status_data["status"] in ["processing", "completed"]
    assert "progress" in status_data

def test_get_status_invalid_job():
    response = client.get("/status/invalid-job-id")
    assert response.status_code == 404
    assert response.json()["detail"] == "Job not found"

def test_list_passes():
    response = client.get("/passes")
    assert response.status_code == 200
    assert "passes" in response.json()