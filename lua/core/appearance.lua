-- ============================================
-- APPEARANCE: theme, window and tab bar
-- ============================================
local themes = require 'core.themes'

local M = {}

M.padding = { left = 0, right = 0, top = 10, bottom = 0 }

function M.apply(config)
  -- ===== THEME =====
  themes.apply_config(config)

  -- ===== WINDOW =====
  config.window_background_opacity = 1.0
  -- left, right and bottom = 0: the footer pane sits flush against the edges
  -- (plugins/ssh_info.lua moves the leftover pixels to the top padding)
  config.window_padding = M.padding
  -- TITLE: native title bar with minimize/maximize/close buttons (without it,
  -- X11 desktops like Cinnamon drop the whole title bar)
  config.window_decorations = 'TITLE | RESIZE'
  config.enable_scroll_bar = false

  -- ===== INACTIVE PANES =====
  -- dimmed so the focused split stands out (the SSH footer is always inactive,
  -- so it is dimmed too)
  config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.7 }

  -- ===== TAB BAR =====
  config.use_fancy_tab_bar = false
  config.hide_tab_bar_if_only_one_tab = false
  config.tab_bar_at_bottom = false
end

return M
