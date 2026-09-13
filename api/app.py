"""Protected resource server used by the OAuth 2.0 API Testing Lab.

Validates incoming Bearer tokens against Keycloak: signature (via JWKS),
issuer, audience, and expiry, then enforces role-based authorization.
"""

import os

import jwt
from fastapi import FastAPI, Header, HTTPException
from jwt import PyJWKClient

app = FastAPI()

KEYCLOAK_ISSUER = os.getenv(
    "KEYCLOAK_ISSUER",
    "http://localhost:8080/realms/api-testing",
)
JWKS_URL = f"{KEYCLOAK_ISSUER}/protocol/openid-connect/certs"
REQUIRED_ROLE = os.getenv("REQUIRED_ROLE", "api-user")

_jwks_client = PyJWKClient(JWKS_URL)


def _validate_token(token: str) -> dict:
    try:
        signing_key = _jwks_client.get_signing_key_from_jwt(token)
    except jwt.PyJWKClientError as exc:
        raise HTTPException(
            status_code=401,
            detail=f"Unable to resolve signing key: {exc}"
        )
    except jwt.exceptions.DecodeError:
        raise HTTPException(status_code=401, detail="Malformed token")

    try:
        claims = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            issuer=KEYCLOAK_ISSUER,
            audience="account",
            options={"require": ["exp", "iat", "iss"]},
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidIssuerError:
        raise HTTPException(status_code=401, detail="Invalid issuer")
    except jwt.InvalidAudienceError:
        raise HTTPException(status_code=401, detail="Invalid audience")
    except jwt.InvalidTokenError as exc:
        raise HTTPException(status_code=401, detail=f"Invalid token: {exc}")

    return claims


def _require_role(claims: dict, role: str) -> None:
    # Same pattern works for scope checks: inspect claims.get("scope", "").split()
    roles = claims.get("realm_access", {}).get("roles", [])
    if role not in roles:
        raise HTTPException(
            status_code=403,
            detail=f"Missing required role: {role}"
        )


@app.get("/users")
def get_users(authorization: str | None = Header(default=None)):

    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Missing Authorization header"
        )

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Invalid Authorization header"
        )

    token = authorization.replace("Bearer ", "").strip()

    if not token:
        raise HTTPException(
            status_code=401,
            detail="Missing token"
        )

    claims = _validate_token(token)
    _require_role(claims, REQUIRED_ROLE)

    return {
        "message": "Authenticated successfully",
        "users": [
            {
                "id": 1,
                "name": "Test User"
            }
        ]
    }
