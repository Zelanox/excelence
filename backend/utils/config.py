import json
import os
import sys

from backend.utils.logger import get_logger


# ==========================================================
# Base folder
# ==========================================================


if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))


CONFIG_FILE = os.path.join(BASE_DIR, "config.json")
<<<<<<< HEAD
DOCUMENTS_FOLDER = os.path.join(BASE_DIR, "data", "documents")
=======
DOCUMENTS_FOLDER = "backend/data/documents"
>>>>>>> 48b5b7e5f20e81cf47af51eff978ce2e3b83027a

logger = get_logger("config")
logger.info("Using config file %s", CONFIG_FILE)

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

logger.debug("Configuration loaded: %s", cfg)