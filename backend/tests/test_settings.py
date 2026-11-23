"""Server settings from the environment, and the shared access-token check."""

import os

from backend.utils.settings import (
    DEFAULT_HOST,
    DEFAULT_PORT,
    MIN_TOKEN_LENGTH,
    load_settings,
    token_matches,
)


def raises(env, fragment):
    try:
        load_settings(env)
    except ValueError as error:
        assert fragment in str(error), (fragment, str(error))
        return True
    return False


def test_defaults_keep_todays_local_behaviour():
    settings = load_settings({})
    assert settings.host == DEFAULT_HOST == "0.0.0.0"
    assert settings.port == DEFAULT_PORT == 8000
    assert settings.allowed_origins == ()
    assert settings.allow_any_localhost is True
    assert settings.documents_dir is None and settings.access_token is None
    assert settings.is_network_exposed is True      # reachable by other devices; needs a token to start


def test_values_are_read_and_trimmed():
    settings = load_settings({
        "EXCELENCE_HOST": " 0.0.0.0 ",
        "EXCELENCE_PORT": " 9001 ",
        "EXCELENCE_DOCUMENTS_DIR": " /data/docs ",
        "EXCELENCE_ACCESS_TOKEN": " a-long-enough-secret ",
    })
    assert (settings.host, settings.port) == ("0.0.0.0", 9001)
    assert settings.documents_dir == "/data/docs"
    assert settings.access_token == "a-long-enough-secret"
    assert settings.is_network_exposed is True


def test_blank_values_count_as_unset():
    settings = load_settings({"EXCELENCE_HOST": "  ", "EXCELENCE_PORT": "", "EXCELENCE_ACCESS_TOKEN": " "})
    assert settings.host == DEFAULT_HOST and settings.port == DEFAULT_PORT and settings.access_token is None


def test_network_exposure():
    for host, exposed in (("127.0.0.1", False), ("localhost", False), ("::1", False),
                          ("0.0.0.0", True), ("192.168.1.20", True), ("example.com", True)):
        assert load_settings({"EXCELENCE_HOST": host}).is_network_exposed is exposed, host


def test_bad_ports_are_rejected():
    for port in ("abc", "0", "65536", "-1", "80.5", "8 000"):
        assert raises({"EXCELENCE_PORT": port}, "EXCELENCE_PORT"), port
    assert load_settings({"EXCELENCE_PORT": "65535"}).port == 65535
    assert load_settings({"EXCELENCE_PORT": "1"}).port == 1


def test_hosts_with_spaces_are_rejected():
    assert raises({"EXCELENCE_HOST": "bad host"}, "spaces")


def test_origins_are_normalised_deduplicated_and_ordered():
    settings = load_settings({"EXCELENCE_ALLOWED_ORIGINS":
        " http://192.168.1.20:8080/ , HTTPS://Sheets.Example.com,http://192.168.1.20:8080,, "})
    assert settings.allowed_origins == ("http://192.168.1.20:8080", "https://sheets.example.com")


def test_bad_origins_are_rejected_with_a_helpful_message():
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "*"}, "does not accept '*'")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "192.168.1.20:8080"}, "not an origin")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "ftp://host"}, "not an origin")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "http://host/app"}, "path")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "http://host?x=1"}, "path")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "http://user:pw@host"}, "path")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "http://host:99999"}, "invalid port")
    assert raises({"EXCELENCE_ALLOWED_ORIGINS": "http://ok.com,not-an-origin"}, "not-an-origin")


def test_localhost_origin_switch():
    assert load_settings({"EXCELENCE_LOCALHOST_ORIGINS": "0"}).allow_any_localhost is False
    assert load_settings({"EXCELENCE_LOCALHOST_ORIGINS": "false"}).allow_any_localhost is False
    assert load_settings({"EXCELENCE_LOCALHOST_ORIGINS": "1"}).allow_any_localhost is True
    assert raises({"EXCELENCE_LOCALHOST_ORIGINS": "maybe"}, "0 or 1")


def test_weak_tokens_are_rejected():
    assert raises({"EXCELENCE_ACCESS_TOKEN": "short"}, "too short")
    assert load_settings({"EXCELENCE_ACCESS_TOKEN": "x" * MIN_TOKEN_LENGTH}).access_token


