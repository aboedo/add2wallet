# Add2Wallet Backend

## Overview
Python FastAPI backend service for processing PDFs and generating Apple Wallet passes.

## Requirements
- Python 3.11+
- pip or poetry

## Setup

### 1. Create Virtual Environment
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
```

### 3. Run Development Server
```bash
python run.py
```

The server will start at `http://localhost:8000`

API documentation available at `http://localhost:8000/docs`

## Testing
```bash
pytest
```

For coverage report:
```bash
pytest --cov=app tests/
```

## API Endpoints

### Upload PDF
```
POST /upload
Content-Type: multipart/form-data
X-API-Key: development-api-key

Body:
- file: PDF file
- user_id: string
- session_token: string
```

### Check Status
```
GET /status/{job_id}
Authorization: Bearer {token}
```

### Download Pass
```
GET /pass/{job_id}
Authorization: Bearer {token}
```

### List Passes
```
GET /passes
Authorization: Bearer {token}
```

## Project Structure
```
backend/
├── app/
│   ├── main.py              # FastAPI application
│   ├── models/              # Pydantic models
│   │   └── responses.py    # API response models
│   ├── services/            # Business logic
│   │   └── pdf_validator.py # PDF validation
│   └── routers/             # API routes (to be added)
├── tests/                   # Test files
├── certificates/            # SSL/Pass certificates (gitignored)
├── uploads/                 # Temporary PDF storage (gitignored)
├── requirements.txt         # Python dependencies
└── run.py                   # Development server script
```

## Environment Variables
Create a `.env` file for configuration:
```
OPENAI_API_KEY=your-key-here
API_KEY=development-api-key
```

## Next Steps
1. Add OpenAI integration for PDF processing
2. Implement pass generation with PassKit
3. Add database for job persistence
4. Implement proper authentication
5. Add Redis for job queue