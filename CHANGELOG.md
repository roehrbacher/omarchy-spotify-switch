# Changelog

Versions match `manifest.json` and `VERSION`; each commit subject starts with its version.

## 0.3.1

- Right-clicking the big icon in the popup heading shows a short joke in
  the tagline (the switch is the icon in the bar). Another click gives
  the next line; the real tagline comes back after a few seconds, or at
  once if you actually switch.
- The bar icon (and the popup heading glyph) is nf-md-monitor_speaker
  (U+F0F5F) again. It is still dimmed when there is no other enabled,
  controllable device to switch to.

## 0.3.0

- Left click opens a popup of your Spotify Connect devices; right click
  still switches to the next enabled device. Each row has a switch to
  never switch to that device. Taglines name the state, the bar icon
  greys out when there is no other device to switch to, and the popup
  keeps a fixed size. While the popup is open, Spotify is re-read every
  10 seconds.
- The bar icon (and the popup heading glyph) is now nf-md-monitor_cellphone
  (U+F0989).

## 0.2.3

- While the popup is open, Spotify is re-read every 10 seconds (and not
  while a switch or a row switch is in flight). The 5-minute read still
  runs only while the popup is closed. The tagline and the list follow a
  status change at once, without closing and reopening.
- Taglines: paused is "Paused · switching keeps it paused"; no session is
  "Nothing playing"; every device off is "All devices are turned off";
  logged out / no client ID are short; offline, busy and error are one
  line, "Can't reach Spotify". "No other device to switch to" still wins
  over the playing or paused hint.

## 0.2.2

- The popup heading is "Spotify Device Switcher" and the line under it is a
  tagline per state, e.g. "Right click the icon to switch" while another
  device is on (list in the README).
- The bar icon is dimmed when there is no other enabled device to switch to
  (phone offline, the rest turned off, or only one device). It follows
  status reads and the switches.
- The popup keeps its size in every state: no message line any more.
  Messages replace the tagline for a few seconds, and the help line under
  the list is always the same text. Clicking a turned-off or restricted row
  does nothing and shows no text.

## 0.2.1

- Every device row in the popup ends in a switch (all on by default). Turn a
  device off and the switcher never moves playback to it: the right click
  skips it, the popup shows it dimmed ("Skipped") and doesn't let you pick
  it until you turn it back on. The device playing right now stays
  highlighted ("Playing · skipped") and the right click goes on from its
  place to the next device that is on. With every device off the right click
  says so and nothing moves.
- Keyboard: Right/Left move between a row and its switch, Space turns a
  device on or off, Enter picks it (on the switch: turns it on or off).
- The setting is the `disabled` list in `config.json` (id and name; matches by
  id, by name when Spotify gave the device a new id), saved atomically with
  mode 600. New commands `omarchy-spotify-switch enable ID` / `disable ID`.

## 0.2.0

- Left click now opens a popup with your Spotify Connect devices, built
  from Omarchy's stock panel parts (Bluetooth popup width, theme font and
  colours, keyboard: `j`/`k`, Enter, Esc, Tab, `r`). It shows the current
  state, each device with its type glyph, the active one highlighted, and
  restricted devices dimmed. Clicking a device moves playback there with
  the play state kept; the row says "Switching…" until Spotify answers.
  Empty, logged-out (with a login row), no-client-ID, Premium, offline and
  busy states are shown in the popup.
- Right click does what left click did before: move playback to the next
  device.
