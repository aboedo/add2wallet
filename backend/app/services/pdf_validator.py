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
        if not pdf_content:
            return False, "PDF file is empty"

        # Try PyPDF2 first, fall back to PyMuPDF for encrypted/unusual PDFs
        valid, error = self._validate_pypdf2(pdf_content)
        if valid:
            return True, ""

        # PyPDF2 failed — try PyMuPDF (fitz) as fallback
        valid_fitz, error_fitz = self._validate_fitz(pdf_content)
        if valid_fitz:
            return True, ""

        # Both failed — return the more informative error
        return False, error

    def _validate_pypdf2(self, pdf_content: bytes) -> Tuple[bool, str]:
        """Validate using PyPDF2."""
        try:
            pdf_file = BytesIO(pdf_content)
            pdf_reader = PyPDF2.PdfReader(pdf_file)

            if len(pdf_reader.pages) == 0:
                return False, "PDF has no pages"

            if pdf_reader.is_encrypted:
                try:
                    if not pdf_reader.decrypt(''):
                        return False, "Password-protected PDFs are not supported"
                except Exception:
                    return False, "Password-protected PDFs are not supported"

            # Optional: try to extract text from first page
            try:
                _ = pdf_reader.pages[0].extract_text()
            except Exception:
                pass

            return True, ""

        except PyPDF2.errors.PdfReadError as e:
            return False, f"Invalid PDF format: {str(e)}"
        except Exception as e:
            return False, f"Error validating PDF: {str(e)}"

    def _validate_fitz(self, pdf_content: bytes) -> Tuple[bool, str]:
        """Validate using PyMuPDF (fitz) as fallback for encrypted/unusual PDFs."""
        try:
            import fitz
            doc = fitz.open(stream=pdf_content, filetype="pdf")

            if doc.page_count == 0:
                doc.close()
                return False, "PDF has no pages"

            if doc.needs_pass:
                # Try empty password (handles restriction-only encryption)
                if not doc.authenticate(''):
                    doc.close()
                    return False, "Password-protected PDFs are not supported"

            doc.close()
            return True, ""

        except Exception as e:
            return False, f"Error validating PDF with fallback: {str(e)}"
