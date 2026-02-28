import os
import uuid as uuid_mod
import requests
from typing import Optional, Dict, Any, Tuple
from dotenv import load_dotenv
import logging

# Load environment variables
load_dotenv()

logger = logging.getLogger(__name__)

class RevenueCatService:
    """Service for interacting with RevenueCat API"""
    
    def __init__(self):
        self.secret_key = os.getenv("REVENUECAT_SECRET_KEY")
        self.base_url = "https://api.revenuecat.com/v2"
        
        if self.secret_key:
            logger.info(f"RevenueCat service initialized with secret key: sk_***{self.secret_key[-8:]}")
            self.headers = {
                "Authorization": f"Bearer {self.secret_key}",
                "Content-Type": "application/json"
            }
        else:
            logger.warning("RevenueCat secret key not found in environment variables")
            self.headers = {}
    
    def deduct_pass(self, user_id: str, is_retry: bool = False, job_id: Optional[str] = None) -> Tuple[bool, Optional[int]]:
        """
        Deduct 1 PASS from the user's virtual currency balance

        Args:
            user_id: The user's RevenueCat app user ID
            is_retry: If True, skip deduction (for retries)
            job_id: Optional job ID used as Idempotency-Key header

        Returns:
            Tuple of (success, new_balance). new_balance is None if unknown.
        """
        logger.info(
            "[DEDUCT_PASS START] user_id=%r is_retry=%s secret_key=%s",
            user_id, is_retry,
            "present" if self.secret_key else "MISSING",
        )

        if is_retry:
            logger.info("[DEDUCT_PASS SKIP] is_retry=True, returning True for user=%s", user_id)
            return True, None

        if not self.secret_key:
            logger.warning("[DEDUCT_PASS SKIP] secret_key not configured, returning True to unblock user=%s", user_id)
            return True, None

        if not user_id or user_id.strip() == "":
            logger.error("[DEDUCT_PASS INVALID_USER] user_id=%r is empty/blank, returning False", user_id)
            return False, None

        from urllib.parse import quote
        encoded_user_id = quote(user_id, safe="")
        logger.info("[DEDUCT_PASS URL] raw=%r encoded=%r", user_id, encoded_user_id)
        url = f"{self.base_url}/projects/projd85d45ec/customers/{encoded_user_id}/virtual_currencies/transactions"
        payload = {
            "adjustments": {
                "PASS": -1
            }
        }

        idempotency_key = job_id if job_id else str(uuid_mod.uuid4())
        request_headers = {**self.headers, "Idempotency-Key": idempotency_key}

        logger.info("[DEDUCT_PASS REQUEST] url=%s idempotency_key=%s", url, idempotency_key)
        logger.info("[DEDUCT_PASS REQUEST] payload=%s", payload)

        try:
            response = requests.post(url, json=payload, headers=request_headers, timeout=10)

            logger.info(
                "[DEDUCT_PASS RESPONSE] status=%d headers=%s body=%s",
                response.status_code, dict(response.headers), response.text,
            )

            if response.status_code == 200:
                logger.info("[DEDUCTION OK] user=%s", user_id)
                # Parse new PASS balance directly from the transaction response
                new_balance = None
                try:
                    data = response.json()
                    for item in data.get("items", []):
                        if item.get("currency_code") == "PASS":
                            new_balance = item.get("balance")
                            break
                except Exception as parse_err:
                    logger.warning("[DEDUCTION PARSE] couldn't parse balance from response: %s", parse_err)
                logger.info("[DEDUCTION POST-BALANCE] user=%s new_balance=%s", user_id, new_balance)
                return True, new_balance
            elif response.status_code == 422:
                logger.warning("[INSUFFICIENT BALANCE] user=%s body=%s", user_id, response.text)
                return False, None
            elif response.status_code == 404:
                logger.warning("[USER NOT FOUND] user=%s body=%s", user_id, response.text)
                return False, None
            elif response.status_code == 400:
                logger.warning("[DEDUCTION FAILED] BAD_REQUEST user=%s body=%s", user_id, response.text)
                return False, None
            else:
                logger.error("[DEDUCTION FAILED] status=%d user=%s body=%s", response.status_code, user_id, response.text)
                return False, None

        except requests.exceptions.RequestException as e:
            logger.error(
                "[NETWORK ERROR] user=%s exception=%s — returning True (silent fail to unblock)",
                user_id, e,
            )
            return True, None
        except Exception as e:
            logger.error(
                "[SILENT FAIL] user=%s exception=%s — returning True to unblock",
                user_id, e, exc_info=True,
            )
            return True, None
    
    def get_balance(self, user_id: str) -> Optional[int]:
        """
        Get the user's current PASS balance

        Args:
            user_id: The user's RevenueCat app user ID

        Returns:
            The user's PASS balance, or None if error
        """
        logger.info("[GET_BALANCE START] user_id=%s", user_id)

        if not self.secret_key or self.secret_key == "your-revenuecat-secret-key-here":
            logger.warning("[GET_BALANCE SKIP] secret_key not configured")
            return None

        try:
            from urllib.parse import quote
            encoded_user_id = quote(user_id, safe="")
            url = f"{self.base_url}/projects/projd85d45ec/customers/{encoded_user_id}"
            response = requests.get(url, headers=self.headers, timeout=10)

            logger.info(
                "[GET_BALANCE RESPONSE] status=%d body=%s",
                response.status_code, response.text[:2000],
            )

            if response.status_code == 200:
                data = response.json()
                virtual_currencies = data.get("customer", {}).get("virtual_currencies", {})
                pass_balance = virtual_currencies.get("PASS", {}).get("balance", 0)
                logger.info("[GET_BALANCE OK] user=%s balance=%s", user_id, pass_balance)
                return pass_balance
            else:
                logger.error("[GET_BALANCE FAILED] user=%s status=%d body=%s", user_id, response.status_code, response.text)
                return None

        except Exception as e:
            logger.error("[GET_BALANCE ERROR] user=%s exception=%s", user_id, e, exc_info=True)
            return None

# Create singleton instance
revenuecat_service = RevenueCatService()