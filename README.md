# Spotify Switcher for Omarchy

One bar icon in the Omarchy bar (`timon.spotify-switch`).

- **Left click** opens a popup with your Spotify Connect devices. Click one
  (or move with `j`/`k` and press Enter) and playback moves there.
- **Right click** moves playback straight to the next device, no popup.
- Each row ends in a **switch**. Turn it off and the switcher never moves
  playback to that device (a Fire TV stick you don't want music on, say).
  All devices are on by default.

Like Omarchy's own bar icons it has no hover tooltip.

## The popup

The popup is built from Omarchy's own panel parts, like the Bluetooth
popup: same width, font and theme colours. At the top is the heading
"Spotify Device Switcher" with a one-line tagline for the state, then the
devices in the same fixed order the right click cycles through (see below).
Each row has the device type glyph and name; the active device is
highlighted and says "Playing" or "Active". Devices Spotify marks as
restricted are dimmed, say "Not controllable" and cannot be picked.

- **The switch is its own click target:** clicking the row picks the device,
  clicking the switch only turns it on or off. With the keyboard, Right moves
  the cursor onto the row's switch and Left back; Space turns the device on or
  off (on the row or on the switch), Enter picks the device (on the switch it
  turns it on or off).
- A device that is off stays in the list, dimmed, and says "Skipped"; it
  can't be picked until you turn it on again. If it is the device playing
  right now it stays highlighted and says "Playing · skipped", and the right
  click goes on from its place to the next device that is on.
- If no other device is on, the right click does nothing (a notification
  says so) and the bar icon is dimmed. Playback stays where it is.
- Clicking a device moves playback there at once: the row says
  "Switching…" until Spotify answers. **The play state is kept** like on a
  right click. Clicking the active device does nothing.
- If the device left in the meantime, the tagline says so for a few seconds
  and the list is the fresh one; playback is never moved to a different
  device by surprise. Clicking a row that is off or not controllable does
  nothing at all.
- The popup opens with the last known state at once and reads Spotify
  again on opening (`r` reads again). While it stays open it re-reads
  every 10 seconds, so play/pause and devices coming or going show up in
  the tagline and the list without closing it. `Esc` closes it, `Tab`
  moves to the next popup, as in Omarchy's other popups.
- With no devices it says how to make one show up; logged out it shows a
  "Log in to Spotify" row that opens the login in your browser; without a
  client ID it says where to put it. While the popup is open, problems
  (Premium needed, offline, busy) show in the tagline instead of a
  notification.
- **The popup never changes size because of a message.** Messages replace
  the tagline (for a few seconds) and the help line under the list is always
  the same text, so the popup is exactly as tall in every state that lists
  the same devices.

Taglines:

| State | Tagline |
| --- | --- |
| playing, another device is on | RIGHT CLICK THE ICON TO SWITCH |
| paused, another device is on | PAUSED · SWITCHING KEEPS IT PAUSED |
| no other device is on (offline, switched off, or only one) | NO OTHER DEVICE TO SWITCH TO |
| every device is switched off | ALL DEVICES ARE TURNED OFF |
| no active session | NOTHING PLAYING |
| a switch in flight | SWITCHING TO <device> |
| logged out | NOT LOGGED IN |
| no client ID | NO CLIENT ID |
| Premium needed (after a failed transfer) | PREMIUM NEEDED TO SWITCH |
| offline, busy or error | CAN'T REACH SPOTIFY |
| no devices | OPEN SPOTIFY ON A DEVICE |

## Turned-off devices

The setting is saved in `~/.config/timon-spotify-switch/config.json` (written
atomically, mode 600, your other settings untouched):

```
"disabled": [{"id": "<device id>", "name": "Kurt's Fire TV"}]
```

An entry matches a device by its id. Spotify can give a device a new id
(a reinstalled app, a reset stick); when the entry's id is no longer in
Spotify's list, the entry matches by name instead (case-insensitive, whole
name), and turning the device off or on again stores the new id. Two devices
with the same name: the one whose id matches is the one that is off. You can
also edit the list by hand (a plain name string works as an entry), or use
`omarchy-spotify-switch disable ID` / `enable ID`.

## What a right click does

1. Takes the devices Spotify Connect lists (`GET /v1/me/player/devices`,
   kept fresh in the background, see Speed). Spotify only lists devices
   where Spotify is open or was active lately, so the cycle runs over
   whatever is there; a missing device is skipped, and a device that left
   since the last read is noticed by the PUT's 404.
