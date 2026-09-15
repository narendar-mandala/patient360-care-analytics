"""Minimal FHIR R4 REST client: read, paged search, retries, token refresh."""

import logging
import time
from collections.abc import Iterator

import requests

from epic_auth import EpicBackendAuth

log = logging.getLogger(__name__)

RETRYABLE = {429, 500, 502, 503, 504}


class FhirRequestError(RuntimeError):
    def __init__(self, status: int, url: str, body: str):
        super().__init__(f"HTTP {status} for {url}: {body[:300]}")
        self.status = status


class FhirClient:
    def __init__(self, base_url: str, auth: EpicBackendAuth, timeout: int = 60, max_retries: int = 5):
        self.base_url = base_url.rstrip("/")
        self.auth = auth
        self.timeout = timeout
        self.max_retries = max_retries
        self.session = requests.Session()
        self.session.headers["Accept"] = "application/fhir+json"

    def _get(self, url: str, params: dict | None = None) -> dict:
        refreshed = False
        for attempt in range(self.max_retries + 1):
            headers = {"Authorization": f"Bearer {self.auth.get_token()}"}
            resp = self.session.get(url, params=params, headers=headers, timeout=self.timeout)

            if resp.status_code == 200:
                return resp.json()
            if resp.status_code == 401 and not refreshed:
                self.auth.get_token(force_refresh=True)
                refreshed = True
                continue
            if resp.status_code in RETRYABLE and attempt < self.max_retries:
                wait = float(resp.headers.get("Retry-After", 2**attempt))
                log.warning("HTTP %s on %s; retrying in %.0fs", resp.status_code, url, wait)
                time.sleep(wait)
                continue
            raise FhirRequestError(resp.status_code, resp.url, resp.text)
        raise FhirRequestError(-1, url, "retries exhausted")

    def read(self, resource_type: str, resource_id: str) -> dict:
        return self._get(f"{self.base_url}/{resource_type}/{resource_id}")

    def read_reference(self, reference: str) -> dict:
        """Resolve 'Practitioner/abc' or an absolute URL."""
        url = reference if reference.startswith("http") else f"{self.base_url}/{reference}"
        return self._get(url)

    def search(self, resource_type: str, params: dict) -> Iterator[dict]:
        """Yield resources across all pages; OperationOutcome warnings are logged, not yielded."""
        bundle = self._get(f"{self.base_url}/{resource_type}", params=params)
        while True:
            for entry in bundle.get("entry", []):
                resource = entry.get("resource", {})
                if resource.get("resourceType") == "OperationOutcome":
                    for issue in resource.get("issue", []):
                        log.info("%s %s: %s", resource_type, issue.get("severity"), issue.get("diagnostics") or issue.get("details", {}).get("text"))
                    continue
                yield resource
            next_url = next((l["url"] for l in bundle.get("link", []) if l.get("relation") == "next"), None)
            if not next_url:
                return
            bundle = self._get(next_url)
