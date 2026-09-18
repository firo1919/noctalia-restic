--!nonstrict
-- Restic status bar widget for Noctalia.
-- Monitors the user systemd service and reads ~/.local/state/restic-backup/status.json
-- for instant, zero-network status reporting.

local serviceName = noctalia.getConfig("service_name") or "restic-backup.service"
local showText = noctalia.getConfig("show_status_text") == true
local pollSeconds = tonumber(noctalia.getConfig("poll_interval_seconds")) or 6
local pollMs = math.max(pollSeconds, 3) * 1000

local currentState = "unknown"
local lastBackupHuman = "unknown"
local isFailed = false

local function loadStatusJson()
  local path = noctalia.expandPath("~/.local/state/restic-backup/status.json")
  local raw = noctalia.readFile(path)
  if raw and raw ~= "" then
    local ok, data = pcall(noctalia.json.decode, raw)
    if ok and type(data) == "table" then
      if data.last_backup_time then
        lastBackupHuman = data.last_backup_time
      end
      if data.status == "failed" then
        isFailed = true
      elseif data.status == "success" then
        isFailed = false
      end
    end
  end
end

local function renderWidget(glyph, glyphColor, text, tooltip)
  local container = barWidget.isVertical() and ui.column or ui.row
  local children = {
    ui.glyph({ name = glyph, size = 15, color = glyphColor }),
  }
  if showText and text ~= "" then
    table.insert(children, ui.label({ text = text, fontSize = 11, color = glyphColor }))
  end

  barWidget.setTooltip(tooltip)
  barWidget.render(container({
    gap = 6,
    align = "center",
    onClick = function()
      noctalia.togglePanel("firo1919/restic:panel")
    end,
  }, children))
end

local function updatePresentation()
  loadStatusJson()

  if currentState == "active" or currentState == "activating" then
    renderWidget("loader", "primary", noctalia.tr("widget.text_running"), noctalia.tr("widget.running_tooltip"))
  elseif currentState == "failed" or isFailed then
    local tooltip = "Restic: Last backup FAILED!\nLast run: " .. lastBackupHuman .. "\nClick to inspect"
    renderWidget("alert-triangle", "error", noctalia.tr("widget.text_failed"), tooltip)
  else
    local tooltip = "Restic: Healthy\nLast backup: " .. lastBackupHuman .. "\nLeft-click: Dashboard\nRight-click: Run Backup"
    renderWidget("cloud-check", "on_surface", "", tooltip)
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
renderWidget("cloud", "on_surface", "", noctalia.tr("widget.idle_tooltip"))
checkStatus()
