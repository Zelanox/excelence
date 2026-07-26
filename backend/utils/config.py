import json
import os
import sys


# ==========================================================
# Base folder
# ==========================================================


if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))


CONFIG_FILE = os.path.join(BASE_DIR, "config.json")

print("CONFIG FILE =", CONFIG_FILE)

# ==========================================================
# Default configuration
# ==========================================================

DEFAULT = {

    "server_ip": "127.0.0.1",

    "server_port": 5000,

    "buffer_size": 4096,

    "cache_file": "cache/document.xlsx"

}


# ==========================================================
# Create config if it doesn't exist
# ==========================================================

if not os.path.exists(CONFIG_FILE):

    with open(CONFIG_FILE, "w", encoding="utf-8-sig") as file:

        json.dump(
            DEFAULT,
            file,
            indent=4
        )


# ==========================================================
# Load config
# ==========================================================

with open(CONFIG_FILE, "r", encoding="utf-8-sig") as file:

    cfg = json.load(file)


# ==========================================================
# Export settings
# ==========================================================

SERVER_IP = cfg.get(
    "server_ip",
    DEFAULT["server_ip"]
)

SERVER_PORT = cfg.get(
    "server_port",
    DEFAULT["server_port"]
)

BUFFER_SIZE = cfg.get(
    "buffer_size",
    DEFAULT["buffer_size"]
)

CACHE_FILE = cfg.get(
    "cache_file",
    DEFAULT["cache_file"]
)

print(cfg)