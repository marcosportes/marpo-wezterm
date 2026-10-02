-- ============================================
-- SSH: reads hosts from ~/.ssh/config and offers a searchable picker (Tabby style)
-- ============================================
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

M.wrapper = wezterm.config_dir .. '/scripts/ssh-reconnect.sh'

local HOME = os.getenv('HOME')

local function expand_path(path)
  return (path:gsub('^~', HOME))
end

local function glob_files(pattern)
  local files = {}
  local handle = io.popen('/bin/ls -d ' .. pattern .. ' 2>/dev/null')
  if handle then
    for file in handle:lines() do
      table.insert(files, file)
    end
    handle:close()
  end
  return files
end

local function parse_ssh_file(filepath, hosts, visited)
  if visited[filepath] then return end
  visited[filepath] = true

  local f = io.open(filepath, 'r')
  if not f then return end

  local current = nil
  for line in f:lines() do
    line = line:match('^%s*(.-)%s*$')
    if line ~= '' and not line:match('^#') then
      local include = line:match('^[Ii]nclude%s+(.+)$')
      if include then
        include = expand_path(include)
        if not include:match('^/') then
          include = HOME .. '/.ssh/' .. include
        end
        for _, file in ipairs(glob_files(include)) do
          parse_ssh_file(file, hosts, visited)
        end
      end

      local host = line:match('^[Hh]ost%s+(.+)$')
      if host then
        current = nil
        -- "Host a b c" defines several aliases; skip wildcard patterns
        for name in host:gmatch('%S+') do
          if not name:match('[*?!]') then
            current = { name = name, address = name }
            table.insert(hosts, current)
            break
          end
        end
      elseif current then
        local hostname = line:match('^[Hh]ost[Nn]ame%s+(.+)$')
        if hostname then current.address = hostname end
        local user = line:match('^[Uu]ser%s+(.+)$')
        if user then current.user = user end
        local port = line:match('^[Pp]ort%s+(%d+)$')
        if port then current.port = port end
      end
    end
  end
  f:close()
end

function M.hosts()
  local hosts = {}
  parse_ssh_file(HOME .. '/.ssh/config', hosts, {})
  table.sort(hosts, function(a, b) return a.name:lower() < b.name:lower() end)
  return hosts
end

local function host_label(h)
  local target = (h.user and (h.user .. '@') or '') .. h.address .. (h.port and (':' .. h.port) or '')
  if target == h.name then return h.name end
  return h.name .. '  (' .. target .. ')'
end

-- Command that opens an SSH tab with automatic reconnect.
-- `lazy`: the wrapper waits for Enter before connecting
function M.spawn_args(ssh_argv, lazy)
  local args = { M.wrapper }
  if lazy then table.insert(args, '--lazy') end
  for _, a in ipairs(ssh_argv) do table.insert(args, a) end
  return args
end

-- If the pane is running ssh (directly or via ssh-reconnect.sh), returns the
-- ssh argv ({ 'ssh', ... }) so it can be reopened elsewhere; nil otherwise
function M.args_of(pane)
  local ok, info = pcall(function() return pane:get_foreground_process_info() end)
  if not ok or not info or not info.argv or #info.argv == 0 then return nil end
  local argv = info.argv
  local exe = info.executable or argv[1]
  if info.name == 'ssh' or exe:match('/ssh$') or exe == 'ssh' then
    return argv
  end
  -- ssh-reconnect.sh waiting for the user to press Enter after a drop
  -- (or still waiting, in --lazy mode, for its tab to be selected)
  for i, a in ipairs(argv) do
    if a:match('ssh%-reconnect%.sh$') then
      local rest = { 'ssh' }
      local j = i + 1
      if argv[j] == '--lazy' then j = j + 1 end
      if argv[j] == 'ssh' then j = j + 1 end
      for k = j, #argv do table.insert(rest, argv[k]) end
      return rest
    end
  end
  return nil
end

-- Footer panes (plugins/ssh_info.lua) are registered here so navigation and
-- session saving can skip them. Kept in wezterm.GLOBAL: survives config reloads
local function footer_key(pane_id) return 'ssh_footer_' .. tostring(pane_id) end

function M.mark_footer(pane)
  wezterm.GLOBAL[footer_key(pane:pane_id())] = true
end

function M.is_footer(pane)
  return wezterm.GLOBAL[footer_key(pane:pane_id())] == true
