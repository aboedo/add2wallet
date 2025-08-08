#!/usr/bin/env python3
"""Test script to verify barcode deduplication works correctly."""

import sys
sys.path.append('.')
from app.services.barcode_extractor import barcode_extractor

def test_barcode_deduplication():
    """Test barcode extraction and deduplication with multiple files."""
    
    test_files = [
        'test_files/eTicket.pdf',
        'test_files/tickets_7587005.pdf', 
        'test_files/Swiftable 2023 tickets.pdf',
        'test_files/roman forum ticket.pdf',
        'test_files/Louvre mobile.pdf'
    ]
    
    for filename in test_files:
        try:
            print(f'=== Testing {filename} ===')
            
            with open(filename, 'rb') as f:
                pdf_data = f.read()

            barcodes = barcode_extractor.extract_barcodes_from_pdf(pdf_data, filename)

            print(f'Found {len(barcodes)} unique barcode(s)')
            for i, bc in enumerate(barcodes):
                print(f'  Barcode {i+1}:')
                print(f'    Type: {bc.get("type")}')
                print(f'    Data: {bc.get("data")}')
                print(f'    Raw bytes hex: {bc.get("raw_bytes", b"").hex()[:50]}...')
                print(f'    Detection count: {bc.get("detection_count")} times')
                print(f'    Found on pages: {bc.get("pages_found")}')
                print(f'    Methods: {bc.get("methods_used")}')
                print(f'    Confidence: {bc.get("confidence")}')
                print()
                
        except FileNotFoundError:
            print(f'  File not found: {filename}')
            print()
        except Exception as e:
            print(f'  Error processing {filename}: {e}')
            print()
    
    print("=== Test completed ===")

if __name__ == '__main__':
    test_barcode_deduplication()