2. Puts them in a **fixed order**: first the names from `order` in the
   config, in that order (an entry matches a device whose name equals it or
   starts with it, ignoring case, so `"Pixel"` matches "Pixel 10 Pro"), then
   all other devices alphabetically (ignoring case; equal names by device
   id). Devices Spotify marks as restricted, and devices you turned off, are
   skipped.
3. Picks the device after the one playing now and wraps around at the end.
   With no active device it picks the first one that is on.
4. Moves playback there (`PUT /v1/me/player`). **The play state is kept**:
   if music was playing it keeps playing on the new device (`play: true`);
   if it was paused, or nothing was active, the `play` flag is left out,
   which Spotify documents as "keep the current state", so a click never
   starts music by surprise.

With only one device available, a right click just shows a notification "XPS (only
device available)". (One device that is *not* active yet is the
"none active" case: the click moves playback to it.)

The icon is lit while a device has the session and there is another device
to switch to, and dimmed (stock `WidgetButton.dimmed`) when there is no
device, you are not logged in, something failed, or no other device is on
(offline, turned off, or only one). When a click cannot switch, or the switch fails, a desktop
notification (`notify-send`, app "Spotify Switcher") says why (in the popup
instead, while it is open); a successful switch shows none. A right click
while logged out opens the login in your browser,
and a login that does not finish is notified too. `omarchy-spotify-switch
status` prints the current state as JSON; its `tooltip` field holds the same
text:

| Text | Meaning |
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

The icon is the Nerd Font glyph nf-md-monitor_speaker (U+F0F5F) from the
font the bar already uses, so it follows the theme colour and the stock
dim/lit states. It is fixed; an `"icon"` key left over in `config.json` or
in a bar entry is ignored. The same glyph is in the popup heading. When
there is no other enabled, controllable device to switch to, the icon is
dimmed; there is no second glyph for that state.

## Speed

A click costs **one PUT** to Spotify, with no process start, no device
list read, no play-state read and no token refresh on the way:

- The widget runs one long-lived helper, `omarchy-spotify-switch serve`
  (it exits with the shell). It keeps an HTTPS connection to Spotify open,
  refreshes the access token ahead of time (10 minutes before it expires, in
  the background) and keeps the device list and play state in the cache.
- On a click the widget switches to the target at once. The helper
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
- Spotify is read at start, after clicks, every 10 seconds while the popup
  is open, and every 5 minutes while it is closed. Spotify has no push channel for
  "playback moved to another device" (e.g. you picked the phone in the
  Spotify app), so without that slow refresh the dim/lit state could stay
  wrong for hours; 5 minutes is two small HTTPS requests per bar, far from
  Spotify's rate limits. Set `"refreshMinutes": 0` in the widget's
  shell.json entry to turn it off, or another number of minutes.
- A pick in the popup is the same single PUT to the chosen device
  (`to <device-id>` on the helper's stdin).
- If the helper is not running, clicks fall back to one-shot
  `omarchy-spotify-switch next` or `to ID` runs (Python start, same cache
  logic).

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
- `python3` (standard library only), `xdg-open` and `notify-send`, all part
  of Omarchy.

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

1. `git clone https://github.com/roehrbacher/omarchy-spotify-device-switch ~/Work/omarchy-spotify-device-switch`
2. `cd ~/Work/omarchy-spotify-device-switch && ./install.sh` (`--dry-run` lists the
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
`~/.local/share/omarchy-config-backups/omarchy-spotify-device-switch/`.

## Files

| Path | What |
| --- | --- |
| `plugin/timon.spotify-switch/` | the bar widget (`SpotifySwitch.qml`, `Cycle.js`, `manifest.json`) → `~/.config/omarchy/plugins/` |
| `bin/omarchy-spotify-switch` | backend: `status`, `next [--from ID]`, `to ID`, `enable ID`, `disable ID`, `serve`, `cached`, `login`, `logout` → `~/.local/bin/` |
| `bin/omarchy-spotify-switch-login` | the login helper |
| `~/.config/timon-spotify-switch/config.json` | `client_id`, `order`, `disabled` (yours, never in git) |
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
The bar icon is a glyph from [Nerd Fonts](https://www.nerdfonts.com)
(Material Design Icons set), not Spotify artwork.

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
