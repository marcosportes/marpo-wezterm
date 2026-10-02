-- ============================================
-- MOUSE
-- ============================================
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

function M.apply(config)
  config.mouse_bindings = {
    -- Right click to paste
    {
      event = { Down = { streak = 1, button = 'Right' } },
      mods = 'NONE',
      action = act.PasteFrom 'Clipboard',
    },
    -- Ctrl+Click to open URLs
    {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'CTRL',
      action = act.OpenLinkAtMouseCursor,
    },
  }
end

return M
