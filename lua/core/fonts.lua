-- ============================================
-- FONTS: family, size and weight come from custom/preferences.lua
-- ============================================
local wezterm = require 'wezterm'
local prefs = require 'custom.preferences'

local M = {}

local function font(weight, italic)
  return wezterm.font_with_fallback({
    { family = prefs.font, weight = weight, italic = italic or false },
    { family = 'Hack Nerd Font Mono', weight = weight, italic = italic or false },
  })
end

function M.apply(config)
  wezterm.add_to_config_reload_watch_list(wezterm.config_dir .. '/lua/custom/preferences.lua')

  config.font = font(prefs.weight_normal)
  config.font_rules = {
    { intensity = 'Bold', italic = false, font = font(prefs.weight_bold) },
    { intensity = 'Bold', italic = true, font = font(prefs.weight_bold, true) },
    { intensity = 'Normal', italic = true, font = font(prefs.weight_normal, true) },
    { intensity = 'Half', italic = false, font = font(400) },
    { intensity = 'Half', italic = true, font = font(400, true) },
  }
  config.font_size = prefs.size
  config.line_height = prefs.line_height
  config.bold_brightens_ansi_colors = true
end

return M
