--!nonstrict
-- Restic control panel for Noctalia.
-- Provides live status, quick actions (Backup, Unlock, safe Prune guard), and journal tail.

local serviceName = "restic-backup.service"
local repository = "rclone:EncryptedGoogleDrive:Backups"
local passwordCommand = "rbw get restic-pass"
local enablePrune = false

local serviceState = "unknown"
local statusMessage = ""
local logLines = {}
local isWorking = false
local pruneArmed = false
local pruneArmedTicks = 0

local render

local function tr(key, args)
  return noctalia.tr(key, args)
end

local function cleanLogLine(raw)
  -- Strip verbose hostname & PID prefix: "Sep 17 20:22:45 noone bash[901888]: message" -> "[20:22:45] message"
  local time, msg = raw:match("^%a+%s+%d+%s+([%d:]+)%s+[%w_-]+%s+[^:]+:%s*(.*)$")
  if time and msg then
    return string.format("[%s] %s", time, msg)
  end
  return raw
end

local function refreshStatus()
  noctalia.runAsync("systemctl --user is-active " .. serviceName, function(res)
    local out = (res and res.stdout) or ""
    serviceState = out:gsub("%s+", "")
    render()
  end, 10000)
end

local function refreshLogs()
  noctalia.runAsync("journalctl --user -u " .. serviceName .. " -n 14 --no-pager", function(res)
    logLines = {}
    local out = (res and res.stdout) or ""
    if out ~= "" then
      for line in out:gmatch("[^\r\n]+") do
        -- Skip systemd boot session dividers
        if not line:match("^%-%-%s+Boot") and not line:match("^%s*$") then
          table.insert(logLines, cleanLogLine(line))
        end
      end
    end
    render()
  end, 15000)
end

local function refreshAll()
  refreshStatus()
  refreshLogs()
end

local function triggerBackup()
  statusMessage = tr("panel.backup_started")
  render()
  noctalia.runAsync("systemctl --user start " .. serviceName, function(res)
    if res and res.exitCode == 0 then
      noctalia.notifyInfo(tr("panel.title"), tr("panel.backup_started"))
    else
      local err = (res and res.stderr ~= "") and res.stderr or "Failed to start backup service"
      noctalia.notifyError(tr("panel.title"), err)
    end
    refreshAll()
  end, 15000)
end

local function unlockRepo()
  if isWorking then
    return
  end
  isWorking = true
  statusMessage = "Unlocking repository..."
  render()

  local cmd = string.format("restic unlock -r %s --password-command %q", repository, passwordCommand)
  noctalia.runAsync(cmd, function(res)
    isWorking = false
    if res and res.exitCode == 0 then
      statusMessage = tr("panel.unlocked_ok")
      noctalia.notifyInfo(tr("panel.title"), tr("panel.unlocked_ok"))
    else
      statusMessage = tr("panel.unlock_failed")
      local err = (res and res.stderr ~= "") and res.stderr or tr("panel.unlock_failed")
      noctalia.notifyError(tr("panel.title"), err)
    end
    refreshAll()
  end, 60000)
end

local function pruneRepo()
  if isWorking then
    return
  end

  -- Safety guard: two-step confirmation
  if not pruneArmed then
    pruneArmed = true
    pruneArmedTicks = 0
    statusMessage = "Click Confirm to prune unneeded snapshots, or Cancel"
    render()
    return
  end

  pruneArmed = false
  isWorking = true
  statusMessage = tr("panel.prune_started")
  render()

  local cmd = string.format(
    "restic forget -r %s --password-command %q --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune",
    repository,
    passwordCommand
  )
  noctalia.runAsync(cmd, function(res)
    isWorking = false
    if res and res.exitCode == 0 then
      statusMessage = tr("panel.prune_done")
      noctalia.notifyInfo(tr("panel.title"), tr("panel.prune_done"))
    else
      statusMessage = tr("panel.prune_failed")
      local err = (res and res.stderr ~= "") and res.stderr or tr("panel.prune_failed")
      noctalia.notifyError(tr("panel.title"), err)
    end
    refreshAll()
  end, 60000)
end

local function cancelPrune()
  pruneArmed = false
  statusMessage = ""
  render()
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
  elseif serviceState == "unknown" then
    stateText = tr("panel.status_unknown")
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
          color = pruneArmed and "error" or "primary",
          flexGrow = 1,
        }),
      })
    )
  end

  -- Action Buttons Row
  local actionButtons = {
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
  }

  -- Only show prune if enabled in settings, with 2-step confirmation
  if enablePrune then
    if pruneArmed then
      table.insert(
        actionButtons,
        ui.button({
          text = tr("panel.btn_confirm_prune"),
          glyph = "alert-triangle",
          variant = "destructive",
          onClick = pruneRepo,
          flexGrow = 1,
        })
      )
      table.insert(
        actionButtons,
        ui.button({
          text = tr("panel.btn_cancel"),
          glyph = "x",
          variant = "ghost",
          onClick = cancelPrune,
        })
      )
    else
      table.insert(
        actionButtons,
        ui.button({
          text = tr("panel.btn_prune"),
          glyph = "trash",
          variant = "ghost",
          onClick = pruneRepo,
          flexGrow = 1,
        })
      )
    end
  end

  table.insert(
    actionButtons,
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      onClick = refreshAll,
    })
  )

  table.insert(children, ui.row({ gap = 6, align = "center" }, actionButtons))

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
        fontSize = 11,
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
        })
      )
    end
  end

  table.insert(
    children,
    ui.scroll({ flexGrow = 1, gap = 4 }, logItems)
  )

  panel.render(ui.column({ flexGrow = 1, gap = 12, align = "stretch" }, children))
end

function onOpen(_context)
  -- Reload configuration dynamically whenever opened
  serviceName = noctalia.getConfig("service_name") or "restic-backup.service"
  repository = noctalia.getConfig("repository") or "rclone:EncryptedGoogleDrive:Backups"
  passwordCommand = noctalia.getConfig("password_command") or "rbw get restic-pass"
  enablePrune = noctalia.getConfig("enable_prune_action") == true

  statusMessage = ""
  pruneArmed = false
  refreshAll()
end

function onClose()
  statusMessage = ""
  pruneArmed = false
end

function update()
  noctalia.setUpdateInterval(2500)
  if pruneArmed then
    pruneArmedTicks += 1
    if pruneArmedTicks >= 4 then -- Auto-disarm after ~10 seconds
      pruneArmed = false
      statusMessage = ""
      render()
    end
  end
  refreshStatus()
end
