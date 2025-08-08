"""Tests for Aztec code logic without external dependencies."""

import sys
import os
import unittest
from unittest.mock import Mock, patch

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestAztecLogic(unittest.TestCase):
    """Test Aztec code detection logic without requiring pyzbar/opencv."""
    
    def setUp(self):
        """Set up test fixtures."""
        # Mock the external dependencies to avoid import errors
        self.pyzbar_mock = Mock()
        self.cv2_mock = Mock()
        self.np_mock = Mock()
        
        # Patch imports before importing our module
        self.patches = [
            patch('app.services.barcode_extractor.pyzbar', self.pyzbar_mock),
            patch('app.services.barcode_extractor.cv2', self.cv2_mock),
            patch('app.services.barcode_extractor.np', self.np_mock),
        ]
        
        for p in self.patches:
            p.start()
        
        # Now import after patching
        from app.services.barcode_extractor import BarcodeExtractor
        self.extractor = BarcodeExtractor()
    
    def tearDown(self):
        """Clean up patches."""
        for p in self.patches:
            p.stop()
    
    def test_format_groups_order(self):
        """Test that format groups are in correct order for Aztec precedence."""
        # Aztec should be first
        self.assertEqual(self.extractor.format_groups[0], {'AZTEC'})
        
        # QR should be second
        self.assertEqual(self.extractor.format_groups[1], {'QRCODE'})
        
        # 1D codes should be third
        one_d_group = self.extractor.format_groups[2]
        self.assertIn('CODE128', one_d_group)
        self.assertIn('PDF417', one_d_group)
        self.assertIn('EAN13', one_d_group)
    
    def test_mixed_aztec_qr_filename_hint(self):
        """Test mixed handling with filename hints."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 500}
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 1000}
        other_code = {'type': 'CODE128', 'data': 'code128_data', 'area': 300}
        
        barcodes = [aztec_code, qr_code, other_code]
        
        # Test with Aztec hint in filename
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "ticket_aztec_123.pdf")
        
        # Should return Aztec + others, no QR
        self.assertEqual(len(result), 2)
        types = [bc['type'] for bc in result]
        self.assertIn('AZTEC', types)
        self.assertIn('CODE128', types)
        self.assertNotIn('QRCODE', types)
    
    def test_mixed_aztec_qr_billet_hint(self):
        """Test mixed handling with billet hint."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 500}
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 1000}
        
        barcodes = [aztec_code, qr_code]
        
        # Test with billet hint (French for ticket)
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "billet_train.pdf")
        
        # Should prefer Aztec despite smaller area
        types = [bc['type'] for bc in result]
        self.assertIn('AZTEC', types)
        self.assertNotIn('QRCODE', types)
    
    def test_mixed_aztec_qr_area_preference(self):
        """Test mixed handling with area preference."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 1200}  # Larger
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 800}
        
        barcodes = [aztec_code, qr_code]
        
        # Test with no hint - should prefer larger Aztec
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "document.pdf")
        
        types = [bc['type'] for bc in result]
        self.assertIn('AZTEC', types)
        self.assertNotIn('QRCODE', types)
    
    def test_mixed_aztec_qr_prefer_larger_qr(self):
        """Test mixed handling preferring larger QR."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 600}
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 1200}  # Larger
        
        barcodes = [aztec_code, qr_code]
        
        # Test with no hint - should prefer larger QR
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "document.pdf")
        
        types = [bc['type'] for bc in result]
        self.assertIn('QRCODE', types)
        self.assertNotIn('AZTEC', types)
    
    def test_choose_best_barcodes_confidence(self):
        """Test barcode selection by confidence."""
        barcodes = [
            {'confidence': 70, 'area': 1000, 'center_distance': 100, 'data': 'low_confidence'},
            {'confidence': 90, 'area': 500, 'center_distance': 50, 'data': 'high_confidence'},
            {'confidence': 90, 'area': 1200, 'center_distance': 75, 'data': 'high_conf_large'}
        ]
        
        result = self.extractor._choose_best_barcodes(barcodes)
        self.assertEqual(len(result), 1)
        # Should pick highest confidence with largest area
        self.assertEqual(result[0]['data'], 'high_conf_large')
    
    def test_choose_best_barcodes_area_tiebreaker(self):
        """Test barcode selection by area when confidence is equal."""
        barcodes = [
            {'confidence': 80, 'area': 500, 'center_distance': 50, 'data': 'small'},
            {'confidence': 80, 'area': 1200, 'center_distance': 75, 'data': 'large'}
        ]
        
        result = self.extractor._choose_best_barcodes(barcodes)
        self.assertEqual(len(result), 1)
        # Should pick larger area
        self.assertEqual(result[0]['data'], 'large')
    
    def test_choose_best_barcodes_centrality_tiebreaker(self):
        """Test barcode selection by centrality when confidence and area are equal."""
        barcodes = [
            {'confidence': 80, 'area': 1000, 'center_distance': 100, 'data': 'far'},
            {'confidence': 80, 'area': 1000, 'center_distance': 50, 'data': 'near'}
        ]
        
        result = self.extractor._choose_best_barcodes(barcodes)
        self.assertEqual(len(result), 1)
        # Should pick more central (lower distance)
        self.assertEqual(result[0]['data'], 'near')
    
    def test_normalize_barcode_format_aztec(self):
        """Test Aztec format normalization for Apple Wallet."""
        result = self.extractor._normalize_barcode_format('AZTEC')
        self.assertEqual(result, 'PKBarcodeFormatAztec')
    
    def test_normalize_barcode_format_qr(self):
        """Test QR format normalization for Apple Wallet."""
        result = self.extractor._normalize_barcode_format('QRCODE')
        self.assertEqual(result, 'PKBarcodeFormatQR')
    
    def test_normalize_barcode_format_code128(self):
        """Test Code128 format normalization for Apple Wallet."""
        result = self.extractor._normalize_barcode_format('CODE128')
        self.assertEqual(result, 'PKBarcodeFormatCode128')
    
    def test_handle_no_barcodes(self):
        """Test handling of empty barcode list."""
        result = self.extractor._handle_mixed_aztec_qr([], "test.pdf")
        self.assertEqual(result, [])
    
    def test_handle_only_aztec(self):
        """Test handling when only Aztec codes are present."""
        aztec_code = {'type': 'AZTEC', 'data': 'aztec_data', 'area': 500}
        other_code = {'type': 'CODE128', 'data': 'code128_data', 'area': 300}
        
        barcodes = [aztec_code, other_code]
        
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "test.pdf")
        # Should return all barcodes unchanged
        self.assertEqual(len(result), 2)
        self.assertEqual(result, barcodes)
    
    def test_handle_only_qr(self):
        """Test handling when only QR codes are present."""
        qr_code = {'type': 'QRCODE', 'data': 'qr_data', 'area': 1000}
        other_code = {'type': 'CODE128', 'data': 'code128_data', 'area': 300}
        
        barcodes = [qr_code, other_code]
        
        result = self.extractor._handle_mixed_aztec_qr(barcodes, "test.pdf")
        # Should return all barcodes unchanged
        self.assertEqual(len(result), 2)
        self.assertEqual(result, barcodes)
    
    def test_calculate_confidence_aztec(self):
        """Test confidence calculation for Aztec codes."""
        mock_barcode = Mock()
        mock_barcode.type = 'AZTEC'
        mock_barcode.data = b'long_data_string_for_testing'
        
        confidence = self.extractor._calculate_confidence(mock_barcode)
        
        # Should get base (70) + high confidence format (20) + long data (10) = 100
        self.assertEqual(confidence, 100)
    
    def test_calculate_confidence_short_data(self):
        """Test confidence calculation for short data."""
        mock_barcode = Mock()
        mock_barcode.type = 'CODE39'
        mock_barcode.data = b'short'
        
        confidence = self.extractor._calculate_confidence(mock_barcode)
        
        # Should get base confidence only (70)
        self.assertEqual(confidence, 70)


def run_logic_tests():
    """Run the logic tests and print results."""
    print("🧪 Running Aztec Code Logic Tests (No External Dependencies)")
    print("=" * 60)
    
    # Discover and run tests
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestAztecLogic)
    
    # Run tests with verbose output
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    print("\n" + "=" * 60)
    print("📊 TEST RESULTS")
    print("=" * 60)
    
    if result.wasSuccessful():
        print("🎉 All logic tests passed!")
        print(f"✅ {result.testsRun} tests passed")
    else:
        print("⚠️  Some logic tests failed")
        print(f"❌ {len(result.failures)} failures, {len(result.errors)} errors")
        
        if result.failures:
            print("\nFailures:")
            for test, failure in result.failures:
                print(f"  - {test}: {failure}")
        
        if result.errors:
            print("\nErrors:")
            for test, error in result.errors:
                print(f"  - {test}: {error}")
    
    return result.wasSuccessful()


if __name__ == "__main__":
    success = run_logic_tests()
    exit(0 if success else 1)