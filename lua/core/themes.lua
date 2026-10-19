-- ============================================
-- THEMES
-- ============================================
-- Gruvbox is the default. The choice is saved in
-- ~/.local/share/wezterm/theme and applied live by plugins/theme.lua.
-- Tab bar colors are shared with plugins/tabs.lua.
local wezterm = require 'wezterm'
local gruv = require 'core.colors'

local M = {}

M.default = 'Gruvbox'

local STATE_DIR = (os.getenv('XDG_DATA_HOME') or (os.getenv('HOME') .. '/.local/share')) .. '/wezterm'
local THEME_FILE = STATE_DIR .. '/theme'

local function tab_bar(bar)
  return {
    background = bar.bar_bg,
    active_tab = { bg_color = bar.active_bg, fg_color = bar.active_fg, intensity = 'Bold' },
    inactive_tab = { bg_color = bar.inactive_bg, fg_color = bar.inactive_fg },
    inactive_tab_hover = { bg_color = bar.hover_bg, fg_color = bar.hover_fg },
    new_tab = { bg_color = bar.bar_bg, fg_color = bar.inactive_fg },
    new_tab_hover = { bg_color = bar.hover_bg, fg_color = bar.hover_fg },
  }
end

-- Two levels cover ansi/brights and the tab_bar cells.
local function clone(src)
  local copy = {}
  for k, v in pairs(src) do
    if type(v) == 'table' then
      local inner = {}
      for ik, iv in pairs(v) do
        if type(iv) == 'table' then
          local cell = {}
          for ck, cv in pairs(iv) do cell[ck] = cv end
          inner[ik] = cell
        else
          inner[ik] = iv
        end
      end
      copy[k] = inner
    else
      copy[k] = v
    end
  end
  return copy
end

local function from_builtin(name, bar, tune)
  return function()
    local src = wezterm.color.get_builtin_schemes()[name]
    local scheme
    if src then
      scheme = clone(src)
    else
      wezterm.log_error('themes: missing builtin scheme ' .. name)
      scheme = { background = bar.inactive_bg, foreground = bar.hover_fg }
    end
    scheme.tab_bar = tab_bar(bar)
    if tune then tune(scheme) end
    return scheme
  end
end

local function entry(id, bar, builtin, tune)
  return {
    id = id,
    label = id,
    bar = bar,
    build = from_builtin(builtin, bar, tune),
  }
end

local gruv_bar = {
  bar_bg = gruv.bg_dim,
  active_bg = gruv.green, active_fg = gruv.bg0,
  inactive_bg = gruv.bg1, inactive_fg = gruv.fg_dim,
  hover_bg = gruv.bg3, hover_fg = gruv.fg0,
}