end

-- Split that follows the current pane: if it is connected over ssh, the new
-- pane opens a connection to the same host; otherwise a normal split.
-- `split` is act.SplitHorizontal or act.SplitVertical
function M.split_action(split)
  return wezterm.action_callback(function(window, pane)
    local argv = M.args_of(pane)
    if argv then
      window:perform_action(split { args = M.spawn_args(argv) }, pane)
    else
      window:perform_action(split { domain = 'CurrentPaneDomain' }, pane)
    end
  end)
end

-- Alt+R: reconnect the ssh connection of the current pane
--   ssh under ssh-reconnect.sh -> SIGUSR1, the wrapper reconnects at once
--   wrapper with no ssh child (dropped or --lazy) -> press Enter for it
--   ssh typed in a shell -> SIGTERM, then run the same command again
function M.reconnect_action()
  return wezterm.action_callback(function(window, pane)
    local ok, info = pcall(function() return pane:get_foreground_process_info() end)
    if not ok or not info or not M.args_of(pane) then
      window:toast_notification('WezTerm', 'This pane is not connected over SSH', nil, 2000)
      return
    end
    if info.name ~= 'ssh' then
      -- the wrapper shares its process group with ssh, so it is what shows up
      -- as the foreground process: signal its ssh child if there is one
      local killed = wezterm.run_child_process {
        'pkill', '-USR1', '-x', '-P', tostring(info.pid), 'ssh',
      }
      if not killed then pane:send_text('\r') end
      return
    end
    local parent = info.ppid and wezterm.procinfo.get_info_for_pid(info.ppid)
    local wrapped = false
    for _, a in ipairs(parent and parent.argv or {}) do
      if a:match('ssh%-reconnect%.sh$') then wrapped = true end
    end
    if wrapped then
      wezterm.run_child_process { 'kill', '-USR1', tostring(info.pid) }
    else
      wezterm.run_child_process { 'kill', '-TERM', tostring(info.pid) }
      local quoted = {}
      for _, a in ipairs(info.argv) do
        table.insert(quoted, "'" .. a:gsub("'", "'\\''") .. "'")
      end
      -- give the shell time to get the prompt back before typing the command
      wezterm.time.call_after(0.5, function()
        pane:send_text(table.concat(quoted, ' ') .. '\r')
      end)
    end
  end)
end

M.local_shells = {
  { id = 'local:zsh', label = '⚡ Local Zsh', args = { 'zsh', '-l' } },
  { id = 'local:bash', label = '💻 Local Bash', args = { 'bash', '-l' } },
  { id = 'local:fish', label = '🐟 Local Fish', args = { 'fish' } },
}

-- Alt+X: searchable picker of SSH hosts + local shells
function M.picker_action()
  return wezterm.action_callback(function(window, pane)
    local choices = {}
    for _, h in ipairs(M.hosts()) do
      table.insert(choices, { id = 'ssh:' .. h.name, label = '🖥️  ' .. host_label(h) })
    end
    table.insert(choices, { id = 'manual', label = '✏️  Connect to another host (user@host)...' })
    for _, s in ipairs(M.local_shells) do
      table.insert(choices, { id = s.id, label = s.label })
    end

    window:perform_action(act.InputSelector {
      title = 'Connections',
      description = 'Type to filter · Enter opens in a new tab · Esc cancels',
      fuzzy_description = '🔎 ',
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(win, p, id)
        if not id then return end
        if id:match('^ssh:') then
          win:perform_action(act.SpawnCommandInNewTab {
            args = M.spawn_args { 'ssh', id:sub(5) },
          }, p)
        elseif id == 'manual' then
          win:perform_action(act.PromptInputLine {
            description = 'SSH to (e.g. user@192.168.0.10 -p 2222):',
            action = wezterm.action_callback(function(w2, p2, line)
              if not line or line == '' then return end
              local argv = { 'ssh' }
              for word in line:gmatch('%S+') do table.insert(argv, word) end
              w2:perform_action(act.SpawnCommandInNewTab { args = M.spawn_args(argv) }, p2)
            end),
          }, p)
        else
          for _, s in ipairs(M.local_shells) do
            if s.id == id then
              win:perform_action(act.SpawnCommandInNewTab { args = s.args }, p)
            end
          end
        end
      end),
    }, pane)
  end)
end

return M
