#!/bin/bash
# install.sh / uninstall.sh into a temp $HOME: files land, config created once
# (600) and never overwritten, --dry-run changes nothing, uninstall removes,
# --purge deletes tokens. Nothing outside the temp dir is touched.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stub"; printf '#!/bin/bash\n' >"$TMP/stub/xdg-open"; chmod +x "$TMP/stub/xdg-open"
run() { env -i HOME="$TMP/home" PATH="$TMP/stub:/usr/bin:/bin" bash "$@"; }
pass=0 fail=0
ok() { if eval "$2"; then echo "ok   $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
H=$TMP/home; mkdir -p "$H"
ok "dry run: lists, changes nothing" 'run "$HERE/install.sh" --dry-run | grep -q "would install" && [[ -z $(find "$H" -type f) ]]'
ok "install: exit 0" 'run "$HERE/install.sh" >/dev/null'
ok "  plugin files" '[[ -f $H/.config/omarchy/plugins/timon.spotify-switch/manifest.json && -f $H/.config/omarchy/plugins/timon.spotify-switch/SpotifySwitch.qml && -f $H/.config/omarchy/plugins/timon.spotify-switch/Cycle.js ]]'
ok "  helpers executable" '[[ -x $H/.local/bin/omarchy-spotify-switch && -x $H/.local/bin/omarchy-spotify-switch-login ]]'
ok "  config created 600 with empty client_id" '[[ $(stat -c %a "$H/.config/timon-spotify-switch/config.json") == 600 && $(jq -r .client_id "$H/.config/timon-spotify-switch/config.json") == "" ]]'
echo '{"client_id":"mine"}' >"$H/.config/timon-spotify-switch/config.json"
ok "reinstall keeps config, no new backup when unchanged" 'run "$HERE/install.sh" >/dev/null && [[ $(jq -r .client_id "$H/.config/timon-spotify-switch/config.json") == mine ]] && [[ $(ls -d "$H"/.local/share/omarchy-config-backups/omarchy-spotify-switch/backup-* | wc -l) == 1 ]]'
mkdir -p "$H/.local/state/timon-spotify-switch"; echo '{}' >"$H/.local/state/timon-spotify-switch/token.json"
ok "uninstall: plugin and helpers gone, token kept" 'run "$HERE/uninstall.sh" >/dev/null && [[ ! -e $H/.config/omarchy/plugins/timon.spotify-switch && ! -e $H/.local/bin/omarchy-spotify-switch && -e $H/.local/state/timon-spotify-switch/token.json ]]'
ok "uninstall --purge: tokens and config gone" 'run "$HERE/install.sh" >/dev/null && run "$HERE/uninstall.sh" --purge >/dev/null && [[ ! -e $H/.local/state/timon-spotify-switch && ! -e $H/.config/timon-spotify-switch ]]'
echo "install: $pass passed, $fail failed"
(( fail == 0 ))