M.list = {
  {
    id = 'Gruvbox',
    label = 'Gruvbox',
    bar = gruv_bar,
    build = function()
      local scheme = clone(wezterm.color.get_builtin_schemes()['Gruvbox Material (Gogh)'])
      -- The original bright black (#3c3836) disappears into the background.
      scheme.brights[1] = gruv.gray
      scheme.selection_bg = gruv.bg3
      scheme.selection_fg = gruv.fg0
      scheme.tab_bar = tab_bar(gruv_bar)
      return scheme
    end,
  },
  entry('Dracula', {
    bar_bg = '#21222c',
    active_bg = '#bd93f9', active_fg = '#282a36',
    inactive_bg = '#282a36', inactive_fg = '#6272a4',
    hover_bg = '#44475a', hover_fg = '#f8f8f2',
  }, 'Dracula (Official)', function(scheme)
    -- The builtin selection foreground is fully transparent.
    scheme.selection_bg = '#44475a'
    scheme.selection_fg = '#f8f8f2'
  end),
  entry('Nord', {
    bar_bg = '#2e3440',
    active_bg = '#88c0d0', active_fg = '#2e3440',
    inactive_bg = '#3b4252', inactive_fg = '#d8dee9',
    hover_bg = '#434c5e', hover_fg = '#eceff4',
  }, 'Nord (Gogh)', function(scheme)
    scheme.selection_bg = '#434c5e'
    scheme.selection_fg = '#eceff4'
  end),
  -- Pro palette, under this name on purpose.
  entry('Wonokai', {
    bar_bg = '#2d2a2e',
    active_bg = '#a9dc76', active_fg = '#363537',
      inactive_bg = '#363537', inactive_fg = '#c1c0c0',
    hover_bg = '#5b595c', hover_fg = '#fdf9f3',
  }, 'Monokai Pro (Gogh)', function(scheme)
    scheme.selection_bg = '#5b595c'
    scheme.selection_fg = '#fdf9f3'
  end),
  entry('One Dark', {
    bar_bg = '#1e2127',
    active_bg = '#61afef', active_fg = '#1e2127',
    inactive_bg = '#282c34', inactive_fg = '#9da5b4',
    hover_bg = '#3e4451', hover_fg = '#abb2bf',
  }, 'One Dark (Gogh)', function(scheme)
    -- The Gogh port uses the comment gray as the foreground.
    scheme.foreground = '#abb2bf'
    scheme.cursor_bg = '#abb2bf'
    scheme.cursor_border = '#abb2bf'
    scheme.cursor_fg = '#1e2127'
    scheme.selection_bg = '#3e4451'
    scheme.selection_fg = '#abb2bf'
  end),
  entry('Ayu', {
    bar_bg = '#0a0e14',
    active_bg = '#e6b450', active_fg = '#0a0e14',
    inactive_bg = '#11151c', inactive_fg = '#b3b1ad',
    hover_bg = '#1f2430', hover_fg = '#e6e1cf',
  }, 'Ayu Dark (Gogh)', function(scheme)
    scheme.selection_bg = '#253340'
    scheme.selection_fg = '#b3b1ad'
  end),
  entry('Everforest', {
    bar_bg = '#232a2e',
    active_bg = '#a7c080', active_fg = '#2d353b',
    inactive_bg = '#343f44', inactive_fg = '#859289',
    hover_bg = '#475258', hover_fg = '#d3c6aa',
  }, 'Everforest Dark Medium (Gogh)', function(scheme)
    scheme.selection_bg = '#573e4a'
    scheme.selection_fg = '#d3c6aa'
  end),
}

local by_id = {}
for _, theme in ipairs(M.list) do by_id[theme.id] = theme end

function M.get(id)
  return by_id[id]
end

function M.read()
  local f = io.open(THEME_FILE, 'r')
  if not f then return nil end
  local id = (f:read('*l') or ''):gsub('%s+$', '')
  f:close()
  if by_id[id] then return id end
  return nil
end

function M.current()
  local id = wezterm.GLOBAL.theme
  if id and by_id[id] then return id end
  return M.read() or M.default
end

function M.bar()
  return (by_id[M.current()] or by_id[M.default]).bar
end

function M.save(id)
  if not by_id[id] then return end
  wezterm.GLOBAL.theme = id
  os.execute('mkdir -p "' .. STATE_DIR .. '"')
  local tmp = THEME_FILE .. '.tmp'
  local f = io.open(tmp, 'w')
  if not f then return end
  f:write(id .. '\n')
  f:close()
  os.rename(tmp, THEME_FILE)
end

-- Registers every scheme and selects the saved one (or Gruvbox).
function M.apply_config(config)
  local id = M.read() or M.default
  wezterm.GLOBAL.theme = id
  local schemes = {}
  for _, theme in ipairs(M.list) do
    schemes[theme.id] = theme.build()
  end
  config.color_schemes = schemes
  config.color_scheme = id
end

-- True when the window's scheme actually changed.
function M.sync(window)
  local id = M.current()
  local overrides = window:get_config_overrides() or {}
  if overrides.color_scheme == id then return false end
  -- Base config already has this scheme (startup, or the reload after a save).
  if not overrides.color_scheme then
    local ok, cfg = pcall(function() return window:effective_config() end)
    if ok and cfg and cfg.color_scheme == id then return false end
  end
  overrides.color_scheme = id
  window:set_config_overrides(overrides)
  return true
end

return M
