-- ============================================
-- KEYMAPS
-- ============================================
-- Feature-specific keys live with their feature:
--   F2 / Shift+F2 -> plugins/tabs.lua · Alt+S -> plugins/session.lua
local wezterm = require 'wezterm'
local act = wezterm.action
local ssh = require 'plugins.ssh'

local M = {}

local function key(mods, k, action)
  return { key = k, mods = mods, action = action }
end

-- The pane in `dir`, ignoring the SSH footer (plugins/ssh_info.lua)
local function neighbor(pane, dir)
  local tab = pane:tab()
  local p = tab and tab:get_pane_direction(dir)
  if p and not ssh.is_footer(p) then return p end
  return nil
end

-- Move to the pane in `dir`; when there is none, jump to the adjacent tab
local function pane_or_tab(dir, delta)
  return wezterm.action_callback(function(window, pane)
    if neighbor(pane, dir) then
      window:perform_action(act.ActivatePaneDirection(dir), pane)
    else
      window:perform_action(act.ActivateTabRelative(delta), pane)
    end
  end)
end

-- Move to the pane in `dir`, never into the SSH footer
local function pane_dir(dir)
  return wezterm.action_callback(function(window, pane)
    if neighbor(pane, dir) then
      window:perform_action(act.ActivatePaneDirection(dir), pane)
    end
  end)
end

-- Always asks before closing the tab (the built-in `confirm` skips the
-- prompt when only a shell is running)
local function close_tab_confirm()
  return wezterm.action_callback(function(window, pane)
    window:perform_action(act.InputSelector {
      title = 'Close this tab?',
      choices = {
        { id = 'no', label = '❌ No, keep it open' },
        { id = 'yes', label = '✅ Yes, close the tab' },
      },
      action = wezterm.action_callback(function(win, p, id)
        if id == 'yes' then
          win:perform_action(act.CloseCurrentTab { confirm = false }, p)
        end
      end),
    }, pane)
  end)
end

-- Copies the visible screen of the active pane (whatever is drawn there, even
-- vim on a server). The tab bar and the SSH footer are not part of the pane.
local function copy_screen()
  return wezterm.action_callback(function(window, pane)
    local text = pane:get_lines_as_text(pane:get_dimensions().viewport_rows)
    text = text:gsub('[ \t]+\n', '\n'):gsub('%s+$', '')
    window:copy_to_clipboard(text, 'Clipboard')
    local _, lines = text:gsub('\n', '')
    window:toast_notification('WezTerm', 'Screen copied (' .. (lines + 1) .. ' lines)', nil, 2000)
  end)
end

function M.apply(config)
  config.keys = {
    -- ===== CONNECTIONS (searchable picker: SSH + local shells) =====
    key('ALT', 'x', ssh.picker_action()),
    key('ALT', 'r', ssh.reconnect_action()),
    key('ALT', 'l', act.ShowLauncherArgs { flags = 'FUZZY|LAUNCH_MENU_ITEMS|DOMAINS' }),

    -- ===== FULL SCREEN =====
    key('NONE', 'F11', act.ToggleFullScreen),

    -- ===== TABS =====
    key('ALT', 't', act.SpawnTab 'CurrentPaneDomain'),
    key('ALT', 'w', close_tab_confirm()),
    key('CTRL', 'Tab', act.ActivateTabRelative(1)),
    key('CTRL|SHIFT', 'Tab', act.ActivateTabRelative(-1)),

    -- ===== MOVE TAB (hold Ctrl+Shift and tap the arrows) =====
    key('CTRL|SHIFT', 'LeftArrow', act.MoveTabRelative(-1)),
    key('CTRL|SHIFT', 'RightArrow', act.MoveTabRelative(1)),

    -- ===== SPLITS/PANES =====
    key('ALT', '\\', ssh.split_action(act.SplitHorizontal)),
    key('ALT', '-', ssh.split_action(act.SplitVertical)),
    key('ALT', 'q', act.CloseCurrentPane { confirm = true }),

    -- ===== PANE / TAB NAVIGATION (Left/Right fall through to tabs) =====
    key('ALT', 'LeftArrow', pane_or_tab('Left', -1)),
    key('ALT', 'RightArrow', pane_or_tab('Right', 1)),
    key('ALT', 'UpArrow', pane_dir('Up')),
    key('ALT', 'DownArrow', pane_dir('Down')),

    -- ===== RESIZE PANES =====
    key('ALT|SHIFT', 'LeftArrow', act.AdjustPaneSize { 'Left', 5 }),
    key('ALT|SHIFT', 'RightArrow', act.AdjustPaneSize { 'Right', 5 }),
    key('ALT|SHIFT', 'UpArrow', act.AdjustPaneSize { 'Up', 5 }),
    key('ALT|SHIFT', 'DownArrow', act.AdjustPaneSize { 'Down', 5 }),

    -- ===== FONT ZOOM =====
    key('CTRL', '+', act.IncreaseFontSize),
    key('CTRL', '-', act.DecreaseFontSize),
    key('CTRL', '0', act.ResetFontSize),

    -- ===== COPY/PASTE =====
    key('CTRL|SHIFT', 'c', act.CopyTo 'Clipboard'),
    key('CTRL|SHIFT', 'v', act.PasteFrom 'Clipboard'),
    key('ALT', 'c', copy_screen()),

    -- ===== SEARCH =====
    key('CTRL|SHIFT', 'f', act.Search 'CurrentSelectionOrEmptyString'),

    -- ===== CLEAR SCREEN =====
    key('ALT', 'k', act.ClearScrollback 'ScrollbackAndViewport'),

    -- ===== RELOAD CONFIG =====
    key('CTRL|SHIFT', 'r', act.ReloadConfiguration),
  }

  -- ===== NUMBERED TAB SHORTCUTS (Alt+1 to Alt+9) =====
  for i = 1, 9 do
    table.insert(config.keys, key('ALT', tostring(i), act.ActivateTab(i - 1)))
  end
end

return M
