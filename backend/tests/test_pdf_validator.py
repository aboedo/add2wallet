import pytest
from app.services.pdf_validator import PDFValidator
from PyPDF2 import PdfWriter
import io

def create_valid_pdf():
    """Create a valid test PDF."""
    pdf_writer = PdfWriter()
    pdf_writer.add_blank_page(width=200, height=200)
    
    pdf_bytes = io.BytesIO()
    pdf_writer.write(pdf_bytes)
    pdf_bytes.seek(0)
    return pdf_bytes.getvalue()

def test_validate_valid_pdf():
    validator = PDFValidator()
    pdf_content = create_valid_pdf()
    
    is_valid, error = validator.validate(pdf_content)
    
    assert is_valid is True
    assert error == ""

def test_validate_empty_content():
    validator = PDFValidator()
    
    is_valid, error = validator.validate(b"")
    
    assert is_valid is False
    assert "PDF file is empty" in error

def test_validate_invalid_pdf():
    validator = PDFValidator()
    
    is_valid, error = validator.validate(b"This is not a PDF")
    
    assert is_valid is False
    assert "Invalid PDF format" in error or "Error validating PDF" in error

def test_validate_pdf_with_no_pages():
    validator = PDFValidator()
    pdf_writer = PdfWriter()
    
    pdf_bytes = io.BytesIO()
    pdf_writer.write(pdf_bytes)
    pdf_bytes.seek(0)
    
    is_valid, error = validator.validate(pdf_bytes.getvalue())
    
    assert is_valid is False
    assert "PDF has no pages" in error