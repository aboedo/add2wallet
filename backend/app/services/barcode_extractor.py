"""Barcode and QR code extraction from PDF files."""

import io
import os
import logging
import tempfile
import base64
import math
from typing import List, Tuple, Optional, Dict, Any, Set

# Required dependencies - no fallbacks
import cv2
import numpy as np
from pyzbar import pyzbar
from pdf2image import convert_from_bytes
from PIL import Image
import fitz  # PyMuPDF
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
        
        # Format groups for ordered detection
        self.format_groups = [
            {'AZTEC'},  # Try Aztec first
            {'QRCODE'},  # Then QR
            {'CODE128', 'CODE39', 'CODE93', 'EAN8', 'EAN13', 'UPC_A', 'UPC_E', 'CODABAR', 'ITF', 'PDF417', 'DATAMATRIX'}  # Then 1D codes
        ]
    
    def extract_barcodes_from_pdf(self, pdf_data: bytes, filename: str) -> List[Dict[str, Any]]:
        """Extract all barcodes from a PDF file using multiple methods.
        
        Args:
            pdf_data: Raw PDF bytes
            filename: Original filename for logging
            
        Returns:
            List of detected barcodes with their data and types
        """
        logger.info(f"🔍 Starting barcode extraction from {filename}")
        
        barcodes = []
        
        logger.info("🚀 Using advanced barcode detection with format prioritization")
        
        # Method 1: Try PyMuPDF for vector-based barcodes (fastest)
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
        
        # Apply context-aware mixed Aztec/QR handling before deduplication
        if barcodes:
            barcodes = self._handle_mixed_aztec_qr(barcodes, filename)
        
        logger.info(f"✅ Total barcodes extracted: {len(barcodes)}")
        return self._deduplicate_barcodes(barcodes)
    
    def decode_with_formats(self, image: np.ndarray, formats: Set[str], try_harder: bool = True) -> List[Dict[str, Any]]:
        """Decode barcodes from image with specific format constraints.
        
        Args:
            image: OpenCV image array
            formats: Set of barcode formats to try (e.g., {'AZTEC'})
            try_harder: Enable enhanced detection (unused with pyzbar, kept for ZXing compatibility)
            
        Returns:
            List of detected barcodes matching the specified formats
        """
        barcodes = []
        
        try:
            # Use pyzbar to detect all barcodes, then filter by formats
            detected_barcodes = pyzbar.decode(image)
            
            for barcode in detected_barcodes:
                if barcode.type in formats:
                    try:
                        # Try UTF-8 first
                        try:
                            barcode_data = barcode.data.decode('utf-8')
                            encoding = 'utf-8'
                        except UnicodeDecodeError:
                            # Fallback to ISO-8859-1
                            barcode_data = barcode.data.decode('iso-8859-1')
                            encoding = 'iso-8859-1'
                        
                        # Get barcode position
                        rect = barcode.rect
                        
                        barcode_info = {
                            'data': barcode_data,
                            'type': barcode.type,
                            'format': self._normalize_barcode_format(barcode.type),
                            'encoding': encoding,
                            'raw_bytes': bytes(barcode.data),
                            'bytes_b64': base64.b64encode(barcode.data).decode('ascii'),
                            'bbox': [rect.left, rect.top, rect.width, rect.height],
                            'area': rect.width * rect.height,
                            'confidence': self._calculate_confidence(barcode),
                            'center_distance': self._calculate_center_distance(image, rect)
                        }
                        
                        barcodes.append(barcode_info)
                        logger.debug(f"📱 Found {barcode.type} with format filter: {barcode_data[:50]}...")
                        
                    except Exception as e:
                        logger.warning(f"⚠️ Error processing barcode: {e}")
                        continue
                        
        except Exception as e:
            logger.warning(f"⚠️ Barcode detection failed: {e}")
        
        return barcodes
    
    def _extract_with_pymupdf(self, pdf_data: bytes) -> List[Dict[str, Any]]:
        """Extract barcodes using PyMuPDF (fast, works with vector graphics).
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of detected barcodes
        """
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
        """Extract barcodes by converting PDF to images with fallback DPI.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            List of detected barcodes
        """
        barcodes = []
        
        # Try 400 DPI first
        for dpi in [400, 600]:
            try:
                logger.debug(f"🔍 Trying rasterization at {dpi} DPI")
                
                # Convert PDF to images
                images = convert_from_bytes(
                    pdf_data,
                    dpi=dpi,
                    fmt='RGB',
                    thread_count=2
                )
                
                page_barcodes = []
                for page_num, image in enumerate(images, 1):
                    # Convert PIL to OpenCV
                    cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
                    
                    # Try enhanced preprocessing if no barcodes found yet
                    if not barcodes:
                        processed_images = self._preprocess_for_barcode_detection(cv_image)
                        
                        for proc_name, proc_image in processed_images.items():
                            method_name = f"rasterized_{dpi}dpi_{proc_name}"
                            detected = self._decode_barcodes(proc_image, page_num, method_name)
                            page_barcodes.extend(detected)
                            
                            # Early exit if we found barcodes
                            if detected:
                                break
                    else:
                        # Standard detection
                        method_name = f"rasterized_{dpi}dpi"
                        detected = self._decode_barcodes(cv_image, page_num, method_name)
                        page_barcodes.extend(detected)
                
                barcodes.extend(page_barcodes)
                
                # If we found barcodes, don't try higher DPI
                if barcodes:
                    logger.info(f"✅ Found barcodes at {dpi} DPI")
                    break
                    
            except Exception as e:
                logger.warning(f"⚠️ Rasterization at {dpi} DPI failed: {e}")
                continue
        
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
        """Decode barcodes from an OpenCV image using ordered format detection.
        
        Args:
            cv_image: OpenCV image array
            page_num: Page number for logging
            method: Detection method used
            
        Returns:
            List of detected barcodes
        """
        return self._try_formats(cv_image, self.format_groups, page_num, method)
    
    def _try_formats(self, image: np.ndarray, format_groups: List[Set[str]], page_num: int, method: str) -> List[Dict[str, Any]]:
        """Try format groups in order until barcodes are found.
        
        Args:
            image: OpenCV image array
            format_groups: List of format sets to try in order
            page_num: Page number for logging
            method: Detection method used
            
        Returns:
            List of detected barcodes from first successful format group
        """
        for group in format_groups:
            barcodes = self.decode_with_formats(image, group, try_harder=True)
            
            if barcodes:
                # Add page and method info
                for barcode in barcodes:
                    barcode['page'] = page_num
                    barcode['method'] = method
                    barcode['source'] = 'embedded-image' if 'pymupdf' in method else 'rasterized-page'
                    barcode['dpi'] = 300 if 'enhanced' in method else 150  # Estimate DPI based on method
                
                # Choose best barcode(s) if multiple found in this group
                selected_barcodes = self._choose_best_barcodes(barcodes)
                
                logger.debug(f"📱 Found {len(selected_barcodes)} barcode(s) on page {page_num} with format group {group}")
                return selected_barcodes
        
        logger.debug(f"📱 No barcodes found on page {page_num} with any format group")
        return []
    
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
    
    def _preprocess_for_barcode_detection(self, image: np.ndarray) -> Dict[str, np.ndarray]:
        """Apply various preprocessing techniques for better barcode detection.
        
        Args:
            image: Original OpenCV image
            
        Returns:
            Dictionary of processed images with method names
        """
        processed = {}
        
        # Convert to grayscale first
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        processed['grayscale'] = gray
        
        # Otsu thresholding
        try:
            _, otsu_thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            processed['otsu'] = otsu_thresh
        except Exception:
            pass
        
        # Light unsharp mask
        try:
            gaussian = cv2.GaussianBlur(gray, (3, 3), 1.0)
            unsharp = cv2.addWeighted(gray, 1.5, gaussian, -0.5, 0)
            processed['unsharp'] = unsharp
        except Exception:
            pass
        
        # Simple deskew attempt (basic rotation detection)
        try:
            deskewed = self._simple_deskew(gray)
            if deskewed is not None:
                processed['deskewed'] = deskewed
        except Exception:
            pass
        
        return processed
    
    def _simple_deskew(self, image: np.ndarray) -> Optional[np.ndarray]:
        """Simple deskew using Hough line detection.
        
        Args:
            image: Grayscale image
            
        Returns:
            Deskewed image or None if deskewing fails
        """
        try:
            # Edge detection
            edges = cv2.Canny(image, 50, 150, apertureSize=3)
            
            # Hough line detection
            lines = cv2.HoughLines(edges, 1, np.pi/180, threshold=100)
            
            if lines is not None and len(lines) > 0:
                # Find the most common angle
                angles = []
                for rho, theta in lines[:10]:  # Use first 10 lines
                    angle = np.degrees(theta) - 90
                    angles.append(angle)
                
                # Use median angle
                if angles:
                    median_angle = np.median(angles)
                    
                    # Only rotate if angle is significant (> 1 degree)
                    if abs(median_angle) > 1:
                        h, w = image.shape[:2]
                        center = (w // 2, h // 2)
                        rotation_matrix = cv2.getRotationMatrix2D(center, median_angle, 1.0)
                        rotated = cv2.warpAffine(image, rotation_matrix, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
                        return rotated
            
        except Exception:
            pass
        
        return None
    
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
    
    def _calculate_center_distance(self, image: np.ndarray, rect) -> float:
        """Calculate distance from barcode center to image center.
        
        Args:
            image: OpenCV image array
            rect: Barcode rectangle
            
        Returns:
            Distance from barcode center to image center
        """
        img_height, img_width = image.shape[:2]
        img_center_x, img_center_y = img_width / 2, img_height / 2
        
        barcode_center_x = rect.left + rect.width / 2
        barcode_center_y = rect.top + rect.height / 2
        
        distance = math.sqrt((barcode_center_x - img_center_x) ** 2 + (barcode_center_y - img_center_y) ** 2)
        return distance
    
    def _choose_best_barcodes(self, barcodes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Choose the best barcode(s) from multiple candidates of the same format.
        
        Args:
            barcodes: List of barcodes of the same format
            
        Returns:
            List containing the best barcode(s)
        """
        if not barcodes:
            return []
        
        if len(barcodes) == 1:
            return barcodes
        
        # Sort by confidence (highest first), then by area (largest first), then by centrality (lowest distance first)
        sorted_barcodes = sorted(barcodes, key=lambda x: (
            -x.get('confidence', 0),     # Higher confidence first (negative for descending)
            -x.get('area', 0),           # Larger area first (negative for descending)
            x.get('center_distance', float('inf'))  # Lower distance first (ascending)
        ))
        
        # For now, return only the best one. In the future, this could be enhanced to return
        # multiple barcodes if they have significantly different content
        return [sorted_barcodes[0]]
    
    def _handle_mixed_aztec_qr(self, all_barcodes: List[Dict[str, Any]], filename: str = "") -> List[Dict[str, Any]]:
        """Handle special case where both Aztec and QR codes are present.
        
        Args:
            all_barcodes: List of all detected barcodes from all methods
            filename: PDF filename for context hints
            
        Returns:
            List with preferred barcode(s)
        """
        if not all_barcodes:
            return []
        
        # Separate Aztec and QR codes
        aztec_codes = [bc for bc in all_barcodes if bc['type'] == 'AZTEC']
        qr_codes = [bc for bc in all_barcodes if bc['type'] == 'QRCODE']
        others = [bc for bc in all_barcodes if bc['type'] not in ['AZTEC', 'QRCODE']]
        
        # If both Aztec and QR are present, apply preference logic
        if aztec_codes and qr_codes:
            filename_lower = filename.lower()
            
            # Check for context hints that prefer Aztec
            aztec_hints = ['aztec', 'billet', 'ticket', 'pass', 'code']
            has_aztec_hint = any(hint in filename_lower for hint in aztec_hints)
            
            if has_aztec_hint:
                logger.info(f"📍 Preferring Aztec code due to filename context: {filename}")
                return aztec_codes + others
            else:
                # Choose based on largest area
                best_aztec = max(aztec_codes, key=lambda x: x.get('area', 0))
                best_qr = max(qr_codes, key=lambda x: x.get('area', 0))
                
                if best_aztec.get('area', 0) >= best_qr.get('area', 0):
                    logger.info(f"📍 Preferring Aztec code due to larger area")
                    return aztec_codes + others
                else:
                    logger.info(f"📍 Preferring QR code due to larger area")
                    return qr_codes + others
        
        # Default case: return all barcodes (ordered detection already handled this)
        return all_barcodes
    
    
    def _infer_barcode_type_from_content(self, data: str, filename: str) -> str:
        """Infer the likely barcode type from content and context.
        
        Args:
            data: Barcode data content
            filename: PDF filename for context hints
            
        Returns:
            Inferred barcode type
        """
        if not data:
            return 'QRCODE'
        
        # Check filename for Aztec hints
        filename_lower = filename.lower()
        aztec_hints = ['aztec', 'billet', 'ticket', 'pass']
        
        if any(hint in filename_lower for hint in aztec_hints):
            logger.info(f"🎯 Inferring AZTEC type due to filename hint: {filename}")
            return 'AZTEC'
        
        # Check content characteristics that might suggest Aztec vs QR
        # Aztec codes often contain structured data for tickets/passes
        if any(keyword in data.lower() for keyword in ['ticket', 'boarding', 'seat', 'flight', 'train', 'event']):
            logger.info(f"🎯 Inferring AZTEC type due to content keywords: {data[:50]}...")
            return 'AZTEC'
        
        # Long alphanumeric strings might be Aztec (common for tickets)
        if len(data) > 20 and any(c.isalpha() for c in data) and any(c.isdigit() for c in data):
            logger.info(f"🎯 Inferring AZTEC type due to long alphanumeric content")
            return 'AZTEC'
        
        # Default to QR for general purpose
        return 'QRCODE'
    
    def _deduplicate_barcodes(self, barcodes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Remove duplicate barcodes based on data content.
        
        Args:
            barcodes: List of detected barcodes
            
        Returns:
            Deduplicated list with highest confidence barcodes
        """
        if not barcodes:
            return barcodes
        
        # Group by exact payload bytes (hex) to avoid collapsing distinct payloads
        # Remove page from grouping key to create one pass per unique barcode content
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for barcode in barcodes:
            raw_bytes: Optional[bytes] = barcode.get('raw_bytes')  # type: ignore
            payload_key = raw_bytes.hex() if isinstance(raw_bytes, (bytes, bytearray)) else str(barcode.get('data'))
            grouped.setdefault(payload_key, []).append(barcode)

        result: List[Dict[str, Any]] = []
        for payload_key, group in grouped.items():
            # For each unique barcode payload, keep only the highest confidence instance
            # Sort by confidence and pick the best one
            group.sort(key=lambda x: x.get('confidence', 0), reverse=True)
            best = group[0]
            
            # Add metadata about how many instances were found
            best['detection_count'] = len(group)
            best['methods_used'] = list(set(bc.get('method', 'unknown') for bc in group))
            
            # Add pages where this barcode was found
            pages_found = sorted(list(set(bc.get('page', 1) for bc in group)))
            best['pages_found'] = pages_found
            
            result.append(best)
        
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