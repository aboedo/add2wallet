#!/usr/bin/env python3
"""Test all files in test_files directory to verify QR code matching and deduplication."""

import sys
import os
sys.path.append('.')
from app.services.barcode_extractor import barcode_extractor

def test_all_files():
    """Test all PDF files in test_files directory."""
    
    test_dir = 'test_files'
    pdf_files = [f for f in os.listdir(test_dir) if f.endswith('.pdf')]
    pdf_files.sort()
    
    print(f"Found {len(pdf_files)} PDF files to test\n")
    
    for filename in pdf_files:
        try:
            print(f'=== {filename} ===')
            
            file_path = os.path.join(test_dir, filename)
            with open(file_path, 'rb') as f:
                pdf_data = f.read()

            barcodes = barcode_extractor.extract_barcodes_from_pdf(pdf_data, filename)

            if barcodes:
                print(f'✅ Found {len(barcodes)} unique barcode(s):')
                for i, bc in enumerate(barcodes, 1):
                    data = bc.get('data', '')
                    display_data = data if len(data) <= 30 else data[:27] + '...'
                    detection_count = bc.get('detection_count', 1)
                    pages = bc.get('pages_found', [bc.get('page', 1)])
                    
                    print(f'  {i}. {bc.get("type")} - "{display_data}"')
                    print(f'     Detected {detection_count} time(s) on page(s) {pages}')
                    
                    # Show raw bytes for verification
                    raw_hex = bc.get('raw_bytes', b'').hex()
                    if raw_hex:
                        display_hex = raw_hex if len(raw_hex) <= 40 else raw_hex[:37] + '...'
                        print(f'     Raw bytes: {display_hex}')
            else:
                print('❌ No barcodes detected')
                
            print()
                
        except Exception as e:
            print(f'❌ Error processing {filename}: {e}')
            print()
    
    print("=== All files tested ===")

if __name__ == '__main__':
    test_all_files()