- While the popup is open, problems show in it instead of a notification.
- New backend command `omarchy-spotify-switch to ID` (and `to ID` on the
  helper's stdin): move playback to that device. A device that is gone is
  reported with the fresh list; it never falls back to another device.

## 0.1.6

- No hover tooltip on the bar icon any more, like Omarchy's own bar icons.
  The icon stays dimmed for errors, no device and logged out; a click that
  cannot switch or fails now shows a desktop notification with the reason,
  a click while logged out still opens the login, and a login that does not
  finish is notified. The `status` command keeps its `tooltip` text.
- Spotify is no longer read on hover (reads: start, clicks, every
  `refreshMinutes`, cache file events).
- The repo is now `roehrbacher/omarchy-spotify-device-switch`. Install
  backups moved to `~/.local/share/omarchy-config-backups/omarchy-spotify-device-switch/`
  (install.sh and uninstall.sh move an old `omarchy-spotify-switch` backup
  folder there). Plugin id `timon.spotify-switch` and the command names are
  unchanged.

## 0.1.5

- The icon is now the monitor-speaker glyph (nf-md-monitor_speaker,
  U+F0F5F); the `icon` setting is removed. An existing `icon` key in
  config.json or a bar entry is ignored.

## 0.1.4

- Docs: neutral description of the `icon` setting and of multiple bar
  entries in the README and changelog.

## 0.1.3

Pre-release review fixes, LICENSE and a public README.

- Fix: a malformed cached device list (hand edit, or an entry without a
  name) crashed the helper's click worker, so clicks were never answered
  and the icon stayed in "switching" for good. Cached lists are now
  validated (a bad one means a fresh read), and neither helper worker can
  die on an unexpected error any more (it answers with an error tooltip).
- Fix: the widget leaves the "click in flight" state after 15 s if no answer
  comes, and reads Spotify again, instead of ignoring every update.
- Fix: an idle connection to the one-shot login listener (any local
  program) blocked the real callback until the login timed out; requests
  now time out after 5 s.
- MIT LICENSE; README: requirements (Premium), Spotify app setup with your
  own client ID, PKCE, the redirect URI, trademark note.

## 0.1.2

- The icon is configurable: `"icon"` per bar entry (shell.json) or in
  config.json, as a preset (`spotify` default, `devices`,
  `monitor-speaker`), `U+XXXX`, or a glyph. Unknown values fall back to the
  Spotify logo.
- Several bar entries are allowed (`allowMultiple`), each with its own
  icon; a click on one updates the others through the cache file.

## 0.1.1

Clicks are fast: one PUT to Spotify instead of a Python start plus three
requests on fresh connections (measured on a laptop: about 0.6–1.2 s of our
own time before Spotify even started its handoff, now about 0.1 s plus
Spotify's PUT).

- New `omarchy-spotify-switch serve`: a long-lived helper the widget starts
  (exits with the shell). It keeps one HTTPS connection to Spotify open,
  refreshes the token in the background 10 min before it expires and takes
  clicks over stdin, so no Python start and no TLS handshake on a click.
- A click uses the cached device list and play state (refreshed in the
  background, on hover at most every 10 s, ~1.5 s after a transfer and every
  5 min); it reads the list again only on a 404 (device gone) and then moves
  to the next device that is there. Play state older than 15 s is read first.
- Paused sessions move without a `play` flag (Spotify keeps the state)
  instead of `play: false`.
- The optimistic icon/tooltip stays until the answer; Spotify still naming
  the old device for a moment after a transfer no longer flips it back (6 s
  window; a device picked elsewhere still wins).
- All HTTP goes through `http.client` with keep-alive; heavy imports are
  lazy (`cached` starts faster).
- Opt-in timing log (`"timing": true`): per-click stages and Spotify's
  handoff time.
- One-shot `next` and `status` still work and fall back the same way.

## 0.1.0

- First version: one Spotify icon (nf-fa-spotify) in the bar. Left click moves
  playback to the next Spotify Connect device in a fixed cycle (preferred
  `order` from the config, then alphabetical; wraps; skips restricted and
  missing devices), keeping the play/pause state. The tooltip names the
  current device or what is wrong (no device, one device, not logged in,
  Premium required, rate limited, offline).
- Shows the cached state at once and the click's target at once; reads
  Spotify at start, after clicks, on hover (≤ every 20 s) and every 5 min.
- Backend `omarchy-spotify-switch` (Python 3 standard library): `status`,
  `next`, `cached`, `login`, `logout`. Login with Authorization Code + PKCE
  on a one-shot `127.0.0.1:8888` listener; tokens in
  `~/.local/state/timon-spotify-switch/token.json` (700/600, atomic),
  refresh with rotation under a lock; 401/403/404/429/5xx/offline handled.
- Tests: backend vs. a fake Spotify, install/uninstall, QML cycle test,
  offscreen software render of the icon and tooltip, secrets check.
