-- ============================================
-- HELP (Alt+H): every command, one line each
-- ============================================
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

local KEY_WIDTH = 18

-- key, what it does
local commands = {
  { 'Alt+H', 'Show this list' },
  { 'Ctrl+Shift+T', 'Change the color theme' },
  { 'Ctrl+Shift+F', 'Change the font and its size' },
  { 'Alt+X', 'SSH host picker' },
  { 'Alt+L', 'Launch menu' },
  { 'Alt+T', 'New tab' },
  { 'Alt+W', 'Close tab (asks first)' },
  { 'Alt+R', 'Reconnect the SSH pane' },
  { 'Alt+I', 'Copy IP, IP:port or ssh command' },
  { 'F2', 'Rename the tab and pick a color' },
  { 'Shift+F2', 'Change only the tab color' },
  { 'Ctrl+Tab', 'Next tab' },
  { 'Ctrl+Shift+Tab', 'Previous tab' },
  { 'Alt+1 … 9', 'Go to tab N' },
  { 'Ctrl+Shift+←/→', 'Move the tab left or right' },
  { 'Alt+\\', 'Split side by side' },
  { 'Alt+-', 'Split top and bottom' },
  { 'Alt+Q', 'Close the pane' },
  { 'Alt+↑/↓', 'Switch pane' },
  { 'Alt+←/→', 'Switch pane, or the next tab' },
  { 'Alt+Shift+arrows', 'Resize the pane' },
  { 'Ctrl+Shift+C', 'Copy the selection' },
  { 'Ctrl+Shift+V', 'Paste' },
  { 'Alt+C', 'Copy the visible screen' },
  { 'Right click', 'Paste' },
  { 'Ctrl+Click', 'Open the link under the cursor' },
  { 'Alt+F', 'Search in the terminal' },
  { 'Alt+K', 'Clear the screen and scrollback' },
  { 'Ctrl++ / Ctrl+-', 'Increase or decrease the font' },
  { 'Ctrl+0', 'Reset the font size' },
  { 'F11', 'Toggle full screen' },
  { 'Ctrl+Shift+P', 'Command palette' },
  { 'Alt+S', 'Save the session now' },
  { 'Ctrl+Shift+R', 'Reload the config' },
  { 'Enter / s / q', 'SSH dropped: reconnect, local shell, close' },
  { 'On startup', 'Ask to update and list the pending commit messages' },
}

local function pad(text)
  local width = wezterm.column_width(text)
  if width >= KEY_WIDTH then return text end
  return text .. string.rep(' ', KEY_WIDTH - width)
end

function M.show_action()
  return wezterm.action_callback(function(window, pane)
    local choices = {}
    for i, cmd in ipairs(commands) do
      table.insert(choices, {
        id = tostring(i),
        label = pad(cmd[1]) .. cmd[2],
      })
    end

    window:perform_action(act.InputSelector {
      title = 'Shortcuts',
      description = 'Type to filter · Enter or Esc closes',
      fuzzy = true,
      fuzzy_description = '🔎 ',
      choices = choices,
      action = wezterm.action_callback(function() end),
    }, pane)
  end)
end

function M.apply(config)
  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'h', mods = 'ALT', action = M.show_action() })
end

return M
