--!nonstrict
-- Restic status bar widget for Noctalia.
-- Monitors the user systemd service running restic backups.

local serviceName = noctalia.getConfig("service_name") or "restic-backup.service"
local showText = noctalia.getConfig("show_status_text") == true
local pollSeconds = tonumber(noctalia.getConfig("poll_interval_seconds")) or 6
local pollMs = math.max(pollSeconds, 3) * 1000

local currentState = "unknown"

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

local function applyState(state)
  currentState = state
  noctalia.state.set("restic_service_state", state)

  if state == "active" or state == "activating" then
    renderWidget("loader", "primary", noctalia.tr("widget.text_running"), noctalia.tr("widget.running_tooltip"))
  elseif state == "failed" then
    renderWidget("alert-triangle", "error", noctalia.tr("widget.text_failed"), noctalia.tr("widget.failed_tooltip"))
  else
    renderWidget("cloud-check", "on_surface", "", noctalia.tr("widget.idle_tooltip"))
  end
end

function checkStatus()
  noctalia.runAsync("systemctl --user is-active " .. serviceName, function(_code, stdout, _stderr)
    local state = (stdout or ""):gsub("%s+", "")
    applyState(state)
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
renderWidget("cloud", "on_surface", "", noctalia.tr("widget.idle_tooltip"))
checkStatus()
