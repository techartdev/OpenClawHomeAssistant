#!/usr/bin/env python3
"""check-openclaw-update.py

Checks npm for the latest `openclaw` version and, if newer than the pinned
version in openclaw_assistant/Dockerfile, bumps:
- openclaw_assistant/Dockerfile (openclaw@X)
- openclaw_assistant/config.yaml add-on version (patch +1)

Then commits and pushes to origin/main.

Designed for HA add-on maintenance automation.

Notes:
- Requires network + npm.
- Requires git configured and repo clean.
- Uses /config/secrets/github.txt (user:token) to authenticate push.
- Resets remote URL back to clean https URL after push.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DOCKERFILE = REPO / "openclaw_assistant" / "Dockerfile"
ADDON_CFG = REPO / "openclaw_assistant" / "config.yaml"
SECRETS_GH = Path("/config/secrets/github.txt")
CLEAN_REMOTE = "https://github.com/techartdev/OpenClawHomeAssistant.git"


def sh(cmd: list[str], *, check: bool = True, capture: bool = False) -> str:
    kwargs = {}
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.STDOUT
        kwargs["text"] = True
    p = subprocess.run(cmd, cwd=REPO, check=False, **kwargs)
    if check and p.returncode != 0:
        out = p.stdout if capture else ""
        raise SystemExit(f"Command failed ({p.returncode}): {' '.join(cmd)}\n{out}")
    return p.stdout.strip() if capture and p.stdout else ""


def parse_openclaw_pinned_version(dockerfile_text: str) -> str:
    m = re.search(r"npm\s+install\s+-g\s+openclaw@([0-9]+\.[0-9]+\.[0-9]+)", dockerfile_text)
    if not m:
        raise SystemExit("Could not find pinned openclaw@X.Y.Z in Dockerfile")
    return m.group(1)


def bump_addon_patch(version: str) -> str:
    # expects something like 0.5.12
    parts = version.strip().strip('"').split(".")
    if len(parts) != 3:
        raise SystemExit(f"Unexpected add-on version format: {version}")
    major, minor, patch = parts
    return f"{major}.{minor}.{int(patch)+1}"


def get_addon_version(cfg_text: str) -> str:
    m = re.search(r"^version:\s*\"([^\"]+)\"\s*$", cfg_text, flags=re.M)
    if not m:
        raise SystemExit("Could not find version: \"...\" in config.yaml")
    return m.group(1)


def main() -> None:
    # ensure clean tree
    status = sh(["git", "status", "--porcelain"], capture=True)
    if status:
        raise SystemExit(f"Repo is not clean; aborting.\n{status}")

    docker = DOCKERFILE.read_text(encoding="utf-8")
    pinned = parse_openclaw_pinned_version(docker)

    latest = sh(["npm", "view", "openclaw", "version"], capture=True)

    if latest == pinned:
        print(f"No update. pinned={pinned} latest={latest}")
        return

    print(f"Updating openclaw {pinned} -> {latest}")

    docker2 = re.sub(r"(npm\s+install\s+-g\s+openclaw@)([0-9]+\.[0-9]+\.[0-9]+)", rf"\g<1>{latest}", docker)
    DOCKERFILE.write_text(docker2, encoding="utf-8")

    cfg = ADDON_CFG.read_text(encoding="utf-8")
    cur_addon = get_addon_version(cfg)
    new_addon = bump_addon_patch(cur_addon)
    cfg2 = re.sub(r"^version:\s*\"([^\"]+)\"\s*$", f'version: "{new_addon}"', cfg, flags=re.M)
    ADDON_CFG.write_text(cfg2, encoding="utf-8")

    sh(["git", "add", str(DOCKERFILE), str(ADDON_CFG)])
    sh(["git", "commit", "-m", f"Bump bundled openclaw to {latest}; bump add-on to {new_addon}"])

    # push
    if not SECRETS_GH.exists():
        raise SystemExit("Missing /config/secrets/github.txt for push auth")

    user, token = SECRETS_GH.read_text(encoding="utf-8").strip().split(":", 1)
    authed = f"https://{user}:{token}@github.com/techartdev/OpenClawHomeAssistant.git"

    sh(["git", "remote", "set-url", "origin", authed])
    try:
        sh(["git", "push", "origin", "main"], check=True)
    finally:
        sh(["git", "remote", "set-url", "origin", CLEAN_REMOTE], check=False)

    print("Done.")


if __name__ == "__main__":
    main()
