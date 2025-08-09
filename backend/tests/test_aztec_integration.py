"""Integration tests for Data Matrix code detection in PDF files."""

import sys
import os
import logging

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Configure logging to see debug output
logging.basicConfig(level=logging.DEBUG)


def test_data_matrix_pdf_detection():
    """Test Data Matrix code detection with the provided test PDF."""
    try:
        from app.services.barcode_extractor import barcode_extractor
        
        test_file_path = os.path.join(os.path.dirname(__file__), '..', 'test_files', 'pass_with_data_matrix.pdf')
        test_file_path = os.path.abspath(test_file_path)
        
        print(f"🔍 Testing Data Matrix detection with: {test_file_path}")
        
        if not os.path.exists(test_file_path):
            print(f"❌ Test file not found at: {test_file_path}")
            return False
            
        with open(test_file_path, 'rb') as f:
            pdf_data = f.read()
        
        print(f"📄 PDF file size: {len(pdf_data)} bytes")
        
        # Extract barcodes using Data Matrix-compatible logic
        result = barcode_extractor.extract_barcodes_from_pdf(pdf_data, "pass_with_data_matrix.pdf")
        
        print(f"✅ Found {len(result)} barcode(s):")
        
        datamatrix_found = False
        for i, bc in enumerate(result, 1):
            barcode_type = bc.get('type', 'unknown')
            barcode_format = bc.get('format', 'unknown') 
            barcode_data = bc.get('data', 'unknown')
            encoding = bc.get('encoding', 'unknown')
            method = bc.get('method', 'unknown')
            confidence = bc.get('confidence', 'unknown')
            source = bc.get('source', 'unknown')
            dpi = bc.get('dpi', 'unknown')
            
            print(f"  {i}. Type: {barcode_type}")
            print(f"     Format: {barcode_format}")
            print(f"     Data: {barcode_data[:100]}{'...' if len(barcode_data) > 100 else ''}")
            print(f"     Encoding: {encoding}")
            print(f"     Method: {method}")
            print(f"     Source: {source}")
            print(f"     DPI: {dpi}")
            print(f"     Confidence: {confidence}")
            
            if 'bytes_b64' in bc:
                print(f"     Base64 length: {len(bc['bytes_b64'])}")
            if 'bbox' in bc:
                print(f"     BBox: {bc['bbox']}")
            print()
            
            if barcode_type == 'DATAMATRIX':
                datamatrix_found = True
                print("🎯 ✅ DATA MATRIX CODE DETECTED!")
        
        if not datamatrix_found:
            print("⚠️  No Data Matrix codes found - checking if QR was detected instead")
            qr_found = any(bc.get('type') == 'QRCODE' for bc in result)
            if qr_found:
                print("📱 QR code was found - this indicates Data Matrix might be misidentified")
        
        return len(result) > 0 and datamatrix_found
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
        print("💡 Make sure all dependencies are installed (pyzbar, opencv, etc.)")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_format_precedence():
    """Test that format precedence works correctly."""
    try:
        from app.services.barcode_extractor import BarcodeExtractor
        
        extractor = BarcodeExtractor()
        
        print("🔧 Testing format precedence...")
        print(f"Format groups: {extractor.format_groups}")
        
        # Verify format order: Aztec -> Data Matrix -> QR -> 1D codes
        assert extractor.format_groups[0] == {'AZTEC'}, "Aztec should be first format group"
        assert extractor.format_groups[1] == {'DATAMATRIX'}, "Data Matrix should be second format group"
        assert extractor.format_groups[2] == {'QRCODE'}, "QR should be third format group"
        assert 'CODE128' in extractor.format_groups[3], "1D codes should be in fourth group"
        
        print("✅ Format precedence is correct")
        return True
        
    except Exception as e:
        print(f"❌ Format precedence test failed: {e}")
        return False


def test_encoding_handling():
    """Test encoding detection capabilities."""
    try:
        from app.services.barcode_extractor import BarcodeExtractor
        import numpy as np
        
        extractor = BarcodeExtractor()
        
        # Create a mock image for testing
        test_image = np.zeros((100, 100, 3), dtype=np.uint8)
        
        print("🔧 Testing encoding handling...")
        
        # Test with empty result for different formats (should not crash)
        for format_type in ['AZTEC', 'DATAMATRIX', 'QRCODE']:
            result = extractor.decode_with_formats(test_image, {format_type})
            print(f"Empty image test for {format_type}: {len(result)} results")
        
        print("✅ Encoding handling works")
        return True
        
    except Exception as e:
        print(f"❌ Encoding test failed: {e}")
        return False


def run_all_tests():
    """Run all integration tests."""
    print("🚀 Starting Data Matrix Code Integration Tests")
    print("=" * 50)
    
    tests = [
        ("Format Precedence", test_format_precedence),
        ("Encoding Handling", test_encoding_handling), 
        ("Data Matrix PDF Detection", test_data_matrix_pdf_detection),
    ]
    
    results = []
    for test_name, test_func in tests:
        print(f"\n📋 Running: {test_name}")
        print("-" * 30)
        try:
            success = test_func()
            results.append((test_name, success))
            status = "✅ PASSED" if success else "❌ FAILED"
            print(f"Result: {status}")
        except Exception as e:
            print(f"❌ ERROR: {e}")
            results.append((test_name, False))
    
    print("\n" + "=" * 50)
    print("📊 TEST SUMMARY")
    print("=" * 50)
    
    passed = sum(1 for _, success in results if success)
    total = len(results)
    
    for test_name, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}")
    
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed!")
    else:
        print("⚠️  Some tests failed - check implementation")
    
    return passed == total


if __name__ == "__main__":
    success = run_all_tests()
    exit(0 if success else 1)