"""Setting up the server: access token, port, and the address for the app.

Covers `excelence-server setup` and `config show | set | unset | token`, the
refusal to start on the network without a token, and that no localhost address
is ever shown for a server that listens on the network.
"""

import contextlib
import io
import tempfile
from pathlib import Path

from backend import service_cli
from backend import service_control as sc
from backend.utils.settings import MIN_TOKEN_LENGTH, load_settings

TOKEN = "a-long-enough-secret"


def make_paths(folder):
    root = Path(folder)
    return sc.ServicePaths(root=root, logs_dir=root / "logs")


def run_cli(argv, paths):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = service_cli.main(argv, paths=paths)
    return code, out.getvalue(), err.getvalue()


def scripted(*answers):
    queue = list(answers)
    prompts = []

    def ask(prompt):
        prompts.append(prompt)
        if not queue:
            raise EOFError
        return queue.pop(0)

    return ask, prompts


def file_values(paths):
    return sc.parse_env_text(paths.env_file.read_text(encoding="utf-8"))[0]


# ---- tokens and keys ----

def test_generated_tokens_are_long_enough_and_different():
    first, second = sc.generate_token(), sc.generate_token()
    assert len(first) >= MIN_TOKEN_LENGTH and first != second
    assert load_settings({"EXCELENCE_ACCESS_TOKEN": first}).access_token == first


def test_short_names_map_to_the_real_setting_names():
    assert sc.resolve_key("token") == "EXCELENCE_ACCESS_TOKEN"
    assert sc.resolve_key(" Port ") == "EXCELENCE_PORT"
    assert sc.resolve_key("excelence_host") == "EXCELENCE_HOST"
    assert sc.resolve_key("nonsense") is None
    assert sc.resolve_key("PATH") is None


# ---- config set / unset ----

def test_set_creates_the_file_and_uses_the_template_line():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        outcome = sc.set_config_value(paths, "token", TOKEN)

        assert outcome.code == 0 and "excelence-server restart" in outcome.message
        text = paths.env_file.read_text(encoding="utf-8")
        assert f"EXCELENCE_ACCESS_TOKEN={TOKEN}" in text
        assert "#EXCELENCE_ACCESS_TOKEN" not in text            # the template line was replaced, not duplicated
        assert text.count("EXCELENCE_ACCESS_TOKEN=") == 1
        assert "#EXCELENCE_PORT=8000" in text                   # the rest of the template is kept


def test_set_changes_an_existing_value_and_keeps_other_lines():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.env_file.write_text("# mine\nEXCELENCE_PORT=9000\nEXCELENCE_DOCUMENTS_DIR=D:\\docs\n", encoding="utf-8")

        assert sc.set_config_value(paths, "port", "9100").code == 0

        text = paths.env_file.read_text(encoding="utf-8")
        assert "EXCELENCE_PORT=9100" in text and "9000" not in text
        assert "# mine" in text and "EXCELENCE_DOCUMENTS_DIR=D:\\docs" in text


def test_set_removes_duplicates_that_would_override_the_new_value():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.env_file.write_text("EXCELENCE_PORT=1111\nEXCELENCE_PORT=2222\n", encoding="utf-8")

        sc.set_config_value(paths, "port", "3333")

        assert file_values(paths) == {"EXCELENCE_PORT": "3333"}


def test_set_rejects_bad_values_and_leaves_the_file_alone():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.env_file.write_text("EXCELENCE_PORT=9000\n", encoding="utf-8")
        before = paths.env_file.read_text(encoding="utf-8")

        for name, value in (("token", "short"), ("port", "abc"), ("port", "70000"), ("host", "a b"), ("token", "  ")):
            outcome = sc.set_config_value(paths, name, value)
            assert outcome.code == sc.EXIT_USAGE, (name, value)

        assert sc.set_config_value(paths, "colour", "red").code == sc.EXIT_USAGE
        assert paths.env_file.read_text(encoding="utf-8") == before


def test_unset_removes_the_line():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.env_file.write_text(f"EXCELENCE_PORT=9000\nEXCELENCE_ACCESS_TOKEN={TOKEN}\n", encoding="utf-8")

        assert sc.set_config_value(paths, "token", None).code == 0
        assert file_values(paths) == {"EXCELENCE_PORT": "9000"}


