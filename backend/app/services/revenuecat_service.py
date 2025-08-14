import os
import requests
from typing import Optional, Dict, Any
from dotenv import load_dotenv
import logging

# Load environment variables
load_dotenv()

logger = logging.getLogger(__name__)

class RevenueCatService:
    """Service for interacting with RevenueCat API"""
    
    def __init__(self):
        self.secret_key = os.getenv("REVENUECAT_SECRET_KEY")
        self.base_url = "https://api.revenuecat.com/v1"
        
        if self.secret_key:
            logger.info(f"RevenueCat service initialized with secret key: sk_***{self.secret_key[-8:]}")
            self.headers = {
                "Authorization": f"Bearer {self.secret_key}",
                "Content-Type": "application/json"
            }
        else:
            logger.warning("RevenueCat secret key not found in environment variables")
            self.headers = {}
    
    def deduct_pass(self, user_id: str, is_retry: bool = False) -> bool:
        """
        Deduct 1 PASS from the user's virtual currency balance
        
        Args:
            user_id: The user's RevenueCat app user ID
            is_retry: If True, skip deduction (for retries)
            
        Returns:
            True if deduction was successful or skipped (retry), False otherwise
        """
        logger.info(f"🔄 DEDUCT_PASS CALLED: user_id='{user_id}' (type: {type(user_id)}), is_retry={is_retry}")
        logger.info(f"🔑 RevenueCat service state: secret_key={'present' if self.secret_key else 'MISSING'}")
        
        if is_retry:
            logger.info(f"⏭️ Skipping PASS deduction for retry (user: {user_id})")
            return True
        
        if not self.secret_key:
            logger.warning("❌ RevenueCat secret key not configured, skipping PASS deduction")
            return True  # Return True to not block pass generation
            
        if not user_id or user_id.strip() == "":
            logger.error(f"❌ Invalid user_id provided: '{user_id}'")
            return False
        
        try:
            # RevenueCat virtual currency transaction endpoint
            url = f"{self.base_url}/subscribers/{user_id}/virtual_currencies/PASS/transactions"
            
            payload = {
                "amount": -1,  # Negative value to deduct
                "transaction_id": f"pass_gen_{user_id}_{os.urandom(8).hex()}",  # Unique transaction ID
                "metadata": {
                    "type": "pass_generation",
                    "source": "backend"
                }
            }
            
            logger.info(f"Making RevenueCat API call to: {url}")
            logger.info(f"Payload: {payload}")
            logger.info(f"Headers: {dict(self.headers)}")
            
            response = requests.post(url, json=payload, headers=self.headers, timeout=10)
            
            logger.info(f"RevenueCat API Response - Status: {response.status_code}")
            logger.info(f"RevenueCat API Response - Body: {response.text}")
            logger.info(f"RevenueCat API Response - Headers: {dict(response.headers)}")
            
            if response.status_code == 200:
                logger.info(f"✅ Successfully deducted 1 PASS from user {user_id}")
                return True
            elif response.status_code == 404:
                logger.warning(f"❌ User {user_id} not found in RevenueCat")
                return False
            elif response.status_code == 400:
                # Might mean insufficient balance
                logger.warning(f"❌ Failed to deduct PASS for user {user_id} (Bad Request): {response.text}")
                return False
            else:
                logger.error(f"❌ RevenueCat API error: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Error calling RevenueCat API: {str(e)}")
            # Don't block pass generation if RevenueCat is down
            return True
        except Exception as e:
            logger.error(f"Unexpected error in deduct_pass: {str(e)}")
            return True
    
    def get_balance(self, user_id: str) -> Optional[int]:
        """
        Get the user's current PASS balance
        
        Args:
            user_id: The user's RevenueCat app user ID
            
        Returns:
            The user's PASS balance, or None if error
        """
        if not self.secret_key or self.secret_key == "your-revenuecat-secret-key-here":
            logger.warning("RevenueCat secret key not configured")
            return None
        
        try:
            url = f"{self.base_url}/subscribers/{user_id}"
            response = requests.get(url, headers=self.headers, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                # Extract virtual currency balance from customer info
                virtual_currencies = data.get("subscriber", {}).get("virtual_currencies", {})
                pass_balance = virtual_currencies.get("PASS", {}).get("balance", 0)
                return pass_balance
            else:
                logger.error(f"Failed to get balance for user {user_id}: {response.status_code}")
                return None
                
        except Exception as e:
            logger.error(f"Error getting balance: {str(e)}")
            return None

# Create singleton instance
revenuecat_service = RevenueCatService()