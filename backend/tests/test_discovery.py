"""Finding the server on the network: the question/answer messages, the proof
that keeps a stranger from posing as the server, and the UDP responder."""

import json
import socket

from backend import discovery
from backend.discovery import DiscoveryResponder, build_reply, compute_proof, start_discovery
from backend.utils.settings import load_settings

TOKEN = "a-long-enough-secret"
NONCE = "00112233445566778899aabbccddeeff"


def question(**changes):
    message = {"excelence": "discover", "v": 1, "nonce": NONCE}
    message.update(changes)
    return json.dumps(message).encode()


def ask(port, data, wait=1.0):
    """Send one datagram to the responder; return its answer or None."""
    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.settimeout(wait)
    try:
        client.sendto(data, ("127.0.0.1", port))
        try:
            return client.recvfrom(1024)[0]
        except socket.timeout:
            return None
    finally:
        client.close()


def make_responder(**kwargs):
    responder = DiscoveryResponder(
        token=TOKEN, http_port=8000, udp_port=0, name="TEST-PC", bind_host="127.0.0.1", **kwargs
    )
    responder.start()
    return responder


# ---- the proof ----

def test_proof_matches_a_known_value_the_app_also_checks():
    # The same value is hard-coded in the Flutter test, so both sides are
    # proven to compute the same HMAC.
    assert compute_proof(TOKEN, NONCE) == "3f392e30a372242f3af6b54d264a6b1de9e09e58cdfd23d885eb0bcfac571293"


def test_proof_depends_on_both_the_token_and_the_number():
    assert compute_proof(TOKEN, NONCE) != compute_proof("another-long-secret", NONCE)
    assert compute_proof(TOKEN, NONCE) != compute_proof(TOKEN, "ff" * 16)


# ---- the reply ----

def test_a_valid_question_gets_name_port_nonce_and_proof_but_never_the_token():
    raw = build_reply(question(), token=TOKEN, name="TEST-PC", port=8000)
    reply = json.loads(raw)

    assert reply == {
        "excelence": "here",
        "v": 1,
        "name": "TEST-PC",
        "port": 8000,
        "nonce": NONCE,
        "proof": compute_proof(TOKEN, NONCE),
    }
    assert TOKEN.encode() not in raw


def test_invalid_questions_get_no_answer():
    bad = [
        b"",
        b"hello",
        b"\xff\xfe\x00",
        b"[]",
        b'"discover"',
        question(excelence="other"),
        question(v=2),
        question(v="1"),
        question(nonce=None),
        question(nonce=123),
        question(nonce="short"),
        question(nonce="zz" * 16),
        question(nonce="ab" * 40),            # longer than 64 hex digits
        b"x" * 600,                           # too large
    ]

    for data in bad:
        assert build_reply(data, token=TOKEN, name="PC", port=8000) is None, data


def test_a_very_long_name_is_cut():
    reply = json.loads(build_reply(question(), token=TOKEN, name="n" * 500, port=8000))
    assert len(reply["name"]) == 64


# ---- the responder over real UDP ----

def test_responder_answers_over_udp():
    responder = make_responder()
    try:
        answer = ask(responder.port, question())

        assert answer is not None
        reply = json.loads(answer)
        assert reply["name"] == "TEST-PC" and reply["port"] == 8000
        assert reply["proof"] == compute_proof(TOKEN, NONCE)
    finally:
        responder.close()


def test_responder_stays_silent_for_junk_and_keeps_working():
    responder = make_responder()
    try:
        assert ask(responder.port, b"not a question", wait=0.6) is None
        assert ask(responder.port, question()) is not None
    finally:
        responder.close()


def test_responder_limits_how_many_questions_it_answers_per_second():
    now = [100.0]
    responder = make_responder(max_per_second=2, clock=lambda: now[0])
    try:
        answers = [ask(responder.port, question(), wait=0.4) for _ in range(5)]
        assert sum(1 for a in answers if a is not None) == 2

        now[0] += 2.0                                         # a new second
        assert ask(responder.port, question()) is not None
    finally:
        responder.close()


def test_close_stops_the_responder_and_frees_the_port():
    responder = make_responder()
    port = responder.port
    responder.close()

    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.bind(("127.0.0.1", port))                       # would fail if still held
    finally:
        probe.close()


def test_start_raises_when_the_port_is_taken():
    holder = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    holder.bind(("127.0.0.1", 0))
    try:
        responder = DiscoveryResponder(
            token=TOKEN, http_port=8000, udp_port=holder.getsockname()[1], bind_host="127.0.0.1"
        )
        try:
            responder.start()
            raised = False
        except OSError:
            raised = True

        assert raised
    finally:
        holder.close()


# ---- when the server starts it ----

def settings_with(**env):
    base = {"EXCELENCE_ACCESS_TOKEN": TOKEN}
    base.update(env)
    return load_settings(base)


def test_not_started_when_switched_off_or_only_local_or_without_a_token():
    assert start_discovery(settings_with(EXCELENCE_DISCOVERY="off")) is None
    assert start_discovery(settings_with(EXCELENCE_HOST="127.0.0.1")) is None
    assert start_discovery(load_settings({})) is None                 # no token


def test_a_taken_port_is_a_warning_not_a_failure():
    holder = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    holder.bind(("", 0))
    try:
        port = holder.getsockname()[1]
        assert start_discovery(settings_with(EXCELENCE_DISCOVERY_PORT=str(port))) is None
    finally:
        holder.close()


def test_started_on_the_configured_port():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(("", 0))
    port = probe.getsockname()[1]
    probe.close()

    responder = start_discovery(settings_with(EXCELENCE_DISCOVERY_PORT=str(port), EXCELENCE_PORT="8123"))
    assert responder is not None
    try:
        assert responder.port == port
        reply = json.loads(ask(port, question()))
        assert reply["port"] == 8123
    finally:
        responder.close()


# ---- the asking side (excelence-server discover) ----

def test_find_servers_finds_a_responder_that_knows_the_token():
    responder = make_responder()
    try:
        found = discovery.find_servers(TOKEN, port=responder.port, targets=["127.0.0.1"], timeout=1.5)

        assert found == [{"name": "TEST-PC", "address": "http://127.0.0.1:8000"}]
    finally:
        responder.close()


def test_find_servers_ignores_a_server_with_another_token():
    responder = make_responder()
    try:
        assert discovery.find_servers("someone-elses-secret", port=responder.port, targets=["127.0.0.1"], timeout=1.0) == []
    finally:
        responder.close()


def test_find_servers_returns_nothing_when_nobody_answers():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()

    assert discovery.find_servers(TOKEN, port=port, targets=["127.0.0.1"], timeout=0.6) == []


def test_broadcast_targets_start_with_the_general_address_and_are_valid():
    targets = discovery.broadcast_targets()

    assert targets[0] == "255.255.255.255"
    assert all(len(t.split(".")) == 4 for t in targets)
    assert not any(t.startswith("127.") for t in targets)
