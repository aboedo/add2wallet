#!/usr/bin/env python3
"""
Test the enhanced barcode consolidation logic.
"""

import os
import sys

# Add the project root to the path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def test_consolidation_scenarios():
    """Test different consolidation scenarios."""
    print("🧪 Testing Barcode Consolidation Logic")
    print("=" * 50)
    
    from app.services.pass_generator import PassGenerator
    
    generator = PassGenerator()
    
    # Test Scenario 1: Duplicate identical barcodes (user's feedback scenario)
    print("\n📋 Scenario 1: Duplicate Identical QR Codes")
    print("-" * 30)
    
    duplicate_barcodes = [
        {
            'data': 'ABC123456789',
            'type': 'QRCODE',
            'source': 'text-analysis',
            'method': 'text_extraction_text_alphanumeric',
            'confidence': 75
        },
        {
            'data': 'ABC123456789',  # Identical data
            'type': 'QRCODE',
            'source': 'text-analysis',
            'method': 'text_extraction_text_alphanumeric',
            'confidence': 75
        }
    ]
    
    result = generator._consolidate_barcodes_for_single_pass(duplicate_barcodes, "data_matrix_ticket.pdf")
    print(f"Result: {len(result)} barcode(s)")
    if result:
        print(f"Selected: {result[0]['data']}, Method: {result[0].get('consolidation_method', 'none')}")
    
    # Test Scenario 2: Different Data Matrix codes (should consolidate by filename)
    print("\n📋 Scenario 2: Multiple Data Matrix Codes")
    print("-" * 30)
    
    datamatrix_barcodes = [
        {
            'data': '75930340250900',
            'type': 'DATAMATRIX',
            'source': 'text-analysis',
            'method': 'text_extraction_text_numeric',
            'confidence': 75
        },
        {
            'data': '2412061957820407849',
            'type': 'DATAMATRIX',
            'source': 'text-analysis',
            'method': 'text_extraction_text_numeric',
            'confidence': 75
        }
    ]
    
    result = generator._consolidate_barcodes_for_single_pass(datamatrix_barcodes, "pass_with_data_matrix.pdf")
    print(f"Result: {len(result)} barcode(s)")
    if result:
        print(f"Selected: {result[0]['data']}, Method: {result[0].get('consolidation_method', 'none')}")
    
    # Test Scenario 3: QR codes with datamatrix filename (should reclassify)
    print("\n📋 Scenario 3: QR Codes with DataMatrix Filename")
    print("-" * 30)
    
    qr_as_datamatrix = [
        {
            'data': 'MATRIX_CODE_12345',
            'type': 'QRCODE',
            'source': 'text-analysis',
            'method': 'text_extraction_text_alphanumeric',
            'confidence': 80
        },
        {
            'data': 'MATRIX_CODE_67890',
            'type': 'QRCODE',
            'source': 'text-analysis',
            'method': 'text_extraction_text_alphanumeric',
            'confidence': 75
        }
    ]
    
    result = generator._consolidate_barcodes_for_single_pass(qr_as_datamatrix, "datamatrix_boarding_pass.pdf")
    print(f"Result: {len(result)} barcode(s)")
    if result:
        print(f"Selected: {result[0]['data']}")
        print(f"Type: {result[0]['type']} (was: {result[0].get('original_type', 'N/A')})")
        print(f"Method: {result[0].get('consolidation_method', 'none')}")
        print(f"Reclassified: {result[0].get('reclassified', False)}")
    
    # Test Scenario 4: Multiple different types (should not consolidate)
    print("\n📋 Scenario 4: Mixed Barcode Types (No Consolidation)")
    print("-" * 30)
    
    mixed_barcodes = [
        {
            'data': 'QR_DATA_123',
            'type': 'QRCODE',
            'source': 'visual-detection',
            'method': 'standard',
            'confidence': 90
        },
        {
            'data': 'AZTEC_DATA_456',
            'type': 'AZTEC',
            'source': 'visual-detection',
            'method': 'standard',
            'confidence': 85
        }
    ]
    
    result = generator._consolidate_barcodes_for_single_pass(mixed_barcodes, "multi_ticket.pdf")
    print(f"Result: {len(result)} barcode(s) (should be 2 - no consolidation)")
    
    # Test Scenario 5: Visual beats text (should prefer visual)
    print("\n📋 Scenario 5: Visual Detection Priority")
    print("-" * 30)
    
    mixed_sources = [
        {
            'data': 'VISUAL_BARCODE',
            'type': 'QRCODE',
            'source': 'visual-detection',
            'method': 'standard',
            'confidence': 95
        },
        {
            'data': 'TEXT_BARCODE_1',
            'type': 'DATAMATRIX',
            'source': 'text-analysis',
            'method': 'text_extraction',
            'confidence': 75
        },
        {
            'data': 'TEXT_BARCODE_2',
            'type': 'DATAMATRIX',
            'source': 'text-analysis',
            'method': 'text_extraction',
            'confidence': 75
        }
    ]
    
    result = generator._consolidate_barcodes_for_single_pass(mixed_sources, "ticket.pdf")
    print(f"Result: {len(result)} barcode(s)")
    if result:
        print(f"Selected: {result[0]['data']} (source: {result[0]['source']})")

if __name__ == "__main__":
    test_consolidation_scenarios()
    
    print("\n" + "=" * 50)
    print("📊 CONSOLIDATION TEST SUMMARY")
    print("=" * 50)
    print("✅ All consolidation scenarios tested")
    print("🎯 The logic should now handle:")
    print("   1. Duplicate identical barcodes → Single pass")
    print("   2. Multiple Data Matrix codes → Single pass (longest)")
    print("   3. QR codes in datamatrix file → Reclassify & consolidate")
    print("   4. Mixed types → No consolidation")
    print("   5. Visual + text → Prefer visual")