def test_new_token_replaces_the_old_one_and_shows_it():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.set_config_value(paths, "token", TOKEN)

        outcome = sc.new_token(paths)

        stored = file_values(paths)["EXCELENCE_ACCESS_TOKEN"]
        assert stored != TOKEN and len(stored) >= MIN_TOKEN_LENGTH
        assert stored in outcome.message and "Settings > Connection" in outcome.message


# ---- config show ----

def test_show_gives_the_address_for_the_app_and_never_localhost():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.set_config_value(paths, "token", TOKEN)

        outcome = sc.show_config(paths, environ={}, lan_ip=lambda: "192.168.1.20")

        assert outcome.code == 0
        assert TOKEN in outcome.message
        assert "http://192.168.1.20:8000" in outcome.message
        assert "127.0.0.1" not in outcome.message and "localhost" not in outcome.message
        assert "will not start" not in outcome.message
        assert "Discovery:      on (UDP 8765)" in outcome.message


def test_show_warns_when_there_is_no_token():
    with tempfile.TemporaryDirectory() as folder:
        outcome = sc.show_config(make_paths(folder), environ={}, lan_ip=lambda: "192.168.1.20")

        assert "NOT SET" in outcome.message and "will not start" in outcome.message
        assert "not created yet" in outcome.message


def test_show_says_so_when_the_network_address_is_unknown():
    with tempfile.TemporaryDirectory() as folder:
        outcome = sc.show_config(make_paths(folder), environ={}, lan_ip=lambda: None)

        assert "ipconfig" in outcome.message and "127.0.0.1" not in outcome.message


def test_show_reports_a_bad_settings_file():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        paths.env_file.write_text("EXCELENCE_PORT=abc\n", encoding="utf-8")

        assert sc.show_config(paths, environ={}).code == sc.EXIT_USAGE


# ---- setup ----

def test_setup_with_enter_keeps_the_suggested_token_and_prints_what_to_type():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        ask, prompts = scripted("", "")
        shown = []

        outcome = sc.run_setup(paths, input_fn=ask, print_fn=shown.append,
                               lan_ip=lambda: "192.168.1.20", make_token=lambda: "suggested-token-1")

        assert outcome.code == 0
        assert "suggested-token-1" in prompts[0]
        assert file_values(paths) == {"EXCELENCE_ACCESS_TOKEN": "suggested-token-1"}
        assert "Server address:  http://192.168.1.20:8000" in outcome.message
        assert "Access token:    suggested-token-1" in outcome.message
        assert "127.0.0.1" not in outcome.message
        assert "netsh advfirewall firewall add rule" in outcome.message
        assert "protocol=UDP localport=8765" in outcome.message


def test_setup_accepts_a_typed_token_and_port_and_asks_again_when_invalid():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        ask, _ = scripted("short", "my-own-long-token", "70000", "9100")
        shown = []

        outcome = sc.run_setup(paths, input_fn=ask, print_fn=shown.append, lan_ip=lambda: "10.0.0.5")

        assert outcome.code == 0
        assert file_values(paths) == {"EXCELENCE_ACCESS_TOKEN": "my-own-long-token", "EXCELENCE_PORT": "9100"}
        assert any("too short" in line for line in shown)
        assert any("EXCELENCE_PORT" in line for line in shown)
        assert "http://10.0.0.5:9100" in outcome.message


def test_setup_keeps_an_existing_token_when_enter_is_pressed():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.set_config_value(paths, "token", TOKEN)
        ask, prompts = scripted("", "")

        outcome = sc.run_setup(paths, input_fn=ask, print_fn=lambda _: None, lan_ip=lambda: "10.0.0.5",
                               make_token=lambda: "should-not-be-used")

        assert TOKEN in prompts[0] and file_values(paths)["EXCELENCE_ACCESS_TOKEN"] == TOKEN
        assert f"Access token:    {TOKEN}" in outcome.message


def test_setup_stops_after_three_short_tokens_without_changing_anything():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        ask, _ = scripted("a", "b", "c")

        outcome = sc.run_setup(paths, input_fn=ask, print_fn=lambda _: None)

        assert outcome.code == sc.EXIT_USAGE and "Nothing was changed" in outcome.message
        assert "EXCELENCE_ACCESS_TOKEN" not in file_values(paths)


