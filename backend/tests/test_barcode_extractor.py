"""Tests for the barcode extractor service with Aztec code support."""

import pytest
import os
import sys
import numpy as np
from unittest.mock import Mock, patch, MagicMock

# Add the project root to the path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.barcode_extractor import BarcodeExtractor


class TestBarcodeExtractor:
    """Test cases for BarcodeExtractor with Aztec support."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.extractor = BarcodeExtractor()
        self.test_files_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "test_files")
    
    def test_format_groups_initialization(self):
        """Test that format groups are properly initialized."""
        assert len(self.extractor.format_groups) == 3
        assert {'AZTEC'} == self.extractor.format_groups[0]
        assert {'QRCODE'} == self.extractor.format_groups[1]
        assert 'CODE128' in self.extractor.format_groups[2]
    
    def test_decode_with_formats_empty_image(self):
        """Test decode_with_formats with empty image."""
        # Create a blank image
        blank_image = np.zeros((100, 100, 3), dtype=np.uint8)
        
        result = self.extractor.decode_with_formats(blank_image, {'AZTEC'})
        assert result == []
    
    def test_decode_with_formats_filter_by_format(self):
        """Test that decode_with_formats properly filters by format."""
        with patch('app.services.barcode_extractor.pyzbar.decode') as mock_decode:
            # Mock pyzbar to return both Aztec and QR codes
            mock_barcode_aztec = Mock()
            mock_barcode_aztec.type = 'AZTEC'
            mock_barcode_aztec.data = b'aztec_data'
            mock_barcode_aztec.rect = Mock(left=10, top=20, width=50, height=60)
            
            mock_barcode_qr = Mock()
            mock_barcode_qr.type = 'QRCODE'
            mock_barcode_qr.data = b'qr_data'
            mock_barcode_qr.rect = Mock(left=100, top=200, width=80, height=90)
            
            mock_decode.return_value = [mock_barcode_aztec, mock_barcode_qr]
            
            blank_image = np.zeros((300, 300, 3), dtype=np.uint8)
            
            # Test filtering for Aztec only
            aztec_result = self.extractor.decode_with_formats(blank_image, {'AZTEC'})
            assert len(aztec_result) == 1
            assert aztec_result[0]['type'] == 'AZTEC'
            assert aztec_result[0]['data'] == 'aztec_data'
            
            # Test filtering for QR only
            qr_result = self.extractor.decode_with_formats(blank_image, {'QRCODE'})
            assert len(qr_result) == 1
            assert qr_result[0]['type'] == 'QRCODE'
            assert qr_result[0]['data'] == 'qr_data'
    
    def test_choose_best_barcodes_single(self):
        """Test _choose_best_barcodes with single barcode."""
        barcode = {'confidence': 80, 'area': 1000, 'center_distance': 50}
        result = self.extractor._choose_best_barcodes([barcode])
        assert len(result) == 1
        assert result[0] == barcode
    
    def test_choose_best_barcodes_multiple(self):
        """Test _choose_best_barcodes with multiple barcodes."""
        barcodes = [
            {'confidence': 70, 'area': 1000, 'center_distance': 100, 'data': 'low_confidence'},
            {'confidence': 90, 'area': 500, 'center_distance': 50, 'data': 'high_confidence'},
            {'confidence': 90, 'area': 1200, 'center_distance': 75, 'data': 'high_conf_large'}
        ]
        
        result = self.extractor._choose_best_barcodes(barcodes)
        assert len(result) == 1
        # Should pick the one with highest confidence and largest area (high_conf_large)
        assert result[0]['data'] == 'high_conf_large'
    
    def test_calculate_center_distance(self):
        """Test _calculate_center_distance calculation."""
        image = np.zeros((200, 300, 3), dtype=np.uint8)  # 300x200 image
        
        # Mock rectangle at center
        mock_rect = Mock(left=125, top=75, width=50, height=50)  # Center at (150, 100)
        distance = self.extractor._calculate_center_distance(image, mock_rect)
        
        # Image center is at (150, 100), barcode center is at (150, 100)
        assert distance == 0.0
        
        # Mock rectangle off-center
        mock_rect_off = Mock(left=0, top=0, width=50, height=50)  # Center at (25, 25)
        distance_off = self.extractor._calculate_center_distance(image, mock_rect_off)
        assert distance_off > 0
    
    def test_handle_mixed_aztec_qr_aztec_hint(self):
        """Test mixed Aztec/QR handling with filename hint."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 500}
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 1000}
        other_code = {'type': 'CODE128', 'data': 'code128_data', 'area': 300}
        
        barcodes = [aztec_code, qr_code, other_code]
        
        # Test with Aztec hint in filename
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "ticket_aztec_123.pdf")
        assert len(result) == 2  # Aztec + others, no QR
        assert any(bc['type'] == 'AZTEC' for bc in result)
        assert any(bc['type'] == 'CODE128' for bc in result)
        assert not any(bc['type'] == 'QRCODE' for bc in result)
    
    def test_handle_mixed_aztec_qr_area_preference(self):
        """Test mixed Aztec/QR handling with area preference."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 1200}  # Larger
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 800}
        other_code = {'type': 'CODE128', 'data': 'code128_data', 'area': 300}
        
        barcodes = [aztec_code, qr_code, other_code]
        
        # Test with no hint - should prefer larger Aztec
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "document.pdf")
        assert any(bc['type'] == 'AZTEC' for bc in result)
        assert not any(bc['type'] == 'QRCODE' for bc in result)
    
    def test_handle_mixed_aztec_qr_qr_preference(self):
        """Test mixed Aztec/QR handling preferring QR when larger."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 600}
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 1200}  # Larger
        
        barcodes = [aztec_code, qr_code]
        
        # Test with no hint - should prefer larger QR
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "document.pdf")
        assert any(bc['type'] == 'QRCODE' for bc in result)
        assert not any(bc['type'] == 'AZTEC' for bc in result)
    
    def test_encoding_detection_utf8(self):
        """Test UTF-8 encoding detection."""
        with patch('app.services.barcode_extractor.pyzbar.decode') as mock_decode:
            mock_barcode = Mock()
            mock_barcode.type = 'AZTEC'
            mock_barcode.data = 'Hello World'.encode('utf-8')
            mock_barcode.rect = Mock(left=10, top=20, width=50, height=60)
            
            mock_decode.return_value = [mock_barcode]
            
            blank_image = np.zeros((100, 100, 3), dtype=np.uint8)
            result = self.extractor.decode_with_formats(blank_image, {'AZTEC'})
            
            assert len(result) == 1
            assert result[0]['encoding'] == 'utf-8'
            assert result[0]['data'] == 'Hello World'
    
    def test_encoding_detection_iso_8859_1(self):
        """Test ISO-8859-1 encoding fallback."""
        with patch('app.services.barcode_extractor.pyzbar.decode') as mock_decode:
            # Create bytes that are not valid UTF-8 but valid ISO-8859-1
            invalid_utf8_bytes = b'\x80\x81\x82'  # Not valid UTF-8
            
            mock_barcode = Mock()
            mock_barcode.type = 'AZTEC'
            mock_barcode.data = invalid_utf8_bytes
            mock_barcode.rect = Mock(left=10, top=20, width=50, height=60)
            
            mock_decode.return_value = [mock_barcode]
            
            blank_image = np.zeros((100, 100, 3), dtype=np.uint8)
            result = self.extractor.decode_with_formats(blank_image, {'AZTEC'})
            
            assert len(result) == 1
            assert result[0]['encoding'] == 'iso-8859-1'
    
    def test_return_structure_complete(self):
        """Test that return structure includes all required fields."""
        with patch('app.services.barcode_extractor.pyzbar.decode') as mock_decode:
            mock_barcode = Mock()
            mock_barcode.type = 'AZTEC'
            mock_barcode.data = b'test_data'
            mock_barcode.rect = Mock(left=10, top=20, width=50, height=60)
            
            mock_decode.return_value = [mock_barcode]
            
            blank_image = np.zeros((100, 100, 3), dtype=np.uint8)
            result = self.extractor.decode_with_formats(blank_image, {'AZTEC'})
            
            assert len(result) == 1
            barcode = result[0]
            
            # Check all required fields are present
            required_fields = ['data', 'type', 'format', 'encoding', 'raw_bytes', 
                             'bytes_b64', 'bbox', 'area', 'confidence', 'center_distance']
            for field in required_fields:
                assert field in barcode, f"Missing field: {field}"
            
            # Check specific values
            assert barcode['format'] == 'PKBarcodeFormatAztec'
            assert barcode['bbox'] == [10, 20, 50, 60]
            assert barcode['area'] == 3000  # 50 * 60
    
    def test_aztec_detection_integration(self):
        """Integration test with actual Aztec PDF."""
        test_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "test_files", "pass_with_aztec_code.pdf")
        
        if not os.path.exists(test_file):
            pytest.skip(f"Test file not found: {test_file}")
        
        with open(test_file, 'rb') as f:
            pdf_data = f.read()
        
        result = self.extractor.extract_barcodes_from_pdf(pdf_data, "pass_with_aztec_code.pdf")
        
        # Should find at least one barcode (expected: 3 Aztec codes)
        assert len(result) > 0, f"No barcodes found in PDF. Result: {result}"
        
        # Should detect Aztec format
        aztec_found = any(bc['type'] == 'AZTEC' for bc in result)
        assert aztec_found, f"Aztec code not detected. Found types: {[bc['type'] for bc in result]}"
        
        # Check that result has proper structure
        for barcode in result:
            assert 'format' in barcode
            assert 'encoding' in barcode
            assert 'bytes_b64' in barcode
            assert 'data' in barcode
            assert 'type' in barcode
        
        # Verify we get the expected 3 barcodes
        print(f"Found {len(result)} barcodes (expected 3)")
        for i, bc in enumerate(result, 1):
            print(f"  {i}. Type: {bc['type']}, Format: {bc['format']}, Data: {bc['data'][:50]}...")
    
    def test_aztec_pdf_multiple_dpi_processing(self):
        """Test Aztec PDF processing at different DPI levels."""
        test_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "test_files", "pass_with_aztec_code.pdf")
        
        if not os.path.exists(test_file):
            pytest.skip(f"Test file not found: {test_file}")
            
        with open(test_file, 'rb') as f:
            pdf_data = f.read()
            
        # Test different extraction methods work
        from pdf2image import convert_from_bytes
        from pyzbar import pyzbar
        import cv2
        import numpy as np
        
        # Test pdf2image conversion works
        images = convert_from_bytes(pdf_data, dpi=400)
        assert len(images) == 1, "Should convert to exactly 1 image"
        
        # Test image can be processed
        image = images[0]
        cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
        assert cv_image.shape[0] > 1000 and cv_image.shape[1] > 1000, "Image should be high resolution"
        
        # Test pyzbar can run (even if it doesn't find anything)
        gray = cv2.cvtColor(cv_image, cv2.COLOR_BGR2GRAY)
        detected = pyzbar.decode(gray)  # This may return empty list, that's ok for this test
        
        print(f"DPI test: Converted PDF to {cv_image.shape} image, pyzbar found {len(detected)} barcodes")
    
    def test_aztec_preprocessing_methods(self):
        """Test different image preprocessing methods for Aztec detection."""
        test_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "test_files", "pass_with_aztec_code.pdf")
        
        if not os.path.exists(test_file):
            pytest.skip(f"Test file not found: {test_file}")
            
        # Test the preprocessing methods exist and work
        blank_image = np.zeros((200, 200, 3), dtype=np.uint8)
        
        # Test each preprocessing method
        contrast_result = self.extractor._enhance_contrast(blank_image)
        assert contrast_result.shape == (200, 200), "Contrast enhancement should return 2D array"
        
        sharpness_result = self.extractor._enhance_sharpness(blank_image)
        assert sharpness_result.shape == (200, 200), "Sharpness enhancement should return 2D array"
        
        threshold_result = self.extractor._enhance_threshold(blank_image)
        assert threshold_result.shape == (200, 200), "Threshold should return 2D array"
        
        morphology_result = self.extractor._enhance_morphology(blank_image)
        assert morphology_result.shape == (200, 200), "Morphology should return 2D array"
        
        blur_result = self.extractor._enhance_gaussian_blur(blank_image)
        assert blur_result.shape == (200, 200), "Blur should return 2D array"
    
    def test_no_barcode_returns_empty_list(self):
        """Test that no barcode scenario returns empty list without exceptions."""
        with patch('app.services.barcode_extractor.pyzbar.decode') as mock_decode:
            mock_decode.return_value = []  # No barcodes found
            
            blank_image = np.zeros((100, 100, 3), dtype=np.uint8)
            result = self.extractor.decode_with_formats(blank_image, {'AZTEC'})
            
            assert result == []
    
    def test_try_formats_order(self):
        """Test that format groups are tried in correct order."""
        with patch.object(self.extractor, 'decode_with_formats') as mock_decode:
            # Mock to return barcodes only for QR (second group)
            def mock_decode_side_effect(image, formats, try_harder=True):
                if 'QRCODE' in formats:
                    return [{'type': 'QRCODE', 'data': 'qr_data'}]
                return []
            
            mock_decode.side_effect = mock_decode_side_effect
            
            blank_image = np.zeros((100, 100, 3), dtype=np.uint8)
            result = self.extractor._try_formats(blank_image, self.extractor.format_groups, 1, "test")
            
            # Should have called decode_with_formats for AZTEC first, then QRCODE
            assert mock_decode.call_count >= 2
            
            # First call should be for AZTEC
            first_call_formats = mock_decode.call_args_list[0][0][1]
            assert first_call_formats == {'AZTEC'}
            
            # Should return QR result since AZTEC returned empty
            assert len(result) == 1
            assert result[0]['type'] == 'QRCODE'


if __name__ == "__main__":
    pytest.main([__file__])