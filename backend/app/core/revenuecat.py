from __future__ import annotations

import logging
from urllib.parse import quote

import requests

from app.core.config import Settings
from app.core.errors import PaymentRequiredError, ProcessingError, UpstreamServiceError


logger = logging.getLogger(__name__)


class RevenueCatClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def deduct_pass(self, user_id: str, is_retry: bool, is_demo: bool, job_id: str) -> int | None:
        if is_demo or is_retry:
            return None
        if not user_id.strip():
            raise ProcessingError("Missing RevenueCat user_id")
        if not self.settings.revenuecat_secret_key:
            logger.info("RevenueCat secret key is not configured; skipping deduction in development")
            return None
        if not self.settings.revenuecat_project_id:
            raise ProcessingError("RevenueCat project is not configured")

        encoded_user_id = quote(user_id, safe="")
        url = (
            "https://api.revenuecat.com/v2/projects/"
            f"{self.settings.revenuecat_project_id}/customers/{encoded_user_id}/virtual_currencies/transactions"
        )
        headers = {
            "Authorization": f"Bearer {self.settings.revenuecat_secret_key}",
            "Content-Type": "application/json",
            "Idempotency-Key": job_id,
        }
        payload = {"adjustments": {"PASS": -1}}

        try:
            response = requests.post(url, json=payload, headers=headers, timeout=10)
        except requests.RequestException as exc:
            raise UpstreamServiceError("RevenueCat deduction is unavailable") from exc

        if response.status_code == 200:
            try:
                body = response.json()
                for item in body.get("items", []):
                    if item.get("currency_code") == "PASS":
                        return item.get("balance")
            except Exception:
                logger.info("RevenueCat balance was not present in deduction response", exc_info=True)
            return None
        if response.status_code == 422:
            raise PaymentRequiredError()
        if response.status_code == 404:
            raise ProcessingError("RevenueCat customer was not found")
        if response.status_code in {401, 403}:
            raise UpstreamServiceError("RevenueCat credentials were rejected")
        raise UpstreamServiceError("RevenueCat deduction failed")

