# Noctalia Restic Backup Plugin

A sleek, native desktop shell plugin for [Noctalia](https://github.com/noctalia-dev/noctalia) to monitor and control [Restic](https://restic.net/) cloud backups directly from your Wayland top bar.

![Noctalia Restic Plugin](https://raw.githubusercontent.com/firomsa/noctalia-restic/main/preview.png)

## ✨ Features

* **Real-time Status Indicator**: Discreet top bar icon reflecting current backup state (Idle, In Progress, Failed).
* **One-Click Actions**:
  * 🚀 **Backup Now**: Instantly trigger your user systemd backup service.
  * 🔓 **Unlock Repo**: Clear stale backend locks (`restic unlock`) with a single click.
  * 🧹 **Prune & Clean**: Run retention policies and prune unneeded snapshots.
* **Live Journal Logs**: View the last 10 lines of `journalctl` directly in the popout panel.
* **Non-Blocking Execution**: All commands run asynchronously without freezing your desktop or bar animations.
* **Fully Themeable**: Inherits your Noctalia color palette, fonts, and corner radius automatically.

## 📦 Requirements

* [Noctalia Shell](https://github.com/noctalia-dev/noctalia) (API v14+)
* `restic` installed and on PATH
* Systemd user service running your backup (e.g. `restic-backup.service`)
* Password provider configured (e.g. `rbw`, `pass`, or environment variable)

## 🚀 Installation & Local Development

### 1. Clone the repository
```bash
git clone https://github.com/firomsa/noctalia-restic.git ~/Projects/noctalia-restic
```

### 2. Add as a Local Noctalia Source
Create a local development sources directory and link the project:
```bash
mkdir -p ~/.local/share/noctalia/sources/local-dev
ln -s ~/Projects/noctalia-restic ~/.local/share/noctalia/sources/local-dev/restic

# Register the source with Noctalia
noctalia msg plugins source add local-dev path ~/.local/share/noctalia/sources/local-dev
```

### 3. Enable the Plugin
```bash
noctalia msg plugins enable firomsa/restic
```

### 4. Add the Widget to Your Bar
In `~/.config/noctalia/settings.json`, add `"firomsa/restic:widget"` to your desired capsule group under `bar.default.capsule_group`:

```json
{
  "id": "g4",
  "members": [ "firomsa/restic:widget", "notes", "recorder" ]
}
```

## ⚙️ Configuration

You can customize the plugin settings in the Noctalia Settings UI under **Plugins → Restic Backup**, or directly in your Noctalia configuration:

| Setting | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `service_name` | String | `restic-backup.service` | The systemd user service name running your backup script |
| `repository` | String | `rclone:EncryptedGoogleDrive:Backups` | The target Restic repository path |
| `password_command` | String | `rbw get restic-pass` | Command used to retrieve the repository encryption password |
| `show_status_text`| Boolean | `false` | Show status text next to the cloud icon on the bar |
| `poll_interval_seconds` | Integer | `6` | Polling interval for querying systemd service state |

## 🛠️ Testing & Linting

Verify plugin validity using the Noctalia CLI:
```bash
noctalia plugins lint ~/Projects/noctalia-restic
```

## 📄 License

MIT © [Firomsa](https://github.com/firomsa)
