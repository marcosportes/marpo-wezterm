-- ============================================
-- SPINNER: animated icon on tabs that are running a command
-- ============================================
-- A tab counts as busy when any of its panes has something other than a shell
-- (or an interactive program from IDLE) in the foreground. Remote commands on
-- SSH tabs can't be seen from here: ssh itself is always in the foreground.
--
-- A busy tab that goes quiet while its program waits for input (paru's
-- [Y/n], a sudo password...) shows a keyboard icon instead and sends a
-- notification through plugins/notify.lua. "Waiting" means: no output for
-- QUIET seconds and the foreground process is blocked reading the terminal
-- (/proc/PID/wchan). Root processes (sudo, pacman) hide wchan, so for those
-- the cursor must also be left mid-line, right after a prompt.
-- The icon is drawn by plugins/tabs.lua.
local wezterm = require 'wezterm'
local ssh = require 'plugins.ssh'
local notify = require 'plugins.notify'

local M = {}

M.frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

-- Foreground programs that don't count as "running a command"
local IDLE = {}
for _, n in ipairs {
  'zsh', 'bash', 'fish', 'sh', 'dash',
  'ssh', 'mosh-client',
  'vi', 'vim', 'nvim', 'nano', 'less', 'more', 'man',
  'htop', 'btop', 'top', 'lazydocker', 'tmux',
} do IDLE[n] = true end

M.waiting_icon = '󰌌'

local FAST, SLOW = 0.15, 1.0 -- seconds between ticks: while something spins / idle
local QUIET = 3 -- seconds without output before a busy pane counts as waiting

local busy = {}  -- tab id -> 'spin' | 'wait'
local panes = {} -- pane id -> { sig, since, waiting }
local frame = 1

function M.icon(tab_id)
  if busy[tab_id] == 'wait' then return M.waiting_icon end
  return busy[tab_id] and M.frames[frame] or nil
end

local function is_busy(pane)
  if ssh.is_footer(pane) then return false end
  local ok, path = pcall(function() return pane:get_foreground_process_name() end)
  if not ok or not path or path == '' then return false end
  return not IDLE[path:match('([^/]+)$')]
end

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local s = f:read('*l')
  f:close()
  return s
end

-- What the pane shows: changes whenever the program prints something
local function signature(pane)
  local ok, sig = pcall(function()
    local c = pane:get_cursor_position()
    local d = pane:get_dimensions()
    return c.x .. ':' .. c.y .. ':' .. d.scrollback_rows .. ':' .. pane:get_lines_as_text()
  end)
  return ok and sig or nil
end

local TTY_READ = { wait_woken = true, n_tty_read = true }

local function blocked_on_input(pane)
  local ok, info = pcall(function() return pane:get_foreground_process_info() end)
  if not ok or not info or not info.pid then return false end
  local wchan = read_file('/proc/' .. info.pid .. '/wchan')
  if wchan and TTY_READ[wchan] then return true end
  if wchan == 'do_wait' then return false end -- waiting for a child process
  -- root process (wchan hidden: "0") or polling: require a prompt-like cursor
  local ok2, c = pcall(function() return pane:get_cursor_position() end)
  return ok2 and c and c.x > 0
end

-- Returns true while the pane waits for input; notifies once per prompt
local function check_waiting(win, pane, t)
  local id = pane:pane_id()
  local sig = signature(pane)
  local st = panes[id]
  if not st or st.sig ~= sig then
    panes[id] = { sig = sig, since = t, waiting = false }
    return false
  end
  if t - st.since < QUIET then return false end
  if st.waiting == nil then return false end -- already checked: not waiting
  if not st.waiting then
    if not blocked_on_input(pane) then st.waiting = nil; return false end
    st.waiting = true
    notify.alert(win, pane, M.waiting_icon, true)
  end
  return true
end

-- Scans every tab and redraws the tab bars while something is busy. One loop
-- per config generation: a reload starts a new one and the old one stops.
local function tick(gen)
  if wezterm.GLOBAL.spinner_gen ~= gen then return end
  local any = false
  local now = {}
  local seen = {}
  local t = os.time()
  for _, win in ipairs(wezterm.gui.gui_windows()) do
    local ok, mw = pcall(function() return win:mux_window() end)
    if ok and mw then
      for _, tab in ipairs(mw:tabs()) do
        local tid = tab:tab_id()
        for _, p in ipairs(tab:panes()) do
          if is_busy(p) then
            seen[p:pane_id()] = true
            if check_waiting(win, p, t) then
              now[tid] = now[tid] or 'wait'
            else
              now[tid] = 'spin'; any = true
            end
          end
        end
      end
    end
  end
  for id in pairs(panes) do if not seen[id] then panes[id] = nil end end
  local changed = false
  for id, v in pairs(busy) do if now[id] ~= v then changed = true end end
  for id in pairs(now) do if not busy[id] then changed = true end end
  busy = now

  if any or changed then
    frame = frame % #M.frames + 1
    -- the tab bar is rebuilt when the right status changes; alternate between
    -- two invisible values to force it
    local nudge = (frame % 2 == 0) and '' or wezterm.format { 'ResetAttributes' }
    for _, win in ipairs(wezterm.gui.gui_windows()) do
      pcall(function() win:set_right_status(nudge) end)
    end
  end
  wezterm.time.call_after(any and FAST or SLOW, function() tick(gen) end)
end

local started = false

function M.apply(config)
  -- started from the first status update: only the GUI runs it, and only once
  wezterm.on('update-status', function()
    if started then return end
    started = true
    local gen = (wezterm.GLOBAL.spinner_gen or 0) + 1
    wezterm.GLOBAL.spinner_gen = gen
    tick(gen)
  end)
end

return M
