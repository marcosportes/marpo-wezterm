-- ============================================
-- SSH INFO: footer with host, IP, time logged in, traffic, latency/jitter,
-- packet loss and a warning when the server stops answering on SSH tabs;
-- on local tabs, host, user, CPU, RAM, disk and network of this machine
-- ============================================
-- Alt+I copies the IP, IP:port or the full ssh command to the clipboard.
local wezterm = require 'wezterm'
local act = wezterm.action
local ssh = require 'plugins.ssh'
local appearance = require 'core.appearance'

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

-- The window rarely fits a whole number of rows; WezTerm leaves the leftover
-- pixels below the last row, i.e. under the footer. Move them to the top
-- padding so the footer row touches the bottom edge.
local function flush_footer(window)
  local ok, top = pcall(function()
    local pad = appearance.padding
    local d = window:active_pane():get_dimensions()
    local cell = math.floor(d.pixel_height / d.viewport_rows)
    -- the retro tab bar is one terminal cell high
    local free = window:get_dimensions().pixel_height - pad.top - pad.bottom - cell
    return pad.top + free % cell
  end)
  if not ok or not top then return end
  local pad = {}
  for k, v in pairs(appearance.padding) do pad[k] = v end
  pad.top = top
  local overrides = window:get_config_overrides() or {}
  local cur = overrides.window_padding or appearance.padding
  local same = true
  for k, v in pairs(pad) do
    if cur[k] ~= v then same = false end
  end
  if same then return end
  overrides.window_padding = pad
  window:set_config_overrides(overrides)
end

-- The footer is always inactive, so WezTerm dims it, including the strip it
-- paints between the divider and the footer row. Hand the footer scripts the
-- terminal background undimmed (inverse of inactive_pane_hsb, which scales
-- linear RGB) so that strip ends up the color of the terminal above.
local function to_linear(c)
  c = c / 255
  return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

local function to_srgb(c)
  c = math.max(0, math.min(1, c))
  c = c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055
  return math.floor(c * 255 + 0.5)
end

local function sync_footer_bg(window)
  local ok, cfg = pcall(function() return window:effective_config() end)
  if not ok or not cfg then return end
  local bg = cfg.resolved_palette and cfg.resolved_palette.background
  if not bg then return end
  local hsb = cfg.inactive_pane_hsb or {}
  local s, v = hsb.saturation or 1, hsb.brightness or 1
  local ok2, r, g, b = pcall(function() return wezterm.color.parse(bg):srgba_u8() end)
  if not ok2 then return end
  local lin = { to_linear(r), to_linear(g), to_linear(b) }
  local max = math.max(lin[1], lin[2], lin[3])
  local out = {}
  for i, c in ipairs(lin) do
    -- undo the saturation scale (distance from the max channel), then brightness
    if s > 0 then c = max - (max - c) / s end
    out[i] = to_srgb(c / v)
  end
  write_state(STATE_DIR .. '/bg', string.format('#%02x%02x%02x', out[1], out[2], out[3]))
end

local function update_status(window)
  window:set_left_status('') -- clears what older versions drew there
  sync_footer_bg(window)
  sync_footer(window)
  flush_footer(window)
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
  wezterm.on('window-resized', flush_footer)
  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'i', mods = 'ALT', action = M.copy_action() })
end

return M
