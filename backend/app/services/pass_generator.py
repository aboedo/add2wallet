"""Apple Wallet Pass Generator Service."""

import json
import os
import tempfile
import zipfile
import shutil
# subprocess removed for Vercel compatibility
import re
from datetime import datetime
from typing import Dict, Any, Optional, List, Tuple
import hashlib
from collections import Counter
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography import x509
from cryptography.x509.oid import NameOID
import PyPDF2
from PIL import Image
import io
from dateutil import parser as date_parser


class PassGenerator:
    """Generates Apple Wallet passes from templates."""
    
    def __init__(self, certificates_path: str = None, assets_path: str = None):
        """Initialize the pass generator.
        
        Args:
            certificates_path: Path to directory containing pass certificates
            assets_path: Path to directory containing pass assets (icons, etc.)
        """
        self.certificates_path = certificates_path or os.path.join(os.path.dirname(__file__), "../../certificates")
        self.assets_path = assets_path or os.path.join(os.path.dirname(__file__), "../../assets")
        self.signing_enabled = self._check_certificates_available()
        
    def create_basic_pass(self, 
                         title: str = "Generic Pass", 
                         description: str = "Generated from PDF",
                         organization: str = "Add2Wallet") -> bytes:
        """Create a basic Apple Wallet pass.
        
        Args:
            title: Pass title
            description: Pass description  
            organization: Organization name
            
        Returns:
            bytes: The .pkpass file as bytes
        """
        
        # Extract identifiers from certificate
        pass_type_id, team_id = self._extract_certificate_identifiers()
        
        # Create pass.json
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": pass_type_id,
            "serialNumber": f"generic-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "teamIdentifier": team_id,
            "organizationName": organization,
            "description": description,
            "logoText": title,
            "foregroundColor": "rgb(255,255,255)",
            "backgroundColor": "rgb(60,60,67)",
            "labelColor": "rgb(255,255,255)",
            "generic": {
                "headerFields": [
                    {
                        "key": "header",
                        "label": "DOCUMENT",
                        "value": title
                    }
                ],
                "primaryFields": [
                    {
                        "key": "title",
                        "label": "",
                        "value": title
                    }
                ],
                "secondaryFields": [
                    {
                        "key": "description", 
                        "label": "Description",
                        "value": description
                    }
                ],
                "auxiliaryFields": [
                    {
                        "key": "generated",
                        "label": "Generated",
                        "value": datetime.now().strftime("%b %d, %Y")
                    }
                ]
            }
        }
        
        # Add associatedStoreIdentifiers if available
        associated_store_ids = self._get_associated_store_identifiers()
        if associated_store_ids:
            pass_json["associatedStoreIdentifiers"] = associated_store_ids
            print(f"✅ Added associatedStoreIdentifiers: {associated_store_ids}")
        
        # Create temporary directory for pass files
        with tempfile.TemporaryDirectory() as temp_dir:
            
            # Write pass.json
            pass_json_path = os.path.join(temp_dir, "pass.json")
            with open(pass_json_path, 'w') as f:
                json.dump(pass_json, f, indent=2)
            
            # Copy icon files to pass directory
            self._copy_icon_assets(temp_dir)
            
            # Create manifest.json (file hashes)
            manifest = self._create_manifest(temp_dir)
            manifest_path = os.path.join(temp_dir, "manifest.json")
            with open(manifest_path, 'w') as f:
                json.dump(manifest, f, indent=2)
            
            # Sign the manifest if certificates are available
            if self.signing_enabled:
                signature = self._sign_manifest_file(manifest_path)
                signature_path = os.path.join(temp_dir, "signature")
                with open(signature_path, 'wb') as f:
                    f.write(signature)
            
            # Create .pkpass zip file
            pkpass_data = self._create_pkpass_zip(temp_dir)
            
            return pkpass_data
    
    def _copy_icon_assets(self, temp_dir: str) -> None:
        """Copy icon assets to the pass directory.
        
        Args:
            temp_dir: Temporary directory for pass files
        """
        icon_files = ['icon.png', 'icon@2x.png', 'icon@3x.png']
        
        for icon_file in icon_files:
            src_path = os.path.join(self.assets_path, icon_file)
            if os.path.exists(src_path):
                dst_path = os.path.join(temp_dir, icon_file)
                shutil.copy2(src_path, dst_path)
                print(f"✅ Copied {icon_file} to pass bundle")
            else:
                print(f"⚠️  Icon file not found: {src_path}")
    
    def _create_manifest(self, pass_dir: str) -> Dict[str, str]:
        """Create manifest.json with file hashes.
        
        Args:
            pass_dir: Directory containing pass files
            
        Returns:
            Dictionary mapping filenames to SHA1 hashes
        """
        manifest = {}
        
        for filename in os.listdir(pass_dir):
            if filename.startswith('.') or filename == 'manifest.json':
                continue
                
            file_path = os.path.join(pass_dir, filename)
            if os.path.isfile(file_path):
                with open(file_path, 'rb') as f:
                    file_hash = hashlib.sha1(f.read()).hexdigest()
                    manifest[filename] = file_hash
        
        return manifest
    
    def _create_pkpass_zip(self, pass_dir: str) -> bytes:
        """Create .pkpass zip file from pass directory.
        
        Args:
            pass_dir: Directory containing pass files
            
        Returns:
            The .pkpass file as bytes
        """
        zip_buffer = []
        
        with tempfile.NamedTemporaryFile() as temp_zip:
            with zipfile.ZipFile(temp_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
                for filename in os.listdir(pass_dir):
                    if not filename.startswith('.'):
                        file_path = os.path.join(pass_dir, filename)
                        if os.path.isfile(file_path):
                            zf.write(file_path, filename)
            
            temp_zip.seek(0)
            return temp_zip.read()
    
    def create_pass_from_pdf_data(self, 
                                 pdf_data: bytes, 
                                 filename: str,
                                 ai_metadata: Dict[str, Any] = None) -> Tuple[List[bytes], List[Dict[str, Any]], List[Dict[str, Any]], List[str]]:
        """Create intelligent passes from PDF data, supporting multiple tickets.
        
        Args:
            pdf_data: Raw PDF bytes
            filename: Original filename
            ai_metadata: AI-extracted metadata (optional)
            
        Returns:
            Tuple of (list of .pkpass files as bytes, list of detected barcodes, list of ticket info, list of warnings)
        """
        print(f"🔍 Analyzing PDF: {filename}")
        
        # Initialize warnings list to collect from all passes
        all_warnings = []
        
        # Step 1: Extract barcodes from PDF
        barcodes: List[Dict[str, Any]] = []
        try:
            from app.services.barcode_extractor import barcode_extractor
            barcodes = barcode_extractor.extract_barcodes_from_pdf(pdf_data, filename)
            print(f"📊 Found {len(barcodes)} barcodes in PDF")
        except Exception as e:
            print(f"⚠️ Barcode extraction failed: {e}")
        
        # Sort barcodes by page then by detected area (descending)
        try:
            def area(bc: Dict[str, Any]) -> int:
                pos = bc.get('position') or {}
                return int((pos.get('width') or 0) * (pos.get('height') or 0))
            barcodes.sort(key=lambda bc: (bc.get('page') or 0, -area(bc)))
        except Exception:
            pass

        # Step 2: Use AI metadata if available, otherwise fall back to basic extraction
        if ai_metadata and ai_metadata.get('ai_processed'):
            print(f"🤖 Using AI-extracted metadata (confidence: {ai_metadata.get('confidence_score', 'unknown')})")
            print(f"📋 AI metadata fields: {list(ai_metadata.keys())}")
            print(f"📍 Event: {ai_metadata.get('event_name', 'N/A')}, Title: {ai_metadata.get('title', 'N/A')}")
            print(f"📅 Date: {ai_metadata.get('date', 'N/A')}, Time: {ai_metadata.get('time', 'N/A')}")
            print(f"🏛️ Venue: {ai_metadata.get('venue_name', 'N/A')}")
            base_pass_info = ai_metadata
        else:
            print("🔄 Falling back to basic PDF analysis")
            # Extract text content from PDF
            pdf_text = self._extract_pdf_text(pdf_data)
            print(f"📝 Extracted {len(pdf_text)} characters of text")
            
            # Analyze PDF content to extract pass information
            base_pass_info = self._extract_pass_info(pdf_text)
            print(f"🎯 Extracted info: {base_pass_info}")
        
        # Step 3: Create tickets based on detected barcodes
        tickets = []
        if barcodes:
            # Apply intelligent barcode consolidation for single-pass documents
            consolidated_barcodes = self._consolidate_barcodes_for_single_pass(barcodes, filename)
            
            # Create one ticket per consolidated barcode
            for i, barcode in enumerate(consolidated_barcodes, 1):
                tickets.append({
                    'barcode': barcode,
                    'metadata': base_pass_info,
                    'ticket_number': i,
                    'total_tickets': len(consolidated_barcodes)
                })
        else:
            # No barcodes, create single pass
            tickets.append({
                'barcode': None,
                'metadata': base_pass_info,
                'ticket_number': 1,
                'total_tickets': 1
            })
        
        print(f"🎫 Detected {len(tickets)} ticket(s) in PDF")
        
        # Step 4: Generate passes for each ticket
        pkpass_files = []
        ticket_info = []
        
        for ticket in tickets:
            ticket_barcode = ticket['barcode']
            ticket_metadata = ticket['metadata']
            ticket_num = ticket['ticket_number']
            total_tickets = ticket['total_tickets']
            
            # Merge barcode data with pass info
            pass_info = ticket_metadata.copy()
            if ticket_barcode:
                # Check if this is a Data Matrix code
                if ticket_barcode.get('type') == 'DATAMATRIX':
                    print(f"🎫 Ticket {ticket_num}: Detected Data Matrix barcode - will be excluded from pass")
                    # Still pass it to the pass generator so it can generate warnings
                    pass_info['primary_barcode'] = ticket_barcode
                else:
                    pass_info['primary_barcode'] = ticket_barcode
                    # Use barcode data if no other barcode data was found
                    if not pass_info.get('barcode_data'):
                        pass_info['barcode_data'] = ticket_barcode['data']
                    print(f"🎫 Ticket {ticket_num}: Using barcode {ticket_barcode['type']} - {ticket_barcode['data'][:50]}...")
            
            # Extract colors directly from PDF - this is more accurate than AI guessing
            print(f"🎨 Extracting colors from PDF...")
            pdf_bg, pdf_fg, pdf_label = self._extract_color_palette_from_pdf_images(pdf_data)
            
            if pdf_bg and pdf_fg and pdf_label:
                bg_color, fg_color, label_color = pdf_bg, pdf_fg, pdf_label
                print(f"✅ Using PDF-extracted colors: bg={bg_color}")
            else:
                # Fall back to smart defaults based on content type
                bg_color, fg_color, label_color = self._analyze_pdf_colors_enhanced(pdf_data, pass_info)
                print(f"🔄 Using fallback color analysis")
            
            # Use AI-extracted title or fallback, then sanitize to avoid code-like titles
            base_title = (pass_info.get('title') or 
                         pass_info.get('event_name') or 
                         (pass_info.get('venue_name') if isinstance(pass_info, dict) else None) or 
                         filename.replace('.pdf', '').replace('_', ' ').title())
            base_title = self._sanitize_title(base_title, fallback_name=pass_info.get('event_name') or filename)
            
            # Customize title for multiple tickets
            if total_tickets > 1:
                title = f"{base_title} (#{ticket_num})"
            else:
                title = base_title
            
            # Use AI-extracted description or create one, then sanitize if it looks like a UUID/code
            base_description = (pass_info.get('description') or 
                               pass_info.get('event_description') or 
                               f"Digital pass from {filename}")
            base_description = self._sanitize_description(
                base_description,
                pass_info=pass_info,
                filename=filename
            )
            
            # Customize description for multiple tickets
            if total_tickets > 1:
                description = f"{base_description} - Ticket {ticket_num} of {total_tickets}"
            else:
                description = base_description
            
            # Ensure sufficient contrast for text readability (do this once, before pass generation)
            bg_color_adjusted, fg_color_adjusted, label_color_adjusted = self._ensure_color_contrast(
                bg_color, fg_color, label_color
            )
            
            # Generate the enhanced pass with barcode
            pkpass_data, pass_warnings = self.create_enhanced_pass(
                title=title,
                description=description,
                pass_info=pass_info,
                bg_color=bg_color_adjusted,
                fg_color=fg_color_adjusted,
                label_color=label_color_adjusted,
                pdf_bytes=pdf_data
            )
            
            pkpass_files.append(pkpass_data)
            all_warnings.extend(pass_warnings)
            
            # Store ticket info for response
            # Don't include Data Matrix barcodes in ticket info since they're unsupported
            stored_barcode = None if (ticket_barcode and ticket_barcode.get('type') == 'DATAMATRIX') else ticket_barcode
            
            # Add color information to metadata for iOS app
            enhanced_metadata = pass_info.copy() if isinstance(pass_info, dict) else {}
            enhanced_metadata.update({
                'background_color': bg_color_adjusted,
                'foreground_color': fg_color_adjusted,
                'label_color': label_color_adjusted
            })
            
            ticket_info.append({
                'ticket_number': ticket_num,
                'total_tickets': total_tickets,
                'title': title,
                'description': description,
                'barcode': stored_barcode,
                'metadata': enhanced_metadata
            })
        
        print(f"✅ Generated {len(pkpass_files)} wallet pass(es)")
        return pkpass_files, barcodes, ticket_info, all_warnings
    
    def create_enhanced_pass(self, 
                            title: str,
                            description: str,
                            pass_info: Dict[str, str],
                            bg_color: str,
                            fg_color: str,
                            label_color: str,
                            organization: str = "Add2Wallet",
                            pdf_bytes: Optional[bytes] = None) -> Tuple[bytes, List[str]]:
        """Create an enhanced pass with extracted PDF data.
        
        Args:
            title: Pass title
            description: Pass description
            pass_info: Extracted information from PDF
            bg_color: Background color
            fg_color: Foreground color  
            label_color: Label color
            organization: Organization name
            
        Returns:
            Tuple of (.pkpass file as bytes, list of warnings)
        """
        # Extract identifiers from certificate
        pass_type_id, team_id = self._extract_certificate_identifiers()
        
        # Initialize warnings list
        warnings = []
        
        # Build pass fields dynamically based on AI-extracted info
        header_fields = []
        primary_fields = []
        secondary_fields = []
        auxiliary_fields = []
        
        print(f"🏗️ Building pass fields for: {title}")
        print(f"   Available metadata fields: {[k for k in pass_info.keys() if pass_info.get(k)]}")
        
        # Header field - use event type for better categorization
        event_type = pass_info.get('event_type', '').upper()
        if event_type and event_type != 'OTHER':
            header_fields.append({
                "key": "header",
                "label": event_type,
                "value": title[:25]  # Limit length for header
            })
            print(f"   Added header: {event_type}")
        elif pass_info.get('event_name'):
            header_fields.append({
                "key": "header",
                "label": "EVENT",
                "value": title[:25]
            })
            print(f"   Added header: EVENT")
        else:
            header_fields.append({
                "key": "header", 
                "label": "DOCUMENT",
                "value": "Digital Pass"
            })
            print(f"   Added header: DOCUMENT")
        
        # Primary field - main title
        primary_fields.append({
            "key": "title",
            "label": "",
            "value": title
        })
        
        # Secondary fields - prioritize most relevant information
        # Date and time
        if pass_info.get('date'):
            secondary_fields.append({
                "key": "date",
                "label": "Date",
                "value": pass_info['date']
            })
            print(f"   Added date: {pass_info['date']}")
            
        if pass_info.get('time'):
            secondary_fields.append({
                "key": "time", 
                "label": "Time",
                "value": pass_info['time']
            })
            print(f"   Added time: {pass_info['time']}")
        
        # Seat/gate information (important for tickets)
        if pass_info.get('seat_info'):
            secondary_fields.append({
                "key": "seat",
                "label": "Seat",
                "value": pass_info['seat_info']
            })
            print(f"   Added seat: {pass_info['seat_info']}")
        elif pass_info.get('gate_info'):
            secondary_fields.append({
                "key": "gate",
                "label": "Gate",
                "value": pass_info['gate_info']
            })
            print(f"   Added gate: {pass_info['gate_info']}")
        
        # Auxiliary fields - venue and additional details
        if pass_info.get('venue_name'):
            auxiliary_fields.append({
                "key": "venue",
                "label": "Venue",
                "value": pass_info['venue_name']
            })
            print(f"   Added venue: {pass_info['venue_name']}")
        elif pass_info.get('venue'):  # Fallback to old field name
            auxiliary_fields.append({
                "key": "venue",
                "label": "Venue",
                "value": pass_info['venue']
            })
            print(f"   Added venue (fallback): {pass_info['venue']}")
        
        # Add performer/artist for entertainment events
        if pass_info.get('performer_artist'):
            auxiliary_fields.append({
                "key": "artist",
                "label": "Artist",
                "value": pass_info['performer_artist']
            })
            print(f"   Added artist: {pass_info['performer_artist']}")
        
        # Add organizer if no performer/artist
        elif pass_info.get('organizer'):
            auxiliary_fields.append({
                "key": "organizer",
                "label": "Organizer",
                "value": pass_info['organizer']
            })
            print(f"   Added organizer: {pass_info['organizer']}")
        
        # Add confirmation number if available
        if pass_info.get('confirmation_number'):
            auxiliary_fields.append({
                "key": "confirmation",
                "label": "Confirmation",
                "value": pass_info['confirmation_number']
            })
            print(f"   Added confirmation: {pass_info['confirmation_number']}")
        
        # Add price if available
        if pass_info.get('price'):
            auxiliary_fields.append({
                "key": "price",
                "label": "Price",
                "value": pass_info['price']
            })
            print(f"   Added price: {pass_info['price']}")
        
        # Add location/city if available but venue wasn't added
        if not pass_info.get('venue_name') and not pass_info.get('venue'):
            if pass_info.get('city'):
                auxiliary_fields.append({
                    "key": "location",
                    "label": "Location",
                    "value": pass_info['city']
                })
                print(f"   Added city: {pass_info['city']}")
            elif pass_info.get('venue_address'):
                auxiliary_fields.append({
                    "key": "address",
                    "label": "Address",
                    "value": pass_info['venue_address'][:50]  # Limit length
                })
                print(f"   Added address: {pass_info['venue_address'][:50]}")
        
        # Always add generation info
        auxiliary_fields.append({
            "key": "generated",
            "label": "Generated",
            "value": datetime.now().strftime("%b %d, %Y")
        })
        
        print(f"   Total fields: {len(header_fields)} header, {len(primary_fields)} primary, {len(secondary_fields)} secondary, {len(auxiliary_fields)} auxiliary")
        
        # Log the colors we're about to use
        print(f"🎨 Setting pass colors:")
        print(f"   Background: {bg_color}")
        print(f"   Foreground: {fg_color}")
        print(f"   Label: {label_color}")
        
        # Create pass.json with enhanced content
        pass_json = {
            "formatVersion": 1,
            "passTypeIdentifier": pass_type_id,
            "serialNumber": f"enhanced-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            "teamIdentifier": team_id,
            "organizationName": organization,
            "description": description,
            "logoText": title[:20],  # Shorter for logo text
            "foregroundColor": fg_color,
            "backgroundColor": bg_color,
            "labelColor": label_color,
            "generic": {
                "headerFields": header_fields,
                "primaryFields": primary_fields,
                "secondaryFields": secondary_fields,
                "auxiliaryFields": auxiliary_fields
            }
        }

        # If AI provided brand colors, keep them for downstream tools (non-standard key ignored by PassKit)
        brand_colors = None
        if isinstance(pass_info, dict):
            palette = pass_info.get('color_palette') or {}
            if isinstance(palette, dict) and palette.get('brand_colors'):
                brand_colors = palette.get('brand_colors')
        if brand_colors:
            pass_json['a2w_brandColors'] = brand_colors
        
        # Add associatedStoreIdentifiers if available
        associated_store_ids = self._get_associated_store_identifiers()
        if associated_store_ids:
            pass_json["associatedStoreIdentifiers"] = associated_store_ids
            print(f"✅ Added associatedStoreIdentifiers: {associated_store_ids}")
        
        # Add barcode to the pass if available
        primary_barcode = pass_info.get('primary_barcode')
        if primary_barcode:
            barcode_type = primary_barcode.get('type', '')
            barcode_format = primary_barcode.get('format', 'PKBarcodeFormatQR')
            
            # Check if this is a Data Matrix code
            if barcode_type == 'DATAMATRIX':
                warnings.append("This PDF contains a Data Matrix code, which is not supported by Apple Wallet. The pass has been saved without a barcode for future reference when support is added.")
                print(f"⚠️ Skipping Data Matrix barcode - not supported by Apple Wallet")
            else:
                # Prefer raw bytes to preserve exact payload; fall back to text
                raw_bytes = primary_barcode.get('raw_bytes')
                barcode_data = primary_barcode.get('data', '')

                # If we have bytes, use ISO-8859-1 mapping for PassKit fidelity
                if raw_bytes is not None and isinstance(raw_bytes, (bytes, bytearray)):
                    try:
                        message_text = bytes(raw_bytes).decode('latin-1')
                    except Exception:
                        message_text = barcode_data or ''
                    pass_json['barcode'] = {
                        "format": barcode_format,
                        "message": message_text,
                        "messageEncoding": "iso-8859-1"
                    }
                    pass_json['barcodes'] = [{
                        "format": barcode_format,
                        "message": message_text,
                        "messageEncoding": "iso-8859-1"
                    }]
                    print(f"🎫 Added barcode preserving raw bytes via latin-1 ({len(raw_bytes)} bytes, format {barcode_format})")
                elif barcode_data:
                    # Avoid accidental whitespace/newlines differences vs. source
                    normalized = str(barcode_data).replace('\r\n', '\n').strip('\n')
                    pass_json['barcode'] = {
                        "format": barcode_format,
                        "message": normalized,
                        "messageEncoding": "iso-8859-1"
                    }
                    pass_json['barcodes'] = [{
                        "format": barcode_format,
                        "message": normalized,
                        "messageEncoding": "iso-8859-1"
                    }]
                    print(f"🎫 Added barcode to pass: {barcode_format} with {len(normalized)} characters")
        else:
            # Fallback: try to use barcode_data from AI extraction
            barcode_data = (pass_info.get('barcode_data') or 
                           pass_info.get('barcode_numbers') or 
                           pass_info.get('confirmation_number'))
            
            if barcode_data and len(str(barcode_data)) > 5:  # Must be meaningful length
                # Default to QR code format for text data
                pass_json['barcode'] = {
                    "format": "PKBarcodeFormatQR",
                    "message": str(barcode_data),
                    "messageEncoding": "iso-8859-1"
                }
                
                pass_json['barcodes'] = [{
                    "format": "PKBarcodeFormatQR", 
                    "message": str(barcode_data),
                    "messageEncoding": "iso-8859-1"
                }]
                
                print(f"🎫 Added fallback QR code with extracted data: {str(barcode_data)[:50]}...")
            else:
                print("⚠️ No barcode data found - pass will not have scannable code")
        
        # Color palette has already been extracted earlier in the process
        # No need to re-extract here

        # Create temporary directory for pass files
        with tempfile.TemporaryDirectory() as temp_dir:
            
            # Write pass.json
            pass_json_path = os.path.join(temp_dir, "pass.json")
            with open(pass_json_path, 'w') as f:
                json.dump(pass_json, f, indent=2)
            
            # Generate dynamic assets (icon/thumbnail) to make the pass distinctive
            try:
                self._generate_dynamic_assets(temp_dir, pdf_bytes, pass_info, bg_color, fg_color)
            except Exception as e:
                print(f"⚠️  Dynamic asset generation failed: {e}. Falling back to static icons")
                self._copy_icon_assets(temp_dir)
            
            # Create manifest.json (file hashes)
            manifest = self._create_manifest(temp_dir)
            manifest_path = os.path.join(temp_dir, "manifest.json")
            with open(manifest_path, 'w') as f:
                json.dump(manifest, f, indent=2)
            
            # Sign the manifest if certificates are available
            if self.signing_enabled:
                signature = self._sign_manifest_file(manifest_path)
                signature_path = os.path.join(temp_dir, "signature")
                with open(signature_path, 'wb') as f:
                    f.write(signature)
            
            # Create .pkpass zip file
            pkpass_data = self._create_pkpass_zip(temp_dir)
            
            return pkpass_data, warnings

    def _extract_color_palette_from_pdf_images(self, pdf_bytes: Optional[bytes]) -> Tuple[Optional[str], Optional[str], Optional[str]]:
        """Extract dominant colors by rasterizing pages and counting pixel occurrences.
        Finds the most common non-white/black color as background.
        Returns (bg, fg, label) in rgb(r, g, b) or (None, None, None) on failure.
        """
        try:
            if not pdf_bytes:
                return None, None, None

            images: List[Image.Image] = []
            # Try PyMuPDF first for speed
            try:
                import fitz  # type: ignore
                doc = fitz.open(stream=pdf_bytes, filetype='pdf')
                # Look at first 2 pages max for performance
                page_limit = min(doc.page_count, 2)
                for i in range(page_limit):
                    page = doc.load_page(i)
                    # Higher resolution for better color extraction
                    pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0))
                    images.append(Image.frombytes("RGB", [pix.width, pix.height], pix.samples))
                doc.close()
            except Exception as e:
                print(f"PyMuPDF failed: {e}")
                images = []

            if not images:
                try:
                    from pdf2image import convert_from_bytes  # type: ignore
                    images = [im.convert('RGB') for im in convert_from_bytes(pdf_bytes, first_page=1, last_page=2, dpi=150)]
                except Exception as e:
                    print(f"pdf2image failed: {e}")
                    return None, None, None

            # Accumulate color counts across all pages
            color_counter: Counter = Counter()
            
            for img in images:
                # Resize for faster processing but keep enough detail
                img.thumbnail((400, 400))
                
                # Convert to limited palette to group similar colors
                quantized = img.convert('P', palette=Image.ADAPTIVE, colors=16)
                palette = quantized.getpalette()
                
                # Count each color's occurrence
                for pixel in quantized.getdata():
                    if palette and pixel * 3 + 2 < len(palette):
                        r = palette[pixel * 3]
                        g = palette[pixel * 3 + 1]
                        b = palette[pixel * 3 + 2]
                        color_counter[(r, g, b)] += 1

            if not color_counter:
                return None, None, None

            # Filter out white, black, and very light grays
            def is_background_color(c: Tuple[int, int, int]) -> bool:
                r, g, b = c
                # Skip whites and very light colors
                if min(r, g, b) > 240:  # Very light/white
                    return False
                # Skip pure blacks
                if max(r, g, b) < 15:  # Very dark/black
                    return False
                # Skip very light grays (high brightness, low saturation)
                brightness = (r + g + b) / 3
                if brightness > 230:  # Too light
                    return False
                return True

            # Find dominant non-white/black color
            valid_colors = [(color, count) for color, count in color_counter.most_common() 
                           if is_background_color(color)]
            
            if not valid_colors:
                # No valid colors found, use a safe default
                print("No dominant colors found, using defaults")
                return "rgb(0,122,255)", "rgb(255,255,255)", "rgb(255,255,255)"
            
            # Use the most common valid color as background
            bg_rgb = valid_colors[0][0]
            
            # Calculate luminance for contrast
            def luminance(c: Tuple[int, int, int]) -> float:
                r, g, b = [x / 255.0 for x in c]
                # Use relative luminance formula
                r = r / 12.92 if r <= 0.03928 else ((r + 0.055) / 1.055) ** 2.4
                g = g / 12.92 if g <= 0.03928 else ((g + 0.055) / 1.055) ** 2.4
                b = b / 12.92 if b <= 0.03928 else ((b + 0.055) / 1.055) ** 2.4
                return 0.2126 * r + 0.7152 * g + 0.0722 * b

            bg_l = luminance(bg_rgb)
            
            # Choose foreground colors for good contrast
            if bg_l > 0.5:  # Light background
                fg_rgb = (0, 0, 0)  # Black text
                label_rgb = (50, 50, 50)  # Dark gray labels
            else:  # Dark background
                fg_rgb = (255, 255, 255)  # White text
                label_rgb = (255, 255, 255)  # White labels
            
            print(f"🎨 Extracted colors - Background: rgb{bg_rgb}, Luminance: {bg_l:.2f}")
            
            # Apple Wallet expects rgb format WITHOUT spaces after commas
            return (
                f"rgb({bg_rgb[0]},{bg_rgb[1]},{bg_rgb[2]})",
                f"rgb({fg_rgb[0]},{fg_rgb[1]},{fg_rgb[2]})",
                f"rgb({label_rgb[0]},{label_rgb[1]},{label_rgb[2]})",
            )
        except Exception as e:
            print(f"⚠️ Color extraction failed: {e}")
            import traceback
            traceback.print_exc()
            return None, None, None

    def _generate_dynamic_assets(self, temp_dir: str, pdf_bytes: Optional[bytes], pass_info: Dict[str, Any], bg_color: str, fg_color: str) -> None:
        """Generate per-pass icon and thumbnail images.
        Creates icon.png, icon@2x.png, icon@3x.png and thumbnail.png when possible.
        """
        # Parse colors
        def parse_rgb(s: str) -> Tuple[int, int, int]:
            m = re.match(r"rgb\((\d+),\s*(\d+),\s*(\d+)\)", s)
            if not m:
                return (0, 122, 255)
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        bg = parse_rgb(bg_color)
        fg = parse_rgb(fg_color)

        # Determine visual hint from metadata
        token = (pass_info.get('event_type') or pass_info.get('title') or '').lower()
        if 'flight' in token or 'air' in token:
            abbrev = 'FLY'
        elif 'concert' in token or 'music' in token or 'show' in token:
            abbrev = 'MUS'
        elif 'sport' in token or 'stadium' in token or 'game' in token:
            abbrev = 'SPT'
        elif 'train' in token or 'rail' in token:
            abbrev = 'RAIL'
        elif 'hotel' in token:
            abbrev = 'HTL'
        elif 'movie' in token or 'theater' in token:
            abbrev = 'MOV'
        elif pass_info.get('barcode') or pass_info.get('primary_barcode'):
            abbrev = 'TKT'
        else:
            abbrev = 'DOC'

        # Generate icon images (29/58/87)
        for size in [29, 58, 87]:
            img = Image.new('RGB', (size, size), bg)
            # Draw abbreviation centered
            try:
                from PIL import ImageDraw, ImageFont
                draw = ImageDraw.Draw(img)
                # Use a basic font; size proportional
                font_size = max(10, int(size * 0.42))
                try:
                    font = ImageFont.truetype("Arial.ttf", font_size)
                except Exception:
                    font = ImageFont.load_default()
                text_w, text_h = draw.textbbox((0, 0), abbrev, font=font)[2:]
                draw.text(((size - text_w) / 2, (size - text_h) / 2), abbrev, fill=fg, font=font)
            except Exception:
                pass
            out_name = 'icon.png' if size == 29 else (f"icon@2x.png" if size == 58 else f"icon@3x.png")
            img.save(os.path.join(temp_dir, out_name), format='PNG')

        # Generate thumbnail from first page if available
        thumb = None
        if pdf_bytes:
            try:
                # Try PyMuPDF
                import fitz  # type: ignore
                doc = fitz.open(stream=pdf_bytes, filetype='pdf')
                if doc.page_count:
                    page = doc.load_page(0)
                    pix = page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5))
                    thumb = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
            except Exception:
                thumb = None
            if thumb is None:
                try:
                    from pdf2image import convert_from_bytes  # type: ignore
                    pages = convert_from_bytes(pdf_bytes, first_page=1, last_page=1)
                    if pages:
                        thumb = pages[0].convert('RGB')
                except Exception:
                    thumb = None
        if thumb is not None:
            thumb.thumbnail((180, 180))
            thumb.save(os.path.join(temp_dir, 'thumbnail.png'), format='PNG')
    
    def _get_associated_store_identifiers(self) -> Optional[List[int]]:
        """Get the App Store identifiers for associated apps.
        
        Returns:
            List of iTunes Store item identifiers, or None if not configured
        """
        app_store_id = os.getenv('APP_STORE_ID')
        if app_store_id:
            try:
                # Convert to int as required by PassKit
                store_id = int(app_store_id)
                return [store_id]
            except ValueError:
                print(f"⚠️ Invalid APP_STORE_ID format: {app_store_id}")
                return None
        return None
    
    def _check_certificates_available(self) -> bool:
        """Check if all required certificate files are available.
        
        Returns:
            True if certificates are available for signing
        """
        # First check for environment variables (for Vercel deployment)
        if os.getenv('PASS_CERT_PEM') and os.getenv('PASS_KEY_PEM') and os.getenv('WWDR_CERT_PEM'):
            print("✅ Certificates found in environment variables - signing enabled")
            return True
            
        # Fallback to file-based certificates
        required_files = ['pass.pem', 'key.pem']
        
        # Check basic required files
        for filename in required_files:
            file_path = os.path.join(self.certificates_path, filename)
            if not os.path.exists(file_path):
                print(f"⚠️  Certificate file not found: {filename}")
                return False
        
        # Check for WWDR certificate (prefer G4, fallback to regular)
        wwdrg4_path = os.path.join(self.certificates_path, 'wwdrg4.pem')
        wwdr_path = os.path.join(self.certificates_path, 'wwdr.pem')
        
        if os.path.exists(wwdrg4_path):
            print("✅ All certificate files found - signing enabled with WWDR G4")
        elif os.path.exists(wwdr_path):
            print("✅ All certificate files found - signing enabled with default WWDR")
        else:
            print("⚠️  No WWDR certificate found (need wwdrg4.pem or wwdr.pem)")
            return False
        
        return True
    
    def _extract_certificate_identifiers(self) -> tuple[str, str]:
        """Extract passTypeIdentifier and teamIdentifier from the certificate.
        
        Returns:
            tuple: (passTypeIdentifier, teamIdentifier)
        """
        if not self.signing_enabled:
            return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"
        
        try:
            # Load certificate from environment or file
            if os.getenv('PASS_CERT_PEM'):
                import base64
                pass_cert_data = base64.b64decode(os.getenv('PASS_CERT_PEM'))
                pass_cert = x509.load_pem_x509_certificate(pass_cert_data)
            else:
                pass_cert_path = os.path.join(self.certificates_path, 'pass.pem')
                with open(pass_cert_path, 'rb') as f:
                    pass_cert = x509.load_pem_x509_certificate(f.read())
            
            # Extract UID from certificate subject (this is the passTypeIdentifier)
            pass_type_id = None
            team_id = None

            try:
                uid_attributes = pass_cert.subject.get_attributes_for_oid(NameOID.USER_ID)
                if uid_attributes:
                    pass_type_id = uid_attributes[0].value
            except Exception:
                pass

            try:
                ou_attributes = pass_cert.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
                if ou_attributes:
                    team_id = ou_attributes[0].value
            except Exception:
                pass
            
            if pass_type_id and team_id:
                print(f"✅ Extracted from certificate: passTypeId={pass_type_id}, teamId={team_id}")
                return pass_type_id, team_id
            else:
                print("⚠️  Could not extract identifiers from certificate, using defaults")
                return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"
                
        except Exception as e:
            print(f"❌ Error extracting certificate identifiers: {e}")
            return "pass.com.andresboedo.add2wallet", "H9DPH4DQG7"
    
    def _sign_manifest_file(self, manifest_path: str) -> bytes:
        """Sign the manifest file with the pass certificate.
        
        Args:
            manifest_path: Path to the manifest.json file
            
        Returns:
            The signature bytes
        """
        if not self.signing_enabled:
            return b""
        
        try:
            # Read the manifest file
            with open(manifest_path, 'rb') as f:
                manifest_data = f.read()
            
            # Load certificates from environment variables or files
            if os.getenv('PASS_CERT_PEM'):
                # Load from environment variables (Vercel deployment)
                import base64
                pass_cert_data = base64.b64decode(os.getenv('PASS_CERT_PEM'))
                pass_key_data = base64.b64decode(os.getenv('PASS_KEY_PEM'))  
                wwdr_cert_data = base64.b64decode(os.getenv('WWDR_CERT_PEM'))
                
                pass_cert = x509.load_pem_x509_certificate(pass_cert_data)
                private_key = serialization.load_pem_private_key(pass_key_data, password=None)
                wwdr_cert = x509.load_pem_x509_certificate(wwdr_cert_data)
                print("🔗 Using certificates from environment variables")
            else:
                # Load from files (local development)
                pass_cert_path = os.path.join(self.certificates_path, 'pass.pem')
                key_path = os.path.join(self.certificates_path, 'key.pem')
                
                # Load the pass certificate
                with open(pass_cert_path, 'rb') as f:
                    pass_cert = x509.load_pem_x509_certificate(f.read())
                
                # Load the private key
                with open(key_path, 'rb') as f:
                    private_key = serialization.load_pem_private_key(f.read(), password=None)
                
                # Load the WWDR certificate - use G4 for passes issued by G4
                wwdrg4_cert_path = os.path.join(self.certificates_path, 'wwdrg4.pem')
                if os.path.exists(wwdrg4_cert_path):
                    with open(wwdrg4_cert_path, 'rb') as f:
                        wwdr_cert = x509.load_pem_x509_certificate(f.read())
                    print("🔗 Using WWDR G4 certificate for signing")
                else:
                    # Fallback to regular WWDR certificate
                    wwdr_cert_path = os.path.join(self.certificates_path, 'wwdr.pem')
                    with open(wwdr_cert_path, 'rb') as f:
                        wwdr_cert = x509.load_pem_x509_certificate(f.read())
                    print("🔗 Using default WWDR certificate for signing")
            
            # Use Python cryptography library for signing (Vercel compatible)
            with open(manifest_path, 'rb') as f:
                manifest_data = f.read()
            
            # Apple Wallet requires a detached, binary CMS signature
            # Historically, SHA1 is used for the CMS signature of the manifest
            options = [
                pkcs7.PKCS7Options.DetachedSignature,
                pkcs7.PKCS7Options.Binary,
            ]
            # Allow selecting digest via env; default to SHA-256. iOS accepts SHA-1 or SHA-256.
            digest_name = os.getenv('PASS_SIGNATURE_DIGEST', 'sha256').lower()
            digest_algo = hashes.SHA1() if 'sha1' in digest_name else hashes.SHA256()

            signature = pkcs7.PKCS7SignatureBuilder().set_data(
                manifest_data
            ).add_signer(
                pass_cert, private_key, digest_algo
            ).add_certificate(
                pass_cert  # Add the pass certificate to the chain
            ).add_certificate(
                wwdr_cert  # Add WWDR certificate to complete the chain
            ).sign(
                serialization.Encoding.DER, options
            )
            
            return signature
            
        except Exception as e:
            print(f"❌ Error signing manifest: {e}")
            return b""
    
    def _sign_manifest(self, manifest_data: bytes) -> bytes:
        """Legacy method - kept for compatibility.
        
        Args:
            manifest_data: The manifest.json file as bytes
            
        Returns:
            The signature bytes
        """
        # Write manifest to temp file and sign it
        with tempfile.NamedTemporaryFile(mode='wb', delete=False) as f:
            f.write(manifest_data)
            temp_path = f.name
        
        try:
            signature = self._sign_manifest_file(temp_path)
            return signature
        finally:
            os.unlink(temp_path)
    
    # OpenSSL subprocess method removed for Vercel compatibility
    # Signing is now handled entirely through Python cryptography library
    
    def _extract_pdf_text(self, pdf_data: bytes) -> str:
        """Extract text content from PDF.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            Extracted text content
        """
        try:
            pdf_reader = PyPDF2.PdfReader(io.BytesIO(pdf_data))
            text_content = ""
            
            for page in pdf_reader.pages:
                text_content += page.extract_text() + "\n"
            
            return text_content.strip()
            
        except Exception as e:
            print(f"❌ Error extracting PDF text: {e}")
            return ""
    
    def _analyze_pdf_colors_enhanced(self, pdf_data: bytes, pass_info: Dict[str, Any]) -> Tuple[str, str, str]:
        """Enhanced PDF color analysis using AI metadata.
        
        Args:
            pdf_data: Raw PDF bytes
            pass_info: AI-extracted pass information
            
        Returns:
            tuple: (background_color, foreground_color, label_color)
        """
        # Use AI metadata for better color decisions
        event_type = pass_info.get('event_type', '').lower()
        event_name = pass_info.get('event_name', '').lower()
        venue_type = pass_info.get('venue_type', '').lower()
        
        # Enhanced color theming based on event type and context
        if event_type == 'flight' or 'airline' in event_name or 'airport' in venue_type:
            return "rgb(0,122,255)", "rgb(255,255,255)", "rgb(255,255,255)"  # Aviation blue
        elif event_type == 'concert' or 'music' in event_name or 'concert' in venue_type:
            return "rgb(255,45,85)", "rgb(255,255,255)", "rgb(255,255,255)"  # Concert red
        elif event_type == 'sports' or 'stadium' in venue_type:
            return "rgb(52,199,89)", "rgb(255,255,255)", "rgb(255,255,255)"  # Sports green
        elif event_type == 'train' or 'railway' in event_name:
            return "rgb(48,176,199)", "rgb(255,255,255)", "rgb(255,255,255)"  # Rail teal
        elif event_type == 'hotel' or 'reservation' in event_name:
            return "rgb(142,142,147)", "rgb(255,255,255)", "rgb(255,255,255)"  # Hotel gray
        elif event_type == 'movie' or 'theater' in venue_type:
            return "rgb(94,92,230)", "rgb(255,255,255)", "rgb(255,255,255)"  # Theater purple
        elif event_type == 'conference' or 'business' in event_name:
            return "rgb(50,173,230)", "rgb(255,255,255)", "rgb(255,255,255)"  # Business blue
        else:
            # Fall back to original color analysis
            return self._analyze_pdf_colors(pdf_data)
    
    def _analyze_pdf_colors(self, pdf_data: bytes) -> Tuple[str, str, str]:
        """Analyze PDF to suggest color palette.
        
        Args:
            pdf_data: Raw PDF bytes
            
        Returns:
            tuple: (background_color, foreground_color, label_color)
        """
        # For now, return a smart default palette based on common ticket colors
        # This is a simplified approach - full implementation would analyze actual PDF colors
        
        try:
            text = self._extract_pdf_text(pdf_data).lower()
            
            # Simple color inference based on content type
            if any(word in text for word in ['airline', 'flight', 'boarding']):
                return "rgb(0,122,255)", "rgb(255,255,255)", "rgb(255,255,255)"  # Blue theme
            elif any(word in text for word in ['concert', 'music', 'show', 'festival']):
                return "rgb(255,45,85)", "rgb(255,255,255)", "rgb(255,255,255)"   # Red theme
            elif any(word in text for word in ['train', 'railway', 'rail']):
                return "rgb(48,176,199)", "rgb(255,255,255)", "rgb(255,255,255)"  # Teal theme
            elif any(word in text for word in ['hotel', 'reservation', 'check']):
                return "rgb(142,142,147)", "rgb(255,255,255)", "rgb(255,255,255)" # Gray theme
            else:
                # Default professional blue
                return "rgb(0,122,255)", "rgb(255,255,255)", "rgb(255,255,255)"
                
        except Exception as e:
            print(f"⚠️  Error analyzing PDF colors: {e}")
            return "rgb(0,122,255)", "rgb(255,255,255)", "rgb(255,255,255)"

    def _ensure_color_contrast(self, bg_color: str, fg_color: str, label_color: str) -> Tuple[str, str, str]:
        """Ensure sufficient contrast between background and text colors.
        
        Args:
            bg_color: Background color in rgb(r,g,b) format
            fg_color: Foreground color in rgb(r,g,b) format
            label_color: Label color in rgb(r,g,b) format
            
        Returns:
            Tuple of (bg_color, fg_color, label_color) with adjusted colors for contrast
        """
        def parse_rgb(color_str: str) -> Tuple[int, int, int]:
            """Parse rgb(r,g,b) string to tuple."""
            import re
            match = re.match(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)', color_str)
            if not match:
                return (0, 0, 0)
            return (int(match.group(1)), int(match.group(2)), int(match.group(3)))
        
        def calculate_luminance(r: int, g: int, b: int) -> float:
            """Calculate relative luminance for contrast calculation.
            Based on WCAG 2.0 formula: https://www.w3.org/TR/WCAG20/#relativeluminancedef
            """
            # Normalize RGB values
            r_norm = r / 255.0
            g_norm = g / 255.0
            b_norm = b / 255.0
            
            # Apply gamma correction
            r_lin = r_norm/12.92 if r_norm <= 0.03928 else ((r_norm + 0.055)/1.055) ** 2.4
            g_lin = g_norm/12.92 if g_norm <= 0.03928 else ((g_norm + 0.055)/1.055) ** 2.4
            b_lin = b_norm/12.92 if b_norm <= 0.03928 else ((b_norm + 0.055)/1.055) ** 2.4
            
            # Calculate luminance
            return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin
        
        def contrast_ratio(lum1: float, lum2: float) -> float:
            """Calculate contrast ratio between two luminances."""
            lighter = max(lum1, lum2)
            darker = min(lum1, lum2)
            return (lighter + 0.05) / (darker + 0.05)
        
        # Parse background color
        bg_r, bg_g, bg_b = parse_rgb(bg_color)
        bg_luminance = calculate_luminance(bg_r, bg_g, bg_b)
        
        # Determine if background is light or dark
        # Using 0.25 as threshold to be more aggressive in detecting light backgrounds
        # This ensures better contrast by treating medium-light backgrounds as light
        # and using dark text for improved readability
        is_light_background = bg_luminance > 0.25
        
        # Set text colors based on background luminance
        if is_light_background:
            # Light background - use dark text
            new_fg_color = "rgb(0,0,0)"  # Black text
            new_label_color = "rgb(60,60,67)"  # Dark gray for labels
            print(f"🔲 Light background detected (luminance: {bg_luminance:.3f}) - using dark text")
        else:
            # Dark background - use light text
            new_fg_color = "rgb(255,255,255)"  # White text
            new_label_color = "rgb(255,255,255)"  # White labels
            print(f"⬜ Dark background detected (luminance: {bg_luminance:.3f}) - using light text")
        
        # Calculate and log contrast ratios for verification
        fg_r, fg_g, fg_b = parse_rgb(new_fg_color)
        fg_luminance = calculate_luminance(fg_r, fg_g, fg_b)
        contrast = contrast_ratio(bg_luminance, fg_luminance)
        
        print(f"📊 Contrast ratio: {contrast:.2f}:1 (Ultra-enhanced standard requires 18.0:1 for maximum readability)")
        
        # Ensure ultra-enhanced contrast compliance (18.0:1 for maximum readability - twice previous standard)
        if contrast < 18.0:
            print(f"⚠️  Warning: Contrast ratio {contrast:.2f} is below ultra-enhanced standard (18.0)")
        
        return bg_color, new_fg_color, new_label_color
    
    def _compute_expiration_date(self, pass_info: Dict[str, Any]) -> str:
        """Compute an ISO8601 expiration date for the pass.
        - If pass_info has an explicit date (and optional time), expire next day 03:00 local time.
        - Otherwise, expire 90 days from now.
        """
        try:
            now = datetime.utcnow()
            date_str = pass_info.get('date')
            time_str = pass_info.get('time')
            if date_str:
                # Combine if time present
                combined = f"{date_str} {time_str}" if time_str else date_str
                dt = date_parser.parse(combined, fuzzy=True, dayfirst=False)
                # Expire next day at 03:00
                expire = dt.replace(hour=3, minute=0, second=0, microsecond=0)
                if expire <= dt:
                    from datetime import timedelta
                    expire = expire + timedelta(days=1)
            else:
                from datetime import timedelta
                expire = now + timedelta(days=90)
            return expire.strftime("%Y-%m-%dT%H:%M:%SZ")
        except Exception:
            from datetime import timedelta
            return (datetime.utcnow() + timedelta(days=90)).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    def _extract_pass_info(self, pdf_text: str) -> Dict[str, str]:
        """Extract basic pass information from PDF text.
        
        Args:
            pdf_text: Extracted text from PDF
            
        Returns:
            Dictionary with extracted information
        """
        info = {
            'title': '',
            'event_name': '',
            'date': '',
            'time': '',
            'venue': '',
            'description': ''
        }
        
        lines = [line.strip() for line in pdf_text.split('\n') if line.strip()]
        
        if not lines:
            return info
        
        # Use AI service heuristics for better title extraction
        try:
            from app.services.ai_service import ai_service
            title = ai_service._basic_title_heuristics(pdf_text, "document.pdf")
            if title and title != "Digital Ticket":
                info['title'] = title
            else:
                # Fallback to first meaningful line approach
                for line in lines[:8]:  # Check more lines
                    # Skip obvious field labels and short codes
                    if (len(line) > 5 and 
                        not re.match(r'^[\d\s\-\+\(\):]+$', line) and 
                        not line.lower().startswith(('commande', 'ticket', 'date', 'acheté', 'order'))):
                        info['title'] = line[:50]
                        break
                # If still no good title found, use fallback
                if not info['title']:
                    info['title'] = "Event Ticket"
        except Exception:
            info['title'] = "Event Ticket"
        
        # Extract dates (look for various date formats)
        date_patterns = [
            r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b',  # MM/DD/YYYY, DD-MM-YYYY
            r'\b(\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})\b',     # YYYY-MM-DD
            r'\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2},? \d{4})\b',  # Month DD, YYYY
            r'\b(\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{4})\b'     # DD Month YYYY
        ]
        
        for pattern in date_patterns:
            match = re.search(pattern, pdf_text, re.IGNORECASE)
            if match:
                info['date'] = match.group(1)
                break
        
        # Extract times (look for time formats)
        time_patterns = [
            r'\b(\d{1,2}:\d{2}\s*(?:AM|PM))\b',  # 12-hour format
            r'\b(\d{1,2}:\d{2})\b'               # 24-hour format
        ]
        
        for pattern in time_patterns:
            match = re.search(pattern, pdf_text, re.IGNORECASE)
            if match:
                info['time'] = match.group(1)
                break
        
        # Smart venue extraction - look for known landmarks first, then generic patterns
        venue_text = ""
        
        # Check for famous landmarks in the text
        if "tour eiffel" in pdf_text.lower() or "eiffel tower" in pdf_text.lower():
            venue_text = "Eiffel Tower"
        elif "louvre" in pdf_text.lower():
            venue_text = "Louvre Museum"
        else:
            # Extract venue/location (look for common venue indicators)
            venue_indicators = ['venue:', 'location:', 'address:', 'at:', '@']
            for line in lines:
                line_lower = line.lower()
                for indicator in venue_indicators:
                    if indicator in line_lower:
                        raw_venue = line[line_lower.find(indicator) + len(indicator):].strip()
                        if len(raw_venue) > 3:
                            # Clean up venue text - remove contact info, URLs, etc.
                            venue_text = self._clean_venue_text(raw_venue)
                            break
                if venue_text:
                    break
        
        if venue_text:
            info['venue'] = venue_text[:100]  # Limit venue length
        
        # Create description
        if info.get('date') or info.get('time') or info.get('venue'):
            desc_parts = []
            if info.get('date'):
                desc_parts.append(info['date'])
            if info.get('time'):
                desc_parts.append(info['time'])
            if info.get('venue'):
                desc_parts.append(info['venue'])
            info['description'] = " • ".join(desc_parts)
        
        return info

    def _clean_venue_text(self, raw_venue: str) -> str:
        """Clean venue text by removing contact info, URLs, and other noise."""
        try:
            import re as _re
            
            # Remove URLs and websites
            cleaned = _re.sub(r'https?://\S+', '', raw_venue)
            cleaned = _re.sub(r'www\.\S+', '', cleaned)
            cleaned = _re.sub(r'\S+\.\S+\.\S+', '', cleaned)  # Remove domain-like strings
            
            # Remove phone numbers
            cleaned = _re.sub(r'\+?\d{1,4}[-.\s]?\(?\d{1,4}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,6}', '', cleaned)
            
            # Remove email-like patterns
            cleaned = _re.sub(r'\S+@\S+', '', cleaned)
            
            # Remove "Our customer service" and similar phrases
            cleaned = _re.sub(r'(?i)(our|customer|service|support|contact|info|information|call|phone|email|price\s+of\s+a)', '', cleaned)
            
            # Clean up multiple spaces and special chars
            cleaned = _re.sub(r'[/\\|]+', ' ', cleaned)  # Replace slashes with spaces
            cleaned = _re.sub(r'\s+', ' ', cleaned).strip()
            
            # If result is too short or empty, return original
            if len(cleaned.strip()) < 3:
                # Try to extract just the first meaningful part before contact info
                parts = raw_venue.split('/')
                if len(parts) > 0:
                    first_part = parts[0].strip()
                    if len(first_part) > 3:
                        return first_part
                return raw_venue
                
            return cleaned.strip()
            
        except Exception:
            return raw_venue

    def _sanitize_title(self, title: str, fallback_name: Optional[str] = None) -> str:
        """Ensure the pass title is human-friendly and not a code/UUID.
        Falls back to a cleaned name when it looks like a code.
        """
        try:
            import re as _re
            if not title or not title.strip():
                cleaned = (fallback_name or "Ticket").replace("_", " ").strip()
                return cleaned[:30] if cleaned else "Ticket"

            cleaned = _re.sub(r"\s+", " ", title.replace("_", " ")).strip().strip('"')

            # UUID patterns (hyphenated and compact 32-hex)
            if _re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", cleaned) or \
               _re.fullmatch(r"[0-9a-fA-F]{32}", cleaned):
                cleaned_fb = (fallback_name or "Digital Pass").replace("_", " ").strip()
                print(f"⚠️ Title looks like UUID, using fallback: {cleaned_fb}")
                return cleaned_fb[:30] if cleaned_fb else "Digital Pass"

            # Too few letters (likely a code) - but be more lenient
            letters_only = _re.sub(r"[^A-Za-z]", "", cleaned)
            if len(letters_only) < 2:  # Changed from 3 to 2
                cleaned_fb = (fallback_name or "Ticket").replace("_", " ").strip()
                print(f"⚠️ Title has too few letters, using fallback: {cleaned_fb}")
                return cleaned_fb[:30] if cleaned_fb else "Ticket"

            # Obvious code-like: long single token without spaces
            if " " not in cleaned and len(cleaned) >= 20:  # Changed from 16 to 20
                cleaned_fb = (fallback_name or "Digital Pass").replace("_", " ").strip()
                print(f"⚠️ Title looks like a long code, using fallback: {cleaned_fb}")
                return cleaned_fb[:30] if cleaned_fb else "Digital Pass"

            # Heuristic: mostly digits/hex characters - be more lenient
            hex_chars = len(_re.findall(r"[0-9A-Fa-f]", cleaned))
            if hex_chars / max(1, len(cleaned)) > 0.8:  # Changed from 0.7 to 0.8
                cleaned_fb = (fallback_name or "Digital Pass").replace("_", " ").strip()
                print(f"⚠️ Title is mostly hex chars, using fallback: {cleaned_fb}")
                return cleaned_fb[:30] if cleaned_fb else "Digital Pass"

            # Only reject if title is ONLY these suspicious tokens, not if it contains them as part of a larger title
            suspicious = ["ADULT", "CHILD", "SENIOR", "INFANT", "YOUTH", "ZONE", "SEAT", "CLASS", "TYPE", "FARE"]
            upper_cleaned = cleaned.upper().strip()
            if upper_cleaned in suspicious:  # Changed from 'any tok in' to exact match
                cleaned_fb = (fallback_name or "Digital Pass").replace("_", " ").strip()
                print(f"⚠️ Title is just a fare class '{upper_cleaned}', using fallback: {cleaned_fb}")
                return cleaned_fb[:30] if cleaned_fb else "Digital Pass"

            # Remove redundant suffixes like "Ticket", "Event", "Receipt" from the end of titles
            redundant_suffixes = [" Ticket", " Event", " Receipt", " Pass", " Voucher", " E-ticket", " Eticket"]
            for suffix in redundant_suffixes:
                if cleaned.endswith(suffix):
                    cleaned = cleaned[:-len(suffix)].strip()
                    print(f"🔄 Removed redundant suffix '{suffix}' from title")
                    break
                # Also check case-insensitive version
                elif cleaned.lower().endswith(suffix.lower()):
                    cleaned = cleaned[:-len(suffix)].strip()
                    print(f"🔄 Removed redundant suffix '{suffix}' from title (case-insensitive)")
                    break

            print(f"✅ Using sanitized title: {cleaned[:30]}")
            return cleaned[:30]
        except Exception as e:
            print(f"❌ Title sanitization error: {e}")
            return (fallback_name or "Digital Pass")[:30] if fallback_name else "Digital Pass"

    def _sanitize_description(self, description: str, pass_info: Dict[str, Any], filename: str) -> str:
        """Avoid showing UUIDs/codes as subtitle. Prefer human info like date/venue.
        """
        try:
            import re as _re
            desc = (description or "").strip()
            looks_like_uuid = _re.match(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", desc) is not None
            mostly_code = len(_re.sub(r"[A-Za-z]", "", desc)) > len(_re.sub(r"[^A-Za-z]", "", desc))
            if not desc or looks_like_uuid or mostly_code:
                parts: list[str] = []
                if pass_info.get('date'):
                    parts.append(str(pass_info['date']))
                if pass_info.get('time'):
                    parts.append(str(pass_info['time']))
                if pass_info.get('venue_name') or pass_info.get('venue'):
                    parts.append(str(pass_info.get('venue_name') or pass_info.get('venue')))
                fallback = " • ".join(parts) if parts else f"Digital pass from {filename}"
                return fallback[:80]
            return desc[:80]
        except Exception:
            return f"Digital pass from {filename}"[:80]

    def _consolidate_barcodes_for_single_pass(self, barcodes: List[Dict[str, Any]], filename: str) -> List[Dict[str, Any]]:
        """Consolidate barcodes for single-pass documents to avoid creating multiple passes.
        
        This handles cases where:
        1. The same barcode appears multiple times in different formats (visual + text)
        2. Multiple related barcode data strings are extracted from text but represent the same logical code
        3. Data Matrix codes that should result in a single pass
        
        Args:
            barcodes: List of detected barcodes
            filename: PDF filename for context
            
        Returns:
            Consolidated list of barcodes (usually 1 for single-pass documents)
        """
        if not barcodes:
            return barcodes
        
        if len(barcodes) == 1:
            return barcodes
        
        print(f"🔄 Consolidating {len(barcodes)} barcodes for single-pass document")
        
        # Group barcodes by detection method
        visual_barcodes = [bc for bc in barcodes if bc.get('source') != 'text-analysis']
        text_barcodes = [bc for bc in barcodes if bc.get('source') == 'text-analysis']
        
        print(f"   Visual: {len(visual_barcodes)}, Text: {len(text_barcodes)}")
        
        # Strategy 1: If we have visual barcodes, prefer them over text extraction
        if visual_barcodes:
            print("   ✅ Using visual detection results (more reliable)")
            return visual_barcodes
        
        # Strategy 2: For text-only detection, check if we should consolidate
        if text_barcodes:
            # Check if all text barcodes are the same type and from similar sources
            same_type = len(set(bc.get('type') for bc in text_barcodes)) == 1
            same_method_pattern = len(set(bc.get('method', '').split('_')[0] for bc in text_barcodes)) == 1
            
            print(f"   Same type: {same_type}, Same method pattern: {same_method_pattern}")
            
            # Check for duplicate identical barcodes (user's feedback about identical QR codes from single Data Matrix)
            unique_data = list(set(bc.get('data', '') for bc in text_barcodes))
            has_duplicates = len(unique_data) < len(text_barcodes)
            
            print(f"   Unique data strings: {len(unique_data)}, Has duplicates: {has_duplicates}")
            
            # Consolidation heuristics
            should_consolidate = False
            consolidation_reason = ""
            
            # Heuristic 1: Identical QR codes from single Data Matrix (user's feedback)
            if has_duplicates and len(text_barcodes) <= 3:
                should_consolidate = True
                consolidation_reason = "duplicate_barcodes"
            
            # Heuristic 2: Data Matrix from text extraction in single-pass document
            elif same_type and text_barcodes[0].get('type') == 'DATAMATRIX' and len(text_barcodes) <= 3:
                filename_lower = filename.lower()
                single_pass_hints = ['ticket', 'pass', 'boarding', 'admission', 'data_matrix', 'datamatrix']
                
                if any(hint in filename_lower for hint in single_pass_hints):
                    should_consolidate = True
                    consolidation_reason = "single_pass_datamatrix"
            
            # Heuristic 3: Same type QR codes that might be misidentified Data Matrix
            elif same_type and text_barcodes[0].get('type') == 'QRCODE' and len(text_barcodes) <= 3:
                filename_lower = filename.lower()
                datamatrix_hints = ['data_matrix', 'datamatrix']
                
                if any(hint in filename_lower for hint in datamatrix_hints):
                    should_consolidate = True
                    consolidation_reason = "qr_likely_datamatrix"
                    # Re-classify as Data Matrix since filename suggests it
                    for bc in text_barcodes:
                        bc['type'] = 'DATAMATRIX'
                        bc['format'] = 'PKBarcodeFormatQR'  # Data Matrix uses QR format in Apple Wallet
                        bc['reclassified'] = True
                        bc['original_type'] = 'QRCODE'
            
            if should_consolidate:
                print(f"   📋 Consolidating due to: {consolidation_reason}")
                
                # Select best barcode (longest data, highest confidence, etc.)
                best_barcode = max(text_barcodes, key=lambda bc: (
                    len(bc.get('data', '')),
                    bc.get('confidence', 0),
                    -bc.get('center_distance', float('inf'))
                ))
                
                print(f"   ✅ Selected best barcode: {best_barcode.get('data', '')[:30]}... ({len(best_barcode.get('data', ''))} chars)")
                
                # Add metadata about consolidation
                best_barcode['consolidated_from'] = len(text_barcodes)
                best_barcode['consolidation_method'] = consolidation_reason
                
                return [best_barcode]
        
        # Strategy 3: Default behavior - return all barcodes if no consolidation applies
        print("   🔄 No consolidation applied, using all barcodes")
        return barcodes


# Global instance
pass_generator = PassGenerator()