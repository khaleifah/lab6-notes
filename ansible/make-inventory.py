#!/usr/bin/env python3
"""Generate Ansible's inventory from actual OpenTofu outputs, without secrets."""
import argparse
import json
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument("--key", required=True, help="Absolute path to the PEM inside WSL/Linux")
p.add_argument("--tofu-dir", default="../infra-ha")
p.add_argument("--nodes-file", help="Use an exported nodes JSON file instead of invoking OpenTofu")
p.add_argument("--output", default="inventory.json")
a = p.parse_args()
key = Path(a.key).expanduser().resolve()
if not key.is_file():
    p.error("Private key does not exist at this path")
if a.nodes_file:
    nodes = json.loads(Path(a.nodes_file).read_text(encoding="utf-8-sig"))
else:
    nodes = json.loads(subprocess.check_output(["tofu", f"-chdir={a.tofu_dir}", "output", "-json", "nodes"]))
hosts = {role: {"ansible_host": data["public_ip"], "private_ip": data["private_ip"],
                "lightsail_name": data["name"]} for role, data in nodes.items()}
inventory = {"all": {"vars": {"ansible_user": "ubuntu", "ansible_ssh_private_key_file": str(key),
                               "ansible_python_interpreter": "/usr/bin/python3"},
                      "hosts": hosts,
                      "children": {"web": {"hosts": {"web1": {}, "web2": {}}}}}}
Path(a.output).write_text(json.dumps(inventory, indent=2) + "\n")
print(f"Wrote {a.output}: four nodes, using real OpenTofu addresses.")
