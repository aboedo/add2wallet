#!/usr/bin/env python3
"""
Test script to verify the Data Matrix warning system works correctly.
This tests our new implementation that generates warnings when Data Matrix codes are detected.
"""

import os
import sys
from pathlib import Path

# Add the project root to the path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

def test_datamatrix_warnings():
    """Test that Data Matrix codes generate warnings and passes without barcodes."""
    print("🧪 Testing Data Matrix Warning System")
    print("=" * 50)
    
    try:
        from app.services.pass_generator import pass_generator
        
        test_file_path = Path(__file__).parent / "test_files" / "pass_with_data_matrix.pdf"
        
        if not test_file_path.exists():
            print(f"❌ Test file not found: {test_file_path}")
            return False
        
        with open(test_file_path, 'rb') as f:
            pdf_data = f.read()
        
        print(f"📄 Testing with PDF file: {test_file_path.name}")
        print(f"📏 File size: {len(pdf_data)} bytes")
        print()
        
        # Test the new 4-return-value signature
        pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
            pdf_data, 
            "pass_with_data_matrix.pdf",
            None  # No AI metadata
        )
        
        print("📊 Results:")
        print(f"   Generated passes: {len(pkpass_files)}")
        print(f"   Detected barcodes: {len(detected_barcodes)}")
        print(f"   Ticket info: {len(ticket_info)}")
        print(f"   Warnings: {len(warnings)}")
        print()
        
        # Analyze detected barcodes
        datamatrix_count = sum(1 for bc in detected_barcodes if bc.get('type') == 'DATAMATRIX')
        qr_count = sum(1 for bc in detected_barcodes if bc.get('type') == 'QRCODE')
        
        print("🔍 Barcode Analysis:")
        print(f"   Data Matrix codes detected: {datamatrix_count}")
        print(f"   QR codes detected: {qr_count}")
        print()
        
        # Check warnings
        print("⚠️ Warnings Analysis:")
        if warnings:
            for i, warning in enumerate(warnings, 1):
                print(f"   {i}. {warning}")
            
            # Check if Data Matrix warning is present
            data_matrix_warnings = [w for w in warnings if 'Data Matrix' in w]
            if data_matrix_warnings:
                print("   ✅ Data Matrix warning correctly generated!")
            else:
                print("   ❌ Data Matrix warning NOT found in warnings")
        else:
            print("   ❌ No warnings generated")
        print()
        
        # Check that passes were generated without barcodes
        print("🎫 Pass Analysis:")
        for i, ticket in enumerate(ticket_info, 1):
            title = ticket.get('title', 'Unknown')
            barcode = ticket.get('barcode')
            print(f"   Ticket {i}: {title}")
            if barcode:
                print(f"      Barcode: {barcode['type']} - {barcode['data'][:30]}...")
                print("      ❌ ERROR: Pass still contains barcode (should be None)")
            else:
                print("      ✅ Correctly generated without barcode")
        print()
        
        # Final assessment
        success_criteria = [
            (datamatrix_count > 0, f"Data Matrix codes detected: {datamatrix_count}"),
            (len(warnings) > 0, f"Warnings generated: {len(warnings)}"),
            (any('Data Matrix' in w for w in warnings), "Data Matrix warning present"),
            (all(t.get('barcode') is None for t in ticket_info), "All passes generated without barcodes")
        ]
        
        print("📋 Success Criteria:")
        all_passed = True
        for passed, desc in success_criteria:
            status = "✅" if passed else "❌"
            print(f"   {status} {desc}")
            if not passed:
                all_passed = False
        
        if all_passed:
            print("\n🎉 SUCCESS: Data Matrix warning system working correctly!")
            print("   - Data Matrix codes are detected")
            print("   - Appropriate warnings are generated") 
            print("   - Passes are created without unsupported barcodes")
            print("   - Users will see clear warning about Data Matrix limitations")
        else:
            print("\n❌ FAILURE: Some criteria not met")
        
        return all_passed
        
    except Exception as e:
        print(f"❌ Test failed with exception: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_api_response_format():
    """Test that the API response includes warnings correctly."""
    print("\n🌐 Testing API Response Format")
    print("-" * 30)
    
    try:
        from app.models.responses import UploadResponse, StatusResponse
        
        # Test UploadResponse with warnings
        upload_response = UploadResponse(
            job_id="test-123",
            status="completed",
            pass_url="/pass/test-123",
            warnings=["This PDF contains a Data Matrix code, which is not supported by Apple Wallet."]
        )
        
        print("📤 UploadResponse test:")
        print(f"   Job ID: {upload_response.job_id}")
        print(f"   Status: {upload_response.status}")
        print(f"   Warnings: {upload_response.warnings}")
        print("   ✅ UploadResponse with warnings works")
        print()
        
        # Test StatusResponse with warnings
        status_response = StatusResponse(
            job_id="test-123",
            status="completed",
            progress=100,
            warnings=["Test warning"]
        )
        
        print("📥 StatusResponse test:")
        print(f"   Job ID: {status_response.job_id}")
        print(f"   Warnings: {status_response.warnings}")
        print("   ✅ StatusResponse with warnings works")
        
        return True
        
    except Exception as e:
        print(f"❌ API response test failed: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Data Matrix Warning System Test Suite")
    print("This test verifies our new warning system for unsupported Data Matrix codes\n")
    
    test1_success = test_datamatrix_warnings()
    test2_success = test_api_response_format()
    
    print("\n" + "=" * 50)
    print("📊 FINAL RESULTS")
    print("=" * 50)
    
    if test1_success and test2_success:
        print("🎉 ALL TESTS PASSED!")
        print("✅ Data Matrix warning system is working correctly")
        print("✅ API response models support warnings")
        print("\n🎯 System behavior:")
        print("   • Data Matrix codes are detected from PDFs")
        print("   • Warnings are generated and returned to client")
        print("   • Passes are created without unsupported barcodes")
        print("   • Users receive clear feedback about limitations")
    else:
        print("❌ SOME TESTS FAILED")
        if not test1_success:
            print("❌ Data Matrix warning system not working properly")
        if not test2_success:
            print("❌ API response models have issues")
    
    sys.exit(0 if (test1_success and test2_success) else 1)