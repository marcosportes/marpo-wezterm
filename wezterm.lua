-- ============================================
-- WEZTERM ENTRY POINT
-- ============================================
-- Layout (Neovim style):
--   lua/core/     base settings (options, appearance, fonts, keymaps, mouse, launch menu)
--   lua/plugins/  features (ssh picker, colored tabs, session restore)
--   lua/custom/   personal tweaks (preferences.lua: font, size, weight)
--   scripts/      helper shell scripts
local wezterm = require 'wezterm'

package.path = table.concat({
  wezterm.config_dir .. '/lua/?.lua',
  wezterm.config_dir .. '/lua/?/init.lua',
  package.path,
}, ';')

return require('core').setup()
