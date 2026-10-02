-- ============================================
-- SESSION RESTORE (Tabby style)
-- ============================================
-- Periodically saves windows/tabs/splits (directory, title, color, SSH connections)
-- to ~/.local/share/wezterm/session.json and reopens everything when WezTerm starts.
local wezterm = require 'wezterm'
local ssh = require 'plugins.ssh'
local tabs = require 'plugins.tabs'
local mux = wezterm.mux

local M = {}

local STATE_DIR = (os.getenv('XDG_DATA_HOME') or (os.getenv('HOME') .. '/.local/share')) .. '/wezterm'
local STATE_FILE = STATE_DIR .. '/session.json'
local SAVE_INTERVAL = 10 -- seconds

-- Open windows maximized on startup
M.start_maximized = true

local json_encode = (wezterm.serde and wezterm.serde.json_encode) or wezterm.json_encode
local json_decode = (wezterm.serde and wezterm.serde.json_decode) or wezterm.json_parse

-- ---------- Save ----------

local function cwd_of(pane)
  local ok, url = pcall(function() return pane:get_current_working_dir() end)
  if not ok or not url then return nil end
  if type(url) == 'userdata' or type(url) == 'table' then
    return url.file_path
  end
  -- older versions return a "file://host/path" string
  return (tostring(url):gsub('^file://[^/]*', ''))
end

local function leaf_state(info)
  return {
    cwd = cwd_of(info.pane),
    domain = info.pane:get_domain_name(),
    ssh = ssh.args_of(info.pane),
    active = info.is_active or nil,
  }
end

-- Rebuilds the split tree from the pane positions.
-- Looks for a vertical/horizontal line that separates the panes into two groups
-- without cutting through any pane, then recurses into each group.
local function build_tree(panes)
  if #panes == 1 then return leaf_state(panes[1]) end

  local function try(pos, size, direction)
    local cuts = {}
    for _, p in ipairs(panes) do cuts[p[pos]] = true end
    local cut_list = {}
    for c in pairs(cuts) do table.insert(cut_list, c) end
    table.sort(cut_list)
    for _, c in ipairs(cut_list) do
      local first, second = {}, {}
      local valid = true
      for _, p in ipairs(panes) do
        if p[pos] + p[size] <= c then
          table.insert(first, p)
        elseif p[pos] >= c then
          table.insert(second, p)
        else
          valid = false
          break
        end
      end
      if valid and #first > 0 and #second > 0 then
        local first_end, second_end, start = 0, 0, math.huge
        for _, p in ipairs(first) do
          first_end = math.max(first_end, p[pos] + p[size])
          start = math.min(start, p[pos])
        end
        for _, p in ipairs(second) do second_end = math.max(second_end, p[pos] + p[size]) end
        local total = second_end - start
        local ratio = (second_end - c) / total
        return {
          direction = direction,
          ratio = math.max(0.05, math.min(0.95, ratio)),
          first = build_tree(first),
          second = build_tree(second),
        }
      end
    end
    return nil
  end

  return try('left', 'width', 'Right')
    or try('top', 'height', 'Bottom')
    or leaf_state(panes[1]) -- unexpected layout: keep a single pane
end

local function tab_state(tab)
  local ok, all = pcall(function() return tab:panes_with_info() end)
  if not ok or not all then return nil end
  -- SSH footers are recreated by plugins/ssh_info.lua, not restored
  local panes = {}
  for _, p in ipairs(all) do
    if not ssh.is_footer(p.pane) then table.insert(panes, p) end
  end
  if #panes == 0 then return nil end
  return { title = tab:get_title(), color = tabs.get_color(tab:tab_id()), tree = build_tree(panes) }
end

function M.save()
  local windows = {}
  for _, win in ipairs(mux.all_windows()) do
    local tabs, active = {}, 1
    for _, info in ipairs(win:tabs_with_info()) do
      local st = tab_state(info.tab)
      if st then
        table.insert(tabs, st)
        if info.is_active then active = #tabs end
      end
    end
    if #tabs > 0 then
      table.insert(windows, { tabs = tabs, active = active, workspace = win:get_workspace() })
    end
  end
  -- Never overwrite a good session with an empty one
  if #windows == 0 then return end

  os.execute('mkdir -p "' .. STATE_DIR .. '"')
  local tmp = STATE_FILE .. '.tmp'
  local f = io.open(tmp, 'w')
  if not f then return end
  f:write(json_encode({ version = 2, windows = windows }))
  f:close()
  os.rename(tmp, STATE_FILE) -- atomic write
end

-- ---------- Restore ----------

