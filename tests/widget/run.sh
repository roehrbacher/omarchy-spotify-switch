#!/bin/bash
# timon.spotify-switch bar icon in an offscreen, software-rendered Quickshell
# with the real backend against the fake Spotify: cached state shows before
# Spotify answers, a click shows the next device at once and the backend
# follows, rapid clicks end on the last target, 403 Premium and one-device
# tooltips, logged-out state arrives via the cache file watch. Saves PNGs of
# the icon + tooltip when asked. Temp XDG dirs only.
#   bash tests/widget/run.sh [shots-dir]
#   OMARCHY_SHELL=<omarchy>/shell   Omarchy's shell sources (default /usr/share/omarchy/shell)
set -u
ulimit -c 0
here=$(cd "$(dirname "$0")" && pwd); root=$here/../..
command -v quickshell >/dev/null || { echo "SKIP: needs quickshell"; exit 77; }
shell=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
[[ -d $shell/Commons ]] || { echo "SKIP: no Omarchy shell sources at $shell (set OMARCHY_SHELL)"; exit 77; }
tmp=$(mktemp -d)
real_home=$HOME
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/config XDG_STATE_HOME=$tmp/state XDG_RUNTIME_DIR=$tmp/run XDG_CACHE_HOME=$tmp/cache
mkdir -p "$HOME" "$XDG_CONFIG_HOME/timon-spotify-switch" "$XDG_RUNTIME_DIR" "$tmp/qs" && chmod 700 "$XDG_RUNTIME_DIR"
# Fonts installed per user (the Nerd font on the box) stay visible.
[[ -d $real_home/.local/share/fonts ]] && mkdir -p "$HOME/.local/share" && ln -s "$real_home/.local/share/fonts" "$HOME/.local/share/fonts"
python3 "$root/tests/lib/fake_spotify.py" "$tmp/port" & fake=$!
qs=""
cleanup() { [[ -n $qs ]] && kill -KILL -- -"$qs" 2>/dev/null; kill "$fake" 2>/dev/null; wait 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT
for _ in $(seq 50); do [[ -s $tmp/port ]] && break; sleep 0.1; done
F=http://127.0.0.1:$(cat "$tmp/port")
export SPOTIFY_SWITCH_API=$F SPOTIFY_SWITCH_ACCOUNTS=$F PATH="$root/bin:$PATH"
fake() { curl -s -X POST --data "$1" "$F/test/state" >/dev/null; }
dev() { printf '{"id":"%s","name":"%s","type":"Computer","is_active":%s}' "$1" "$2" "${3:-false}"; }
echo '{"client_id":"test-client","order":["Pixel","gaming PC","XPS"],"icon":"devices"}' >"$XDG_CONFIG_HOME/timon-spotify-switch/config.json"
SD=$XDG_STATE_HOME/timon-spotify-switch; mkdir -p "$SD"; chmod 700 "$SD"
printf '{"access_token":"acc-0","refresh_token":"ref-0","expires_at":%d}\n' $(( $(date +%s) + 3600 )) >"$SD/token.json"; chmod 600 "$SD/token.json"
fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC'),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker'),$(dev ar Arcade)],\"playing\":true}"
omarchy-spotify-switch status >/dev/null               # last session's cache
fake '{"force":{"GET /v1/me/player/devices":[{"delay":1.5},{"delay":1.5}]}}'   # first reads (two bar entries) are slow
ln -s "$shell/Commons" "$tmp/qs/Commons"; ln -s "$shell/Ui" "$tmp/qs/Ui"
cp "$here/shell.qml" "$tmp/qs/shell.qml"
export SW_SRC=$root/plugin/timon.spotify-switch SW_SHOTS=${1:-$tmp}
mkdir -p "$SW_SHOTS"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software setsid timeout -s KILL 60 quickshell -p "$tmp/qs/shell.qml" >"$tmp/out" 2>&1 &
qs=$!
for _ in $(seq 500); do
  if grep -q 'SW CTL premium' "$tmp/out" && [[ ! -e $tmp/c1 ]]; then touch "$tmp/c1"
    fake '{"force":{"PUT /v1/me/player":[{"status":403,"body":{"error":{"status":403,"message":"Player command failed: Premium required","reason":"PREMIUM_REQUIRED"}}}]}}'; fi
  if grep -q 'SW CTL single' "$tmp/out" && [[ ! -e $tmp/c2 ]]; then touch "$tmp/c2"; fake "{\"devices\":[$(dev xps XPS true)]}"; fi
  if grep -q 'SW CTL logout' "$tmp/out" && [[ ! -e $tmp/c3 ]]; then touch "$tmp/c3"; omarchy-spotify-switch logout >/dev/null; fi
  grep -q 'SW RESULT' "$tmp/out" && break; kill -0 $qs 2>/dev/null || break; sleep 0.1
done
sleep 0.3
kill -KILL -- -"$qs" 2>/dev/null; wait "$qs" 2>/dev/null; qs=""
grep -E 'SW |rror|warn' "$tmp/out" | grep -v -e qt.qpa -e "SW CTL"
p=$(grep -c ' ok$' "$tmp/out"); f=$(grep -c 'want=.* FAIL$' "$tmp/out")
[[ -n ${1:-} ]] && ls "$SW_SHOTS"/[0-9]-*.png 2>/dev/null | sed 's/^/shot: /'
echo "widget: $p passed, $f failed"
grep -q 'SW RESULT PASS' "$tmp/out"