def test_settings_are_immutable():
    settings = load_settings({})
    try:
        settings.port = 1
    except Exception:
        return
    raise AssertionError("settings should be frozen")


# ---- access token ----

def test_everything_is_allowed_when_no_token_is_configured():
    assert token_matches(None, None) and token_matches("anything", None) and token_matches(None, "")


def test_token_must_be_supplied_as_a_bearer_header():
    secret = "correct-horse-battery"
    assert token_matches(f"Bearer {secret}", secret) is True
    assert token_matches(f"bearer {secret}", secret) is True              # scheme is case-insensitive
    assert token_matches(f"Bearer  {secret} ", secret) is True            # stray spaces tolerated

    for header in (None, "", "Bearer", "Bearer ", secret, f"Basic {secret}", f"Token {secret}",
                   "Bearer wrong-token-value", f"Bearer {secret}x", f"Bearer {secret[:-1]}"):
        assert token_matches(header, secret) is False, header


def test_token_comparison_handles_unicode_without_raising():
    assert token_matches("Bearer ٣٤٥٦٧٨٩٠١٢٣٤", "abcdefghijkl") is False
    assert token_matches("Bearer ٣٤٥٦٧٨٩٠١٢٣٤", "٣٤٥٦٧٨٩٠١٢٣٤") is True


# ---- the runner refuses to start on bad configuration ----

def test_runner_stops_with_a_clear_error_on_bad_config():
    from backend import run_server

    saved = os.environ.get("EXCELENCE_PORT")
    os.environ["EXCELENCE_PORT"] = "not-a-port"
    try:
        assert run_server.main([]) == 2
    finally:
        if saved is None:
            os.environ.pop("EXCELENCE_PORT", None)
        else:
            os.environ["EXCELENCE_PORT"] = saved


# ---- a server on the network must have an access token ----

def test_network_server_without_token_must_not_start():
    from backend.utils.settings import startup_problem

    problem = startup_problem(load_settings({}))
    assert problem is not None and "access token" in problem and "excelence-server setup" in problem

    assert startup_problem(load_settings({"EXCELENCE_HOST": "192.168.1.20"})) is not None


def test_server_with_token_or_only_this_pc_may_start():
    from backend.utils.settings import startup_problem

    assert startup_problem(load_settings({"EXCELENCE_ACCESS_TOKEN": "a-long-enough-secret"})) is None
    assert startup_problem(load_settings({"EXCELENCE_HOST": "127.0.0.1"})) is None


def test_runner_refuses_to_listen_on_the_network_without_a_token():
    from backend import run_server

    saved = {name: os.environ.get(name) for name in ("EXCELENCE_HOST", "EXCELENCE_ACCESS_TOKEN")}
    os.environ["EXCELENCE_HOST"] = "0.0.0.0"
    os.environ.pop("EXCELENCE_ACCESS_TOKEN", None)
    try:
        assert run_server.main([]) == 2
    finally:
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value


# ---- discovery settings ----

def test_discovery_is_on_by_default_on_port_8765():
    settings = load_settings({})
    assert settings.discovery_enabled is True and settings.discovery_port == 8765


def test_discovery_can_be_switched_off_and_moved():
    for value in ("off", "0", "false", "no", "OFF"):
        assert load_settings({"EXCELENCE_DISCOVERY": value}).discovery_enabled is False, value
    for value in ("on", "1", "true", "yes"):
        assert load_settings({"EXCELENCE_DISCOVERY": value}).discovery_enabled is True, value

    assert load_settings({"EXCELENCE_DISCOVERY_PORT": "9000"}).discovery_port == 9000


def test_bad_discovery_settings_are_refused_with_their_own_name():
    for env, name in (
        ({"EXCELENCE_DISCOVERY": "maybe"}, "EXCELENCE_DISCOVERY"),
        ({"EXCELENCE_DISCOVERY_PORT": "abc"}, "EXCELENCE_DISCOVERY_PORT"),
        ({"EXCELENCE_DISCOVERY_PORT": "0"}, "EXCELENCE_DISCOVERY_PORT"),
        ({"EXCELENCE_DISCOVERY_PORT": "70000"}, "EXCELENCE_DISCOVERY_PORT"),
    ):
        try:
            load_settings(env)
        except ValueError as error:
            assert name in str(error), env
        else:
            raise AssertionError(f"{env} should be refused")
