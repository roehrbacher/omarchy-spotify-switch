# Changelog

Versions match `manifest.json` and `VERSION`; each commit subject starts with its version.

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
