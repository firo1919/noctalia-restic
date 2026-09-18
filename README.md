# Noctalia Restic Backup Plugin

A native desktop shell plugin for [Noctalia](https://github.com/noctalia-dev/noctalia) to monitor, configure, browse, and safely restore [Restic](https://restic.net/) cloud backups directly from your Wayland top bar.

Inspired by [omarchy-time-machine](https://github.com/jankeesvw/omarchy-time-machine), this plugin provides instant visibility, cached snapshot browsing, non-destructive file restoration, and automated systemd generator management.

## Features

* **Panel-Managed Settings**: Configure your backup repository, Bitwarden password command, sources, and automated schedule directly from the panel.
* **Automated Systemd Generator**: Generates clean, XDG-compliant `noctalia-restic.service`, `noctalia-restic.timer`, and `runner.sh` scripts with low I/O priority (`Nice=19`).
* **Zero-Network Status Check**: Reads a local status file (`~/.local/state/noctalia-restic/status.json`) written on completion of your backup. Displays exact backup age on the bar with 0 ms latency without hitting the cloud.
* **Smart Failure Indication**: The bar icon stays clean and quiet when healthy, and turns red (`alert-triangle`) when a backup fails or becomes critically stale.
* **Snapshot Browser**: Explore all historical snapshots (timestamp, paths, snapshot ID) in a dedicated tab with instant cached loading.
* **Non-Destructive Restore**: Restore any snapshot with a single click. Files are always extracted safely into `~/Restored/YYYY-MM-DD-HHMM-<id>/` so your active files can never be accidentally overwritten.
* **One-Click Maintenance**:
  * **Backup Now**: Instantly trigger your user systemd backup service.
  * **Unlock Repo**: Clear stale backend locks (`restic unlock`) with a single click.
  * **Prune & Clean**: Run retention policies with a two-step safety confirmation guard.
* **Live Journal Logs**: View real-time output from `journalctl` directly in the panel.

## Architecture & XDG Layout

All generated files and state follow standard XDG specifications:

| Path | Purpose |
| :--- | :--- |
| `~/.config/noctalia-restic/config.json` | User backup configuration (repository, sources, schedule) |
| `~/.local/share/noctalia-restic/runner.sh` | Auto-generated backup runner script (umask 077, locked execution) |
| `~/.local/state/noctalia-restic/status.json` | Local backup run status, timestamps, and exit codes |
| `~/.cache/noctalia-restic/snapshots.json` | Cached cloud snapshot metadata for instant UI browsing |
| `~/.config/systemd/user/noctalia-restic.{service,timer}` | Auto-generated user systemd units |

## Requirements

* [Noctalia Shell](https://github.com/noctalia-dev/noctalia) (API v14+)
* `restic` installed and on PATH
* `python3` (for generator and snapshot management)
* Password provider configured (e.g. `rbw`, `pass`, or environment variable)

## Installation & Local Development

### 1. Clone the repository
```bash
git clone https://github.com/firo1919/noctalia-restic.git ~/Projects/noctalia-restic
```

### 2. Add as a Local Noctalia Source
```bash
mkdir -p ~/.local/share/noctalia/sources/local-dev
ln -s ~/Projects/noctalia-restic ~/.local/share/noctalia/sources/local-dev/restic

# Register the source with Noctalia
noctalia msg plugins source add local-dev path ~/.local/share/noctalia/sources/local-dev
```

### 3. Generate Standard Systemd Units
```bash
python3 ~/Projects/noctalia-restic/manage_restic.py install
```

### 4. Enable the Plugin
```bash
noctalia msg plugins enable firo1919/restic
```

### 5. Add the Widget to Your Bar
Open Noctalia Settings (`noctalia msg settings-open`) → **Bar** → select your capsule group → **Add Widget** → **Restic Backup** (`firo1919/restic:widget`).

## License

MIT © [firo1919](https://github.com/firo1919)
