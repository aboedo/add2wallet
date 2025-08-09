#!/usr/bin/env python3
"""
Comprehensive test to verify Data Matrix detection bug.
This test uploads the data matrix PDF through the full API pipeline
to confirm the bug: getting 2 QR passes instead of 1 Data Matrix pass.
"""

import os
import sys
import json
from pathlib import Path

# Add the project root to the path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def test_data_matrix_bug():
    """Test the full pipeline to confirm the Data Matrix bug."""
    print("🧪 Testing Data Matrix Bug Reproduction")
    print("=" * 60)
    
    # Step 1: Test barcode extraction directly
    print("\n📊 Step 1: Direct Barcode Extraction Test")
    print("-" * 40)
    
    try:
        from app.services.barcode_extractor import barcode_extractor
        
        test_file_path = Path(__file__).parent / "test_files" / "pass_with_data_matrix.pdf"
        
        if not test_file_path.exists():
            print(f"❌ Test file not found: {test_file_path}")
            return False
        
        with open(test_file_path, 'rb') as f:
            pdf_data = f.read()
        
        print(f"📄 PDF file size: {len(pdf_data)} bytes")
        
        # Extract barcodes
        result = barcode_extractor.extract_barcodes_from_pdf(pdf_data, "pass_with_data_matrix.pdf")
        
        print(f"✅ Found {len(result)} barcode(s):")
        
        qr_codes = []
        datamatrix_codes = []
        
        for i, bc in enumerate(result, 1):
            barcode_type = bc.get('type', 'unknown')
            barcode_format = bc.get('format', 'unknown')
            barcode_data = bc.get('data', 'unknown')
            method = bc.get('method', 'unknown')
            source = bc.get('source', 'unknown')
            
            print(f"  {i}. Type: {barcode_type}")
            print(f"     Format: {barcode_format}")
            print(f"     Data: {barcode_data[:50]}{'...' if len(barcode_data) > 50 else ''}")
            print(f"     Method: {method}")
            print(f"     Source: {source}")
            print()
            
            if barcode_type == 'QRCODE':
                qr_codes.append(bc)
            elif barcode_type == 'DATAMATRIX':
                datamatrix_codes.append(bc)
        
        print(f"📊 Summary:")
        print(f"   QR Codes: {len(qr_codes)}")
        print(f"   Data Matrix Codes: {len(datamatrix_codes)}")
        print(f"   Total: {len(result)}")
        
        # Analyze the issue
        if len(qr_codes) > 0 and len(datamatrix_codes) == 0:
            print("\n⚠️  BUG DETECTED: Found QR codes but no Data Matrix codes")
            print("   This suggests visual detection is misidentifying Data Matrix as QR")
        elif len(datamatrix_codes) > 0 and len(qr_codes) == 0:
            print("\n✅ GOOD: Found only Data Matrix codes (text fallback working)")
        elif len(qr_codes) > 0 and len(datamatrix_codes) > 0:
            print("\n⚠️  MIXED: Found both QR and Data Matrix codes")
            print("   This could indicate both visual misdetection AND text fallback")
        
    except Exception as e:
        print(f"❌ Barcode extraction test failed: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    # Step 2: Test pass generation
    print("\n🎫 Step 2: Pass Generation Test")
    print("-" * 40)
    
    try:
        from app.services.pass_generator import pass_generator
        
        pkpass_files, detected_barcodes, ticket_info = pass_generator.create_pass_from_pdf_data(
            pdf_data, 
            "pass_with_data_matrix.pdf",
            None  # No AI metadata
        )
        
        print(f"✅ Generated {len(pkpass_files)} pass file(s)")
        print(f"📊 Found {len(detected_barcodes)} unique barcode(s)")
        print(f"🎫 Created {len(ticket_info)} ticket(s)")
        
        for i, ticket in enumerate(ticket_info, 1):
            barcode = ticket.get('barcode')
            print(f"  Ticket {i}: {ticket['title']}")
            if barcode:
                print(f"    Barcode: {barcode['type']} - {barcode['data'][:50]}...")
                print(f"    Format: {barcode.get('format', 'unknown')}")
            else:
                print(f"    No barcode")
            print()
        
        # Analyze the bug
        if len(pkpass_files) > 1:
            print(f"\n⚠️  BUG CONFIRMED: Generated {len(pkpass_files)} passes instead of 1")
            print("   This indicates multiple barcodes were detected and treated as separate tickets")
            
            qr_tickets = sum(1 for t in ticket_info if t.get('barcode') and t['barcode']['type'] == 'QRCODE')
            dm_tickets = sum(1 for t in ticket_info if t.get('barcode') and t['barcode']['type'] == 'DATAMATRIX')
            
            print(f"   QR Code tickets: {qr_tickets}")
            print(f"   Data Matrix tickets: {dm_tickets}")
            
            if qr_tickets > 0 and dm_tickets == 0:
                print("   🔥 MAIN BUG: Data Matrix codes detected as QR codes")
        elif len(pkpass_files) == 1:
            ticket = ticket_info[0]
            barcode = ticket.get('barcode')
            if barcode and barcode['type'] == 'DATAMATRIX':
                print("\n✅ GOOD: Single pass with Data Matrix code")
            elif barcode and barcode['type'] == 'QRCODE':
                print("\n⚠️  ISSUE: Single pass but with QR code (should be Data Matrix)")
            else:
                print("\n⚠️  ISSUE: Single pass but no barcode")
        
        return True
        
    except Exception as e:
        print(f"❌ Pass generation test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_visual_vs_text_detection():
    """Test visual detection vs text fallback separately."""
    print("\n🔍 Step 3: Visual vs Text Detection Analysis")
    print("-" * 40)
    
    try:
        from app.services.barcode_extractor import BarcodeExtractor
        import cv2
        import numpy as np
        from pdf2image import convert_from_bytes
        from pyzbar import pyzbar
        
        extractor = BarcodeExtractor()
        
        test_file_path = Path(__file__).parent / "test_files" / "pass_with_data_matrix.pdf"
        
        with open(test_file_path, 'rb') as f:
            pdf_data = f.read()
        
        print("🖼️ Testing visual detection directly:")
        
        # Convert PDF to image
        images = convert_from_bytes(pdf_data, dpi=400)
        if images:
            # Convert first page to OpenCV format
            pil_image = images[0]
            cv_image = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
            
            # Try pyzbar directly (raw detection)
            print(f"📸 Image size: {cv_image.shape}")
            raw_barcodes = pyzbar.decode(cv_image)
            
            print(f"🔍 Raw pyzbar detection found {len(raw_barcodes)} barcodes:")
            for i, bc in enumerate(raw_barcodes, 1):
                print(f"  {i}. Type: {bc.type} (detected by pyzbar)")
                print(f"     Data: {bc.data.decode('utf-8', errors='ignore')[:50]}...")
                print()
            
            # Test our format group detection
            print("🎯 Testing format groups:")
            for i, group in enumerate(extractor.format_groups, 1):
                group_results = extractor.decode_with_formats(cv_image, group)
                print(f"  Group {i} {group}: {len(group_results)} results")
                for bc in group_results:
                    print(f"    Found: {bc['type']} - {bc['data'][:30]}...")
        
        # Test text-based detection
        print("\n📝 Testing text-based detection:")
        text_barcodes = extractor._extract_barcodes_from_text(pdf_data, "pass_with_data_matrix.pdf")
        print(f"📄 Text extraction found {len(text_barcodes)} potential barcodes:")
        for bc in text_barcodes:
            print(f"  Type: {bc['type']} - {bc['data'][:50]}...")
            print(f"  Method: {bc['method']}")
            print()
        
    except Exception as e:
        print(f"❌ Visual vs text detection test failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("🚀 Data Matrix Bug Investigation")
    print("This test will help identify exactly where the bug occurs")
    print()
    
    success = test_data_matrix_bug()
    test_visual_vs_text_detection()
    
    print("\n" + "=" * 60)
    print("📋 SUMMARY")
    print("=" * 60)
    if success:
        print("✅ Test completed successfully")
        print("📊 Check the output above to identify the specific bug location")
    else:
        print("❌ Test failed - check error messages above")
    
    print("\n💡 Expected bug symptoms:")
    print("   - pyzbar detects Data Matrix codes as QRCODE type")
    print("   - Visual detection finds codes in QR group, not DATAMATRIX group")
    print("   - Pass generator creates multiple passes (one per detected barcode)")
    print("   - Result: 2 QR passes instead of 1 Data Matrix pass")