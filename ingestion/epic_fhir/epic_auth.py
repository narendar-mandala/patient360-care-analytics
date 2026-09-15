"""OAuth 2.0 Backend Services (client_credentials + signed JWT assertion) for Epic."""

import json
import threading
import time
import uuid
from pathlib import Path

import jwt
import requests

ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"


class EpicAuthError(RuntimeError):
    pass


class EpicBackendAuth:
    def __init__(self, client_id: str, private_key_path: str | Path, token_url: str, jwks_path: str | Path | None = None):
        if not client_id:
            raise EpicAuthError("EPIC_CLIENT_ID is empty; set it in .env")
        self.client_id = client_id
        self.token_url = token_url
        self._private_key = Path(private_key_path).read_bytes()
        self._kid = self._read_kid(jwks_path)
        self._token: str | None = None
        self._expires_at = 0.0
        self._lock = threading.Lock()

    @staticmethod
    def _read_kid(jwks_path) -> str | None:
        if jwks_path and Path(jwks_path).exists():
            keys = json.loads(Path(jwks_path).read_text()).get("keys", [])
            return keys[0].get("kid") if keys else None
        return None

    def _client_assertion(self) -> str:
        now = int(time.time())
        claims = {
            "iss": self.client_id,
            "sub": self.client_id,
            "aud": self.token_url,
            "jti": str(uuid.uuid4()),
            "iat": now,
            "nbf": now,
            "exp": now + 240,  # Epic rejects assertions valid for more than 5 minutes
        }
        headers = {"typ": "JWT", **({"kid": self._kid} if self._kid else {})}
        return jwt.encode(claims, self._private_key, algorithm="RS384", headers=headers)

    def get_token(self, force_refresh: bool = False) -> str:
        with self._lock:
            if not force_refresh and self._token and time.time() < self._expires_at - 60:
                return self._token
            resp = requests.post(
                self.token_url,
                data={
                    "grant_type": "client_credentials",
                    "client_assertion_type": ASSERTION_TYPE,
                    "client_assertion": self._client_assertion(),
                },
                timeout=30,
            )
            if resp.status_code != 200:
                raise EpicAuthError(f"Token request failed ({resp.status_code}): {resp.text[:500]}")
            body = resp.json()
            self._token = body["access_token"]
            self._expires_at = time.time() + int(body.get("expires_in", 300))
            return self._token
