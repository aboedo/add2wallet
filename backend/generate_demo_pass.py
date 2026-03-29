#!/usr/bin/env python3
"""
One-off script: generate a demo .pkpass with a future date override.
Usage: python generate_demo_pass.py
Output: demo_eiffel_future.pkpass
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from app.services.pass_generator import PassGenerator
from app.services.barcode_extractor import BarcodeExtractor
from app.services.ai_service import AIService

# Future date override
FUTURE_DATE = "2026-12-15"
FUTURE_TIME = "14:00"
PDF_PATH = os.path.expanduser("~/repos/add2wallet/ios/Add2Wallet/Resources/torre_ifel.pdf")
OUTPUT_PATH = "demo_eiffel_future.pkpass"

def main():
    print(f"📄 Reading PDF: {PDF_PATH}")
    with open(PDF_PATH, "rb") as f:
        pdf_bytes = f.read()

    print("🔍 Extracting barcodes...")
    extractor = BarcodeExtractor()
    barcodes = extractor.extract_barcodes_from_pdf(pdf_bytes, "torre_ifel.pdf")
    print(f"   Found {len(barcodes)} barcode(s)")

    generator = PassGenerator()

    if barcodes:
        barcode = barcodes[0]
        pass_info = {
            'title': 'Eiffel Tower Access',
            'venue': 'Eiffel Tower',
            'date': FUTURE_DATE,
            'time': FUTURE_TIME,
            'city': 'Paris',
            'barcode_data': barcode.get('data', barcode.get('value', '')),
            'barcode_format': barcode.get('format', 'PKBarcodeFormatQR'),
            'pass_type': 'attraction',
            'color': 'rgb(30, 144, 255)',
            'ticket_number': 1,
            'total_tickets': 1,
        }
        print(f"   Pass info: {pass_info}")
        pkpass_data, warnings = generator.create_enhanced_pass(
            title='Eiffel Tower Access',
            description='Eiffel Tower Ticket',
            pass_info=pass_info,
            bg_color='rgb(30, 144, 255)',
            fg_color='rgb(255, 255, 255)',
            label_color='rgb(200, 230, 255)',
            pdf_bytes=pdf_bytes,
        )
    else:
        print("❌ No barcodes found — can't generate pass")
        return

    with open(OUTPUT_PATH, "wb") as f:
        f.write(pkpass_data)
    print(f"✅ Saved: {OUTPUT_PATH} ({len(pkpass_data):,} bytes)")

if __name__ == "__main__":
    main()
