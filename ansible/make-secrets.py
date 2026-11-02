#!/usr/bin/env python3
"""Generate one shared signing key and DB password; preserve them on reruns."""
import json
import os
from pathlib import Path
import secrets

path = Path("secrets.yml")
if path.exists():
    raise SystemExit("secrets.yml already exists; preserved. Do not regenerate it for a rerun.")
payload = {"db_password": secrets.token_hex(24), "app_secret": secrets.token_hex(32)}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as output:
    # JSON is also valid YAML, so Ansible can load it directly.
    json.dump(payload, output, indent=2)
    output.write("\n")
print("Created secrets.yml with permissions 600; values are not printed.")
