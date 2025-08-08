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
            
            # Check if PDF is encrypted and requires password
            if pdf_reader.is_encrypted:
                # Try to decrypt with empty password (handles PDFs with user restrictions only)
                try:
                    if not pdf_reader.decrypt(''):
                        return False, "Password-protected PDFs are not supported"
                except Exception:
                    # If decryption fails, treat as password-protected
                    return False, "Password-protected PDFs are not supported"
            
            # Optional: try to extract text from first page, but do not fail if it doesn't work
            try:
                _ = pdf_reader.pages[0].extract_text()
            except Exception:
                # Some valid PDFs (image-only, special encodings) cannot extract text; still consider valid
                pass
            
            return True, ""
            
        except PyPDF2.errors.PdfReadError as e:
            return False, f"Invalid PDF format: {str(e)}"
        except Exception as e:
            return False, f"Error validating PDF: {str(e)}"