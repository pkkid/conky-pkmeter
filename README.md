# Conky-PKMeter

<img align="right" src="preview.png">

A Conky configuration written entirely in Lua. It includes clock, weather,
system, GPU, process, network, filesystem, media, Bambu printer, and AI usage
(Claude and Codex) widgets.

## Installation

```bash
sudo apt install conky-all lua-socket lua-sec playerctl curl unzip
git clone https://github.com/pkkid/conky-pkmeter.git
cd conky-pkmeter
conky -c conkyrc
```

## Configuration

Widget settings and display order are defined in `config.lua`. Window placement,
size, and Conky behavior are configured in `conkyrc`.
Long titles, including accented characters and emoji, are shortened to fit.

- `openmeteo`: Set your location, timezone, units, and icon theme.
- `networks`: Find interface names with `ip link`, then configure the devices to monitor.
- `filesystems`: Find mount paths with `df -h`, then configure the paths to monitor.
- `nowplaying`: Uses `playerctl` for playback information and controls.
- `bambu`: Set the printer host, serial number, and LAN access code.

## AI Usage

The `aiusage` widget combines Claude and Codex usage in one panel. Enable or
disable either service with `enabled` in `config.aiusage.claude` or
`config.aiusage.codex`. Each service shows its five-hour and weekly usage
(e.g. `Claude 5h`, `Codex Week`) with local reset times: `1:13p` for five-hour
windows and `Sat 4:32p` for weekly windows.

The header shows the plans, time since the oldest limit update, and a status
dot per service: blue while running, orange while waiting for you. With both
active the dots sit side by side; clicking the header refreshes both services.

The model mix and weekly pacing are hidden by default; click the widget content
to toggle them, or set `show_details = true`. The model mix lists each
service's top three local models by token share and prompt count, allocated
against that service's own limit, so the combined list totals up to 200%. It
excludes activity from other machines. Cloud limits refresh every 15 minutes;
failed reads keep the last snapshot and retry with capped backoff. Model mixes
refresh every five minutes in a background Lua process.

### Codex

Starts the locally installed Codex App Server and reads the account's limit
snapshot into `/tmp/pkmeter-codex.json`. Codex must be on `PATH` and logged in
with a supported account; API-key-only and Bedrock authentication do not
provide usage data. Requires `timeout` from GNU coreutils. Task status and the
model mix read local Codex session records.

### Claude

Reads the account usage endpoint with `curl`, using Claude Code's stored login
in `~/.claude/.credentials.json` (or `$CLAUDE_CONFIG_DIR`), into
`/tmp/pkmeter-claude.json`. It never refreshes the login itself; an expired
token shows stale data until Claude Code is used again. Task status reads the
undocumented `~/.claude/sessions` files, which may change between releases. The
model mix reads local transcripts in `~/.claude/projects`.

## Auto Start

Add the following command to Ubuntu Startup Applications:

```bash
/usr/bin/bash -c "/usr/bin/sleep 5; cd ~/Projects/conky-pkmeter/ && conky -c conkyrc"
```

## Mouse Clicks

[Conky issue #2047](https://github.com/brndnmtthws/conky/issues/2047) can cause
mouse clicks to be reported as `mouse_enter` under XWayland and some X11 window
managers. As a temporary workaround, handle `mouse_enter` instead of
`button_down` in `pkmeter.lua` and use:

```lua
own_window_type = 'normal',
own_window_hints = 'skip_taskbar,sticky,below',
```

This workaround may display a window title on the panel.

## Credits

Fisadev and Zineddine SAIBI created the original Conky drawing scripts.
