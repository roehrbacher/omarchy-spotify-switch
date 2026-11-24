# Changelog

Versions match `manifest.json` and `VERSION`; each commit subject starts with its version.

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
