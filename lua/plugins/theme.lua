-- ============================================
-- THEME PICKER (Shift+T)
-- ============================================
local wezterm = require 'wezterm'
local act = wezterm.action
local themes = require 'core.themes'

local M = {}

local function repaint(window)
  local on = not wezterm.GLOBAL.theme_nudge
  wezterm.GLOBAL.theme_nudge = on
  window:set_right_status(on and wezterm.format { 'ResetAttributes' } or '')
end

local function apply_all()
  for _, win in ipairs(wezterm.mux.all_windows()) do
    local gui = win:gui_window()
    if gui then
      themes.sync(gui)
      repaint(gui)
    end
  end
end

function M.picker_action()
  return wezterm.action_callback(function(window, pane)
    local current = themes.current()
    local choices = {}
    for _, theme in ipairs(themes.list) do
      table.insert(choices, {
        id = theme.id,
        label = wezterm.format {
          { Foreground = { Color = theme.bar.active_bg } },
          { Text = '████ ' },
          'ResetAttributes',
          { Text = theme.label .. (theme.id == current and '  ✓' or '') },
        },
      })
    end

    window:perform_action(act.InputSelector {
      title = 'Theme',
      description = 'Type to filter · Enter applies · Esc cancels',
      fuzzy = true,
      fuzzy_description = '🔎 ',
      choices = choices,
      action = wezterm.action_callback(function(win, _, id)
        if not id or not themes.get(id) then return end
        themes.save(id)
        apply_all()
        win:toast_notification('WezTerm', 'Theme: ' .. themes.get(id).label, nil, 2000)
      end),
    }, pane)
  end)
end

function M.apply(config)
  -- A window opened after a switch, before the next reload, still has the
  -- scheme from the last load. update-status catches it.
  wezterm.on('update-status', function(window)
    if themes.sync(window) then repaint(window) end
  end)

  config.keys = config.keys or {}
  table.insert(config.keys, { key = 't', mods = 'SHIFT', action = M.picker_action() })
end

return M
