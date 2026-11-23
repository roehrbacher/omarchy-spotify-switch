#!/bin/bash
# Undo Spotify Switcher.
#   ./uninstall.sh          remove the plugin and helpers, restore what the first install replaced
#   ./uninstall.sh --last   only undo the last install/update (latest backup)
#   ./uninstall.sh --purge  like the default, and also delete tokens, cache and config
set -euo pipefail
ID=timon.spotify-switch
BKROOT="$HOME/.local/share/omarchy-config-backups/omarchy-spotify-switch"
if [[ ${1:-} == --last ]]; then
  BK=$(ls -d "$BKROOT"/backup-* 2>/dev/null | sort | tail -1)
  [[ -n $BK ]] || { echo "No backup found in $BKROOT"; exit 1; }
  [[ -f $BK/.new ]] && while read -r p; do rm -f "${HOME:?}/$p"; done <"$BK/.new"
  (cd "$BK" && find . -type f ! -name .new -print0 | while IFS= read -r -d '' f; do mkdir -p "$HOME/$(dirname "$f")"; cp -a "$f" "$HOME/$f"; done)
  echo "Restored $BK (the version before the last update)."; exit 0
fi
rm -rf "${HOME:?}/.config/omarchy/plugins/$ID"
rm -f "$HOME/.local/bin/omarchy-spotify-switch" "$HOME/.local/bin/omarchy-spotify-switch-login"
FIRST=$(ls -d "$BKROOT"/backup-* 2>/dev/null | sort | head -1)
if [[ -n $FIRST ]]; then
  (cd "$FIRST" && find . -type f ! -name .new -print0 | while IFS= read -r -d '' f; do mkdir -p "$HOME/$(dirname "$f")"; cp -a "$f" "$HOME/$f"; done)
fi
if [[ ${1:-} == --purge ]]; then
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/timon-spotify-switch" "${XDG_CONFIG_HOME:-$HOME/.config}/timon-spotify-switch"
  echo "Tokens, cache and config deleted."
fi
command -v omarchy-mark-reload-needed >/dev/null && omarchy-mark-reload-needed "Spotify Switcher removed" || true
echo "Removed $ID. Take \"$ID\" out of your bar (Omarchy settings) if it is listed."
