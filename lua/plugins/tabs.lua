-- ============================================
-- TABS: name + color (Tabby style)
-- ============================================
-- F2 renames the tab and then offers 12 colors; Shift+F2 changes only the color.
-- The color is kept in wezterm.GLOBAL (survives config reloads) and is saved
-- in the session by session.lua.
local wezterm = require 'wezterm'
local act = wezterm.action
local c = require 'core.colors'
local notify = require 'plugins.notify'
local spinner = require 'plugins.spinner'

local M = {}

M.colors = {
  { name = 'Red',          hex = '#ea6962' },
  { name = 'Orange',       hex = '#e78a4e' },
  { name = 'Yellow',       hex = '#d8a657' },
  { name = 'Green',        hex = '#a9b665' },
  { name = 'Dark green',   hex = '#6f8352' },
  { name = 'Aqua',         hex = '#89b482' },
  { name = 'Blue',         hex = '#7daea3' },
  { name = 'Dark blue',    hex = '#45707a' },
  { name = 'Purple',       hex = '#b16286' },
  { name = 'Pink',         hex = '#d3869b' },
  { name = 'Brown',        hex = '#a0785a' },
  { name = 'Gray',         hex = '#928374' },
}

-- Default tab bar colors (same as the theme in core/appearance.lua)
local BAR = {
  active_bg = c.green, active_fg = c.bg0,
  inactive_bg = c.bg1, inactive_fg = c.fg_dim,
  hover_bg = c.bg3, hover_fg = c.fg0,
}

-- Fixed tab width in columns (~ the size of Tabby's tabs).
-- Shrinks automatically when there are too many tabs to fit the bar.
M.tab_width = 24

local function key(tab_id) return 'tabcolor_' .. tostring(tab_id) end

function M.get_color(tab_id)
  local c = wezterm.GLOBAL[key(tab_id)]
  if c == nil or c == '' then return nil end
  return c
end

function M.set_color(tab_id, hex)
  wezterm.GLOBAL[key(tab_id)] = hex or ''
end

-- ---------- Tab rendering ----------

local function tab_title(tab)
  local title = tab.tab_title
  if not title or title == '' then title = tab.active_pane.title end
  return title
end

function M.format_tab_title(tab, _, _, _, hover, max_width)
  local color = M.get_color(tab.tab_id)
  local width = math.min(M.tab_width, max_width)
  local inner = math.max(1, width - 3) -- left + right padding + color stripe
  local text = (tab.tab_index + 1) .. ': ' .. tab_title(tab)
  -- bell rung while the tab was in the background (plugins/notify.lua)
  if tab.is_active then
    notify.clear_bell(tab.tab_id)
  elseif notify.has_bell(tab.tab_id) then
    text = '󰂞 ' .. text
  end
  -- something running in the tab (plugins/spinner.lua)
  local spin = spinner.icon(tab.tab_id)
  if spin then text = spin .. ' ' .. text end
  text = wezterm.truncate_right(text, inner)
  text = text .. string.rep(' ', inner - wezterm.column_width(text))

  if tab.is_active then
    return {
      { Background = { Color = color or BAR.active_bg } },
      { Foreground = { Color = BAR.active_fg } },
      { Attribute = { Intensity = 'Bold' } },
      { Text = ' ' .. text .. '  ' },
    }
  end

  local bg = hover and BAR.hover_bg or BAR.inactive_bg
  if color then
    -- colored inactive tab: stripe + text in the chosen color
    return {
      { Background = { Color = bg } },
      { Foreground = { Color = color } },
      { Text = '▌' .. text .. '  ' },
    }
  end
  return {
    { Background = { Color = bg } },
    { Foreground = { Color = hover and BAR.hover_fg or BAR.inactive_fg } },
    { Text = ' ' .. text .. '  ' },
  }
end

-- ---------- Color picker ----------

local function color_picker(window, pane, tab)
  local current = M.get_color(tab:tab_id())
  local choices = {
    { id = 'none', label = '     No color' .. (current == nil and '  ✓' or '') },
  }
  for _, c in ipairs(M.colors) do
    table.insert(choices, {
      id = c.hex,
      label = wezterm.format {
        { Foreground = { Color = c.hex } },
        { Text = '████ ' },
        'ResetAttributes',
        { Text = c.name .. (current == c.hex and '  ✓' or '') },
      },
    })
  end

  window:perform_action(act.InputSelector {
    title = 'Tab color',
    description = 'Key/↑↓ + Enter selects · Esc keeps the current color',
    choices = choices,
    action = wezterm.action_callback(function(_, _, id)
      if not id then return end
      M.set_color(tab:tab_id(), id ~= 'none' and id or nil)
    end),
  }, pane)
end

-- F2: rename and pick a color
function M.rename_action()
  return wezterm.action_callback(function(window, pane)
    local tab = window:active_tab()
    window:perform_action(act.PromptInputLine {
      description = 'Tab name (empty = automatic) · Esc cancels',
      initial_value = tab:get_title(),
      action = wezterm.action_callback(function(w, p, line)
        if line == nil then return end
        tab:set_title(line)
        color_picker(w, p, tab)
      end),
    }, pane)
  end)
end

-- Shift+F2: color only
function M.color_action()
  return wezterm.action_callback(function(window, pane)
    color_picker(window, pane, window:active_tab())
  end)
end

function M.apply(config)
  wezterm.on('format-tab-title', M.format_tab_title)
  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'F2', mods = 'NONE', action = M.rename_action() })
  table.insert(config.keys, { key = 'F2', mods = 'SHIFT', action = M.color_action() })
end

return M
