"""Fallback barcode and QR code extraction from PDF files without external dependencies."""

import io
import os
import logging
import tempfile
from typing import List, Tuple, Optional, Dict, Any
import re
import PyPDF2
from PIL import Image

# Try to import PyMuPDF, but don't fail if it's not available (Vercel serverless)
try:
    import fitz  # PyMuPDF
    HAS_PYMUPDF = True
except ImportError:
    HAS_PYMUPDF = False
    fitz = None

# Configure logging
logger = logging.getLogger(__name__)


class FallbackBarcodeExtractor:
    """Extract barcodes and QR codes from PDF files using text analysis and basic image processing."""
    
    def __init__(self):
        """Initialize the fallback barcode extractor."""
        self.barcode_patterns = [
            # Common barcode patterns
            r'\b[0-9]{8,20}\b',  # Basic numerical barcodes
            r'\b[A-Z0-9]{10,30}\b',  # Alphanumeric codes
            r'\b[0-9]{3}-[0-9]{3}-[0-9]{6}\b',  # Formatted codes
            r'\b[A-Z]{2}[0-9]{6,12}\b',  # Flight/train style codes
            r'\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b',  # UUID style
        ]
    
    def extract_barcodes_from_pdf(self, pdf_data: bytes, filename: str) -> List[Dict[str, Any]]:
        """Extract all potential barcodes from a PDF file using text analysis.
        
        Args:
            pdf_data: Raw PDF bytes
            filename: Original filename for logging
            
        Returns:
            List of detected barcode-like data with their types
        """
        logger.info(f"🔍 Starting fallback barcode extraction from {filename}")
        
        barcodes = []
        
        try:
            # Method 1: Extract from PDF text
            text_barcodes = self._extract_from_text(pdf_data)
            barcodes.extend(text_barcodes)
            logger.info(f"📝 Text analysis found {len(text_barcodes)} potential barcodes")
            
            # Method 2: Extract from image metadata and OCR-like analysis
            image_barcodes = self._extract_from_images_basic(pdf_data)
            # Avoid duplicates
            existing_data = {bc['data'] for bc in barcodes}
            new_barcodes = [bc for bc in image_barcodes if bc['data'] not in existing_data]
            barcodes.extend(new_barcodes)
            logger.info(f"🖼️ Image analysis found {len(new_barcodes)} additional potential barcodes")
            
        except Exception as e:
            logger.warning(f"⚠️ Fallback extraction error: {e}")
        
        logger.info(f"✅ Total potential barcodes extracted: {len(barcodes)}")
        return self._rank_and_filter_barcodes(barcodes)
    
    def _extract_from_text(self, pdf_data: bytes) -> List[Dict[str, Any]]:
        """Extract potential barcode data from PDF text content.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of potential barcodes found in text
        """
        barcodes = []
        
        try:
            # Extract text using PyPDF2
            reader = PyPDF2.PdfReader(io.BytesIO(pdf_data))
            text_content = ""
            
            for page in reader.pages:
                text_content += page.extract_text() + "\n"
            
            # Search for barcode patterns
            for i, pattern in enumerate(self.barcode_patterns):
                matches = re.finditer(pattern, text_content)
                for match in matches:
                    barcode_data = match.group().strip()
                    
                    # Skip if too short or too common
                    if len(barcode_data) < 6 or barcode_data.lower() in ['page', 'total', 'amount']:
                        continue
                    
                    barcode_info = {
                        'data': barcode_data,
                        'type': self._guess_barcode_type(barcode_data),
                        'format': self._normalize_barcode_format('UNKNOWN'),
                        'method': 'text_extraction',
                        'confidence': self._calculate_text_confidence(barcode_data, pattern),
                        'pattern_index': i,
                        'context': self._get_surrounding_context(text_content, match.start(), match.end())
                    }
                    
                    barcodes.append(barcode_info)
                    
        except Exception as e:
            logger.warning(f"⚠️ Text extraction failed: {e}")
        
        return barcodes
    
    def _extract_from_images_basic(self, pdf_data: bytes) -> List[Dict[str, Any]]:
        """Extract potential barcode data from PDF images using basic analysis.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of potential barcodes from images
        """
        barcodes = []
        
        if not HAS_PYMUPDF:
            logger.warning("⚠️ PyMuPDF not available, skipping image-based barcode detection")
            return []
            
        try:
            # Use PyMuPDF to extract images and analyze them
            doc = fitz.open(stream=pdf_data, filetype="pdf")
            
            for page_num in range(len(doc)):
                page = doc[page_num]
                
                # Look for images that might contain barcodes
                image_list = page.get_images()
                
                for img_index, img in enumerate(image_list):
                    try:
                        # Get image
                        xref = img[0]
                        pix = fitz.Pixmap(doc, xref)
                        
                        if pix.n - pix.alpha < 4:  # GRAY or RGB
                            # Convert to PIL Image
                            img_data = pix.tobytes("png")
                            pil_image = Image.open(io.BytesIO(img_data))
                            
                            # Basic barcode detection heuristics
                            width, height = pil_image.size
                            
                            # Typical barcode dimensions (wide and short, or square for QR)
                            aspect_ratio = width / height
                            
                            if (aspect_ratio > 2 or aspect_ratio < 0.5) or (0.8 < aspect_ratio < 1.2):
                                # Might be a barcode - create placeholder entry
                                barcode_info = {
                                    'data': f"IMAGE_BARCODE_{page_num}_{img_index}",
                                    'type': 'QRCODE' if 0.8 < aspect_ratio < 1.2 else 'CODE128',
                                    'format': self._normalize_barcode_format('QRCODE' if 0.8 < aspect_ratio < 1.2 else 'CODE128'),
                                    'method': 'image_heuristic',
                                    'confidence': 30,  # Low confidence without actual decoding
                                    'page': page_num + 1,
                                    'image_size': (width, height),
                                    'aspect_ratio': aspect_ratio
                                }
                                barcodes.append(barcode_info)
                        
                        pix = None  # Clean up
                        
                    except Exception as e:
                        logger.debug(f"Error processing image {img_index} on page {page_num}: {e}")
                        continue
            
            doc.close()
            
        except Exception as e:
            logger.warning(f"⚠️ Image analysis failed: {e}")
        
        return barcodes
    
    def _guess_barcode_type(self, data: str) -> str:
        """Guess the barcode type based on the data pattern.
        
        Args:
            data: Barcode data string
            
        Returns:
            Guessed barcode type
        """
        if re.match(r'^[0-9]+$', data):
            if len(data) == 13:
                return 'EAN13'
            elif len(data) == 12:
                return 'UPC_A'
            elif len(data) == 8:
                return 'EAN8'
            else:
                return 'CODE128'
        elif re.match(r'^[A-Z0-9]+$', data):
            return 'CODE39'
        elif '-' in data or any(c.islower() for c in data):
            return 'QRCODE'
        else:
            return 'CODE128'
    
    def _normalize_barcode_format(self, barcode_type: str) -> str:
        """Normalize barcode format for Apple Wallet.
        
        Args:
            barcode_type: Original barcode type
            
        Returns:
            Normalized format for Apple Wallet
        """
        format_mapping = {
            'QRCODE': 'PKBarcodeFormatQR',
            'PDF417': 'PKBarcodeFormatPDF417', 
            'CODE128': 'PKBarcodeFormatCode128',
            'AZTEC': 'PKBarcodeFormatAztec',
            'CODE39': 'PKBarcodeFormatCode128',
            'CODE93': 'PKBarcodeFormatCode128',
            'EAN13': 'PKBarcodeFormatCode128',
            'EAN8': 'PKBarcodeFormatCode128',
            'UPC_A': 'PKBarcodeFormatCode128',
            'UPC_E': 'PKBarcodeFormatCode128',
            'CODABAR': 'PKBarcodeFormatCode128',
            'ITF': 'PKBarcodeFormatCode128',
            'DATAMATRIX': 'PKBarcodeFormatQR',
            'UNKNOWN': 'PKBarcodeFormatQR'
        }
        
        return format_mapping.get(barcode_type, 'PKBarcodeFormatQR')
    
    def _calculate_text_confidence(self, data: str, pattern: str) -> int:
        """Calculate confidence score for text-extracted barcode.
        
        Args:
            data: Barcode data
            pattern: Regex pattern that matched
            
        Returns:
            Confidence score 0-100
        """
        confidence = 50  # Base confidence
        
        # Higher confidence for longer codes
        if len(data) > 15:
            confidence += 20
        elif len(data) > 10:
            confidence += 10
        
        # Higher confidence for structured patterns
        if '-' in data or any(c.islower() for c in data):
            confidence += 15
        
        # Higher confidence for purely numeric codes
        if re.match(r'^[0-9]+$', data):
            confidence += 10
        
        return min(confidence, 95)  # Cap at 95% since we can't be 100% sure without visual verification
    
    def _get_surrounding_context(self, text: str, start: int, end: int, context_size: int = 50) -> str:
        """Get surrounding text context for a matched barcode.
        
        Args:
            text: Full text content
            start: Match start position
            end: Match end position
            context_size: Number of characters before and after to include
            
        Returns:
            Surrounding context string
        """
        context_start = max(0, start - context_size)
        context_end = min(len(text), end + context_size)
        
        return text[context_start:context_end].replace('\n', ' ').strip()
    
    def _rank_and_filter_barcodes(self, barcodes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Rank and filter barcodes by confidence and likelihood.
        
        Args:
            barcodes: List of detected barcodes
            
        Returns:
            Filtered and ranked list of most likely barcodes
        """
        if not barcodes:
            return barcodes
        
        # Remove obvious false positives
        filtered_barcodes = []
        for barcode in barcodes:
            data = barcode['data']
            
            # Skip common false positives
            if (data.lower() in ['page', 'total', 'amount', 'price', 'date', 'time'] or 
                len(data) < 6 or
                data.startswith('IMAGE_BARCODE_')):  # Skip image placeholders for now
                continue
                
            filtered_barcodes.append(barcode)
        
        # Sort by confidence
        filtered_barcodes.sort(key=lambda x: x.get('confidence', 0), reverse=True)
        
        # Group by data to remove duplicates, keeping highest confidence
        data_groups = {}
        for barcode in filtered_barcodes:
            data = barcode['data']
            if data not in data_groups or barcode.get('confidence', 0) > data_groups[data].get('confidence', 0):
                data_groups[data] = barcode
        
        result = list(data_groups.values())
        result.sort(key=lambda x: x.get('confidence', 0), reverse=True)
        
        return result
    
    def get_primary_barcode(self, barcodes: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """Get the primary barcode (highest confidence).
        
        Args:
            barcodes: List of detected barcodes
            
        Returns:
            Primary barcode or None if no barcodes found
        """
        if not barcodes:
            return None
        
        # Return the first (highest confidence) barcode
        return barcodes[0]
    
    def detect_multiple_tickets(self, barcodes: List[Dict[str, Any]], ai_metadata: Dict[str, Any] = None) -> List[Dict[str, Any]]:
        """Detect if there are multiple tickets/passes in the PDF.
        
        Args:
            barcodes: List of detected barcodes
            ai_metadata: AI-extracted metadata
            
        Returns:
            List of ticket entries, each containing barcode and metadata
        """
        # Always create at least one ticket, even if no barcodes found
        if not barcodes:
            return [{
                'barcode': None,
                'metadata': ai_metadata or {},
                'ticket_number': 1,
                'total_tickets': 1
            }]
        
        tickets = []
        
        # If only one barcode, create single ticket
        if len(barcodes) == 1:
            tickets.append({
                'barcode': barcodes[0],
                'metadata': ai_metadata or {},
                'ticket_number': 1,
                'total_tickets': 1
            })
            return tickets
        
        # Multiple barcodes - create separate tickets
        for i, barcode in enumerate(barcodes, 1):
            ticket_metadata = (ai_metadata or {}).copy()
            
            # Customize metadata for each ticket
            if ai_metadata:
                # Add ticket-specific information
                ticket_metadata['title'] = f"{ticket_metadata.get('title', 'Ticket')} #{i}"
                ticket_metadata['description'] = f"{ticket_metadata.get('description', '')} (Ticket {i} of {len(barcodes)})"
                
                # Add seat info if we can infer it from barcode context
                if hasattr(barcode, 'context') and barcode.get('context'):
                    context = barcode['context'].upper()
                    seat_matches = re.findall(r'SEAT\s*[:\-]?\s*([A-Z0-9]+)|ROW\s*[:\-]?\s*([A-Z0-9]+)', context)
                    if seat_matches:
                        seat_info = ' '.join([m[0] or m[1] for m in seat_matches])
                        ticket_metadata['seat_info'] = seat_info
            
            tickets.append({
                'barcode': barcode,
                'metadata': ticket_metadata,
                'ticket_number': i,
                'total_tickets': len(barcodes)
            })
        
        return tickets


# Global instance
fallback_barcode_extractor = FallbackBarcodeExtractor()