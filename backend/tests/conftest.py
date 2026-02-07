import pytest
import os
import sys

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

TEST_FILES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "test_files"
)

TEST_PDFS = [
    "GTC-3M0VV9Q4-BoedoAndres.pdf",
    "Louvre mobile.pdf",
    "Swiftable 2023 tickets.pdf",
    "cbm_receipt_269143.pdf",
    "cmVzdGZ1bF9zcG9vbnMuMHVAaWNsb3VkLmNvbTIzNTU0MjA0cXI0Qmhqa2s=-111707572.pdf",
    "eTicket.pdf",
    "pasajes.pdf",
    "pass_with_aztec_code.pdf",
    "roman forum ticket.pdf",
    "tickets_7587005.pdf",
    "torre ifel.pdf",
]
