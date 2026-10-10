"""Server settings read from environment variables.

Separating the server from the client means the server can no longer
assume it is only ever spoken to by a page on the same machine. Everything
that differs between "my laptop" and "a shared server" is configured here,
through the environment, with defaults that keep today's local behavior:

    EXCELENCE_HOST                 interface to listen on (default 127.0.0.1;
                                   use 0.0.0.0 to accept other machines)
    EXCELENCE_PORT                 port to listen on (default 8000)
    EXCELENCE_ALLOWED_ORIGINS      comma-separated origins of web clients
                                   allowed to call the API, e.g.
                                   "http://192.168.1.20:8080,https://sheets.example.com"
    EXCELENCE_LOCALHOST_ORIGINS    "0" to stop also accepting any
                                   http://localhost:<port> page (default on)
    EXCELENCE_DOCUMENTS_DIR        where workbooks are stored
    EXCELENCE_ACCESS_TOKEN         if set, every request must carry
                                   "Authorization: Bearer <token>"

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

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000

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

    @property
    def is_network_exposed(self) -> bool:
        """True when machines other than this one can reach the server."""
        return self.host not in _LOOPBACK_HOSTS


def _parse_port(raw: str) -> int:
    try:
        port = int(raw.strip())
    except ValueError:
        raise ValueError(f"EXCELENCE_PORT must be a whole number, got {raw!r}.") from None

    if not 1 <= port <= 65535:
        raise ValueError(f"EXCELENCE_PORT must be between 1 and 65535, got {port}.")

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

    return ServerSettings(
        host=host,
        port=port,
        allowed_origins=tuple(origins),
        allow_any_localhost=localhost_flag in ("1", "true", "yes"),
        documents_dir=get("EXCELENCE_DOCUMENTS_DIR"),
        access_token=token,
    )


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
