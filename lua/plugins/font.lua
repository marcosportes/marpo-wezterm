-- ============================================
-- FONT PICKER (Ctrl+Shift+F): Nerd Font family and size
-- ============================================
-- The choice is saved in ~/.local/share/wezterm/font (core/fonts.lua reads it)
-- and applies to every window. Fonts other than the bundled Hack are fetched
-- from the Nerd Fonts release the first time they are picked
-- (scripts/font-install.sh) into ~/.local/share/wezterm/fonts.
local wezterm = require 'wezterm'
local act = wezterm.action
local fonts = require 'core.fonts'

local M = {}

-- family as WezTerm knows it, release asset (nil: bundled in fonts/), MB to
-- download, file prefix when the asset ships other families too
M.list = {
  { family = 'Hack Nerd Font Mono' },
  { family = 'JetBrainsMono Nerd Font Mono', asset = 'JetBrainsMono', mb = 6, prefix = 'JetBrainsMono' },
  { family = 'FiraCode Nerd Font Mono', asset = 'FiraCode', mb = 2 },
  { family = 'MesloLGS Nerd Font Mono', asset = 'Meslo', mb = 4, prefix = 'MesloLGS' },
  { family = 'CaskaydiaCove Nerd Font Mono', asset = 'CascadiaCode', mb = 3 }, -- Cascadia Code
  { family = 'SauceCodePro Nerd Font Mono', asset = 'SourceCodePro', mb = 3 }, -- Source Code Pro
  { family = 'BlexMono Nerd Font Mono', asset = 'IBMPlexMono', mb = 3 },      -- IBM Plex Mono
  { family = 'Iosevka Nerd Font Mono', asset = 'Iosevka', mb = 87 },
  { family = 'UbuntuMono Nerd Font Mono', asset = 'UbuntuMono', mb = 2 },
  { family = 'RobotoMono Nerd Font Mono', asset = 'RobotoMono', mb = 3 },
  { family = 'DejaVuSansM Nerd Font Mono', asset = 'DejaVuSansMono', mb = 2 },
  { family = 'GeistMono Nerd Font Mono', asset = 'GeistMono', mb = 5 },
  { family = 'Inconsolata Nerd Font Mono', asset = 'Inconsolata', mb = 2 },
  { family = 'VictorMono Nerd Font Mono', asset = 'VictorMono', mb = 3 },
  { family = 'Mononoki Nerd Font Mono', asset = 'Mononoki', mb = 2 },
}

M.sizes = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 28 }

local INSTALL = wezterm.config_dir .. '/scripts/font-install.sh'
local DOWNLOAD_TIMEOUT = 600 -- seconds before a download is given up

local by_family = {}
for _, f in ipairs(M.list) do by_family[f.family] = f end

local function asset_dir(f)
  return fonts.DOWNLOAD_DIR .. '/' .. f.asset
end

local function installed(f)
  if not f.asset then return true end
  local ok, files = pcall(wezterm.read_dir, asset_dir(f))
  return ok and #files > 0
end

local function exists(path)
  local f = io.open(path, 'r')
  if f then f:close() end
  return f ~= nil
end

local function save(window, pane, family, size)
  os.execute('mkdir -p "' .. fonts.DOWNLOAD_DIR .. '"')
  local tmp = fonts.STATE_FILE .. '.tmp'
  local f = io.open(tmp, 'w')
  if not f then return end
  f:write(family .. '\t' .. tostring(size) .. '\n')
  f:close()
  os.rename(tmp, fonts.STATE_FILE)
  window:perform_action(act.ReloadConfiguration, pane)
  window:toast_notification('WezTerm', 'Font: ' .. family .. ' ' .. tostring(size), nil, 2000)
end

-- Fetches the font in the background; update-status applies it when done
local function download(window, f, size)
  os.execute('mkdir -p "' .. fonts.DOWNLOAD_DIR .. '"')
  os.remove(asset_dir(f) .. '.failed')
  wezterm.GLOBAL.font_pending = { family = f.family, size = size, started = os.time() }
  wezterm.background_child_process {
    'bash', '-c', '"$0" "$1" "$2" "$3" || : >"$2/$1.failed"',
    INSTALL, f.asset, fonts.DOWNLOAD_DIR, f.prefix or '*',
  }
  window:toast_notification('WezTerm', 'Downloading ' .. f.family .. ' (' .. f.mb .. ' MB)…', nil, 3000)
end

local function check_download(window, pane)
  local p = wezterm.GLOBAL.font_pending
  if not p then return end
  local f = by_family[p.family]
  if f and installed(f) then
    wezterm.GLOBAL.font_pending = nil
    save(window, pane, p.family, p.size)
  elseif not f or exists(asset_dir(f) .. '.failed') or os.time() - p.started > DOWNLOAD_TIMEOUT then
    wezterm.GLOBAL.font_pending = nil
    window:toast_notification('WezTerm', 'Could not download ' .. p.family, nil, 4000)
  end
end

local function pick_size(window, pane, family)
  local _, current = fonts.current()
  local choices = {}
  for _, size in ipairs(M.sizes) do
    table.insert(choices, {
      id = tostring(size),
      label = tostring(size) .. (size == current and '  ✓' or ''),
    })
  end
  window:perform_action(act.InputSelector {
    title = 'Font size',
    description = 'Type to filter · Enter applies · Esc cancels',
    fuzzy = true,
    fuzzy_description = '🔎 ',
    choices = choices,
    action = wezterm.action_callback(function(win, p, id)
      if id then save(win, p, family, tonumber(id)) end
    end),
  }, pane)
end

function M.picker_action()
  return wezterm.action_callback(function(window, pane)
    local family, size = fonts.current()
    local choices = {
      {
        id = 'size',
        label = wezterm.format {
          { Attribute = { Intensity = 'Bold' } },
          { Text = '󰛖  Size: ' .. tostring(size) .. '  (Enter to change)' },
        },
      },
    }
    for _, f in ipairs(M.list) do
      local note = ''
      if f.family == family then
        note = '  ✓'
      elseif not installed(f) then
        note = '  · download ' .. f.mb .. ' MB'
      end
      table.insert(choices, { id = f.family, label = f.family .. note })
    end

    window:perform_action(act.InputSelector {
      title = 'Font',
      description = 'Type to filter · Enter applies · Esc cancels',
      fuzzy = true,
      fuzzy_description = '🔎 ',
      choices = choices,
      action = wezterm.action_callback(function(win, p, id)
        if id == nil then return end
        if id == 'size' then return pick_size(win, p, family) end
        local f = by_family[id]
        if not f or id == family then return end
        if installed(f) then
          save(win, p, f.family, size)
        else
          download(win, f, size)
        end
      end),
    }, pane)
  end)
end

function M.apply(config)
  wezterm.on('update-status', check_download)
  config.keys = config.keys or {}
  table.insert(config.keys, { key = 'f', mods = 'CTRL|SHIFT', action = M.picker_action() })
end

return M
