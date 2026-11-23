# Spotify Switcher for Omarchy

One Spotify icon in the Omarchy bar (`timon.spotify-switch`). **Left click**
moves Spotify playback to the next Spotify Connect device; the tooltip names
the device that plays now. No popup, no panel.

## What a click does

1. Takes the devices Spotify Connect lists (`GET /v1/me/player/devices`,
   kept fresh in the background, see Speed). Spotify only lists devices
   where Spotify is open or was active lately, so the cycle runs over
   whatever is there; a missing device is skipped, and a device that left
   since the last read is noticed by the PUT's 404.
2. Puts them in a **fixed order**: first the names from `order` in the
   config, in that order (an entry matches a device whose name equals it or
   starts with it, ignoring case, so `"Pixel"` matches "Pixel 10 Pro"), then
   all other devices alphabetically (ignoring case; equal names by device
   id). Devices Spotify marks as restricted are skipped.
3. Picks the device after the one playing now and wraps around at the end.
   With no active device it picks the first one.
4. Moves playback there (`PUT /v1/me/player`). **The play state is kept**:
   if music was playing it keeps playing on the new device (`play: true`);
   if it was paused, or nothing was active, the `play` flag is left out,
   which Spotify documents as "keep the current state", so a click never
   starts music by surprise.

With only one device available, a click just says "Spotify: XPS (only device
available)" in the tooltip. (One device that is *not* active yet is the
"none active" case: the click moves playback to it.)

The icon is lit while a device plays Spotify and dimmed (stock
`WidgetButton.dimmed`) when there is no device, you are not logged in, or
something failed. The tooltip says what:

| Tooltip | Meaning |
| --- | --- |
| `Spotify: <device>` | that device has the session |
| `Spotify: no active device, click to play on <device>` | devices there, none active |
| `Spotify: no device (open Spotify on a device)` | Spotify Connect lists nothing |
| `Spotify: <device> (only device available)` | nothing to switch to |
| `Spotify: Premium needed to switch devices` | 403 `PREMIUM_REQUIRED`: moving playback needs Premium |
| `Spotify: not logged in (run omarchy-spotify-switch-login)` | no token, or it was revoked (a click opens the login) |
| `Spotify: no client ID set (see README)` | no `client_id` in the config |
| `Spotify: busy, try again in 30s` | 429; waits up to 3 s by itself, longer `Retry-After`s are shown |
| `Spotify: <device> (offline, last known)` | no network |
| `Spotify: <device> is no longer available` | the device left between the list and the click |

## Icon

The icon is a glyph from the Nerd Font the bar already uses, so it follows
the theme colour and the stock dim/lit states. Pick it with `"icon"`:

| Value | Glyph |
| --- | --- |
| `spotify` (default) | nf-fa-spotify, the Spotify logo |
| `devices` | nf-md-devices (a phone next to a monitor) |
| `monitor-speaker` | nf-md-monitor_speaker (a monitor with a speaker) |
| `U+F04C3` or the glyph itself | any other Nerd Font glyph |

Set it for every bar entry in `config.json` (`"icon": "devices"`), or per
bar entry in `~/.config/omarchy/shell.json`:
`{"id": "timon.spotify-switch", "icon": "devices"}`. The bar entry wins.
The widget allows several bar entries, each with its own icon; each one is
a full, working switcher, and a click on one updates the others.

## Speed

A click costs **one PUT** to Spotify, with no process start, no device
list read, no play-state read and no token refresh on the way:

- The widget runs one long-lived helper, `omarchy-spotify-switch serve`
  (it exits with the shell). It keeps an HTTPS connection to Spotify open,
  refreshes the access token ahead of time (10 minutes before it expires, in
  the background) and keeps the device list and play state in the cache.
- On a click the icon and tooltip switch to the target at once. The helper
  sends `PUT /me/player` straight away using the cached list; only when that
  device is gone (404) does it read the list again and move to the next one
  that is there. The play state comes from the cache if it is under 15 s
  old, otherwise one quick `GET /me/player` comes first.
- About 1.5 s after a transfer the helper reads Spotify again to confirm.
  Spotify can still name the old device for a moment, so for 6 s the
  transfer's target wins over a lagging "old device" answer (a device picked
  elsewhere still wins at once). The icon never flips back and forth.
- The last known state shows at once on start: every answer is written to a
  cache file (`status.json`) that the widget watches (an event, not a poll).
- Spotify is read at start, after clicks, when the pointer rests on the icon
  (at most every 10 s) and every 5 minutes. Spotify has no push channel for
  "playback moved to another device" (e.g. you picked the phone in the
  Spotify app), so without that slow refresh the dim/lit state could stay
  wrong for hours; 5 minutes is two small HTTPS requests per bar, far from
  Spotify's rate limits. Set `"refreshMinutes": 0` in the widget's
  shell.json entry to turn it off, or another number of minutes.
- If the helper is not running, clicks fall back to one-shot
  `omarchy-spotify-switch next` runs (Python start, same cache logic).

What stays slow is Spotify's own handoff: the PUT only returns once Spotify
has told the target device, and the device then has to buffer and start the
audio. On a test laptop that was about 0.35 s for the PUT and 0.8 s until
the position moved; a phone took 2.2 s just for the PUT (the app has to
wake), and across a handful of real clicks the median from click to sound was
about 3 s, nearly all of it Spotify's handoff. The bar cannot speed that up.

### Timing log (opt-in)

