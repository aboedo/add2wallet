#!/usr/bin/env python3
"""Test the Eiffel Tower ticket to see exact metadata response."""

import sys
import json
import asyncio
from pathlib import Path
sys.path.append('.')

from app.services.pass_generator import PassGenerator
from app.services.ai_service import AIService
from app.services.barcode_extractor import barcode_extractor

async def test_eiffel_tower():
    """Process torre ifel.pdf and show the exact metadata response."""
    
    pdf_file = Path("test_files/torre ifel.pdf")
    if not pdf_file.exists():
        print(f"❌ File not found: {pdf_file}")
        return
    
    print("="*80)
    print("🗼 Testing Eiffel Tower ticket (torre ifel.pdf)")
    print("="*80)
    
    # Read PDF
    with open(pdf_file, 'rb') as f:
        pdf_data = f.read()
    
    # Step 1: Extract text
    print("\n📄 Step 1: Extracting text from PDF...")
    import fitz  # PyMuPDF
    doc = fitz.open(stream=pdf_data, filetype="pdf")
    pdf_text = ""
    for page in doc:
        pdf_text += page.get_text()
    doc.close()
    print(f"Extracted {len(pdf_text)} characters of text")
    
    # Step 2: AI Analysis (optional - may fail without API key)
    ai_metadata = None
    try:
        print("\n🤖 Step 2: AI Analysis...")
        ai_service = AIService()
        ai_metadata = await ai_service.analyze_pdf_content(pdf_text, "torre ifel.pdf")
        print("AI metadata extracted successfully")
        print("\n--- AI Metadata (before colors) ---")
        print(json.dumps(ai_metadata, indent=2, default=str))
    except Exception as e:
        print(f"⚠️ AI analysis skipped: {e}")
        ai_metadata = {}
    
    # Step 3: Generate pass with colors
    print("\n🎨 Step 3: Generating pass with color extraction...")
    pass_generator = PassGenerator()
    
    try:
        pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
            pdf_data, 
            "torre ifel.pdf",
            ai_metadata
        )
        
        print(f"\n✅ Generated {len(pkpass_files)} pass(es)")
        print(f"📊 Detected {len(detected_barcodes)} barcode(s)")
        
        if warnings:
            print(f"⚠️ Warnings: {warnings}")
        
        # Show the enhanced metadata with colors
        if ticket_info and len(ticket_info) > 0:
            enhanced_metadata = ticket_info[0]["metadata"]
            
            print("\n" + "="*80)
            print("🎯 EXACT RESPONSE THAT iOS APP WOULD RECEIVE:")
            print("="*80)
            
            # Simulate the UploadResponse
            response = {
                "job_id": "test-job-123",
                "status": "completed",
                "pass_url": "/pass/test-job-123",
                "ai_metadata": enhanced_metadata,
                "ticket_count": len(pkpass_files),
                "warnings": warnings
            }
            
            print(json.dumps(response, indent=2, default=str))
            
            print("\n" + "="*80)
            print("🎨 COLOR FIELDS IN METADATA:")
            print("="*80)
            print(f"background_color: {enhanced_metadata.get('background_color', 'NOT FOUND')}")
            print(f"foreground_color: {enhanced_metadata.get('foreground_color', 'NOT FOUND')}")
            print(f"label_color: {enhanced_metadata.get('label_color', 'NOT FOUND')}")
            
    except Exception as e:
        print(f"\n❌ Error generating pass: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    asyncio.run(test_eiffel_tower())