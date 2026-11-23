# Spotify Switcher for Omarchy

One Spotify icon in the Omarchy bar (`timon.spotify-switch`). **Left click**
moves Spotify playback to the next Spotify Connect device; the tooltip names
the device that plays now. No popup, no panel.

## What a click does

1. Reads the devices Spotify Connect lists right now
   (`GET /v1/me/player/devices`). Spotify only lists devices where Spotify is
   open or was active lately, so the cycle runs over whatever is there; a
   missing device is skipped.
2. Puts them in a **fixed order**: first the names from `order` in the
   config, in that order (an entry matches a device whose name equals it or
   starts with it, ignoring case, so `"Pixel"` matches "Pixel 10 Pro"), then
   all other devices alphabetically (ignoring case; equal names by device
   id). Devices Spotify marks as restricted are skipped.
3. Picks the device after the one playing now and wraps around at the end.
   With no active device it picks the first one.
4. Moves playback there (`PUT /v1/me/player`). **The play state is kept**:
   if music was playing it keeps playing on the new device (`play: true`);
   if it was paused, or nothing was active, it moves paused (`play: false`),
   so a click never starts music by surprise.

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

## Speed

- The bar shows the last known state at once: the backend writes every
  answer to a cache file (`status.json`), which the widget reads on start
  and watches for changes (an event, not a poll).
- A click shows the target device in the icon's state and tooltip at once
  (optimistic); the backend's answer follows a moment later and corrects it
  if Spotify disagrees. Rapid clicks step through the cycle and end where the
  last one pointed.
- Spotify is read at start, after every click, when the pointer rests on the
  icon (at most every 20 s), and every 5 minutes. Spotify has no push channel
  for "playback moved to another device" (e.g. you picked the phone in the
  Spotify app), so without that slow refresh the dim/lit state could stay
  wrong for hours; 5 minutes is one small HTTPS request
  (`/me/player/devices`) per bar, far from Spotify's rate limits. Set
  `"refreshMinutes": 0` in the widget's shell.json entry to turn it off, or
  another number of minutes.

## Install

Needs only what Omarchy already ships: `python3` (standard library only),
`xdg-open`. Nothing is installed system-wide.

1. Create a Spotify app at <https://developer.spotify.com/dashboard> with the
   redirect URI `http://127.0.0.1:8888/callback` and the Web API enabled. No
   client secret is used (Authorization Code with PKCE).
2. `git clone https://github.com/roehrbacher/omarchy-spotify-switch ~/Work/omarchy-spotify-switch`
3. `cd ~/Work/omarchy-spotify-switch && ./install.sh` (`--dry-run` lists the changes first)
4. Put the app's client ID in `~/.config/timon-spotify-switch/config.json`:
   `{"client_id": "<id>", "order": ["Pixel", "gaming PC", "XPS"]}`
   (`order` is optional; use your devices' names as Spotify shows them.)
5. `omarchy-spotify-switch-login`: opens the Spotify login in your browser and
   waits up to 3 minutes for the answer on `127.0.0.1:8888` (one request,
   then the listener is gone).
6. Add `timon.spotify-switch` to your bar in Omarchy's settings, then click
   the reload icon when it suits you.

Update: `git pull && ./install.sh`. Undo: `./uninstall.sh` (plugin and
helpers; keeps your login), `./uninstall.sh --purge` (also deletes tokens,
cache and config), `./uninstall.sh --last` (back to the version before the
last update). Backups live in
`~/.local/share/omarchy-config-backups/omarchy-spotify-switch/`.

## Files

| Path | What |
| --- | --- |
| `plugin/timon.spotify-switch/` | the bar widget (`SpotifySwitch.qml`, `Cycle.js`, `manifest.json`) → `~/.config/omarchy/plugins/` |
| `bin/omarchy-spotify-switch` | backend: `status`, `next [--from ID]`, `cached`, `login`, `logout` → `~/.local/bin/` |
| `bin/omarchy-spotify-switch-login` | the login helper |
| `~/.config/timon-spotify-switch/config.json` | `client_id`, `order` (yours, never in git) |
| `~/.local/state/timon-spotify-switch/token.json` | tokens: dir 700, file 600, written atomically |
| `~/.local/state/timon-spotify-switch/status.json` | the last status the bar shows (no tokens) |

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