`"timing": true` in the config (or `SPOTIFY_SWITCH_TIMING=1`) writes one JSON
line per click to `~/.local/state/timon-spotify-switch/timing.log` (600,
rotated at 256 KB): `queued` (widget click to helper), `get_devices` /
`get_player` (only when the cache was too old), `token`, `put`,
`cache_write`, `backend_total`, `answer_to_widget` and `click_to_widget`.
A second `handoff` line says when Spotify reported the target active and
its playback position moving, measured from the PUT's answer (this polls
`GET /me/player` up to 10 s after each click, only while timing is on). No
device ids or tokens are logged.

## Requirements

- [Omarchy](https://omarchy.org) 4.x (its Quickshell bar and plugin system).
- **Spotify Premium.** Spotify only lets Premium accounts move playback
  through the Web API; without it every click shows "Premium needed to
  switch devices".
- Your own Spotify developer app (free). This plugin ships no client ID.
- `python3` (standard library only) and `xdg-open`, both part of Omarchy.

## Spotify app setup

1. Open <https://developer.spotify.com/dashboard> and create an app.
2. Redirect URI: exactly `http://127.0.0.1:8888/callback` (Spotify requires
   the loopback IP, not `localhost`).
3. APIs: tick **Web API**.
4. While the app is in Development mode, add your Spotify account's e-mail
   under **User Management**, or Spotify refuses the login.
5. Copy the **Client ID**. No client secret is needed or used: the login is
   Authorization Code with PKCE (S256), the flow meant for apps that cannot
   keep a secret.

## Install

1. `git clone https://github.com/roehrbacher/omarchy-spotify-switch ~/Work/omarchy-spotify-switch`
2. `cd ~/Work/omarchy-spotify-switch && ./install.sh` (`--dry-run` lists the
   changes first; nothing is installed system-wide and nothing runs as root)
3. Put your client ID in `~/.config/timon-spotify-switch/config.json`
   (created by the installer, mode 600):
   `{"client_id": "<your client id>", "order": ["Pixel", "Living room", "Laptop"]}`
   `order` is optional: names (or name prefixes) of your devices as Spotify
   shows them, in the order you want to cycle.
4. `omarchy-spotify-switch-login`: opens the Spotify login in your browser and
   waits up to 3 minutes for the answer on `127.0.0.1:8888` (one request,
   then the listener is gone). `SPOTIFY_SWITCH_LOGIN_TIMEOUT=600` gives you
   longer.
5. Add `timon.spotify-switch` to your bar in Omarchy's settings and reload
   the shell.

Update: `git pull && ./install.sh`. Undo: `./uninstall.sh` (plugin and
helpers; keeps your login), `./uninstall.sh --purge` (also deletes tokens,
cache and config), `./uninstall.sh --last` (back to the version before the
last update). Backups live in
`~/.local/share/omarchy-config-backups/omarchy-spotify-switch/`.

## Files

| Path | What |
| --- | --- |
| `plugin/timon.spotify-switch/` | the bar widget (`SpotifySwitch.qml`, `Cycle.js`, `manifest.json`) → `~/.config/omarchy/plugins/` |
| `bin/omarchy-spotify-switch` | backend: `status`, `next [--from ID]`, `serve`, `cached`, `login`, `logout` → `~/.local/bin/` |
| `bin/omarchy-spotify-switch-login` | the login helper |
| `~/.config/timon-spotify-switch/config.json` | `client_id`, `order` (yours, never in git) |
| `~/.local/state/timon-spotify-switch/token.json` | tokens: dir 700, file 600, written atomically |
| `~/.local/state/timon-spotify-switch/status.json` | the last status the bar shows (no tokens) |
| `~/.local/state/timon-spotify-switch/timing.log` | only with `"timing": true` |

`SPOTIFY_SWITCH_CLIENT_ID` overrides the config's client ID.

## Login and tokens

- Authorization Code with PKCE (S256), scopes
  `user-read-playback-state user-modify-playback-state`, a random `state`
  checked on the callback, a 43–128 character verifier. The listener binds
  only `127.0.0.1:8888` and serves one callback.
- The access token is refreshed a minute before it expires, or once after a
  401. Spotify may hand out a new refresh token on refresh (rotation); it
  replaces the old one, otherwise the old one is kept. Refreshes run under a
  file lock, so two bars refreshing at once cannot lose a rotated token.
- A rejected refresh (revoked app, password change) shows "not logged in";
  run `omarchy-spotify-switch-login` again.
- The API hosts are fixed. Tests may point them at `http://127.0.0.1:<port>`
  only, so no environment variable can send tokens anywhere else.

## Not affiliated with Spotify

Spotify is a trademark of Spotify AB. This is an independent, unofficial
plugin that uses the public Spotify Web API under your own developer app.
The bar icons are glyphs from [Nerd Fonts](https://www.nerdfonts.com)
(Font Awesome and Material Design Icons sets), not Spotify artwork.

## Tests

```
bash tests/run-all.sh                 # everything below
bash tests/backend.test.sh            # backend vs. a fake Spotify on 127.0.0.1
bash tests/install.test.sh            # install/uninstall into a temp $HOME
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_cycle.qml
OMARCHY_SHELL=<omarchy>/shell bash tests/widget/run.sh [shots-dir]   # offscreen software render
bash tests/secrets.test.sh            # nothing secret in the files, history or hook
```

All tests use temp XDG dirs, a fake Spotify (`tests/lib/fake_spotify.py`)
and fake tokens; they never talk to Spotify or touch your login. The widget
test runs Quickshell with `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software`
under `timeout`, kills its process group and leaves nothing running; run it
on a build box, not on a desktop with a live shell.

## Development

`git config core.hooksPath .githooks` enables the pre-commit hook: gitleaks
plus a pattern check for IPs, MACs, serials, tokens and your client ID. It
fails closed (no gitleaks, no commit). The version is `manifest.json`
`version` (also `VERSION`); each commit subject starts with it.

## License

MIT, see [LICENSE](LICENSE).
