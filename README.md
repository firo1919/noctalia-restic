# Noctalia Restic Backup Plugin

A native desktop shell plugin for [Noctalia](https://github.com/noctalia-dev/noctalia) to monitor, browse, and safely restore [Restic](https://restic.net/) cloud backups directly from your Wayland top bar.

Inspired by [omarchy-time-machine](https://github.com/jankeesvw/omarchy-time-machine), this plugin provides instant visibility, cached snapshot browsing, and non-destructive file restoration.

## Features

* **Zero-Network Status Check**: Reads a local status file (`~/.local/state/restic-backup/status.json`) written on completion of your backup. Displays exact backup age on the bar with 0 ms latency without hitting the cloud.
* **Smart Failure Indication**: Follows the Time Machine rule—the bar icon stays clean and quiet when healthy, and turns red (`alert-triangle`) when a backup fails or becomes critically stale.
* **Snapshot Browser**: Explore all historical snapshots (timestamp, paths, snapshot ID) in a dedicated tab with instant cached loading.
* **Non-Destructive Restore**: Restore any snapshot with a single click. Files are always extracted safely into `~/Restored/YYYY-MM-DD-HHMM-<id>/` so your active files can never be accidentally overwritten.
* **One-Click Maintenance**:
  * **Backup Now**: Instantly trigger your user systemd backup service.
  * **Unlock Repo**: Clear stale backend locks (`restic unlock`) with a single click.
  * **Prune & Clean**: Run retention policies with a two-step safety confirmation guard.
* **Live Journal Logs**: View real-time output from `journalctl` directly in the panel.
* **Password Manager Integration**: Native support for Bitwarden via `rbw`.

## Requirements

* [Noctalia Shell](https://github.com/noctalia-dev/noctalia) (API v14+)
* `restic` installed and on PATH
* Systemd user service running your backup (e.g. `restic-backup.service`)
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

### 3. Enable the Plugin
```bash
noctalia msg plugins enable firo1919/restic
```

### 4. Add the Widget to Your Bar
Open Noctalia Settings (`noctalia msg settings-open`) → **Bar** → select your capsule group → **Add Widget** → **Restic Backup** (`firo1919/restic:widget`).

## Configuration

Settings can be customized in Noctalia Settings under **Plugins → Restic Backup**:

| Setting | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `service_name` | String | `restic-backup.service` | The systemd user service name running your backup script |
| `repository` | String | `rclone:EncryptedGoogleDrive:Backups` | The target Restic repository path |
| `password_command` | String | `rbw get restic-pass` | Command used to retrieve the repository encryption password |
| `enable_prune_action` | Boolean | `false` | Enable the prune button (disabled by default for safety) |
| `show_status_text`| Boolean | `false` | Show status text next to the cloud icon on the bar |
| `poll_interval_seconds` | Integer | `6` | Polling interval for querying systemd service state |

## License

MIT © [firo1919](https://github.com/firo1919)
