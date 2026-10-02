-- ============================================
-- APPEARANCE: theme, window and tab bar
-- ============================================
local wezterm = require 'wezterm'
local c = require 'core.colors'

local M = {}

local function gruvbox_material()
  local scheme = wezterm.color.get_builtin_schemes()['Gruvbox Material (Gogh)']
  -- The original "bright black" (#3c3836) disappears into the background; use the
  -- theme's gray instead so comments, zsh-autosuggestions etc. stay readable.
  scheme.brights[1] = c.gray
  scheme.selection_bg = c.bg3
  scheme.selection_fg = c.fg0
  scheme.tab_bar = {
    background = c.bg_dim,
    active_tab = { bg_color = c.green, fg_color = c.bg0, intensity = 'Bold' },
    inactive_tab = { bg_color = c.bg1, fg_color = c.fg_dim },
    inactive_tab_hover = { bg_color = c.bg3, fg_color = c.fg0 },
    new_tab = { bg_color = c.bg_dim, fg_color = c.fg_dim },
    new_tab_hover = { bg_color = c.bg3, fg_color = c.fg0 },
  }
  return scheme
end

function M.apply(config)
  -- ===== THEME =====
  config.color_schemes = { ['Gruvbox Material'] = gruvbox_material() }
  config.color_scheme = 'Gruvbox Material'

  -- ===== WINDOW =====
  config.window_background_opacity = 1.0
  config.window_padding = { left = 10, right = 10, top = 10, bottom = 10 }
  config.window_decorations = 'RESIZE'
  config.enable_scroll_bar = false

  -- ===== INACTIVE PANES =====
  -- dimmed so the focused split stands out (the SSH footer is always inactive,
  -- so it is dimmed too)
  config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.7 }

  -- ===== TAB BAR =====
  config.use_fancy_tab_bar = false
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_bar_at_bottom = false
  config.tab_max_width = 32
end

return M
