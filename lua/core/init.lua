-- ============================================
-- CORE: builds the config and applies every module in order
-- ============================================
local wezterm = require 'wezterm'

local M = {}

-- Base settings, applied first
local core_modules = {
  'core.options',
  'core.appearance',
  'core.fonts',
  'core.launch_menu',
  'core.keymaps',
  'core.mouse',
}

-- Features; they add their own events and key bindings on top of core
local plugins = {
  'plugins.session',
  'plugins.tabs',
  'plugins.ssh_info',
  'plugins.notify',
  'plugins.spinner',
}

function M.setup()
  local config = wezterm.config_builder and wezterm.config_builder() or {}

  for _, name in ipairs(core_modules) do
    require(name).apply(config)
  end
  for _, name in ipairs(plugins) do
    require(name).apply(config)
  end

  return config
end

return M
