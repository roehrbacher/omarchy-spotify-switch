#!/bin/bash
# Install or update Spotify Switcher (timon.spotify-switch) for this user.
# Backs up every file it replaces to
#   ~/.local/share/omarchy-config-backups/omarchy-spotify-switch/backup-<time>/
# (uninstall.sh restores it). Never touches shell.json, never restarts the
# shell, never overwrites your config.json or tokens.
#   ./install.sh            install / update
#   ./install.sh --dry-run  only list what would change
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -ne 0 ]] || { echo "Run as your user, not root."; exit 1; }
DRY=0; [[ ${1:-} == --dry-run ]] && DRY=1
for c in python3 xdg-open; do command -v "$c" >/dev/null || { echo "Needs $c."; exit 1; }; done
ID=timon.spotify-switch
BKROOT="$HOME/.local/share/omarchy-config-backups/omarchy-spotify-switch"
BK="$BKROOT/backup-$(date +%Y%m%d-%H%M%S)"
put() { # put <src> <dest under $HOME> <mode>
  local dest="$HOME/$2"
  if [[ -e $dest ]] && cmp -s "$1" "$dest"; then return 0; fi
  if (( DRY )); then echo "would install ~/$2"; return 0; fi
  mkdir -p "$BK"
  if [[ -e $dest ]]; then mkdir -p "$BK/$(dirname "$2")"; cp -a "$dest" "$BK/$2"; else echo "$2" >>"$BK/.new"; fi
  mkdir -p "$(dirname "$dest")"
  install -m "$3" "$1" "$dest.new.$$" && mv -f "$dest.new.$$" "$dest"   # atomic
  echo "installed ~/$2"
}
for f in bin/*; do put "$f" ".local/bin/${f#bin/}" 755; done
for f in $(cd plugin && find "$ID" -type f); do put "plugin/$f" ".config/omarchy/plugins/$f" 644; done
CFG="$HOME/.config/timon-spotify-switch/config.json"
if [[ ! -e $CFG ]]; then
  if (( DRY )); then echo "would create ~/.config/timon-spotify-switch/config.json (empty client_id)"
  else mkdir -p "$(dirname "$CFG")"; install -m 600 config.example.json "$CFG"; echo "created $CFG (add your client_id)"; fi
fi
(( DRY )) && exit 0
[[ -d $BK ]] && echo "Backup: $BK"
command -v omarchy-mark-reload-needed >/dev/null && omarchy-mark-reload-needed "Spotify Switcher $(cat VERSION) installed" || true
echo "Next: put your Spotify client_id in $CFG, run omarchy-spotify-switch-login,"
echo "then add \"$ID\" to your bar (Omarchy settings) and click the reload icon when it suits you."
