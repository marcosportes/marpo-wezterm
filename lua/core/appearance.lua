-- ============================================
-- APPEARANCE: theme, window and tab bar
-- ============================================
local themes = require 'core.themes'

local M = {}

function M.apply(config)
  -- ===== THEME =====
  themes.apply_config(config)

  -- ===== WINDOW =====
  config.window_background_opacity = 1.0
  config.window_padding = { left = 10, right = 10, top = 10, bottom = 10 }
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
