-- ============================================
-- LAUNCH MENU (Alt+L; the searchable picker is on Alt+X)
-- ============================================
local ssh = require 'plugins.ssh'

local M = {}

function M.apply(config)
  config.launch_menu = {}
  for _, s in ipairs(ssh.local_shells) do
    table.insert(config.launch_menu, { label = s.label, args = s.args })
  end
  for _, h in ipairs(ssh.hosts()) do
    table.insert(config.launch_menu, {
      label = '🖥️  SSH: ' .. h.name,
      args = ssh.spawn_args { 'ssh', h.name },
    })
  end
end

return M
