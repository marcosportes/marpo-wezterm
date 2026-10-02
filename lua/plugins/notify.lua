-- ============================================
-- NOTIFY: desktop notification when a tab you are not looking at rings the bell
-- ============================================
-- Rings with `long-command; printf '\a'` (or a shell hook that does it after
-- slow commands). The tab also gets a bell icon until it is selected; the
-- icon is drawn by plugins/tabs.lua. plugins/spinner.lua also calls M.alert
-- when a running command stops to wait for input (a [Y/n] prompt).
local wezterm = require 'wezterm'

local M = {}

local COOLDOWN = 5 -- seconds between notifications of the same pane

local function key(tab_id) return 'tabbell_' .. tostring(tab_id) end

function M.has_bell(tab_id)
  return wezterm.GLOBAL[key(tab_id)] == true
end

function M.clear_bell(tab_id)
  if M.has_bell(tab_id) then wezterm.GLOBAL[key(tab_id)] = false end
end

local last = {} -- pane id -> time of its last notification

-- Marks the tab and shows a desktop notification, unless the tab is on screen.
-- `force` skips the per-pane cooldown (used for "waiting for input").
function M.alert(window, pane, icon, force)
  local ok, tab = pcall(function() return pane:tab() end)
  if not ok or not tab then return end
  local active = window:active_tab()
  local visible = window:is_focused() and active and active:tab_id() == tab:tab_id()
  if visible then return end

  if not (active and active:tab_id() == tab:tab_id()) then
    wezterm.GLOBAL[key(tab:tab_id())] = true
  end

  local now = os.time()
  if not force and last[pane:pane_id()] and now - last[pane:pane_id()] < COOLDOWN then return end
  last[pane:pane_id()] = now

  local index = '?'
  for _, t in ipairs(window:mux_window():tabs_with_info()) do
    if t.tab:tab_id() == tab:tab_id() then index = t.index + 1 end
  end
  local title = tab:get_title()
  if title == '' then title = pane:get_title() end
  window:toast_notification('WezTerm', icon .. ' Tab ' .. index .. ': ' .. title, nil, 4000)
end

local function on_bell(window, pane)
  M.alert(window, pane, '󰂞')
end

function M.apply(config)
  wezterm.on('bell', on_bell)
end

return M
