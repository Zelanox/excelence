"""Server settings read from environment variables.

Separating the server from the client means the server can no longer
assume it is only ever spoken to by a page on the same machine. Everything
that differs between "my laptop" and "a shared server" is configured here,
through the environment, with defaults that keep today's local behavior:

    EXCELENCE_HOST                 interface to listen on (default 0.0.0.0: every
                                   network interface, so phones and other PCs can
                                   connect; a server that listens on the network
                                   needs EXCELENCE_ACCESS_TOKEN)
    EXCELENCE_PORT                 port to listen on (default 8000)
    EXCELENCE_ALLOWED_ORIGINS      comma-separated origins of web clients
                                   allowed to call the API, e.g.
                                   "http://192.168.1.20:8080,https://sheets.example.com"
    EXCELENCE_LOCALHOST_ORIGINS    "0" to stop also accepting any
                                   http://localhost:<port> page (default on)
    EXCELENCE_DOCUMENTS_DIR        where workbooks are stored
    EXCELENCE_ACCESS_TOKEN         if set, every request must carry
                                   "Authorization: Bearer <token>"
    EXCELENCE_DISCOVERY            "off" to stop answering "who is the server?"
                                   questions from devices on the network
                                   (default on; see backend/discovery.py)
    EXCELENCE_DISCOVERY_PORT       UDP port for those questions (default 8765)

Bad values raise ValueError at startup with a message saying what to fix:
a server that quietly falls back to a default (say, a mistyped origin that
is then silently ignored) is much harder to diagnose than one that refuses
to start.
"""

from __future__ import annotations

import hmac
import re
from collections.abc import Mapping
from dataclasses import dataclass
from urllib.parse import urlsplit

DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8000
DEFAULT_DISCOVERY_PORT = 8765

# Short tokens are guessable over a network; this is only a floor.
MIN_TOKEN_LENGTH = 12

LOCALHOST_ORIGIN_REGEX = r"http://(localhost|127\.0\.0\.1)(:\d+)?"

_LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}


@dataclass(frozen=True)
class ServerSettings:

    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    allowed_origins: tuple[str, ...] = ()
    allow_any_localhost: bool = True
    documents_dir: str | None = None
    access_token: str | None = None
    discovery_enabled: bool = True
    discovery_port: int = DEFAULT_DISCOVERY_PORT

    @property
    def is_network_exposed(self) -> bool:
        """True when machines other than this one can reach the server."""
        return self.host not in _LOOPBACK_HOSTS


def _parse_port(raw: str, name: str = "EXCELENCE_PORT") -> int:
    try:
        port = int(raw.strip())
    except ValueError:
        raise ValueError(f"{name} must be a whole number, got {raw!r}.") from None

    if not 1 <= port <= 65535:
        raise ValueError(f"{name} must be between 1 and 65535, got {port}.")

    return port


def _normalize_origin(raw: str) -> str:
    """Validate one origin and return it in canonical form (no path, no trailing slash)."""
    origin = raw.strip().rstrip("/")

    if origin == "*":
        raise ValueError(
            "EXCELENCE_ALLOWED_ORIGINS does not accept '*': list the exact "
            "origins of your web clients (e.g. http://192.168.1.20:8080)."
        )

    parts = urlsplit(origin)

    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise ValueError(
            f"EXCELENCE_ALLOWED_ORIGINS entry {raw!r} is not an origin: expected "
            "scheme://host[:port], e.g. http://192.168.1.20:8080."
        )

    if parts.path or parts.query or parts.fragment or parts.username:
        raise ValueError(
            f"EXCELENCE_ALLOWED_ORIGINS entry {raw!r} must not contain a path, "
            "query or credentials - just scheme://host[:port]."
        )

    try:
        parts.port  # raises ValueError for an out-of-range or non-numeric port
    except ValueError:
        raise ValueError(f"EXCELENCE_ALLOWED_ORIGINS entry {raw!r} has an invalid port.") from None

    return f"{parts.scheme}://{parts.netloc}".lower()


def load_settings(env: Mapping[str, str] | None = None) -> ServerSettings:
    """Build settings from ``env`` (defaults to the process environment)."""
    if env is None:
        import os

        env = os.environ

    def get(name: str) -> str | None:
        value = env.get(name)
        return value.strip() if value and value.strip() else None

    host = get("EXCELENCE_HOST") or DEFAULT_HOST

    if re.search(r"\s", host):
        raise ValueError(f"EXCELENCE_HOST must not contain spaces, got {host!r}.")

    raw_port = get("EXCELENCE_PORT")
    port = _parse_port(raw_port) if raw_port is not None else DEFAULT_PORT

    origins: list[str] = []

    for part in (get("EXCELENCE_ALLOWED_ORIGINS") or "").split(","):
        if part.strip():
            origin = _normalize_origin(part)

            if origin not in origins:
                origins.append(origin)

    localhost_flag = (get("EXCELENCE_LOCALHOST_ORIGINS") or "1").lower()

    if localhost_flag not in ("0", "1", "true", "false", "yes", "no"):
        raise ValueError("EXCELENCE_LOCALHOST_ORIGINS must be 0 or 1.")

    token = get("EXCELENCE_ACCESS_TOKEN")

    if token is not None and len(token) < MIN_TOKEN_LENGTH:
        raise ValueError(
            f"EXCELENCE_ACCESS_TOKEN is too short ({len(token)} characters); "
            f"use at least {MIN_TOKEN_LENGTH}."
        )

    discovery_flag = (get("EXCELENCE_DISCOVERY") or "on").lower()

    if discovery_flag not in ("on", "off", "1", "0", "true", "false", "yes", "no"):
        raise ValueError("EXCELENCE_DISCOVERY must be on or off.")

    raw_discovery_port = get("EXCELENCE_DISCOVERY_PORT")
    discovery_port = (
        _parse_port(raw_discovery_port, "EXCELENCE_DISCOVERY_PORT")
        if raw_discovery_port is not None
        else DEFAULT_DISCOVERY_PORT
    )

    return ServerSettings(
        host=host,
        port=port,
        allowed_origins=tuple(origins),
        allow_any_localhost=localhost_flag in ("1", "true", "yes"),
        documents_dir=get("EXCELENCE_DOCUMENTS_DIR"),
        access_token=token,
        discovery_enabled=discovery_flag in ("on", "1", "true", "yes"),
        discovery_port=discovery_port,
    )


def startup_problem(settings: ServerSettings) -> str | None:
    """Why the server must not start with these settings, or None if it may.

    A server that other machines can reach but that has no access token would
    let anyone on the network read, change and delete every document, so it
    refuses to start instead of only warning.
    """
    if settings.is_network_exposed and settings.access_token is None:
        return (
            "The server listens on the network but has no access token, so anyone "
            "on the network could change your documents. Run: excelence-server setup "
            "(or set EXCELENCE_ACCESS_TOKEN in excelence.env)."
        )

    return None


def token_matches(authorization_header: str | None, expected_token: str | None) -> bool:
    """Whether a request's Authorization header satisfies the access token.

    With no token configured every request is allowed. Otherwise the header
    must be exactly ``Bearer <token>``, compared in constant time so the
    check can't be used to guess the token one character at a time.
    """
    if not expected_token:
        return True

    if not authorization_header:
        return False

    scheme, _, supplied = authorization_header.partition(" ")

    if scheme.lower() != "bearer" or not supplied:
        return False

    return hmac.compare_digest(supplied.strip().encode(), expected_token.encode())