local function load()
  local f = io.open(STATE_FILE, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  local ok, state = pcall(json_decode, content)
  if ok and type(state) == 'table' and type(state.windows) == 'table' then
    return state
  end
  wezterm.log_error('session.lua: could not read ' .. STATE_FILE)
  return nil
end

local function first_leaf(node)
  while node.first do node = node.first end
  return node
end

-- Restored SSH panes start in --lazy mode and are registered here; they only
-- connect once their tab is selected (see wake_lazy_panes)
local function lazy_key(pane)
  return 'lazy_ssh_' .. tostring(pane:pane_id())
end

local function mark_lazy(leaf, pane)
  if leaf.ssh then wezterm.GLOBAL[lazy_key(pane)] = true end
end

local function wake_lazy_panes(window)
  local ok, tab = pcall(function() return window:active_tab() end)
  if not ok or not tab then return end
  for _, p in ipairs(tab:panes()) do
    local k = lazy_key(p)
    if wezterm.GLOBAL[k] then
      wezterm.GLOBAL[k] = false
      p:send_text('\r')
    end
  end
end

local function spawn_args(leaf)
  local args = {}
  if leaf.ssh then
    args.args = ssh.spawn_args(leaf.ssh, true)
  elseif leaf.cwd and leaf.cwd ~= '' then
    args.cwd = leaf.cwd
  end
  if leaf.domain and leaf.domain ~= 'local' then
    args.domain = { DomainName = leaf.domain }
  end
  return args
end

-- `pane` is already running first_leaf(node); create the remaining splits
local function restore_splits(node, pane, active)
  if not node.first then
    if node.active then active.pane = pane end
    return
  end
  local leaf = first_leaf(node.second)
  local args = spawn_args(leaf)
  args.direction = node.direction
  args.size = node.ratio
  local new_pane = pane:split(args)
  mark_lazy(leaf, new_pane)
  restore_splits(node.first, pane, active)
  restore_splits(node.second, new_pane, active)
end

local function tab_tree(t)
  -- sessions saved by version 1 (no splits)
  return t.tree or { cwd = t.cwd, domain = t.domain, ssh = t.ssh }
end

local function restore(state)
  for _, w in ipairs(state.windows) do
    local mux_win
    for i, t in ipairs(w.tabs) do
      local ok, err = pcall(function()
        local tree = tab_tree(t)
        local leaf = first_leaf(tree)
        local args = spawn_args(leaf)
        local tab, pane
        if not mux_win then
          args.workspace = w.workspace
          tab, pane, mux_win = mux.spawn_window(args)
        else
          tab, pane = mux_win:spawn_tab(args)
        end
        mark_lazy(leaf, pane)
        local active = {}
        restore_splits(tree, pane, active)
        if active.pane then active.pane:activate() end
        if t.title and t.title ~= '' then tab:set_title(t.title) end
        if t.color then tabs.set_color(tab:tab_id(), t.color) end
      end)
      if not ok then wezterm.log_error('session.lua: failed to restore tab ' .. i .. ': ' .. tostring(err)) end
    end
    if mux_win then
      local tabs = mux_win:tabs()
      local target = tabs[w.active] or tabs[1]
      if target then target:activate() end
    end
  end
end

local function maximize_all()
  if not M.start_maximized then return end
  for _, win in ipairs(mux.all_windows()) do
    pcall(function()
      local gui = win:gui_window()
      if gui then gui:maximize() end
    end)
  end
end

function M.apply(config)
  wezterm.on('gui-startup', function(cmd)
    -- `wezterm start -- command` opens only that command, without restoring
    if cmd and cmd.args then
      mux.spawn_window(cmd)
    else
      local state = load()
      if state and #state.windows > 0 then
        restore(state)
      end
      if #mux.all_windows() == 0 then
        mux.spawn_window(cmd or {})
      end
    end
    maximize_all()
    wezterm.GLOBAL.session_restored = true
  end)

  -- update-status fires every ~1s per window; save at most every SAVE_INTERVAL
  wezterm.on('update-status', function(window)
    wake_lazy_panes(window)
    if not wezterm.GLOBAL.session_restored then return end
    local now = os.time()
    if now - (wezterm.GLOBAL.session_last_save or 0) < SAVE_INTERVAL then return end
    wezterm.GLOBAL.session_last_save = now
    M.save()
  end)

  config.keys = config.keys or {}
  -- Alt+S: save now
  table.insert(config.keys, {
    key = 's',
    mods = 'ALT',
    action = wezterm.action_callback(function(win)
      M.save()
      win:toast_notification('WezTerm', 'Session saved', nil, 2000)
    end),
  })
end

return M
