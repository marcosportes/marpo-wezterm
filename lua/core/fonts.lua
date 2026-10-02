-- ============================================
-- FONTS: family, size and weight come from custom/preferences.lua
-- ============================================
local wezterm = require 'wezterm'
local prefs = require 'custom.preferences'

local M = {}

-- Hack only ships 400 and 700; asking for another weight works on recent
-- WezTerm (closest match) but older builds show an error, so snap it here.
local function snap(family, weight)
  if family:find('Hack') then return weight < 550 and 400 or 700 end
  return weight
end

local function font(weight, italic)
  return wezterm.font_with_fallback({
    { family = prefs.font, weight = snap(prefs.font, weight), italic = italic or false },
    { family = 'Hack Nerd Font Mono', weight = snap('Hack', weight), italic = italic or false },
  })
end

function M.apply(config)
  wezterm.add_to_config_reload_watch_list(wezterm.config_dir .. '/lua/custom/preferences.lua')

  -- Bundled Hack Nerd Font Mono: works without installing it on the system
  config.font_dirs = { wezterm.config_dir .. '/fonts' }

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
