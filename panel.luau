--!nonstrict
-- Restic control panel for Noctalia.
-- Features:
-- 1. Multi-tab dashboard: Overview, Snapshots Browser, and Live Logs.
-- 2. Instant status reporting from ~/.local/state/restic-backup/status.json.
-- 3. Cached snapshot browser with non-destructive restore into ~/Restored/.
-- 4. Two-step safety armed confirmation on Prune.

local serviceName = "restic-backup.service"
local repository = "rclone:EncryptedGoogleDrive:Backups"
local passwordCommand = "rbw get restic-pass"
local enablePrune = false

local activeTab = "overview" -- "overview" | "snapshots" | "logs"
local serviceState = "unknown"
local statusMessage = ""
local statusData = nil
local snapshotsList = {}
local logLines = {}

local isWorking = false
local isFetchingSnapshots = false
local pruneArmed = false
local pruneArmedTicks = 0

local render

local function tr(key, args)
  return noctalia.tr(key, args)
end

local function getHelperScriptPath()
  return noctalia.pluginDir() .. "/manage_restic.py"
end

local function cleanLogLine(raw)
  local time, msg = raw:match("^%a+%s+%d+%s+([%d:]+)%s+[%w_-]+%s+[^:]+:%s*(.*)$")
  if time and msg then
    return string.format("[%s] %s", time, msg)
  end
  return raw
end

local function loadStatusFile()
  local path = noctalia.expandPath("~/.local/state/restic-backup/status.json")
  local raw = noctalia.readFile(path)
  if raw and raw ~= "" then
    local ok, data = pcall(noctalia.json.decode, raw)
    if ok and type(data) == "table" then
      statusData = data
    end
  end
end

local function loadCachedSnapshots()
  local path = noctalia.expandPath("~/.cache/noctalia-restic/snapshots.json")
  local raw = noctalia.readFile(path)
  if raw and raw ~= "" then
    local ok, data = pcall(noctalia.json.decode, raw)
    if ok and type(data) == "table" then
      snapshotsList = {}
      for i = #data, 1, -1 do -- reverse: newest first
        table.insert(snapshotsList, data[i])
      end
    end
  end
end

local function refreshStatus()
  loadStatusFile()
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
        if not line:match("^%-%-%s+Boot") and not line:match("^%s*$") then
          table.insert(logLines, cleanLogLine(line))
        end
      end
    end
    render()
  end, 15000)
end

local function refreshAll()
  loadCachedSnapshots()
  refreshStatus()
  refreshLogs()
end

local function fetchCloudSnapshots()
  if isFetchingSnapshots then
    return
  end
  isFetchingSnapshots = true
  statusMessage = "Fetching snapshots from Google Drive..."
  render()

  local scriptPath = getHelperScriptPath()
  local cmd = 'python3 "' .. scriptPath .. '" fetch-snapshots'

  noctalia.runAsync(cmd, function(res)
    isFetchingSnapshots = false
    if res and res.stdout and res.stdout ~= "" then
      local ok, data = pcall(noctalia.json.decode, res.stdout)
      if ok and data.ok then
        statusMessage = string.format("Fetched %d snapshots.", data.count or 0)
        loadCachedSnapshots()
      else
        statusMessage = "Failed to fetch cloud snapshots."
      end
    else
      statusMessage = "Snapshot query timed out."
    end
    render()
  end, 90000)
end

