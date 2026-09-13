# Conky-PKMeter

<img align="right" src="preview.png">

A Conky configuration written entirely in Lua. It includes clock, weather,
system, GPU, process, network, filesystem, media, Bambu printer, and Codex usage
widgets.

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

## Codex Usage

The Codex widget displays available five-hour and weekly usage, compact reset
times, weekly pacing, and the top three locally recorded models by token share
and prompt count. Every 15 minutes it starts the locally installed
Codex App Server and reads the authenticated account's current limit snapshot;
it stores the result in `/tmp/pkmeter-codex.json`. Codex must be on `PATH` and
logged in with a supported account. API-key-only and Bedrock authentication do
not provide this account usage data. The poller also requires the standard
`timeout` command from GNU coreutils.

The header shows the plan and time since the last limit update. Weekly resets
show the local weekday (e.g. `Sun`), or the reset time when it is today
(e.g. `10:34a` or `9:30p`).

Task status refreshes every five seconds, shown blue while running or orange
while waiting; it reads local Codex session records for that state only.
Clicking refreshes cloud limits immediately. Failed cloud reads retain the last
successful snapshot and retry with capped exponential backoff. The local model
mix refreshes every five minutes in a background Lua process without a network
request, and its default scan limit is 30 seconds. Its percentages are each
model's token share allocated against the selected cloud-reported limit, so it
excludes Codex activity from other machines and services.

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
