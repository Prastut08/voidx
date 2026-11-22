import os
import time
import requests
from typing import Optional, Dict, Any

class DTNAuthService:
    """
    Dedicated OAuth 2.0 client_credentials token manager for the DTN Tropical Cyclone API.
    Handles token caching, automatic refreshing prior to expiration, and retry logic.
    Never exposes or logs client secrets or access tokens.
    """
    def __init__(self):
        self.client_id = os.getenv("DTN_CLIENT_ID", "").strip()
        self.client_secret = os.getenv("DTN_CLIENT_SECRET", "").strip()
        self.auth_url = os.getenv("DTN_AUTH_URL", "https://api.auth.dtn.com/v1/tokens/authorize").strip()
        self.audience = "https://tropical.api.dtn.com"
        
        self._cached_token: Optional[str] = None
        self._token_expires_at: float = 0.0

    @property
    def is_configured(self) -> bool:
        return bool(self.client_id and self.client_secret)

    def get_valid_token(self, force_refresh: bool = False) -> Optional[str]:
        if not self.is_configured:
            return None

        # Return cached token if valid for at least another 60 seconds
        if not force_refresh and self._cached_token and time.time() < (self._token_expires_at - 60):
            return self._cached_token

        return self._authenticate()

    def _authenticate(self, retry: bool = True) -> Optional[str]:
        payload = {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "audience": self.audience
        }
        headers = {
            "Content-Type": "application/json"
        }

        try:
            res = requests.post(self.auth_url, json=payload, headers=headers, timeout=12)
            if res.status_code == 200:
                data = res.json()
                self._cached_token = data.get("access_token")
                expires_in = int(data.get("expires_in", 3600))
                self._token_expires_at = time.time() + expires_in
                return self._cached_token
            elif retry:
                time.sleep(1)
                return self._authenticate(retry=False)
        except Exception as e:
            if retry:
                time.sleep(1)
                return self._authenticate(retry=False)
            print(f"[DTN Auth] Error acquiring token: {type(e).__name__}")
        
        return None
