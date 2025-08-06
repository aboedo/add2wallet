import PyPDF2
from io import BytesIO
from typing import Tuple

class PDFValidator:
    """Validates PDF files for security and structure."""
    
    def validate(self, pdf_content: bytes) -> Tuple[bool, str]:
        """
        Validate PDF content.
        
        Returns:
            Tuple of (is_valid, error_message)
        """
        try:
            # Check if content is not empty
            if not pdf_content:
                return False, "PDF file is empty"
            
            # Try to parse the PDF
            pdf_file = BytesIO(pdf_content)
            pdf_reader = PyPDF2.PdfReader(pdf_file)
            
            # Check if PDF has pages
            if len(pdf_reader.pages) == 0:
                return False, "PDF has no pages"
            
            # Check if PDF is encrypted (we don't support encrypted PDFs yet)
            if pdf_reader.is_encrypted:
                return False, "Encrypted PDFs are not supported"
            
            # Try to extract text from first page (basic validation)
            try:
                first_page = pdf_reader.pages[0]
                text = first_page.extract_text()
            except Exception as e:
                return False, f"Cannot extract text from PDF: {str(e)}"
            
            return True, ""
            
        except PyPDF2.errors.PdfReadError as e:
            return False, f"Invalid PDF format: {str(e)}"
        except Exception as e:
            return False, f"Error validating PDF: {str(e)}"