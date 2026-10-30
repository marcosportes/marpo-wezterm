# WezTerm: main shortcuts

## Connections and tabs
| Shortcut | Action |
|---|---|
| `Alt+X` | **SSH host picker** with search (+ local shells and "another host") |
| `Alt+L` | WezTerm's default launch menu |
| `Alt+T` | New tab |
| `Alt+W` | Close tab (always asks for confirmation) |
| `Alt+R` | Reconnect the SSH connection of the current pane (e.g. when the server hangs) |
| `Alt+I` | Copy the IP, IP:port or ssh command of the active SSH pane |
| `F2` | Rename tab and pick a color (empty name = automatic) |
| `Shift+F2` | Change only the tab color |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |
| `Alt+1` … `Alt+9` | Go to tab N |
| `Ctrl+Shift+←/→` | Move the current tab left/right (hold and repeat) |

## Panes (splits)
| Shortcut | Action |
|---|---|
| `Alt+\` | Split side by side (on an SSH pane, the new pane connects to the same host) |
| `Alt+-` | Split top/bottom (same SSH behavior) |
| `Alt+Q` | Close pane |
| `Alt+↑↓` | Switch pane |
| `Alt+←→` | Switch pane; with no pane on that side, previous/next tab |
| `Alt+Shift+←↑→↓` | Resize pane |

## Text and screen
| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` / `Ctrl+Shift+V` | Copy / paste |
| `Alt+C` | Copy the whole visible screen of the pane (no tab bar or footer; works with vim over SSH) |
| Right click | Paste |
| `Ctrl+Click` | Open link |
| `Alt+F` | Search in terminal |
| `Alt+K` | Clear screen and scrollback |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | Increase / decrease / reset font size |
| `F11` | Toggle full screen |
| `Ctrl+Shift+P` | Command palette (all actions) |

## Session
| Shortcut | Action |
|---|---|
| `Alt+S` | Save session now (it already saves every 10 s) |
| `Ctrl+Shift+R` | Reload config |

## Theme and font
| Shortcut | Action |
|---|---|
| `Ctrl+Shift+T` | Theme list: Gruvbox (default), Dracula, Nord, Wonokai, One Dark, Ayu, Everforest |
| `Ctrl+Shift+F` | Font list (Nerd Fonts: Hack, JetBrains Mono, Fira Code, Meslo, Cascadia, …) and font size |
| `Alt+H` | Shortcut list: every command and a one-line description |

The chosen theme is stored in `~/.local/share/wezterm/theme` and applies to every window.
The chosen font and size are stored in `~/.local/share/wezterm/font` and win over
`lua/custom/preferences.lua`. Fonts other than the bundled Hack are downloaded from the
Nerd Fonts release the first time they are picked, into `~/.local/share/wezterm/fonts`.

## Updates
Each time WezTerm starts it checks GitHub once. If origin is ahead of the last
`./setup.sh`, it asks with the same prompt as closing a tab and lists the
pending commit messages. **Yes** runs
`./setup.sh` (git pull and sync). The installed commit is recorded in
`~/.local/share/wezterm/install`. Offline, up to date, or not a fast-forward
stays quiet.

On startup WezTerm restores windows, tabs, splits, directories, tab names/colors
and SSH connections (file: `~/.local/share/wezterm/session.json`).

## When SSH drops
Tabs opened with `Alt+X` show: **Enter** reconnect · **q** close tab.

## SSH footer
Every SSH tab gets a 1-row footer at the bottom with host, user@IP:port, time
logged in (counted from when you get into the server, "authenticating..." while it
asks for a password/passphrase), data sent/received (total and per second),
latency ± jitter (green < 80 ms, yellow < 200 ms, red above) and packet loss
(retransmitted segments, orange while growing). When you type and the server
answers nothing for 5 s, the host turns yellow (red after 15 s) with
"⚠ no response for ... · Alt+R reconnects". It updates every 2 s from local TCP
counters, so it adds no traffic and runs nothing on the server. `Alt+↑↓` skip it,
it is not saved in the session (it is recreated), and it closes when the
connection ends.

On narrow windows the footers (SSH and local) keep every item: secondary texts
(totals, labels, hints) shrink first, then the values show only their first
letters ("marpo-l…"), down to just the icons.

## Notifications
When a tab you are not looking at rings the bell (`long-command; printf '\a'`),
a desktop notification names it and the tab gets a 󰂞 icon until you select it.
`~/.zshrc` rings the bell by itself after commands that take 10 s or more
(editors, pagers, ssh and other interactive programs are skipped).
A command that stops to wait for input in a background tab (paru's `[Y/n]`,
a sudo password...) also notifies, and its spinner turns into 󰌌 until it prints
again.

## Busy tabs
Tabs running a command show a spinner (⠋⠙⠹…) before their number. Shells, ssh
and interactive programs (vim, less, htop...) don't count; commands running on
the remote side of an SSH tab can't be seen.

## Panes
Inactive panes are dimmed so the focused split stands out (the SSH footer too).

## Files
```
wezterm.lua                 entry point (sets up lua/ in the path, calls core)
lua/
  custom/
    preferences.lua         font, size, weight (normal/bold): the place for quick tweaks
  core/
    init.lua                builds the config and loads every module in order
    options.lua             rendering/performance, bell, general behavior
    colors.lua              Gruvbox Material palette (the default theme)
    themes.lua              theme list, saved choice, live switch
    appearance.lua          theme, window, tab bar
    fonts.lua               font setup (reads custom/preferences.lua)
    keymaps.lua             key bindings
    mouse.lua               mouse bindings
    launch_menu.lua         Alt+L menu
  plugins/
    ssh.lua                 reads ~/.ssh/config, Alt+X picker
    tabs.lua                tab colors and width (12 colors in M.colors), F2/Shift+F2
    session.lua             saves/restores the session, Alt+S, opens maximized (M.start_maximized)
    ssh_info.lua            SSH footer (creates/keeps it) and Alt+I copy
    notify.lua              notification + tab icon on bell in background tabs
    spinner.lua             spinner on busy tabs, 󰌌 + notification when waiting for input
    theme.lua               Ctrl+Shift+T theme list
    font.lua                Ctrl+Shift+F font and size list, downloads Nerd Fonts
    help.lua                Alt+H shortcut list
    update.lua              startup check for a newer version on GitHub
scripts/
  ssh-reconnect.sh          SSH reconnect
  ssh-footer.sh             draws the SSH footer
  local-footer.sh           draws the local footer (CPU, RAM, disk, network)
  footer-fit.sh             shrinks the footers to the window width
  wezterm-usage.sh          WezTerm's own CPU/RAM, at the far right of the footers
  font-install.sh           downloads a Nerd Font for the Ctrl+Shift+F list
  check-update.sh           compares the installed commit with GitHub
  apply-update.sh           runs setup.sh when the update prompt is accepted
```

To add a new module: create it in `lua/core/` or `lua/plugins/` with an
`M.apply(config)` function and list it in `lua/core/init.lua`.
