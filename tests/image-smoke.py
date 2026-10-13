#!/usr/bin/env python3
"""Inspect the generic image without booting it, mounting it, or using libvirt."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


def output(*args):
    return subprocess.check_output(args, text=True)


raw = (
    Path(__file__).resolve().parents[1]
    / "mkosi.output/base/hermes-discord-base.raw"
)
info = json.loads(output("qemu-img", "info", "--output=json", str(raw.with_suffix(".qcow2"))))
assert info["format"] == "qcow2"
assert info["virtual-size"] == 20 * 1024**3
assert "backing-filename" not in info, "Image depends on another disk"

table = json.loads(output("sfdisk", "--json", str(raw)))["partitiontable"]
root = next(part for part in table["partitions"] if part["name"] == "root-x86-64")
sector = table["sectorsize"]

# Extract only the root partition to a temporary sparse file. No loop devices,
# root privileges, guest execution, or live storage are needed.
with tempfile.TemporaryDirectory(dir=os.environ.get("DELTA_SCRATCH_DIR")) as temporary:
    filesystem = Path(temporary) / "root.ext4"
    source = json.dumps(
        {
            "driver": "raw",
            "file": {"driver": "file", "filename": str(raw)},
            "offset": root["start"] * sector,
            "size": root["size"] * sector,
        }
    )
    subprocess.run(
        ["qemu-img", "convert", "-O", "raw", "-S", "4k", f"json:{source}", str(filesystem)],
        check=True,
    )

    def debug(command):
        return subprocess.run(
            ["debugfs", "-R", command, str(filesystem)],
            text=True,
            capture_output=True,
            check=True,
        )

    for path in (
        "/root/.ssh/authorized_keys",
        "/var/lib/hermes/.hermes/auth.json",
        "/var/lib/hermes/.hermes/.env",
        "/var/lib/hermes/.hermes/hermes-agent",
        "/var/lib/hermes/.hermes/voice-ready",
        "/etc/ssh/ssh_host_ed25519_key",
        "/etc/ssh/ssh_host_ecdsa_key",
        "/etc/ssh/ssh_host_rsa_key",
    ):
        assert "File not found by ext2_lookup" in debug(f"stat {path}").stderr, (
            f"Unexpected identity or runtime file: {path}"
        )

    # Inspect the password marker without printing any shadow contents.
    shadow = debug("cat /etc/shadow").stdout
    password = next(line.split(":")[1] for line in shadow.splitlines() if line.startswith("root:"))
    assert password.startswith("!"), "Root password is not locked"
    assert "0644" in debug("stat /usr/lib/os-release").stdout
    assert "0755" in debug("stat /usr/local/libexec/hermes-voice/agent").stdout
    assert "hermes-state" in debug("cat /etc/fstab").stdout

json.loads(raw.with_suffix(".manifest").read_text())
print("PASS: base image layout, permissions, locked root, and absent runtime identity")
