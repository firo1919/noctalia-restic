--!nonstrict
-- Restic control panel for Noctalia.
-- Provides live status, quick actions (Backup, Unlock, Prune), and journal tail.

local serviceName = noctalia.getConfig("service_name") or "restic-backup.service"
local repository = noctalia.getConfig("repository") or "rclone:EncryptedGoogleDrive:Backups"
local passwordCommand = noctalia.getConfig("password_command") or "rbw get restic-pass"

local serviceState = "unknown"
local statusMessage = ""
local logLines = {}
local isWorking = false

local render

local function tr(key, args)
  return noctalia.tr(key, args)
end

local function refreshStatus()
  noctalia.runAsync("systemctl --user is-active " .. serviceName, function(_code, stdout, _stderr)
    serviceState = (stdout or ""):gsub("%s+", "")
    render()
  end)
end

local function refreshLogs()
  noctalia.runAsync("journalctl --user -u " .. serviceName .. " -n 10 --no-pager", function(_code, stdout, _stderr)
    logLines = {}
    if stdout ~= nil and stdout ~= "" then
      for line in stdout:gmatch("[^\r\n]+") do
        table.insert(logLines, line)
      end
    end
    render()
  end)
end

local function refreshAll()
  refreshStatus()
  refreshLogs()
end

local function triggerBackup()
  statusMessage = tr("panel.backup_started")
  render()
  noctalia.runAsync("systemctl --user start " .. serviceName, function(code, _stdout, stderr)
    if code == 0 then
      noctalia.notifyInfo(tr("panel.title"), tr("panel.backup_started"))
    else
      noctalia.notifyError(tr("panel.title"), stderr or "Failed to start backup service")
    end
    refreshAll()
  end)
end

local function unlockRepo()
  if isWorking then
    return
  end
  isWorking = true
  statusMessage = "Unlocking repository..."
  render()

  local cmd = string.format("restic unlock -r %s --password-command %q", repository, passwordCommand)
  noctalia.runAsync(cmd, function(code, _stdout, stderr)
    isWorking = false
    if code == 0 then
      statusMessage = tr("panel.unlocked_ok")
      noctalia.notifyInfo(tr("panel.title"), tr("panel.unlocked_ok"))
    else
      statusMessage = tr("panel.unlock_failed")
      noctalia.notifyError(tr("panel.title"), stderr or tr("panel.unlock_failed"))
    end
    refreshAll()
  end)
end

local function pruneRepo()
  if isWorking then
    return
  end
  isWorking = true
  statusMessage = tr("panel.prune_started")
  render()

  local cmd = string.format(
    "restic forget -r %s --password-command %q --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune",
    repository,
    passwordCommand
  )
  noctalia.runAsync(cmd, function(code, _stdout, stderr)
    isWorking = false
    if code == 0 then
      statusMessage = tr("panel.prune_done")
      noctalia.notifyInfo(tr("panel.title"), tr("panel.prune_done"))
    else
      statusMessage = tr("panel.prune_failed")
      noctalia.notifyError(tr("panel.title"), stderr or tr("panel.prune_failed"))
    end
    refreshAll()
  end)
end

function render()
  local stateText = tr("panel.status_idle")
  local stateColor = "on_surface_variant"
  local stateGlyph = "cloud-check"

  if serviceState == "active" or serviceState == "activating" then
    stateText = tr("panel.status_running")
    stateColor = "primary"
    stateGlyph = "loader"
  elseif serviceState == "failed" then
    stateText = tr("panel.status_failed")
    stateColor = "error"
    stateGlyph = "alert-triangle"
  end

  local children = {}

  -- Header
  table.insert(
    children,
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = stateGlyph, size = 20, color = stateColor }),
      ui.label({
        text = tr("panel.title"),
        fontSize = 15,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.label({
        text = stateText,
        fontSize = 11,
        fontWeight = "bold",
        color = stateColor,
      }),
    })
  )

  -- Repository info
  table.insert(
    children,
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "database", size = 13, color = "on_surface_variant" }),
      ui.label({
        text = repository,
        fontSize = 11,
        color = "on_surface_variant",
        flexGrow = 1,
        maxLines = 1,
      }),
    })
  )

  -- Status banner
  if statusMessage ~= "" then
    table.insert(
      children,
      ui.row({ paddingH = 8, paddingV = 4 }, {
        ui.label({
          text = statusMessage,
          fontSize = 11,
          color = "primary",
          flexGrow = 1,
        }),
      })
    )
  end

  -- Action Buttons
  table.insert(
    children,
    ui.row({ gap = 6, align = "center" }, {
      ui.button({
        text = tr("panel.btn_backup_now"),
        glyph = "player-play",
        variant = "primary",
        onClick = triggerBackup,
        flexGrow = 1,
      }),
      ui.button({
        text = tr("panel.btn_unlock"),
        glyph = "lock-open",
        variant = "ghost",
        onClick = unlockRepo,
        flexGrow = 1,
      }),
      ui.button({
        text = tr("panel.btn_prune"),
        glyph = "trash",
        variant = "ghost",
        onClick = pruneRepo,
        flexGrow = 1,
      }),
      ui.button({
        glyph = "refresh",
        variant = "ghost",
        onClick = refreshAll,
      }),
    })
  )

  -- Logs Header
  table.insert(
    children,
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "terminal-2", size = 14, color = "on_surface_variant" }),
      ui.label({
        text = tr("panel.logs_title"),
        fontSize = 12,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
    })
  )

  -- Log lines container
  local logItems = {}
  if #logLines == 0 then
    table.insert(
      logItems,
      ui.label({
        text = "No recent logs",
        fontSize = 10,
        color = "on_surface_variant",
      })
    )
  else
    for _, line in ipairs(logLines) do
      table.insert(
        logItems,
        ui.label({
          text = line,
          fontSize = 10,
          color = "on_surface_variant",
          maxLines = 1,
        })
      )
    end
  end

  table.insert(
    children,
    ui.scroll({ flexGrow = 1 }, {
      ui.column({ gap = 3, align = "stretch" }, logItems),
    })
  )

  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, children))
end

function onOpen(_context)
  statusMessage = ""
  refreshAll()
end

function onClose()
  statusMessage = ""
end

function update()
  refreshStatus()
end
