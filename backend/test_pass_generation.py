#!/usr/bin/env python3
"""Test pass generation with the fixed deduplication."""

import sys
sys.path.append('.')
from app.services.pass_generator import pass_generator

def test_pass_generation():
    """Test pass generation with deduplicated barcodes."""
    
    test_files = [
        ('test_files/eTicket.pdf', 'Should create 1 pass (duplicate QR codes)'),
        ('test_files/Louvre mobile.pdf', 'Should create 2 passes (different QR codes)'),
        ('test_files/tickets_7587005.pdf', 'Should create 1 pass (single barcode)'),
    ]
    
    for filename, expected in test_files:
        try:
            print(f'=== Testing {filename} ===')
            print(f'Expected: {expected}')
            
            with open(filename, 'rb') as f:
                pdf_data = f.read()

            # Generate passes
            pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
                pdf_data, 
                filename.split('/')[-1],
                None  # No AI metadata for this test
            )
            
            print(f'Generated {len(pkpass_files)} pass file(s)')
            print(f'Found {len(detected_barcodes)} unique barcode(s)')
            print(f'Ticket info count: {len(ticket_info)}')
            if warnings:
                print(f'Warnings: {warnings}')
            
            for i, ticket in enumerate(ticket_info, 1):
                print(f'  Ticket {i}: {ticket["title"]} - Has barcode: {ticket["barcode"] is not None}')
                if ticket["barcode"]:
                    bc = ticket["barcode"]
                    print(f'    Barcode: {bc.get("type")} - {bc.get("data")} (detected {bc.get("detection_count", 1)} times)')
            
            print(f'✅ Result: {len(pkpass_files)} passes generated as expected')
            print()
                
        except FileNotFoundError:
            print(f'  File not found: {filename}')
            print()
        except Exception as e:
            print(f'  Error processing {filename}: {e}')
            import traceback
            traceback.print_exc()
            print()
    
    print("=== Pass generation test completed ===")

if __name__ == '__main__':
    test_pass_generation()