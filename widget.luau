--!nonstrict
-- Restic status bar widget for Noctalia.
-- Monitors the user systemd service and reads ~/.local/state/noctalia-restic/status.json
-- for instant, zero-network status reporting with native hover tooltips.

local serviceName = noctalia.getConfig("service_name") or "noctalia-restic.service"
local showText = noctalia.getConfig("show_status_text") == true
local pollSeconds = tonumber(noctalia.getConfig("poll_interval_seconds")) or 6
local pollMs = math.max(pollSeconds, 3) * 1000

local currentState = "unknown"
local lastBackupHuman = "Never"
local lastBackupEpoch = 0
local repoTarget = "Google Drive"
local isFailed = false

local function formatRelativeTime(epoch)
  if not epoch or epoch == 0 then
    return "Never"
  end
  local now = os.time()
  local diff = math.max(0, now - epoch)
  if diff < 60 then
    return "Just now"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return string.format("%d min%s ago", mins, mins == 1 and "" or "s")
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return string.format("%d hour%s ago", hours, hours == 1 and "" or "s")
  else
    local days = math.floor(diff / 86400)
    return string.format("%d day%s ago", days, days == 1 and "" or "s")
  end
end

local function loadStatusJson()
  local path = noctalia.expandPath("~/.local/state/noctalia-restic/status.json")
  local raw = noctalia.readFile(path)
  if raw and raw ~= "" then
    local ok, data = pcall(noctalia.json.decode, raw)
    if ok and type(data) == "table" then
      if data.last_backup_time then
        lastBackupHuman = data.last_backup_time
      end
      if data.last_backup_epoch then
        lastBackupEpoch = tonumber(data.last_backup_epoch) or 0
      end
      if data.repository then
        local r = data.repository
        if r:find("GoogleDrive") then
          repoTarget = "Google Drive (Cloud)"
        else
          repoTarget = r:match("([^/:]+)$") or r
        end
      end
      if data.status == "failed" then
        isFailed = true
      elseif data.status == "success" then
        isFailed = false
      end
    end
  end
end

local function updatePresentation()
  loadStatusJson()

  local relTime = formatRelativeTime(lastBackupEpoch)

  if currentState == "active" or currentState == "activating" then
    barWidget.setGlyph("loader")
    barWidget.setGlyphColor("primary")
    barWidget.setText(showText and noctalia.tr("widget.text_running") or "")
    barWidget.setTooltip({
      { key = "Status", value = "Backup in progress..." },
      { key = "Target", value = repoTarget },
      { key = "Started", value = relTime },
      { key = "Left-click", value = "Open live dashboard" },
    })
  elseif currentState == "failed" or isFailed then
    barWidget.setGlyph("alert-triangle")
    barWidget.setGlyphColor("error")
    barWidget.setText(showText and noctalia.tr("widget.text_failed") or "")
    barWidget.setTooltip({
      { key = "Status", value = "Backup FAILED" },
      { key = "Last Run", value = lastBackupHuman .. " (" .. relTime .. ")" },
      { key = "Target", value = repoTarget },
      { key = "Left-click", value = "Inspect logs & unlock" },
    })
  else
    barWidget.setGlyph("cloud-check")
    barWidget.setGlyphColor("on_surface")
    barWidget.setText("")
    barWidget.setTooltip({
      { key = "Status", value = "Healthy / Up to date" },
      { key = "Last Backup", value = relTime .. " (" .. lastBackupHuman .. ")" },
      { key = "Target", value = repoTarget },
      { key = "Left-click", value = "Open Dashboard" },
      { key = "Right-click", value = "Start Backup Now" },
    })
  end
end

function checkStatus()
  noctalia.runAsync("systemctl --user is-active " .. serviceName, function(res)
    local out = (res and res.stdout) or ""
    currentState = out:gsub("%s+", "")
    updatePresentation()
  end)
end

function update()
  noctalia.setUpdateInterval(pollMs)
  checkStatus()
end

function onClick()
  noctalia.togglePanel("firo1919/restic:panel")
end

-- Initial render
loadStatusJson()
barWidget.setGlyph("cloud")
barWidget.setGlyphColor("on_surface")
barWidget.setText("")
barWidget.setTooltip("Restic: Initializing...")
checkStatus()
