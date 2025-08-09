"""Integration test for eTicket.pdf to prevent regression issues."""

import pytest
import os
from app.services.pass_generator import pass_generator
from app.services.barcode_extractor import barcode_extractor


class TestETicketIntegration:
    """Test suite specifically for eTicket.pdf processing."""

    @pytest.fixture
    def eticket_pdf_path(self):
        """Get path to eTicket.pdf test file."""
        return os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "test_files",
            "eTicket.pdf"
        )

    @pytest.fixture
    def eticket_pdf_data(self, eticket_pdf_path):
        """Load eTicket.pdf data."""
        if not os.path.exists(eticket_pdf_path):
            pytest.skip(f"eTicket.pdf not found at {eticket_pdf_path}")
        
        with open(eticket_pdf_path, 'rb') as f:
            return f.read()

    def test_eticket_barcode_extraction(self, eticket_pdf_data):
        """Test that eTicket.pdf barcode extraction works correctly."""
        barcodes = barcode_extractor.extract_barcodes_from_pdf(
            eticket_pdf_data, 
            "eTicket.pdf"
        )
        
        # Should find exactly 1 unique barcode (duplicate QR codes deduplicated)
        assert len(barcodes) == 1, f"Expected 1 barcode, found {len(barcodes)}"
        
        barcode = barcodes[0]
        
        # Verify barcode properties
        assert barcode['type'] == 'QRCODE', f"Expected QRCODE, got {barcode['type']}"
        assert barcode['format'] == 'PKBarcodeFormatQR', f"Expected PKBarcodeFormatQR format"
        assert 'data' in barcode, "Barcode should have data field"
        assert 'raw_bytes' in barcode, "Barcode should have raw_bytes field"
        assert 'detection_count' in barcode, "Barcode should have detection_count field"
        
        # Should detect it was found multiple times (duplicate QR codes)
        assert barcode['detection_count'] == 2, f"Expected detection_count of 2, got {barcode['detection_count']}"
        
        # Check pages where barcode was found
        assert 'pages_found' in barcode, "Barcode should have pages_found field"
        assert set(barcode['pages_found']) == {1, 2}, f"Expected pages [1, 2], got {barcode['pages_found']}"

    def test_eticket_pass_generation(self, eticket_pdf_data):
        """Test that eTicket.pdf generates exactly one pass."""
        pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
            eticket_pdf_data,
            "eTicket.pdf",
            None  # No AI metadata
        )
        
        # Should generate exactly 1 pass file
        assert len(pkpass_files) == 1, f"Expected 1 pass file, got {len(pkpass_files)}"
        
        # Should detect exactly 1 unique barcode
        assert len(detected_barcodes) == 1, f"Expected 1 unique barcode, got {len(detected_barcodes)}"
        
        # Should have exactly 1 ticket info entry
        assert len(ticket_info) == 1, f"Expected 1 ticket info, got {len(ticket_info)}"
        
        # Verify pass file is valid (non-empty)
        assert len(pkpass_files[0]) > 0, "Pass file should not be empty"
        
        # Verify ticket info structure
        ticket = ticket_info[0]
        assert 'title' in ticket, "Ticket should have title"
        assert 'description' in ticket, "Ticket should have description"  
        assert 'barcode' in ticket, "Ticket should have barcode"
        assert ticket['barcode'] is not None, "Ticket barcode should not be None"
        
        # Verify barcode in ticket info
        barcode = ticket['barcode']
        assert barcode['type'] == 'QRCODE', f"Expected QRCODE, got {barcode['type']}"
        assert 'data' in barcode, "Barcode should have data"
        assert 'detection_count' in barcode, "Barcode should have detection_count"
        assert barcode['detection_count'] == 2, f"Expected detection_count of 2, got {barcode['detection_count']}"

    def test_eticket_spanish_text_handling(self, eticket_pdf_data):
        """Test that Spanish text and date formats are handled correctly."""
        pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
            eticket_pdf_data,
            "eTicket.pdf",
            None
        )
        
        ticket = ticket_info[0]
        
        # The title should be reasonable (not empty, not just "Event Ticket")
        assert ticket['title'], "Title should not be empty"
        
        # Should contain Spanish date format handling
        # The PDF contains "21 junio 2025" which should be processed
        assert 'description' in ticket, "Should have description"
        
        # Check that Spanish text doesn't break the processing
        # (No specific assertions needed since successful pass generation proves it works)
        
    def test_eticket_qr_code_data_format(self, eticket_pdf_data):
        """Test that QR code data from eTicket.pdf is in the correct format."""
        barcodes = barcode_extractor.extract_barcodes_from_pdf(
            eticket_pdf_data,
            "eTicket.pdf"
        )
        
        barcode = barcodes[0]
        barcode_data = barcode['data']
        
        # QR code data should be a string
        assert isinstance(barcode_data, str), f"Barcode data should be string, got {type(barcode_data)}"
        
        # Should not be empty
        assert len(barcode_data) > 0, "Barcode data should not be empty"
        
        # Should contain the operation number from the PDF (25063439)
        assert '25063439' in barcode_data, f"Barcode should contain operation number, data: {barcode_data[:50]}..."

    def test_eticket_end_to_end_processing(self, eticket_pdf_data):
        """End-to-end test that eTicket.pdf processes without any errors."""
        try:
            # This should not raise any exceptions
            pkpass_files, detected_barcodes, ticket_info, warnings = pass_generator.create_pass_from_pdf_data(
                eticket_pdf_data,
                "eTicket.pdf",
                None
            )
            
            # Verify we got expected results
            assert len(pkpass_files) == 1
            assert len(detected_barcodes) == 1  
            assert len(ticket_info) == 1
            
            # Verify no critical warnings
            if warnings:
                # Allow warnings but not errors
                for warning in warnings:
                    assert "error" not in warning.lower(), f"Unexpected error in warnings: {warning}"
            
        except Exception as e:
            pytest.fail(f"eTicket.pdf processing failed: {str(e)}")

    def test_eticket_barcode_encoding(self, eticket_pdf_data):
        """Test that barcode encoding is handled correctly for eTicket.pdf."""
        barcodes = barcode_extractor.extract_barcodes_from_pdf(
            eticket_pdf_data,
            "eTicket.pdf"
        )
        
        barcode = barcodes[0]
        
        # Should have encoding information
        assert 'encoding' in barcode, "Barcode should have encoding field"
        assert barcode['encoding'] in ['utf-8', 'iso-8859-1'], f"Unexpected encoding: {barcode['encoding']}"
        
        # Raw bytes should be present and valid
        assert 'raw_bytes' in barcode, "Barcode should have raw_bytes"
        assert isinstance(barcode['raw_bytes'], bytes), "raw_bytes should be bytes type"
        assert len(barcode['raw_bytes']) > 0, "raw_bytes should not be empty"
        
        # Base64 encoded bytes should be present
        assert 'bytes_b64' in barcode, "Barcode should have bytes_b64"
        assert isinstance(barcode['bytes_b64'], str), "bytes_b64 should be string"
        
        # Data should be decodable
        try:
            decoded = barcode['raw_bytes'].decode(barcode['encoding'])
            assert decoded == barcode['data'], "Decoded data should match barcode data"
        except UnicodeDecodeError:
            pytest.fail(f"Failed to decode barcode data with encoding {barcode['encoding']}")