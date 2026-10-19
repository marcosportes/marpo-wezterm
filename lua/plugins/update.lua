-- ============================================
-- UPDATE CHECK
-- ============================================
-- Once each time WezTerm starts, compares the commit installed by setup.sh
-- with GitHub. If origin is ahead, asks with the same prompt as closing a tab.
-- Yes runs setup.sh (pull + sync). Offline or up to date stays quiet.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

local STATE_DIR = (os.getenv('XDG_DATA_HOME') or (os.getenv('HOME') .. '/.local/share')) .. '/wezterm'
local STAMP = STATE_DIR .. '/install'
local RESULT = STATE_DIR .. '/update-remote'
local FINISHED = STATE_DIR .. '/update-finished'
local CHECK_WAIT = 20 -- seconds for the background fetch
local UPDATE_WAIT = 150 -- seconds for setup.sh

local function read_line(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local line = (f:read('*l') or ''):gsub('%s+$', '')
  f:close()
  if line == '' then return nil end
  return line
end

-- First line is the status. The rest are pending commit subjects.
local function read_result(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local status = (f:read('*l') or ''):gsub('%s+$', '')
  local notes = {}
  for line in f:lines() do
    if line ~= '' then table.insert(notes, line) end
  end
  f:close()
  if status == '' then return nil end
  return status, notes
end

local function describe(notes)
  if #notes == 0 then
    return 'A newer version is on GitHub. Update now?'
  end
  local lines = { 'A newer version is on GitHub:' }
  local limit = 8
  for i = 1, math.min(#notes, limit) do
    table.insert(lines, '• ' .. notes[i])
  end
  if #notes > limit then
    table.insert(lines, '• … and ' .. (#notes - limit) .. ' more')
  end
  table.insert(lines, 'Update now?')
  return table.concat(lines, '\n')
end

local function read_stamp()
  local f = io.open(STAMP, 'r')
  if not f then return nil end
  local stamp = {}
  for line in f:lines() do
    local key, value = line:match('^(%w+)=(.*)$')
    if key then stamp[key] = value end
  end
  f:close()
  if stamp.source and stamp.source ~= '' and stamp.commit and stamp.commit ~= '' then
    return stamp
  end
  return nil
end

local function start_check(stamp)
  os.remove(RESULT)
  wezterm.GLOBAL.update_source = stamp.source
  wezterm.GLOBAL.update_commit = stamp.commit
  wezterm.GLOBAL.update_started = os.time()
  wezterm.GLOBAL.update_checking = true
  wezterm.background_child_process {
    'sh',
    wezterm.config_dir .. '/scripts/check-update.sh',
    stamp.source,
    stamp.commit,
    RESULT,
  }
end

local function run_update(win, remote)
  os.remove(FINISHED)
  wezterm.GLOBAL.update_waiting = remote
  wezterm.GLOBAL.update_wait_since = os.time()
  wezterm.background_child_process {
    'sh',
    wezterm.config_dir .. '/scripts/apply-update.sh',
    wezterm.GLOBAL.update_source,
    FINISHED,
  }
  win:toast_notification('WezTerm', 'Updating…', nil, 4000)
end

local function ask(window, pane, remote, notes)
  window:perform_action(act.InputSelector {
    title = 'Update available',
    description = describe(notes),
    choices = {
      { id = 'no', label = '❌ No, not now' },
      { id = 'yes', label = '✅ Yes, update' },
    },
    action = wezterm.action_callback(function(win, _, id)
      if id ~= 'yes' then return end
      run_update(win, remote)
    end),
  }, pane)
end

function M.apply(config)
  wezterm.on('update-status', function(window, pane)
    if not wezterm.GLOBAL.session_restored then return end

    if wezterm.GLOBAL.update_waiting then
      local done = read_line(FINISHED)
      if not done then
        if os.time() - (wezterm.GLOBAL.update_wait_since or 0) > UPDATE_WAIT then
          wezterm.GLOBAL.update_waiting = nil
          window:toast_notification('WezTerm', 'Update failed. Run ./setup.sh in the repo.', nil, 4000)
        end
        return
      end
      local want = wezterm.GLOBAL.update_waiting
      wezterm.GLOBAL.update_waiting = nil
      os.remove(FINISHED)
      if done == want then
        window:toast_notification('WezTerm', 'Updated', nil, 3000)
      else
        window:toast_notification('WezTerm', 'Update failed. Run ./setup.sh in the repo.', nil, 4000)
      end
      return
    end

    if wezterm.GLOBAL.update_prompted then return end

    if not wezterm.GLOBAL.update_checking then
      local stamp = read_stamp()
      if not stamp then
        wezterm.GLOBAL.update_prompted = true
        return
      end
      start_check(stamp)
      return
    end

    local remote, notes = read_result(RESULT)
    if not remote then
      if os.time() - (wezterm.GLOBAL.update_started or 0) > CHECK_WAIT then
        wezterm.GLOBAL.update_prompted = true
      end
      return
    end

    if remote == 'fail' or remote == 'same' or remote == wezterm.GLOBAL.update_commit then
      wezterm.GLOBAL.update_prompted = true
      os.remove(RESULT)
      return
    end
    pane = pane or window:active_pane()
    if not pane then return end
    wezterm.GLOBAL.update_prompted = true
    os.remove(RESULT)
    ask(window, pane, remote, notes or {})
  end)
end

return M
