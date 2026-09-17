--!nonstrict
-- Restic status bar widget for Noctalia.
-- Monitors the user systemd service running restic backups.

local serviceName = noctalia.getConfig("service_name") or "restic-backup.service"
local showText = noctalia.getConfig("show_status_text") == true
local pollSeconds = tonumber(noctalia.getConfig("poll_interval_seconds")) or 6
local pollMs = math.max(pollSeconds, 3) * 1000

local function applyState(state)
  noctalia.state.set("restic_service_state", state)

  if state == "active" or state == "activating" then
    barWidget.setGlyph("loader")
    barWidget.setGlyphColor("primary")
    if showText then
      barWidget.setText(noctalia.tr("widget.text_running"))
    else
      barWidget.setText("")
    end
    barWidget.setTooltip(noctalia.tr("widget.running_tooltip"))
  elseif state == "failed" then
    barWidget.setGlyph("alert-triangle")
    barWidget.setGlyphColor("error")
    if showText then
      barWidget.setText(noctalia.tr("widget.text_failed"))
    else
      barWidget.setText("")
    end
    barWidget.setTooltip(noctalia.tr("widget.failed_tooltip"))
  else
    barWidget.setGlyph("cloud-check")
    barWidget.setGlyphColor("on_surface")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("widget.idle_tooltip"))
  end
end

local function checkStatus()
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
  noctalia.togglePanel("firomsa/restic:panel")
end

function onRightClick()
  noctalia.runAsync("systemctl --user start " .. serviceName, function(_code)
    checkStatus()
  end)
end

-- Initial render
barWidget.setGlyph("cloud")
barWidget.setGlyphColor("on_surface")
barWidget.setText("")
barWidget.setTooltip(noctalia.tr("widget.idle_tooltip"))

checkStatus()
