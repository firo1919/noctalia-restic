#!/usr/bin/env python3
"""
Helper engine for Noctalia Restic Plugin (firo1919/restic).
Handles snapshot caching, non-destructive file restoration, and status tracking.
Inspired by omarchy-time-machine architecture.
"""

import sys
import os
import json
import time
import subprocess

CACHE_DIR = os.path.expanduser("~/.cache/noctalia-restic")
STATE_DIR = os.path.expanduser("~/.local/state/restic-backup")
SNAPSHOTS_CACHE = os.path.join(CACHE_DIR, "snapshots.json")
STATUS_FILE = os.path.join(STATE_DIR, "status.json")

def get_config():
    # Read repo and password command from environment or defaults
    repo = os.environ.get("RESTIC_REPOSITORY", "rclone:EncryptedGoogleDrive:Backups")
    pwd_cmd = os.environ.get("RESTIC_PASSWORD_COMMAND", "rbw get restic-pass")
    return repo, pwd_cmd

def cmd_fetch_snapshots():
    os.makedirs(CACHE_DIR, exist_ok=True)
    repo, pwd_cmd = get_config()

    cmd = [
        "restic", "snapshots",
        "-r", repo,
        "--password-command", pwd_cmd,
        "--json"
    ]

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            with open(SNAPSHOTS_CACHE, "w") as f:
                json.dump(data, f, indent=2)
            print(json.dumps({"ok": True, "count": len(data), "cached_at": int(time.time())}))
            return
        else:
            print(json.dumps({"ok": False, "error": res.stderr.strip()}))
            return
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))

def cmd_restore(snapshot_id):
    if not snapshot_id:
        print(json.dumps({"ok": False, "error": "Missing snapshot ID"}))
        return

    repo, pwd_cmd = get_config()

    # Non-destructive restore: always restore into ~/Restored/YYYY-MM-DD-HHMM-<id>
    timestamp_str = time.strftime("%Y-%m-%d-%H%M")
    target_dir = os.path.expanduser(f"~/Restored/{timestamp_str}-{snapshot_id[:8]}")
    os.makedirs(target_dir, exist_ok=True)

    cmd = [
        "restic", "restore", snapshot_id,
        "--target", target_dir,
        "-r", repo,
        "--password-command", pwd_cmd
    ]

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if res.returncode == 0:
            print(json.dumps({
                "ok": True,
                "snapshot_id": snapshot_id,
                "target": target_dir,
                "message": f"Snapshot #{snapshot_id[:8]} restored safely to {target_dir}"
            }))
        else:
            print(json.dumps({"ok": False, "error": res.stderr.strip()}))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))

def cmd_status():
    if os.path.isfile(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                data = json.load(f)
            data["ok"] = True
            print(json.dumps(data))
            return
        except Exception:
            pass
    print(json.dumps({"ok": False, "error": "No status file found"}))

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Missing command argument"}))
        sys.exit(1)

    subcmd = sys.argv[1]
    if subcmd == "fetch-snapshots":
        cmd_fetch_snapshots()
    elif subcmd == "restore":
        sid = sys.argv[2] if len(sys.argv) > 2 else ""
        cmd_restore(sid)
    elif subcmd == "status":
        cmd_status()
    else:
        print(json.dumps({"ok": False, "error": f"Unknown command '{subcmd}'"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
