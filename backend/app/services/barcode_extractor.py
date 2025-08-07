"""Barcode and QR code extraction from PDF files."""

import io
import os
import logging
import tempfile
from typing import List, Tuple, Optional, Dict, Any

# Import all dependencies - should be available in properly configured environment
import cv2
import numpy as np
from pyzbar import pyzbar
from pdf2image import convert_from_bytes

# Always available imports
from PIL import Image
try:
    import fitz  # PyMuPDF
    HAS_PYMUPDF = True
except ImportError:
    print("⚠️ PyMuPDF not available")
    HAS_PYMUPDF = False
    fitz = None

import PyPDF2

# Configure logging
logger = logging.getLogger(__name__)


class BarcodeExtractor:
    """Extract barcodes and QR codes from PDF files."""
    
    def __init__(self):
        """Initialize the barcode extractor."""
        self.supported_formats = {
            'CODE128', 'CODE39', 'CODE93', 'CODABAR', 'EAN8', 'EAN13',
            'UPC_A', 'UPC_E', 'ITF', 'QRCODE', 'DATAMATRIX', 'PDF417',
            'AZTEC'
        }
    
    def extract_barcodes_from_pdf(self, pdf_data: bytes, filename: str) -> List[Dict[str, Any]]:
        """Extract all barcodes from a PDF file using multiple methods.
        
        Args:
            pdf_data: Raw PDF bytes
            filename: Original filename for logging
            
        Returns:
            List of detected barcodes with their data and types
        """
        logger.info(f"🔍 Starting barcode extraction from {filename}")
        
        # All dependencies should be available with proper configuration
        
        barcodes = []
        
        # Method 1: Try PyMuPDF for vector-based barcodes (fastest)
        if HAS_PYMUPDF:
            try:
                pymupdf_barcodes = self._extract_with_pymupdf(pdf_data)
                barcodes.extend(pymupdf_barcodes)
                logger.info(f"📊 PyMuPDF found {len(pymupdf_barcodes)} barcodes")
            except Exception as e:
                logger.warning(f"⚠️ PyMuPDF extraction failed: {e}")
        
        # Method 2: Convert PDF to images and scan (more thorough)
        try:
            image_barcodes = self._extract_from_images(pdf_data)
            # Avoid duplicates by checking barcode data
            existing_data = {bc['data'] for bc in barcodes}
            new_barcodes = [bc for bc in image_barcodes if bc['data'] not in existing_data]
            barcodes.extend(new_barcodes)
            logger.info(f"🖼️ Image scanning found {len(new_barcodes)} additional barcodes")
        except Exception as e:
            logger.warning(f"⚠️ Image-based extraction failed: {e}")
        
        # Method 3: Enhanced image processing for difficult barcodes
        if not barcodes:
            try:
                enhanced_barcodes = self._extract_with_enhancement(pdf_data)
                barcodes.extend(enhanced_barcodes)
                logger.info(f"🔧 Enhanced processing found {len(enhanced_barcodes)} barcodes")
            except Exception as e:
                logger.warning(f"⚠️ Enhanced extraction failed: {e}")
        
        logger.info(f"✅ Total barcodes extracted: {len(barcodes)}")
        return self._deduplicate_barcodes(barcodes)
    
    def _extract_with_pymupdf(self, pdf_data: bytes) -> List[Dict[str, Any]]:
        """Extract barcodes using PyMuPDF (fast, works with vector graphics).
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of detected barcodes
        """
        if not HAS_PYMUPDF:
            return []
            
        barcodes = []
        
        # Open PDF with PyMuPDF
        doc = fitz.open(stream=pdf_data, filetype="pdf")
        
        for page_num in range(len(doc)):
            page = doc[page_num]
            
            # Get page as image
            pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))  # 2x scale for better quality
            img_data = pix.tobytes("png")
            
            # Convert to PIL Image and then to OpenCV format
            pil_image = Image.open(io.BytesIO(img_data))
            cv_image = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
            
            # Detect barcodes
            page_barcodes = self._decode_barcodes(cv_image, page_num + 1)
            barcodes.extend(page_barcodes)
        
        doc.close()
        return barcodes
    
    def _extract_from_images(self, pdf_data: bytes) -> List[Dict[str, Any]]:
        """Extract barcodes by converting PDF to images.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of detected barcodes
        """
        barcodes = []
        
        # Convert PDF to images
        images = convert_from_bytes(
            pdf_data,
            dpi=300,  # High DPI for better barcode detection
            fmt='RGB',
            thread_count=2
        )
        
        for page_num, image in enumerate(images, 1):
            # Convert PIL to OpenCV
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            
            # Detect barcodes
            page_barcodes = self._decode_barcodes(cv_image, page_num)
            barcodes.extend(page_barcodes)
        
        return barcodes
    
    def _extract_with_enhancement(self, pdf_data: bytes) -> List[Dict[str, Any]]:
        """Extract barcodes with image enhancement techniques.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of detected barcodes
        """
        barcodes = []
        
        # Convert PDF to high-resolution images
        images = convert_from_bytes(
            pdf_data,
            dpi=600,  # Very high DPI
            fmt='RGB'
        )
        
        for page_num, image in enumerate(images, 1):
            # Convert PIL to OpenCV
            cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
            
            # Try multiple image enhancement techniques
            enhancement_methods = [
                self._enhance_contrast,
                self._enhance_sharpness,
                self._enhance_threshold,
                self._enhance_morphology,
                self._enhance_gaussian_blur
            ]
            
            for enhance_method in enhancement_methods:
                try:
                    enhanced_image = enhance_method(cv_image)
                    page_barcodes = self._decode_barcodes(enhanced_image, page_num, f"enhanced_{enhance_method.__name__}")
                    barcodes.extend(page_barcodes)
                except Exception as e:
                    logger.debug(f"Enhancement method {enhance_method.__name__} failed: {e}")
                    continue
        
        return barcodes
    
    def _decode_barcodes(self, cv_image: np.ndarray, page_num: int, method: str = "standard") -> List[Dict[str, Any]]:
        """Decode barcodes from an OpenCV image.
        
        Args:
            cv_image: OpenCV image array
            page_num: Page number for logging
            method: Detection method used
            
        Returns:
            List of detected barcodes
        """
        barcodes = []
        
        try:
            # Use pyzbar to detect barcodes
            detected_barcodes = pyzbar.decode(cv_image)
            
            for barcode in detected_barcodes:
                try:
                    # Decode barcode data
                    barcode_data = barcode.data.decode('utf-8')
                    barcode_type = barcode.type
                    
                    # Get barcode position
                    rect = barcode.rect
                    
                    barcode_info = {
                        'data': barcode_data,
                        'type': barcode_type,
                        'format': self._normalize_barcode_format(barcode_type),
                        'page': page_num,
                        'method': method,
                        'position': {
                            'x': rect.left,
                            'y': rect.top,
                            'width': rect.width,
                            'height': rect.height
                        },
                        'confidence': self._calculate_confidence(barcode)
                    }
                    
                    barcodes.append(barcode_info)
                    logger.debug(f"📱 Found {barcode_type} on page {page_num}: {barcode_data[:50]}...")
                    
                except UnicodeDecodeError:
                    # Try different encodings
                    for encoding in ['latin-1', 'ascii', 'cp1252']:
                        try:
                            barcode_data = barcode.data.decode(encoding)
                            barcode_info = {
                                'data': barcode_data,
                                'type': barcode.type,
                                'format': self._normalize_barcode_format(barcode.type),
                                'page': page_num,
                                'method': method,
                                'encoding': encoding
                            }
                            barcodes.append(barcode_info)
                            break
                        except UnicodeDecodeError:
                            continue
                except Exception as e:
                    logger.warning(f"⚠️ Error processing barcode: {e}")
                    continue
                    
        except Exception as e:
            logger.warning(f"⚠️ Barcode detection failed on page {page_num}: {e}")
        
        return barcodes
    
    def _enhance_contrast(self, image: np.ndarray) -> np.ndarray:
        """Enhance image contrast."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        return cv2.convertScaleAbs(gray, alpha=1.5, beta=0)
    
    def _enhance_sharpness(self, image: np.ndarray) -> np.ndarray:
        """Enhance image sharpness."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        kernel = np.array([[-1,-1,-1], [-1,9,-1], [-1,-1,-1]])
        return cv2.filter2D(gray, -1, kernel)
    
    def _enhance_threshold(self, image: np.ndarray) -> np.ndarray:
        """Apply adaptive threshold."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        return cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2)
    
    def _enhance_morphology(self, image: np.ndarray) -> np.ndarray:
        """Apply morphological operations."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        return cv2.morphologyEx(gray, cv2.MORPH_CLOSE, kernel)
    
    def _enhance_gaussian_blur(self, image: np.ndarray) -> np.ndarray:
        """Apply Gaussian blur to reduce noise."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        return cv2.GaussianBlur(gray, (3, 3), 0)
    
    def _normalize_barcode_format(self, barcode_type: str) -> str:
        """Normalize barcode format for Apple Wallet.
        
        Args:
            barcode_type: Original barcode type from pyzbar
            
        Returns:
            Normalized format for Apple Wallet
        """
        format_mapping = {
            'QRCODE': 'PKBarcodeFormatQR',
            'PDF417': 'PKBarcodeFormatPDF417', 
            'CODE128': 'PKBarcodeFormatCode128',
            'AZTEC': 'PKBarcodeFormatAztec',
            'CODE39': 'PKBarcodeFormatCode128',  # Fallback to Code128
            'CODE93': 'PKBarcodeFormatCode128',  # Fallback to Code128
            'EAN13': 'PKBarcodeFormatCode128',   # Fallback to Code128
            'EAN8': 'PKBarcodeFormatCode128',    # Fallback to Code128
            'UPC_A': 'PKBarcodeFormatCode128',   # Fallback to Code128
            'UPC_E': 'PKBarcodeFormatCode128',   # Fallback to Code128
            'CODABAR': 'PKBarcodeFormatCode128', # Fallback to Code128
            'ITF': 'PKBarcodeFormatCode128',     # Fallback to Code128
            'DATAMATRIX': 'PKBarcodeFormatQR'   # Fallback to QR
        }
        
        return format_mapping.get(barcode_type, 'PKBarcodeFormatQR')
    
    def _calculate_confidence(self, barcode) -> int:
        """Calculate confidence score for barcode detection.
        
        Args:
            barcode: pyzbar barcode object
            
        Returns:
            Confidence score 0-100
        """
        # Base confidence on barcode quality indicators
        confidence = 70  # Base confidence
        
        # Higher confidence for common, well-supported formats
        if barcode.type in ['QRCODE', 'PDF417', 'CODE128']:
            confidence += 20
        
        # Higher confidence for longer data (usually more reliable)
        if len(barcode.data) > 20:
            confidence += 10
        
        return min(confidence, 100)
    
    def _deduplicate_barcodes(self, barcodes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Remove duplicate barcodes based on data content.
        
        Args:
            barcodes: List of detected barcodes
            
        Returns:
            Deduplicated list with highest confidence barcodes
        """
        if not barcodes:
            return barcodes
        
        # Group by data content
        data_groups = {}
        for barcode in barcodes:
            data = barcode['data']
            if data not in data_groups:
                data_groups[data] = []
            data_groups[data].append(barcode)
        
        # Keep the highest confidence barcode from each group
        result = []
        for data, group in data_groups.items():
            # Sort by confidence (highest first)
            group.sort(key=lambda x: x.get('confidence', 0), reverse=True)
            best_barcode = group[0]
            
            # Add detection count information
            best_barcode['detection_count'] = len(group)
            best_barcode['methods_used'] = list(set(bc.get('method', 'unknown') for bc in group))
            
            result.append(best_barcode)
        
        # Sort by confidence for final result
        result.sort(key=lambda x: x.get('confidence', 0), reverse=True)
        
        return result
    
    def get_primary_barcode(self, barcodes: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """Get the primary barcode (highest confidence, most likely to be the ticket).
        
        Args:
            barcodes: List of detected barcodes
            
        Returns:
            Primary barcode or None if no barcodes found
        """
        if not barcodes:
            return None
        
        # Prioritize by barcode type (QR codes and PDF417 are common for tickets)
        priority_types = ['QRCODE', 'PDF417', 'CODE128', 'AZTEC']
        
        for barcode_type in priority_types:
            for barcode in barcodes:
                if barcode['type'] == barcode_type:
                    return barcode
        
        # If no priority type found, return the first (highest confidence)
        return barcodes[0]


# Global instance
barcode_extractor = BarcodeExtractor()