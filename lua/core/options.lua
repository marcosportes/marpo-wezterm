-- ============================================
-- OPTIONS: rendering, performance and general behavior
-- ============================================
local wezterm = require 'wezterm'

-- Native Wayland (true) or XWayland (false). Even when true, desktops whose
-- Wayland compositor draws no title bars for apps (no server-side decorations)
-- run through XWayland, so the system title bar and its buttons stay
local PREFER_WAYLAND = false
local NO_SSD_DESKTOPS = { 'GNOME', 'Pantheon' }

local function desktop_draws_title_bar()
  local desktop = (os.getenv('XDG_CURRENT_DESKTOP') or ''):upper()
  for _, name in ipairs(NO_SSD_DESKTOPS) do
    if desktop:find(name:upper(), 1, true) then return false end
  end
  return true
end

local M = {}

function M.apply(config)
  -- ===== SLOW MOUSE FIX =====
  config.front_end = 'OpenGL'
  config.max_fps = 144
  config.animation_fps = 30
  config.cursor_blink_rate = 0
  config.enable_wayland = PREFER_WAYLAND and desktop_draws_title_bar()

  -- ===== PERFORMANCE =====
  config.scrollback_lines = 10000
  config.enable_kitty_graphics = false
  config.enable_kitty_keyboard = true

  -- ===== HYPERLINKS AND URLs =====
  config.hyperlink_rules = wezterm.default_hyperlink_rules()

  -- ===== GENERAL BEHAVIOR =====
  config.automatically_reload_config = true
  config.check_for_updates = false
  config.exit_behavior = 'Close'
  config.window_close_confirmation = 'NeverPrompt'

  -- Disable the annoying bell
  config.audible_bell = 'Disabled'
  config.visual_bell = {
    fade_in_duration_ms = 75,
    fade_out_duration_ms = 75,
    target = 'CursorColor',
  }
end

return M
