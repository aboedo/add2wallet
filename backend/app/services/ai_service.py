"""AI-powered PDF analysis and event enrichment service using OpenAI."""

import os
import json
import re
import logging
import asyncio
from typing import Dict, Any, Optional, List, Tuple
from datetime import datetime
import requests
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class AIService:
    """Service for AI-powered PDF analysis and event enrichment."""
    
    def __init__(self, api_key: Optional[str] = None):
        """Initialize the AI service.
        
        Args:
            api_key: OpenAI API key. If None, will read from environment.
        """
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        self.ai_enabled = bool(self.api_key)
        
        if self.ai_enabled:
            try:
                # Initialize with minimal configuration for serverless environments
                self.client = OpenAI(
                    api_key=self.api_key,
                    timeout=30.0
                )
                logger.info("🤖 AI service initialized successfully with OpenAI")
            except Exception as e:
                logger.error(f"❌ Failed to initialize OpenAI client: {e}")
                self.ai_enabled = False
                self.client = None
        else:
            logger.warning("⚠️ OpenAI API key not found. AI features disabled.")
            self.client = None
        
        self._cache = {}  # Simple in-memory cache for venue lookups
    
    async def analyze_pdf_content(self, pdf_text: str, filename: str) -> Dict[str, Any]:
        """Analyze PDF content using OpenAI to extract structured metadata.
        
        Args:
            pdf_text: Raw text extracted from PDF
            filename: Original filename for context
            
        Returns:
            Dictionary with extracted metadata
        """
        if not self.ai_enabled:
            logger.warning("🔄 AI disabled, using fallback metadata extraction")
            return self._create_fallback_metadata(pdf_text, filename)
        
        logger.info(f"🤖 Starting AI analysis of PDF: {filename}")
        
        try:
            # Step 1: Extract basic information from PDF
            basic_info = await self._extract_pdf_metadata(pdf_text, filename)
            logger.info(f"📋 Basic info extracted: {basic_info.get('event_name', 'Unknown')}")
            
            # Step 2: Enrich with web search if we have enough information
            enriched_info = await self._enrich_event_data(basic_info)
            logger.info(f"🌐 Enrichment completed with {len(enriched_info)} fields")

            # Step 3: Refine the user-facing title to avoid codes like "ADULT 12 UY"
            try:
                title_result = await self._refine_title(pdf_text, enriched_info, filename)
                if title_result and title_result.get("title"):
                    enriched_info["title"] = title_result["title"]
                    if not enriched_info.get("event_name"):
                        enriched_info["event_name"] = title_result["title"]
                    enriched_info["title_confidence"] = title_result.get("confidence")
                    enriched_info["title_refined"] = True
                    logger.info(f"🏷️ Refined title: {enriched_info['title']}")
            except Exception as e:
                logger.warning(f"⚠️ Title refinement failed, using extracted title: {e}")
                # Best-effort heuristic fallback
                heuristic_title = self._basic_title_heuristics(pdf_text, filename) or enriched_info.get("title")
                if heuristic_title:
                    enriched_info.setdefault("title", heuristic_title)
            
            return enriched_info
            
        except Exception as e:
            logger.error(f"❌ Error in AI analysis: {str(e)}")
            import traceback
            traceback.print_exc()
            return self._create_fallback_metadata(pdf_text, filename)
    
    async def _extract_pdf_metadata(self, pdf_text: str, filename: str) -> Dict[str, Any]:
        """Extract structured metadata from PDF text using OpenAI.
        
        Args:
            pdf_text: Raw text from PDF
            filename: Original filename
            
        Returns:
            Dictionary with extracted metadata
        """
        if not self.ai_enabled:
            return self._create_fallback_metadata(pdf_text, filename)
            
        # Design a comprehensive prompt for metadata extraction  
        safe_pdf_text = pdf_text[:4000].replace('{', '{{').replace('}', '}}').replace('%', '%%')
        
        prompt = """You are preparing content for an Apple Wallet pass. Your job is to extract the PRIMARY SUBJECT from this document - what did the user actually buy access to?

FILE: {}
DOCUMENT CONTENT:
{}

INSTRUCTIONS:
1. SCAN the document for PROMINENT proper nouns, brand names, venue names, or show titles
2. IGNORE fine print, legal text, terms and conditions
3. LOOK for what is displayed most prominently (usually at the top)
4. IF you find descriptors like "2 parks", "3 days", "multi-venue", combine them with the main subject
5. The title should answer: "What did I buy a ticket for?"

Return JSON with extracted information:
{{
    "event_type": "concert|flight|hotel|train|movie|conference|sports|museum|attraction|other",
    "event_name": "The PRIMARY SUBJECT of this ticket - what the user is actually going to see/do/experience",
    "title": "Concise title (max 30 chars) combining the MAIN SUBJECT with any relevant descriptors. Extract the primary proper noun/brand from the document and combine with scope/duration if present. Never return generic terms like 'ticket' or '2 parks' without the actual venue/brand name.",
    "description": "Brief description",
    "date": "Event date (YYYY-MM-DD format if possible)",
    "time": "Event time (HH:MM format if possible)", 
    "venue_name": "Venue or location name - just the venue, not contact info",
    "venue_address": "Full address if available",
    "city": "City name",
    "state_country": "State/Province/Country",
    "organizer": "Event organizer or company",
    "seat_info": "Seat, row, section info",
    "barcode_data": "Any barcode or QR code text found in the document",
    "barcode_numbers": "Any numerical codes that might be barcodes",
    "qr_text": "Any text that appears to be from a QR code",
    "price": "Ticket price if mentioned",
    "confirmation_number": "Booking/confirmation number",
    "gate_info": "Gate, platform, or check-in info",
    "latitude": "GPS latitude if location known",
    "longitude": "GPS longitude if location known",
    "additional_info": "Any other relevant details",
    "confidence_score": "0-100 indicating extraction confidence"
}}

Important: 
- For most fields, include information that is clearly present in the text
- Use null for missing information
- Standardize date/time formats
- For venue_name, extract ONLY the venue name (e.g., 'Eiffel Tower'), not contact info or website URLs
- Be precise with venue names and addresses
- Identify the document type accurately
- Look carefully for any barcode, QR code, or reference numbers
- Extract any long numerical strings that could be barcodes
- Identify ticket numbers, confirmation codes, and reference IDs
- For the "title", find the most PROMINENT proper noun, brand name, or venue name in the document
- COMBINE that main subject with any descriptors (2 parks, 3 days, etc.) found in the document
- IGNORE legal headers, terms, conditions - focus on what's prominently displayed
- The title should be specific enough that someone would recognize what they bought
""".format(filename, safe_pdf_text)

        try:
            response = self.client.chat.completions.create(
                model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                messages=[
                    {
                        "role": "system", 
                        "content": "You are an expert at analyzing ticket and booking documents. Extract information accurately and return valid JSON."
                    },
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1,  # Low temperature for consistent extraction
                max_tokens=1000
            )
            
            # Parse the response
            response_text = response.choices[0].message.content.strip()
            logger.info(f"📱 OpenAI response: {response_text[:200]}...")
            
            # Clean up response and extract JSON
            if "```json" in response_text:
                json_start = response_text.find("```json") + 7
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()
            elif "{" in response_text:
                # Find first { and last }
                json_start = response_text.find("{")
                json_end = response_text.rfind("}") + 1
                response_text = response_text[json_start:json_end]
            
            extracted_data = json.loads(response_text)
            
            # Add processing metadata
            extracted_data["ai_processed"] = True
            extracted_data["processing_timestamp"] = datetime.now().isoformat()
            extracted_data["model_used"] = "gpt-4"
            
            return extracted_data
            
        except json.JSONDecodeError as e:
            logger.error(f"❌ Failed to parse JSON response: {e}")
            return self._create_fallback_metadata(pdf_text, filename)
        except Exception as e:
            logger.error(f"❌ OpenAI API error: {e}")
            return self._create_fallback_metadata(pdf_text, filename)

    async def _refine_title(self, pdf_text: str, metadata: Dict[str, Any], filename: str) -> Dict[str, Any]:
        """Use OpenAI to generate a concise, user-friendly pass title.
        Returns dict with keys: title, confidence.
        """
        if not self.ai_enabled:
            return {"title": self._basic_title_heuristics(pdf_text, filename), "confidence": 40}

        try:
            context = {
                "filename": filename,
                "event_type": metadata.get("event_type"),
                "event_name": metadata.get("event_name"),
                "venue_name": metadata.get("venue_name"),
                "date": metadata.get("date"),
                "time": metadata.get("time"),
                "existing_title": metadata.get("title"),
            }

            prompt = (
                "Create a concise, meaningful title for an Apple Wallet pass.\n"
                "CRITICAL: Identify the PRIMARY SUBJECT from the document - what did the user actually buy?\n\n"
                "Context-aware rules:\n"
                "- Max 30 characters\n"
                "- For shows/concerts: Use the performance/artist name (e.g., 'Hamilton', 'Taylor Swift')\n"
                "- For attractions: Use the venue/attraction name (e.g., 'Louvre Museum', 'Empire State')\n"
                "- For transportation: Use route or flight info (e.g., 'NYC-LAX', 'Flight AA123')\n"
                "- For multi-venue passes: Extract the brand/system name from the document and combine with scope\n"
                "- Look for brand names, venue names, show titles in the actual document text\n"
                "- If you see '2 parks' or '3 days', find the associated brand/venue name in the document\n"
                "- Never return just descriptors like '2 parks' without the actual venue/brand\n"
                "- Avoid generic labels like 'ADULT', 'CHILD', codes, or SKUs\n\n"
                f"Existing data: {json.dumps(context)[:1500]}\n\n"
                f"PDF excerpt:\n{pdf_text[:1500].replace('{', '{{').replace('}', '}}')}\n\n"
                "Analyze the document to find the most specific name/brand/venue mentioned.\n"
                "Return JSON: {\"title\": \"<specific meaningful title>\", \"confidence\": 0-100}"
            )

            response = self.client.chat.completions.create(
                model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                messages=[
                    {"role": "system", "content": "You generate short, clean titles for Wallet passes."},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.2,
                max_tokens=200,
            )

            text = response.choices[0].message.content.strip()
            if "```json" in text:
                s = text.find("```json") + 7
                e = text.find("```", s)
                text = text[s:e].strip()
            return json.loads(text)
        except Exception as e:
            logger.warning(f"Title refinement via AI failed: {e}")
            return {"title": self._basic_title_heuristics(pdf_text, filename), "confidence": 40}
    
    async def _enrich_event_data(self, basic_info: Dict[str, Any]) -> Dict[str, Any]:
        """Enrich event data with web search and location lookup.
        
        Args:
            basic_info: Basic information extracted from PDF
            
        Returns:
            Enhanced information with additional context
        """
        enriched = basic_info.copy()
        
        try:
            # Step 1: Get GPS coordinates for venue
            if basic_info.get('venue_name') or basic_info.get('venue_address'):
                location_info = await self._get_location_info(basic_info)
                enriched.update(location_info)
            
            # Step 2: Search for event details online
            if basic_info.get('event_name') and basic_info.get('date'):
                event_details = await self._search_event_details(basic_info)
                enriched.update(event_details)
            
            # Step 3: Enhance venue information
            if basic_info.get('venue_name') and basic_info.get('city'):
                venue_details = await self._get_venue_details(basic_info)
                enriched.update(venue_details)
            
            enriched["enrichment_completed"] = True
            return enriched
            
        except Exception as e:
            logger.error(f"❌ Error in event enrichment: {e}")
            enriched["enrichment_completed"] = False
            return enriched
    
    async def _get_location_info(self, event_info: Dict[str, Any]) -> Dict[str, Any]:
        """Get GPS coordinates and detailed location information.
        
        Args:
            event_info: Event information with venue details
            
        Returns:
            Dictionary with location enhancements
        """
        venue_name = event_info.get('venue_name', '')
        venue_address = event_info.get('venue_address', '')
        city = event_info.get('city', '')
        state_country = event_info.get('state_country', '')
        event_name = event_info.get('event_name', '')
        date = event_info.get('date', '')
        
        # Create search query for location (fallback to event name when venue info missing)
        base_parts = [venue_name, venue_address, city, state_country]
        if not any(p.strip() for p in base_parts):
            base_parts = [event_name, city, state_country, date]
        location_query = " ".join([p for p in base_parts if p and p.strip()])
        
        # Check cache first
        cache_key = f"location:{location_query}"
        if cache_key in self._cache:
            logger.info(f"📍 Using cached location data for: {venue_name}")
            return self._cache[cache_key]
        
        try:
            # Use OpenAI to search for and validate location information
            prompt = f"""
            Find detailed location information for: "{location_query}"
            
            Search online and provide accurate information in JSON format:
            {{
                "latitude": "GPS latitude as float",
                "longitude": "GPS longitude as float", 
                "formatted_address": "Complete standardized address",
                "venue_type": "Type of venue (stadium, theater, airport, etc.)",
                "capacity": "Venue capacity if known",
                "website": "Official venue website",
                "phone": "Venue phone number",
                "nearby_landmarks": ["list", "of", "nearby", "landmarks"],
                "public_transport": "Nearby public transport info",
                "parking_info": "Parking availability info"
            }}
            
            Only return information you can verify. Use null for unknown values.
            """

            response = self.client.chat.completions.create(
                model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                messages=[
                    {
                        "role": "system",
                        "content": "You are a location expert. Search for and provide accurate venue information. Only return verified data."
                    },
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1,
                max_tokens=800
            )

            response_text = response.choices[0].message.content.strip()
            
            # Clean and parse JSON response
            if "```json" in response_text:
                json_start = response_text.find("```json") + 7
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()
            
            location_data = json.loads(response_text)
            
            # Cache the result
            self._cache[cache_key] = location_data
            
            logger.info(f"📍 Found location data for {venue_name}")
            return location_data
            
        except Exception as e:
            logger.error(f"❌ Error getting location info: {e}")
            return {
                "location_lookup_failed": True,
                "error": str(e)
            }
    
    async def _search_event_details(self, event_info: Dict[str, Any]) -> Dict[str, Any]:
        """Search for additional event details online.
        
        Args:
            event_info: Basic event information
            
        Returns:
            Dictionary with additional event details
        """
        event_name = event_info.get('event_name', '')
        date = event_info.get('date', '')
        city = event_info.get('city', '')
        
        search_query = f"{event_name} {date} {city}".strip()
        cache_key = f"event:{search_query}"
        
        if cache_key in self._cache:
            return self._cache[cache_key]
        
        try:
            prompt = f"""
            Search for event details: "{search_query}"
            
            Find and return information in JSON format:
            {{
                "event_description": "Detailed description of the event",
                "event_category": "More specific category",
                "performer_artist": "Main performer, artist, or speaker",
                "duration": "Event duration if known",
                "age_restriction": "Age restrictions if any",
                "dress_code": "Dress code if mentioned",
                "official_website": "Official event website",
                "social_media": "Official social media links",
                "additional_dates": "Other dates for same event/tour",
                "ticket_provider": "Official ticket provider",
                "similar_events": "Similar upcoming events",
                "weather_considerations": "Outdoor event weather info"
            }}
            
            Only return verified information found online.
            """

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {
                        "role": "system",
                        "content": "You are an event research specialist. Find accurate, up-to-date event information."
                    },
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1,
                max_tokens=800
            )

            response_text = response.choices[0].message.content.strip()
            
            # Parse JSON response
            if "```json" in response_text:
                json_start = response_text.find("```json") + 7
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()
            
            event_details = json.loads(response_text)
            self._cache[cache_key] = event_details
            
            logger.info(f"🎪 Found event details for {event_name}")
            return event_details
            
        except Exception as e:
            logger.error(f"❌ Error searching event details: {e}")
            return {
                "event_search_failed": True,
                "error": str(e)
            }
    
    async def _get_venue_details(self, event_info: Dict[str, Any]) -> Dict[str, Any]:
        """Get detailed venue information.
        
        Args:
            event_info: Event information with venue name
            
        Returns:
            Dictionary with venue details
        """
        venue_name = event_info.get('venue_name', '')
        city = event_info.get('city', '')
        
        venue_query = f"{venue_name} {city}".strip()
        cache_key = f"venue:{venue_query}"
        
        if cache_key in self._cache:
            return self._cache[cache_key]
        
        try:
            prompt = f"""
            Get detailed venue information for: "{venue_query}"
            
            Return information in JSON format:
            {{
                "venue_description": "Description of the venue",
                "seating_chart_url": "URL to seating chart if available",
                "amenities": ["list", "of", "venue", "amenities"],
                "accessibility": "Accessibility information",
                "food_options": "Food and beverage options",
                "security_info": "Security and entry requirements",
                "history": "Brief venue history if notable",
                "upcoming_events": "Other notable upcoming events"
            }}
            """

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {
                        "role": "system",
                        "content": "You are a venue information specialist. Provide helpful venue details."
                    },
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1,
                max_tokens=600
            )

            response_text = response.choices[0].message.content.strip()
            
            # Parse JSON response
            if "```json" in response_text:
                json_start = response_text.find("```json") + 7
                json_end = response_text.find("```", json_start)
                response_text = response_text[json_start:json_end].strip()
            
            venue_details = json.loads(response_text)
            self._cache[cache_key] = venue_details
            
            logger.info(f"🏟️ Found venue details for {venue_name}")
            return venue_details
            
        except Exception as e:
            logger.error(f"❌ Error getting venue details: {e}")
            return {
                "venue_search_failed": True,
                "error": str(e)
            }
    
    def _basic_title_heuristics(self, pdf_text: str, filename: str) -> str:
        """Heuristic title picker when AI is unavailable.
        Focus on user-friendly names and avoid code-like strings.
        """
        text = pdf_text or ""
        t = text.lower()
        
        # Transportation
        if "boarding" in t and ("airlines" in t or "airline" in t or re.search(r"\bflight\b", t)):
            m = re.search(r"\b([A-Z]{2})\s?\d{2,4}\b", pdf_text)
            if m:
                return f"Boarding Pass {m.group(1)}"
            return "Boarding Pass"
        
        # Generic patterns
        if "billet" in t or "entrada" in t or "ticket" in t:
            return "Event Ticket"
        
        # Fallback to cleaned filename
        base = filename.replace('.pdf', '').replace('_', ' ').strip()
        base = re.sub(r"\s+", " ", base)
        # Avoid titles that are mostly numbers or codes
        if len(re.sub(r"[^A-Za-z]", "", base)) < 3:
            return "Digital Ticket"
        # Trim to sensible length
        return base[:30]
    
    def _create_fallback_metadata(self, pdf_text: str, filename: str) -> Dict[str, Any]:
        """Create fallback metadata using basic pattern matching.
        
        Args:
            pdf_text: Raw PDF text
            filename: Original filename
            
        Returns:
            Basic metadata dictionary
        """
        logger.info("🔄 Using fallback metadata extraction")
        
        # Use simplified extraction with improved title heuristics
        lines = [line.strip() for line in pdf_text.split('\n') if line.strip()]
        
        # Prefer heuristic title over naive first line
        title = self._basic_title_heuristics(pdf_text, filename)
        
        # Basic date extraction
        date_pattern = r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b'
        date_match = re.search(date_pattern, pdf_text)
        
        # Basic time extraction
        time_pattern = r'\b(\d{1,2}:\d{2}\s*(?:AM|PM)?)\b'
        time_match = re.search(time_pattern, pdf_text, re.IGNORECASE)
        
        return {
            "event_type": "other",
            "event_name": title,
            "title": title,
            "description": f"Digital pass from {filename}",
            "date": date_match.group(1) if date_match else None,
            "time": time_match.group(1) if time_match else None,
            "ai_processed": False,
            "fallback_used": True,
            "processing_timestamp": datetime.now().isoformat(),
            "confidence_score": 30
        }


# Global instance
ai_service = AIService()