local function restoreSnapshot(snapshotId)
  if isWorking then
    return
  end
  isWorking = true
  statusMessage = tr("panel.restoring")
  render()

  local scriptPath = getHelperScriptPath()
  local cmd = 'python3 "' .. scriptPath .. '" restore ' .. string.format("%q", snapshotId)

  noctalia.runAsync(cmd, function(res)
    isWorking = false
    if res and res.stdout and res.stdout ~= "" then
      local ok, data = pcall(noctalia.json.decode, res.stdout)
      if ok and data.ok then
        statusMessage = data.message or "Restored successfully."
        noctalia.notify("Restic Restore", data.message or "Snapshot restored safely.")
      else
        local err = (data and data.error) or "Restore failed"
        statusMessage = err
        noctalia.notifyError("Restic Restore", err)
      end
    else
      statusMessage = "Restore command timed out."
      noctalia.notifyError("Restic Restore", "Restore process timed out.")
    end
    render()
  end, 240000)
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
  end, 90000)
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
  elseif serviceState == "failed" or (statusData and statusData.status == "failed") then
    stateText = tr("panel.status_failed")
    stateColor = "error"
    stateGlyph = "alert-triangle"
  elseif serviceState == "unknown" then
    stateText = tr("panel.status_unknown")
  end

  local children = {}

  -- Top Header
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

  -- Navigation Tabs
  local tabButtons = {
    ui.button({
      text = tr("panel.tab_overview"),
      variant = (activeTab == "overview") and "primary" or "ghost",
      fontSize = 11,
      onClick = function()
        activeTab = "overview"
        render()
      end,
      flexGrow = 1,
    }),
    ui.button({
      text = string.format("%s (%d)", tr("panel.tab_snapshots"), #snapshotsList),
      variant = (activeTab == "snapshots") and "primary" or "ghost",
      fontSize = 11,
      onClick = function()
        activeTab = "snapshots"
        render()
      end,
      flexGrow = 1,
    }),
    ui.button({
      text = tr("panel.tab_logs"),
      variant = (activeTab == "logs") and "primary" or "ghost",
      fontSize = 11,
      onClick = function()
        activeTab = "logs"
        render()
      end,
      flexGrow = 1,
    }),
  }
  table.insert(children, ui.row({ gap = 4, align = "center" }, tabButtons))

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

  -- Content based on active tab
  if activeTab == "overview" then
    local overviewItems = {}

    -- Meta Info Card
    table.insert(
      overviewItems,
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

    local lastRunStr = (statusData and statusData.last_backup_time) or "Never recorded"
    table.insert(
      overviewItems,
      ui.row({ gap = 6, align = "center" }, {
        ui.glyph({ name = "clock", size = 13, color = "on_surface_variant" }),
        ui.label({
          text = string.format("%s: %s", tr("panel.last_backup_label"), lastRunStr),
          fontSize = 11,
          color = "on_surface",
          fontWeight = "bold",
        }),
      })
    )

    table.insert(overviewItems, ui.separator())

    -- Action Buttons
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

    table.insert(overviewItems, ui.row({ gap = 6, align = "center" }, actionButtons))

    table.insert(
      children,
      ui.scroll({ flexGrow = 1, gap = 8 }, overviewItems)
    )

  elseif activeTab == "snapshots" then
    local snapItems = {}

    -- Snapshots header with Refresh button
    table.insert(
      snapItems,
      ui.row({ align = "center", justify = "between" }, {
        ui.label({
          text = string.format("%s (%d)", tr("panel.snapshots_title"), #snapshotsList),
          fontSize = 12,
          fontWeight = "bold",
          color = "on_surface",
          flexGrow = 1,
        }),
        ui.button({
          text = isFetchingSnapshots and "Fetching..." or tr("panel.btn_fetch_snapshots"),
          glyph = "refresh",
          variant = "ghost",
          fontSize = 11,
          onClick = fetchCloudSnapshots,
        }),
      })
    )

    if #snapshotsList == 0 then
      table.insert(
        snapItems,
        ui.label({
          text = tr("panel.no_snapshots"),
          fontSize = 11,
          color = "on_surface_variant",
        })
      )
    else
      for _, snap in ipairs(snapshotsList) do
        local sid = snap.short_id or (snap.id and snap.id:sub(1, 8)) or "unknown"
        local timeStr = snap.time and snap.time:sub(1, 19):gsub("T", " ") or ""
        local pathStr = (snap.paths and table.concat(snap.paths, ", ")) or ""

        local rowChildren = {
          ui.column({ flexGrow = 1, gap = 2 }, {
            ui.row({ gap = 6, align = "center" }, {
              ui.label({ text = "#" .. sid, fontSize = 11, fontWeight = "bold", color = "primary" }),
              ui.label({ text = timeStr, fontSize = 10, color = "on_surface" }),
            }),
            ui.label({ text = pathStr, fontSize = 9, color = "on_surface_variant", maxLines = 1 }),
          }),
          ui.button({
            text = tr("panel.btn_restore"),
            glyph = "rotate-2",
            variant = "ghost",
            fontSize = 10,
            onClick = function()
              restoreSnapshot(snap.id or sid)
            end,
          }),
        }

        table.insert(
          snapItems,
          ui.row({ gap = 8, align = "center", paddingV = 4 }, rowChildren)
        )
        table.insert(snapItems, ui.separator())
      end
    end

    table.insert(
      children,
      ui.scroll({ flexGrow = 1, gap = 6 }, snapItems)
    )

  elseif activeTab == "logs" then
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
      ui.scroll({ flexGrow = 1, gap = 3 }, logItems)
    )
  end

  panel.render(ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, children))
end

function onOpen(_context)
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
    if pruneArmedTicks >= 4 then
      pruneArmed = false
      statusMessage = ""
      render()
    end
  end
  refreshStatus()
end
