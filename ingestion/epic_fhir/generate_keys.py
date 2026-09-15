"""Generate the RSA key pair used for Epic Backend Services (SMART) auth.

Writes to ./keys:
  privatekey.pem     - private key, keep secret
  jwks.json          - public JWK Set (host at a public HTTPS URL for Epic)
  publickey509.pem   - self-signed X.509 cert (for portals that accept an upload)
"""

import base64
import datetime as dt
import hashlib
import json
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

KEY_DIR = Path(__file__).parent / "keys"


def b64url_uint(value: int) -> str:
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def rfc7638_thumbprint(n: str, e: str) -> str:
    canonical = json.dumps({"e": e, "kty": "RSA", "n": n}, separators=(",", ":"), sort_keys=True)
    return base64.urlsafe_b64encode(hashlib.sha256(canonical.encode()).digest()).rstrip(b"=").decode()


def main() -> None:
    KEY_DIR.mkdir(exist_ok=True)
    private_path = KEY_DIR / "privatekey.pem"
    if private_path.exists():
        raise SystemExit(f"{private_path} already exists; delete it deliberately if you want to rotate keys.")

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_path.write_bytes(
        key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    )

    numbers = key.public_key().public_numbers()
    n, e = b64url_uint(numbers.n), b64url_uint(numbers.e)
    kid = rfc7638_thumbprint(n, e)
    jwks = {"keys": [{"kty": "RSA", "alg": "RS384", "use": "sig", "kid": kid, "n": n, "e": e}]}
    (KEY_DIR / "jwks.json").write_text(json.dumps(jwks, indent=2))

    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "healthcare-data-platform")])
    now = dt.datetime.now(dt.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - dt.timedelta(days=1))
        .not_valid_after(now + dt.timedelta(days=730))
        .sign(key, hashes.SHA256())
    )
    (KEY_DIR / "publickey509.pem").write_bytes(cert.public_bytes(serialization.Encoding.PEM))

    print(f"Keys written to {KEY_DIR}")
    print(f"kid = {kid}")
    print("Host keys/jwks.json at a public HTTPS URL and register it on fhir.epic.com.")


if __name__ == "__main__":
    main()
