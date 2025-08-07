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
                self.client = OpenAI(api_key=self.api_key)
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
            
            return enriched_info
            
        except Exception as e:
            logger.error(f"❌ Error in AI analysis: {str(e)}")
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
        prompt = f"""
        Analyze the following PDF content and extract structured information. This appears to be from a file named "{filename}".

        PDF Content:
        {pdf_text[:4000]}  # Limit content to avoid token limits

        Extract the following information and return as JSON:
        {{
            "event_type": "concert|flight|hotel|train|movie|conference|sports|other",
            "event_name": "Full name of event/service",
            "title": "Short title for wallet pass",
            "description": "Brief description",
            "date": "Event date (YYYY-MM-DD format if possible)",
            "time": "Event time (HH:MM format if possible)", 
            "venue_name": "Venue or location name",
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
            "additional_info": "Any other relevant details",
            "confidence_score": "0-100 indicating extraction confidence"
        }}

        Important: 
        - Only include information that is clearly present in the text
        - Use null for missing information
        - Standardize date/time formats
        - Be precise with venue names and addresses
        - Identify the document type accurately
        - Look carefully for any barcode, QR code, or reference numbers
        - Extract any long numerical strings that could be barcodes
        - Identify ticket numbers, confirmation codes, and reference IDs
        """

        try:
            response = self.client.chat.completions.create(
                model="gpt-4",
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
        
        # Create search query for location
        location_query = f"{venue_name} {venue_address} {city}".strip()
        
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
                model="gpt-4",
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
    
    def _create_fallback_metadata(self, pdf_text: str, filename: str) -> Dict[str, Any]:
        """Create fallback metadata using basic pattern matching.
        
        Args:
            pdf_text: Raw PDF text
            filename: Original filename
            
        Returns:
            Basic metadata dictionary
        """
        logger.info("🔄 Using fallback metadata extraction")
        
        # Use simplified extraction similar to existing pass_generator logic
        lines = [line.strip() for line in pdf_text.split('\n') if line.strip()]
        
        # Extract title from first meaningful line
        title = filename.replace('.pdf', '').replace('_', ' ').title()
        for line in lines[:5]:
            if len(line) > 3 and not re.match(r'^[\d\s\-\+\(\)]+$', line):
                title = line[:50]
                break
        
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