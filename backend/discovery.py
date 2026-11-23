"""Let devices on the network find the server without typing its address.

A client broadcasts one small UDP message ("who is an Excelence server?")
carrying a random number. The server answers the sender with its name, its
HTTP port, that same number and a PROOF: an HMAC-SHA256 of the number keyed
with the access token. The token itself is never sent. A client only accepts
an answer whose proof it can reproduce with its own token, so another machine
on the Wi-Fi cannot pretend to be the server and collect tokens, and a client
with a different token simply never sees this server.

Request:  {"excelence": "discover", "v": 1, "nonce": "<16-64 hex digits>"}
Reply:    {"excelence": "here", "v": 1, "name": "...", "port": 8000,
           "nonce": "<same>", "proof": "<hex hmac_sha256(token, nonce)>"}

The reply is only a little larger than the request and the responder answers
at most ``max_per_second`` questions per second, so it is of no use for
flooding anybody.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
import socket
import threading
import time
from collections.abc import Callable

from backend.utils.logger import get_logger

logger = get_logger("discovery")

PROTOCOL_VERSION = 1
MAX_MESSAGE_BYTES = 512
_NONCE = re.compile(r"^[0-9a-f]{16,64}$")


def compute_proof(token: str, nonce: str) -> str:
    """Hex HMAC-SHA256 of ``nonce`` keyed with ``token``."""
    return hmac.new(token.encode("utf-8"), nonce.encode("utf-8"), hashlib.sha256).hexdigest()


def build_reply(data: bytes, *, token: str, name: str, port: int) -> bytes | None:
    """The answer to one received message, or None if it is not a valid question."""
    if not data or len(data) > MAX_MESSAGE_BYTES:
        return None

    try:
        message = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return None

    if (
        not isinstance(message, dict)
        or message.get("excelence") != "discover"
        or message.get("v") != PROTOCOL_VERSION
    ):
        return None

    nonce = message.get("nonce")

    if not isinstance(nonce, str) or not _NONCE.match(nonce):
        return None

    reply = {
        "excelence": "here",
        "v": PROTOCOL_VERSION,
        "name": name[:64],
        "port": port,
        "nonce": nonce,
        "proof": compute_proof(token, nonce),
    }

    return json.dumps(reply, separators=(",", ":")).encode("utf-8")


class DiscoveryResponder:
    """Answers discovery questions on a UDP port, in a background thread."""

    def __init__(
        self,
        *,
        token: str,
        http_port: int,
        udp_port: int,
        name: str | None = None,
        bind_host: str = "",
        max_per_second: int = 20,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._token = token
        self._http_port = http_port
        self._udp_port = udp_port
        self._name = name or socket.gethostname()
        self._bind_host = bind_host
        self._max_per_second = max_per_second
        self._clock = clock

        self._socket: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._window_start = 0.0
        self._window_count = 0
        self._last_logged: dict[str, float] = {}

    @property
    def port(self) -> int:
        """The UDP port actually bound (useful when 0 was asked for)."""
        if self._socket is None:
            return self._udp_port

        return self._socket.getsockname()[1]

    def start(self) -> None:
        """Bind and start answering. Raises OSError if the port is taken."""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        try:
            sock.bind((self._bind_host, self._udp_port))
        except OSError:
            sock.close()
            raise

        sock.settimeout(0.5)
        self._socket = sock
        self._thread = threading.Thread(target=self._run, name="excelence-discovery", daemon=True)
        self._thread.start()

    def close(self) -> None:
        self._stop.set()

        if self._thread is not None:
            self._thread.join(timeout=2)

        if self._socket is not None:
            self._socket.close()
            self._socket = None

    def _allowed(self) -> bool:
        now = self._clock()

        if now - self._window_start >= 1.0:
            self._window_start = now
            self._window_count = 0

        self._window_count += 1

        return self._window_count <= self._max_per_second

    def _run(self) -> None:
        sock = self._socket

        while not self._stop.is_set() and sock is not None:
            try:
                data, sender = sock.recvfrom(1024)
            except socket.timeout:
                continue
            except OSError:
                # Windows reports an ICMP "port unreachable" from an earlier
                # reply as an error on the next receive; keep listening.
                if self._stop.is_set():
                    break

                continue

            if not self._allowed():
                continue

            reply = build_reply(data, token=self._token, name=self._name, port=self._http_port)

            if reply is None:
                continue

            try:
                sock.sendto(reply, sender)
            except OSError as error:
                logger.warning("Could not answer a discovery question from %s: %s", sender[0], error)
                continue

            # Evidence for "the app cannot find the server": did the question
            # arrive? (At most once per sender every 10 seconds.)
            now = self._clock()

            if now - self._last_logged.get(sender[0], -1e9) >= 10.0:
                self._last_logged[sender[0]] = now
                logger.info("Answered a discovery question from %s", sender[0])


def start_discovery(settings) -> DiscoveryResponder | None:
    """Start answering discovery questions if the settings call for it.

    Not started when it is switched off, when the server only listens on this
    PC, or when there is no token (the proof needs one). A port that is
    already taken is a warning, not a failure: the server still works, devices
    just have to be given its address.
    """
    if not settings.discovery_enabled or not settings.is_network_exposed or settings.access_token is None:
        return None

    responder = DiscoveryResponder(
        token=settings.access_token,
        http_port=settings.port,
        udp_port=settings.discovery_port,
    )

    try:
        responder.start()
    except OSError as error:
        logger.warning(
            "Devices cannot find this server automatically: UDP port %s is not available (%s). "
            "Give them the address instead, or change EXCELENCE_DISCOVERY_PORT.",
            settings.discovery_port,
            error,
        )
        return None

    logger.info("Answering discovery questions on UDP port %s", responder.port)

    return responder


# ----------------------------------------------------------------------
# The asking side, for diagnosing from the server PC (excelence-server discover)
# ----------------------------------------------------------------------

def broadcast_targets() -> list[str]:
    """The general broadcast address plus the /24 broadcast of each local address."""
    targets = ["255.255.255.255"]

    try:
        addresses = socket.gethostbyname_ex(socket.gethostname())[2]
    except OSError:
        addresses = []

    for address in addresses:
        parts = address.split(".")

        if len(parts) == 4 and not address.startswith(("127.", "169.254.")):
            target = ".".join(parts[:3]) + ".255"

            if target not in targets:
                targets.append(target)

    return targets


def find_servers(
    token: str,
    *,
    port: int = 8765,
    timeout: float = 3.0,
    targets: list[str] | None = None,
) -> list[dict[str, str]]:
    """Ask the network for servers that know ``token``; what the app's
    "Find server" button does. Returns ``[{"name": ..., "address": ...}]``."""
    nonce = secrets.token_hex(16)
    request = json.dumps({"excelence": "discover", "v": PROTOCOL_VERSION, "nonce": nonce}).encode("utf-8")
    expected = compute_proof(token, nonce)
    targets = broadcast_targets() if targets is None else targets

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.2)

    found: list[dict[str, str]] = []
    start = time.monotonic()
    send_at = [0.0, 0.5, 1.5]

    try:
        while time.monotonic() - start < timeout:
            elapsed = time.monotonic() - start

            while send_at and send_at[0] <= elapsed:
                send_at.pop(0)

                for target in targets:
                    try:
                        sock.sendto(request, (target, port))
                    except OSError:
                        pass

            try:
                data, sender = sock.recvfrom(1024)
            except socket.timeout:
                continue
            except OSError:
                continue

            try:
                reply = json.loads(data.decode("utf-8"))
                good = (
                    isinstance(reply, dict)
                    and reply.get("excelence") == "here"
                    and reply.get("v") == PROTOCOL_VERSION
                    and reply.get("nonce") == nonce
                    and isinstance(reply.get("proof"), str)
                    and hmac.compare_digest(reply["proof"], expected)
                    and isinstance(reply.get("port"), int)
                )
            except (UnicodeDecodeError, ValueError):
                good = False

            if good:
                server = {"name": str(reply.get("name", "")), "address": f"http://{sender[0]}:{reply['port']}"}

                if server not in found:
                    found.append(server)
    finally:
        sock.close()

    return found
