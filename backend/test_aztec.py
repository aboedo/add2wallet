#!/usr/bin/env python3
"""Test Aztec code generation and extraction."""

import os
import sys
import json
import base64
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from app.services.barcode_extractor import barcode_extractor
from app.services.pass_generator import PassGenerator

def test_aztec_generation():
    """Test generating a pass with an Aztec code."""
    print("\n🧪 Testing Aztec Code Generation")
    print("=" * 50)
    
    # Create a test pass configuration with Aztec code
    pass_data = {
        "formatVersion": 1,
        "passTypeIdentifier": "pass.com.example.ticket",
        "serialNumber": "AZTEC-TEST-001",
        "teamIdentifier": "TESTTEAM",
        "organizationName": "Aztec Test Org",
        "description": "Test Aztec Code Pass",
        "foregroundColor": "rgb(0, 0, 0)",
        "backgroundColor": "rgb(255, 255, 255)",
        "labelColor": "rgb(100, 100, 100)",
        "boardingPass": {
            "transitType": "PKTransitTypeTrain",
            "primaryFields": [
                {
                    "key": "origin",
                    "label": "FROM",
                    "value": "Paris"
                },
                {
                    "key": "destination", 
                    "label": "TO",
                    "value": "Lyon"
                }
            ],
            "secondaryFields": [
                {
                    "key": "passenger",
                    "label": "PASSENGER",
                    "value": "John Doe"
                }
            ],
            "auxiliaryFields": [
                {
                    "key": "seat",
                    "label": "SEAT",
                    "value": "4A"
                },
                {
                    "key": "class",
                    "label": "CLASS",
                    "value": "First"
                }
            ],
            "backFields": []
        },
        "barcode": {
            "message": "AZTEC-TICKET-12345-ABCDEF-TRAIN-PARIS-LYON",
            "format": "PKBarcodeFormatAztec",
            "messageEncoding": "iso-8859-1"
        },
        "barcodes": [
            {
                "message": "AZTEC-TICKET-12345-ABCDEF-TRAIN-PARIS-LYON",
                "format": "PKBarcodeFormatAztec",
                "messageEncoding": "iso-8859-1"
            }
        ]
    }
    
    # Create output directory
    output_dir = Path("/tmp/aztec_test")
    output_dir.mkdir(exist_ok=True)
    
    # Save pass.json
    pass_json_path = output_dir / "pass.json"
    with open(pass_json_path, "w") as f:
        json.dump(pass_data, f, indent=2)
    
    print(f"✅ Created pass.json with Aztec code configuration")
    print(f"   Format: {pass_data['barcode']['format']}")
    print(f"   Message: {pass_data['barcode']['message']}")
    
    return output_dir

def test_aztec_extraction():
    """Test extracting Aztec codes from a PDF."""
    print("\n🧪 Testing Aztec Code Extraction")
    print("=" * 50)
    
    # Check if we have a test PDF with Aztec code
    test_pdfs = [
        "/Users/andresboedo/personal_projects/add2wallet/backend/uploads",
        "/tmp/test_aztec.pdf"
    ]
    
    pdf_found = False
    for pdf_path in test_pdfs:
        if os.path.exists(pdf_path):
            if os.path.isdir(pdf_path):
                # Check for PDFs in directory
                pdf_files = list(Path(pdf_path).glob("*.pdf"))
                if pdf_files:
                    pdf_path = pdf_files[0]
                    pdf_found = True
                    break
            else:
                pdf_found = True
                break
    
    if not pdf_found:
        print("⚠️  No test PDF found. Creating a synthetic test...")
        # For now, we'll just test the extraction logic
        test_extraction_logic()
        return
    
    print(f"📄 Testing with PDF: {pdf_path}")
    
    # Read PDF
    with open(pdf_path, "rb") as f:
        pdf_data = f.read()
    
    # Extract barcodes
    barcodes = barcode_extractor.extract_barcodes_from_pdf(pdf_data, str(pdf_path))
    
    print(f"\n📊 Extraction Results:")
    print(f"   Total barcodes found: {len(barcodes)}")
    
    for i, barcode in enumerate(barcodes, 1):
        print(f"\n   Barcode #{i}:")
        print(f"   - Type: {barcode.get('type')}")
        print(f"   - Format: {barcode.get('format')}")
        print(f"   - Data: {barcode.get('data', '')[:50]}...")
        print(f"   - Confidence: {barcode.get('confidence')}%")
        print(f"   - Method: {barcode.get('method')}")
        print(f"   - Page: {barcode.get('page')}")
        
        # Check if it's an Aztec code
        if barcode.get('type') == 'AZTEC':
            print(f"   ✅ AZTEC CODE DETECTED!")

def test_extraction_logic():
    """Test the Aztec detection logic without actual PDFs."""
    print("\n🧪 Testing Aztec Detection Logic")
    print("=" * 50)
    
    # Test format groups
    print(f"Format groups priority: {barcode_extractor.format_groups}")
    
    # Test barcode type inference
    test_cases = [
        ("TICKET-12345-AZTEC", "ticket.pdf"),
        ("QR-GENERAL-DATA", "document.pdf"),
        ("BOARDING-PASS-XYZ123", "boarding_pass.pdf"),
        ("TRAIN-BILLET-456", "billet_train.pdf")
    ]
    
    print("\n📝 Testing barcode type inference:")
    for data, filename in test_cases:
        inferred_type = barcode_extractor._infer_barcode_type_from_content(data, filename)
        print(f"   Data: '{data[:30]}...', File: '{filename}' -> {inferred_type}")
    
    # Test format normalization
    print("\n📝 Testing format normalization:")
    formats_to_test = ['AZTEC', 'QRCODE', 'CODE128', 'PDF417']
    for fmt in formats_to_test:
        normalized = barcode_extractor._normalize_barcode_format(fmt)
        print(f"   {fmt} -> {normalized}")

def main():
    """Run all Aztec code tests."""
    print("🚀 Starting Aztec Code Compatibility Tests")
    print("=" * 50)
    
    try:
        # Test generation
        output_dir = test_aztec_generation()
        
        # Test extraction
        test_aztec_extraction()
        
        print("\n✅ All tests completed!")
        print(f"   Generated test pass in: {output_dir}")
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())