def test_setup_can_be_cancelled():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        ask, _ = scripted()                      # input() raises EOFError straight away

        outcome = sc.run_setup(paths, input_fn=ask, print_fn=lambda _: None)

        assert outcome.code == sc.EXIT_FAILED and "cancelled" in outcome.message


# ---- start refuses without a token ----

def test_start_refuses_to_listen_on_the_network_without_a_token():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        def must_not_launch(*args, **kwargs):
            raise AssertionError("the server must not be launched")

        outcome = sc.start(paths, {"EXCELENCE_HOST": "0.0.0.0"}, popen=must_not_launch)

        assert outcome.code == sc.EXIT_USAGE
        assert "access token" in outcome.message and "excelence-server setup" in outcome.message


# ---- command line ----

def test_cli_config_commands():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        code, out, _ = run_cli(["config", "set", "token", TOKEN], paths)
        assert code == 0 and file_values(paths)["EXCELENCE_ACCESS_TOKEN"] == TOKEN

        code, out, _ = run_cli(["config", "set", "documents", "D:\\My Docs"], paths)
        assert code == 0 and file_values(paths)["EXCELENCE_DOCUMENTS_DIR"] == "D:\\My Docs"

        code, out, _ = run_cli(["config", "show"], paths)
        assert code == 0 and TOKEN in out

        code, out, _ = run_cli(["config", "token"], paths)
        assert code == 0 and "New access token:" in out

        code, out, _ = run_cli(["config", "unset", "documents"], paths)
        assert code == 0 and "EXCELENCE_DOCUMENTS_DIR" not in file_values(paths)


def test_cli_config_usage_errors_exit_with_the_usage_code():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        for argv in (["config", "set"], ["config", "set", "token"], ["config", "bogus"], ["config", "show", "x"]):
            code, _, err = run_cli(argv, paths)
            assert code == sc.EXIT_USAGE and "Usage" in err, argv

        code, _, err = run_cli(["config", "set", "token", "short"], paths)
        assert code == sc.EXIT_USAGE and "Not saved" in err


def test_help_lists_the_setup_commands():
    code, out, _ = run_cli(["help"], make_paths("/tmp/x"))
    assert code == 0 and "setup" in out and "config show" in out and "config token" in out


def test_discovery_can_be_changed_with_config_set():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)

        assert sc.set_config_value(paths, "discovery", "off").code == 0
        assert sc.set_config_value(paths, "discovery-port", "9000").code == 0
        assert sc.set_config_value(paths, "discovery", "maybe").code == sc.EXIT_USAGE

        assert file_values(paths) == {"EXCELENCE_DISCOVERY": "off", "EXCELENCE_DISCOVERY_PORT": "9000"}
        assert "Discovery:      off" in sc.show_config(paths, environ={}, lan_ip=lambda: "10.0.0.5").message


# ---- excelence-server discover ----

def test_discover_reports_what_it_found():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.set_config_value(paths, "token", TOKEN)
        calls = []

        def finder(token, port):
            calls.append((token, port))
            return [{"name": "SERVER-PC", "address": "http://192.168.1.30:8000"}]

        outcome = sc.run_discover(paths, environ={}, finder=finder)

        assert outcome.code == 0 and "SERVER-PC  http://192.168.1.30:8000" in outcome.message
        assert calls == [(TOKEN, 8765)]


def test_discover_says_what_to_check_when_nothing_answers():
    with tempfile.TemporaryDirectory() as folder:
        paths = make_paths(folder)
        sc.set_config_value(paths, "token", TOKEN)

        outcome = sc.run_discover(paths, environ={}, finder=lambda token, port: [])

        assert outcome.code == sc.EXIT_FAILED
        assert "firewall" in outcome.message and "UDP 8765" in outcome.message and "Private" in outcome.message


def test_discover_needs_a_token():
    with tempfile.TemporaryDirectory() as folder:
        outcome = sc.run_discover(make_paths(folder), environ={}, finder=lambda token, port: [])

        assert outcome.code == sc.EXIT_USAGE and "setup" in outcome.message
