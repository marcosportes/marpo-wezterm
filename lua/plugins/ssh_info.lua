-- ============================================
-- SSH INFO: footer with host, IP, time logged in, traffic, latency/jitter,
-- packet loss and a warning when the server stops answering on SSH tabs;
-- on local tabs, host, user, CPU, RAM, disk and network of this machine
-- ============================================
-- Alt+I copies the IP, IP:port or the full ssh command to the clipboard.
local wezterm = require 'wezterm'
local act = wezterm.action
local ssh = require 'plugins.ssh'

local M = {}

-- ssh argv -> resolved target; `ssh -G` runs once per connection
local cache = {}

local function is_ip(s)
  return s:match('^%d+%.%d+%.%d+%.%d+$') or s:find(':', 1, true)
end

local function resolve_ip(hostname)
  if is_ip(hostname) then return hostname end
  local ok, out = wezterm.run_child_process { 'getent', 'ahostsv4', hostname }
  return ok and out:match('^(%S+)') or nil
end

-- Returns { alias, user, hostname, ip, port } for the pane, or nil if not on ssh
function M.target_of(pane)
  local argv = ssh.args_of(pane)
  if not argv then return nil end
  local k = table.concat(argv, '\0')
  if cache[k] == nil then
    local args = { 'ssh', '-G' }
    for i = 2, #argv do table.insert(args, argv[i]) end
    local ok, out = wezterm.run_child_process(args)
    if ok then
      local t = {
        alias = out:match('\nhost (%S+)') or out:match('^host (%S+)'),
        user = out:match('\nuser (%S+)'),
        hostname = out:match('\nhostname (%S+)'),
        port = out:match('\nport (%d+)'),
      }
      t.ip = t.hostname and resolve_ip(t.hostname) or t.hostname
      cache[k] = t
    else
      cache[k] = false
    end
  end
  return cache[k] or nil
end

-- ---------- Footer ----------
-- A 1-row pane at the bottom of each tab, drawn by scripts/ssh-footer.sh on
-- SSH tabs and by scripts/local-footer.sh (CPU, RAM, disk, network) otherwise.
-- WezTerm has a single tab bar row, so the footer has to be a pane. WezTerm
-- writes what to show into a state file; the script reads it every 2s.

M.script = wezterm.config_dir .. '/scripts/ssh-footer.sh'
M.local_script = wezterm.config_dir .. '/scripts/local-footer.sh'
local STATE_DIR = (os.getenv('XDG_RUNTIME_DIR') or '/tmp') .. '/wezterm-ssh-footer'
os.execute('mkdir -p "' .. STATE_DIR .. '"')

local written = {} -- state file -> last line written

local function write_state(path, line)
  if written[path] == line then return end
  local f = io.open(path, 'w')
  if not f then return end
  f:write(line .. '\n')
  f:close()
  written[path] = line
end

local LOCAL_HOST = wezterm.hostname()

-- Who is logged in on the remote end right now: `su`/`sudo -i` there changes
-- it, but ssh (and so `ssh -G`) only knows the login user. Taken from the
-- title most shells set ("user@host: ~", Debian/Ubuntu's default prompt), else
-- from WezTerm's shell integration (WEZTERM_USER), else nil. Both are ignored
-- when they name this machine: left over from the local shell before ssh.
local function remote_user(pane)
  local ok, title = pcall(function() return pane:get_title() end)
  if ok and title then
    local user, host = title:match('^([%w._-]+)@([%w._-]+)')
    if user and host ~= LOCAL_HOST then return user end
  end
  local ok2, vars = pcall(function() return pane:get_user_vars() end)
  if ok2 and vars and vars.WEZTERM_USER and vars.WEZTERM_USER ~= ''
    and vars.WEZTERM_HOST and vars.WEZTERM_HOST ~= LOCAL_HOST then
    return vars.WEZTERM_USER
  end
  return nil
end

local function foreground_pid(pane)
  local ok, info = pcall(function() return pane:get_foreground_process_info() end)
  return ok and info and info.pid or nil
end

local function sync_footer(window)
  local ok, tab = pcall(function() return window:active_tab() end)
  if not ok or not tab then return end

  local footer, panes = nil, {}
  for _, p in ipairs(tab:panes_with_info()) do
    if ssh.is_footer(p.pane) then footer = p else table.insert(panes, p) end
  end
  if #panes == 0 then
    -- only the footer is left: close it so the tab closes too
    if footer then
      window:perform_action(act.CloseCurrentPane { confirm = false }, footer.pane)
    end
    return
  end

  -- the footer never keeps the focus (e.g. after a mouse click)
  if footer and footer.is_active then
    window:perform_action(act.ActivatePaneDirection 'Up', footer.pane)
  end

  -- show the active pane when it is on ssh, otherwise the first ssh pane
  local target, t
  for _, p in ipairs(panes) do
    local pt = M.target_of(p.pane)
    if pt and (p.is_active or not target) then target, t = p.pane, pt end
  end

  -- each script exits by itself once the state file stops describing its
  -- mode; the next update then opens the other footer
  local path = STATE_DIR .. '/tab_' .. tostring(tab:tab_id())
  local script
  if target then
    local pid = foreground_pid(target)
    if not pid then return end
    write_state(path, table.concat({
      pid, t.alias or '?', remote_user(target) or t.user or '', t.ip or t.hostname or '?', t.port or '22',
    }, '\t'))
    script = M.script
  else
    -- no ssh in this tab: footer with this machine's stats
    target = panes[1].pane
    for _, p in ipairs(panes) do
      if p.is_active then target = p.pane end
    end
    -- the tty lets the script see who runs the foreground program (su, sudo -i)
    local ok_tty, tty = pcall(function() return target:get_tty_name() end)
    write_state(path, 'local\t' .. (ok_tty and tty or ''))
    script = M.local_script
  end

  if not footer then
    local new = target:split {
      direction = 'Bottom',
      top_level = true, -- full width, below every split of the tab
      size = 1,         -- rows
      args = { script, path },
    }
    ssh.mark_footer(new)
    target:activate()
  elseif footer.height > 1 then
    -- resizing the window spreads rows proportionally; give them back
    window:perform_action(act.AdjustPaneSize { 'Down', footer.height - 1 }, footer.pane)
  end
end

local function update_status(window)
  window:set_left_status('') -- clears what older versions drew there
  sync_footer(window)
end

-- Alt+I: copy IP / IP:port / ssh command of the active SSH pane
function M.copy_action()
  return wezterm.action_callback(function(window, pane)
    local t = M.target_of(pane)
    if not t then
      window:toast_notification('WezTerm', 'This pane is not connected over SSH', nil, 2000)
      return
    end
    local ip = t.ip or t.hostname
    local cmd = 'ssh ' .. (t.port ~= '22' and ('-p ' .. t.port .. ' ') or '')
      .. (t.user and (t.user .. '@') or '') .. ip
    window:perform_action(act.InputSelector {
      title = 'Copy SSH info',
      choices = {
        { id = ip, label = 'IP        ' .. ip },
        { id = ip .. ':' .. t.port, label = 'IP:port   ' .. ip .. ':' .. t.port },
        { id = cmd, label = 'Command   ' .. cmd },
      },
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        win:copy_to_clipboard(id, 'Clipboard')
        win:toast_notification('WezTerm', 'Copied: ' .. id, nil, 2000)
      end),
    }, pane)
  end)
end

function M.apply(config)
  wezterm.on('update-status', update_status)
  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'i', mods = 'ALT', action = M.copy_action() })
end

return M
