#!/bin/bash
# Backend tests against a fake Spotify on 127.0.0.1 (tests/lib/fake_spotify.py):
# cycle order, wrap-around, no/one device, play state, token refresh and
# rotation, 401/403/404/429/5xx, offline, login (PKCE, one-shot listener),
# token file perms. Temp XDG dirs only; never talks to the real Spotify.
#   bash tests/backend.test.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
export XDG_CONFIG_HOME=$TMP/config XDG_STATE_HOME=$TMP/state HOME=$TMP/home
mkdir -p "$XDG_CONFIG_HOME/timon-spotify-switch" "$HOME" "$TMP/stub"
CFG=$XDG_CONFIG_HOME/timon-spotify-switch/config.json
SD=$XDG_STATE_HOME/timon-spotify-switch
B="$HERE/bin/omarchy-spotify-switch"
python3 "$HERE/tests/lib/fake_spotify.py" "$TMP/port" & FAKE=$!
cleanup() { kill "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
for _ in $(seq 50); do [[ -s $TMP/port ]] && break; sleep 0.1; done
P=$(cat "$TMP/port"); F=http://127.0.0.1:$P
export SPOTIFY_SWITCH_API=$F SPOTIFY_SWITCH_ACCOUNTS=$F
pass=0 fail=0
ok() { if eval "$2"; then echo "ok   $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
fake() { curl -s -X POST --data "$1" "$F/test/state" >/dev/null; }
fstate() { curl -s "$F/test/state" | jq -r "$1"; }
flog() { curl -s "$F/test/log"; }
logcount() { flog | jq "[.[] | select(.req == \"$1\")] | length"; }
put_body() { flog | jq -r '[.[] | select(.req == "PUT /v1/me/player")] | last | .body'; }
token() { # token <access> <refresh> <expires_in_s>
  mkdir -p "$SD"; chmod 700 "$SD"
  printf '{"access_token":"%s","refresh_token":"%s","expires_at":%d}\n' "$1" "$2" $(( $(date +%s) + $3 )) >"$SD/token.json"
  chmod 600 "$SD/token.json"
}
dev() { printf '{"id":"%s","name":"%s","type":"Computer","is_active":%s,"is_restricted":%s}' "$1" "$2" "${3:-false}" "${4:-false}"; }
five() { fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC'),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker'),$(dev ar Arcade)],\"playing\":true}"; }
names() { jq -r '[.devices[].name] | join(",")'; }
perm() { stat -c %a "$1"; }

# --- config / login state ---
ok "no client ID -> no_client_id" '[[ $("$B" status | jq -r .state) == no_client_id ]]'
echo '{"client_id":"test-client","order":["Pixel","gaming PC","XPS"]}' >"$CFG"
ok "no token -> need_login, tooltip says how" '"$B" status | jq -e ".state == \"need_login\" and (.tooltip | test(\"omarchy-spotify-switch-login\"))" >/dev/null'
ok "env client ID overrides config" 'SPOTIFY_SWITCH_CLIENT_ID=env-client "$B" status | jq -e ".state == \"need_login\"" >/dev/null'
ok "API override must be 127.0.0.1" '! SPOTIFY_SWITCH_API=https://example.com "$B" status >/dev/null 2>&1'

# --- cycle order ---
token acc-0 ref-0 3600; five
S=$("$B" status)
ok "preferred order, then the rest alphabetically" '[[ $(names <<<"$S") == "Pixel 10 Pro,gaming PC,XPS,Arcade,Kitchen speaker" ]]'
ok "status: current device and tooltip" '[[ $(jq -r ".device.name + \"|\" + .tooltip" <<<"$S") == "XPS|Spotify: XPS" ]]'
ok "status: next is precomputed (XPS -> Arcade)" '[[ $(jq -r .next.name <<<"$S") == Arcade ]]'
ok "status writes the cache, 600 in a 700 dir" '[[ $(jq -r .device.name "$SD/status.json") == XPS && $(perm "$SD/status.json") == 600 && $(perm "$SD") == 700 ]]'
ok "cached: same status without network" '[[ $("$B" cached | jq -r .device.name) == XPS ]]'
N=$("$B" next)
ok "next: XPS -> Arcade" '[[ $(jq -r ".state + \"|\" + .device.name" <<<"$N") == "ok|Arcade" && $(fstate ".devices[] | select(.is_active) | .id") == ar ]]'
ok "next keeps playing (play:true)" '[[ $(put_body | jq -c .) == "{\"device_ids\":[\"ar\"],\"play\":true}" ]]'
"$B" next >/dev/null
ok "next: Arcade -> Kitchen speaker" '[[ $(fstate ".devices[] | select(.is_active) | .name") == "Kitchen speaker" ]]'
ok "next: wraps Kitchen speaker -> Pixel 10 Pro" '[[ $("$B" next | jq -r .device.name) == "Pixel 10 Pro" ]]'
ok "next: Pixel -> gaming PC" '[[ $("$B" next | jq -r .device.name) == "gaming PC" ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC'),$(dev px Pixel)]}"
ok "next --from px (stale server state) -> gaming PC" '[[ $("$B" next --from px | jq -r .device.name) == "gaming PC" ]]'
echo '{"client_id":"test-client"}' >"$CFG"; five
ok "no order configured: alphabetical (case-insensitive)" '[[ $("$B" status | names) == "Arcade,gaming PC,Kitchen speaker,Pixel 10 Pro,XPS" ]]'
ok "alphabetical next wraps XPS -> Arcade" '[[ $("$B" next | jq -r .device.name) == Arcade ]]'
fake "{\"devices\":[$(dev b Bravo),$(dev a2 Alpha),$(dev a1 Alpha)]}"
ok "equal names stay in a stable order (by id)" '[[ $("$B" status | jq -r "[.devices[].id] | join(\",\")") == "a1,a2,b" ]]'
echo '{"client_id":"test-client","order":["Pixel","gaming PC","XPS"]}' >"$CFG"

# --- no active / one / none / restricted ---
fake "{\"devices\":[$(dev xps XPS),$(dev px 'Pixel 10 Pro')],\"playing\":false}"
ok "no active device: status says so" '"$B" status | jq -e ".device == null and (.tooltip | test(\"no active device\"))" >/dev/null'
ok "no active device: next -> first in cycle" '[[ $("$B" next | jq -r .device.name) == "Pixel 10 Pro" ]]'
ok "nothing was playing: no play flag (Spotify keeps it paused)" '[[ $(put_body | jq -c "has(\"play\")") == false ]]'
fake "{\"devices\":[$(dev xps XPS true)],\"playing\":true}"; "$B" status >/dev/null
before=$(logcount "PUT /v1/me/player")
ok "single active device: tooltip says so" '[[ $("$B" next | jq -r .tooltip) == "Spotify: XPS (only device available)" ]]'
ok "single active device: no transfer" '[[ $(logcount "PUT /v1/me/player") == "$before" ]]'
fake "{\"devices\":[$(dev xps XPS)]}"; "$B" status >/dev/null
ok "single inactive device: next plays there" '[[ $("$B" next | jq -r .device.name) == XPS ]]'
fake '{"devices":[]}'; "$B" status >/dev/null
before=$(logcount "PUT /v1/me/player")
ok "no devices: no_device, no transfer" '[[ $("$B" next | jq -r .state) == no_device && $(logcount "PUT /v1/me/player") == "$before" ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev tv TV false true),$(dev px Pixel)]}"; "$B" status >/dev/null
ok "restricted device skipped (XPS -> Pixel, not TV)" '[[ $("$B" next | jq -r .device.name) == Pixel ]]'
fake "{\"devices\":[$(dev xps XPS true),{\"id\":null,\"name\":\"Ghost\",\"is_active\":false},$(dev px Pixel)]}"
ok "device without id ignored" '[[ $("$B" status | names) == "Pixel,XPS" ]]'

# --- tokens ---
five; token old-acc ref-0 -10; fake '{"access":"acc-0","refresh":"ref-0","rotate":true,"n":0}'
r0=$(logcount "POST /api/token")
ok "expired access token: refreshed, call succeeds" '[[ $("$B" status | jq -r .state) == ok ]]'
ok "  one refresh" '[[ $(( $(logcount "POST /api/token") - r0 )) == 1 ]]'
ok "  rotated refresh token saved" '[[ $(jq -r .refresh_token "$SD/token.json") == ref-1 && $(jq -r .access_token "$SD/token.json") == acc-1 ]]'
ok "  token.json 600, state dir 700, no temp files left" '[[ $(perm "$SD/token.json") == 600 && $(perm "$SD") == 700 && -z $(find "$SD" -name ".tmp-*") ]]'
ok "  refresh sends client_id, no secret" 'flog | jq -r "[.[] | select(.req == \"POST /api/token\")] | last | .body" | grep -q "client_id=test-client" && ! flog | jq -r ".[].body" | grep -qi secret'
fake '{"rotate":false}'; token old-acc ref-1 -10
ok "no rotation: old refresh token kept" '"$B" status >/dev/null; [[ $(jq -r .refresh_token "$SD/token.json") == ref-1 ]]'
token revoked-acc ref-1 3600
r0=$(logcount "POST /api/token")
ok "401 on a fresh-looking token: refresh + retry" '[[ $("$B" status | jq -r .state) == ok && $(( $(logcount "POST /api/token") - r0 )) == 1 ]]'
fake '{"force":{"GET /v1/me/player/devices":[{"status":401},{"status":401}]}}'
ok "401 again after refresh -> need_login" '[[ $("$B" status | jq -r .state) == need_login ]]'
token old-acc ref-wrong -10
ok "refresh rejected (invalid_grant) -> need_login" '"$B" status | jq -e ".state == \"need_login\" and (.tooltip | test(\"expired\"))" >/dev/null'
fake '{"rotate":true}'; token old-acc "$(fstate .refresh)" -10
r0=$(logcount "POST /api/token")
pids=(); for i in 1 2 3 4; do "$B" status >"$TMP/par$i" & pids+=($!); done; wait "${pids[@]}"
ok "4 parallel calls with an expired token: one refresh (lock), all ok" '[[ $(( $(logcount "POST /api/token") - r0 )) == 1 ]] && [[ $(cat "$TMP"/par* | jq -r .state | sort -u) == ok ]]'
ok "cache holds no tokens" '! grep -qE "acc-|ref-|access_token|refresh_token" "$SD/status.json"'

# --- API errors ---
token "$(fstate .access)" "$(fstate .refresh)" 3600; five
fake '{"force":{"GET /v1/me/player/devices":[{"status":429,"headers":{"Retry-After":"1"}}]}}'
t0=$(date +%s%N)
ok "429 Retry-After 1: waits, retries, ok" '[[ $("$B" status | jq -r .state) == ok ]]'
ok "  waited about 1 s" '(( ($(date +%s%N) - t0) / 1000000 >= 900 ))'
fake '{"force":{"GET /v1/me/player/devices":[{"status":429,"headers":{"Retry-After":"30"}}]}}'
t0=$(date +%s%N); R=$("$B" status)
ok "429 Retry-After 30: rate_limited at once, tooltip says 30s" '[[ $(jq -r .state <<<"$R") == rate_limited && $(jq -r .tooltip <<<"$R") == *30s* ]] && (( ($(date +%s%N) - t0) / 1000000 < 3000 ))'
ok "  last known device kept" '[[ $(jq -r .device.name <<<"$R") == XPS ]]'
fake '{"force":{"PUT /v1/me/player":[{"status":403,"body":{"error":{"status":403,"message":"Player command failed: Premium required","reason":"PREMIUM_REQUIRED"}}}]}}'
ok "403 PREMIUM_REQUIRED -> premium, clear tooltip" '[[ $("$B" next | jq -r ".state + \"|\" + .tooltip") == "premium|Spotify: Premium needed to switch devices" ]]'
five; "$B" status >/dev/null
fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC'),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker')]}"
g0=$(logcount "GET /v1/me/player/devices")
ok "404 (Arcade left, cache still lists it): re-read once, moves to the next one there" '[[ $("$B" next | jq -r .device.name) == "Kitchen speaker" && $(( $(logcount "GET /v1/me/player/devices") - g0 )) == 1 ]]'
"$B" status >/dev/null
fake '{"force":{"PUT /v1/me/player":[{"status":404,"body":{"error":{"status":404}}},{"status":404,"body":{"error":{"status":404}}}]}}'
ok "404 twice -> says the device is no longer available" '[[ $("$B" next | jq -r .tooltip) == *"is no longer available" ]]'
fake '{"force":{"GET /v1/me/player/devices":[{"status":502}]}}'
ok "5xx -> error" '[[ $("$B" status | jq -r .state) == error ]]'
five; "$B" status >/dev/null
DEAD=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
R=$(SPOTIFY_SWITCH_API=http://127.0.0.1:$DEAD "$B" status)
ok "network down -> offline, last device in tooltip" '[[ $(jq -r .state <<<"$R") == offline && $(jq -r .tooltip <<<"$R") == "Spotify: XPS (offline, last known)" ]]'

# --- the click path (0.1.1): one PUT, cached list and play state ---
token "$(fstate .access)" "$(fstate .refresh)" 3600; five; "$B" status >/dev/null
n0=$(flog | jq length)
"$B" next >/dev/null
ok "fresh cache: a click is exactly one request, the PUT" '[[ $(flog | jq -c "[.[$n0:][] | .req]") == "[\"PUT /v1/me/player\"]" ]]'
ok "  cached playing -> play:true" '[[ $(put_body | jq -c .play) == true ]]'
"$B" status >/dev/null
jq '.read_ms -= 20000' "$SD/status.json" >"$TMP/c" && mv "$TMP/c" "$SD/status.json"
n0=$(flog | jq length); "$B" next >/dev/null
ok "play state older than 15 s: GET /me/player, then PUT (no device list)" '[[ $(flog | jq -c "[.[$n0:][] | .req]") == "[\"GET /v1/me/player\",\"PUT /v1/me/player\"]" ]]'
"$B" status >/dev/null
jq '.read_ms -= 700000' "$SD/status.json" >"$TMP/c" && mv "$TMP/c" "$SD/status.json"
n0=$(flog | jq length); "$B" next >/dev/null
ok "device list older than 10 min: read again first" '[[ $(flog | jq -c "[.[$n0:][] | .req] | .[0]") == "\"GET /v1/me/player/devices\"" ]]'
rm -f "$SD/status.json"; n0=$(flog | jq length)
ok "no cache at all: reads the list, then moves" '[[ $("$B" next | jq -r .state) == ok && $(flog | jq -c "[.[$n0:][] | .req] | .[0]") == "\"GET /v1/me/player/devices\"" ]]'
five; "$B" status >/dev/null; "$B" next >/dev/null   # XPS -> Arcade
fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC'),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker'),$(dev ar Arcade)]}"
ok "Spotify still names the old device right after a transfer: the target stays" '[[ $("$B" status | jq -r .device.name) == Arcade ]]'
fake "{\"devices\":[$(dev xps XPS),$(dev pc 'gaming PC' true),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker'),$(dev ar Arcade)]}"
ok "  but a different device (picked elsewhere) wins at once" '[[ $("$B" status | jq -r .device.name) == "gaming PC" ]]'
"$B" next >/dev/null   # gaming PC -> XPS
fake "{\"devices\":[$(dev xps XPS),$(dev pc 'gaming PC' true),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker'),$(dev ar Arcade)]}"
jq '.transfer.at_ms -= 7000' "$SD/status.json" >"$TMP/c" && mv "$TMP/c" "$SD/status.json"
ok "  and after 6 s Spotify's word counts again" '[[ $("$B" status | jq -r .device.name) == "gaming PC" ]]'

# --- to ID: the popup's choice (0.2.0) ---
token "$(fstate .access)" "$(fstate .refresh)" 3600; five; "$B" status >/dev/null
n0=$(flog | jq length)
T=$("$B" to px)
ok "to px: XPS -> Pixel 10 Pro (not the cycle's next), ok" '[[ $(jq -r ".state + \"|\" + .device.name" <<<"$T") == "ok|Pixel 10 Pro" && $(fstate ".devices[] | select(.is_active) | .id") == px ]]'
ok "  fresh cache: exactly one request, the PUT, keeps playing" '[[ $(flog | jq -c "[.[$n0:][] | .req]") == "[\"PUT /v1/me/player\"]" && $(put_body | jq -c .) == "{\"device_ids\":[\"px\"],\"play\":true}" ]]'
ok "  cache updated: Pixel active, transfer recorded" '[[ $(jq -r ".device.id + \"|\" + .transfer.id + \"|\" + .transfer.from" "$SD/status.json") == "px|px|xps" ]]'
before=$(logcount "PUT /v1/me/player")
ok "to the active device: no transfer, says where it plays" '[[ $("$B" to px | jq -r ".state + \"|\" + .tooltip") == "ok|Spotify: Pixel 10 Pro" && $(logcount "PUT /v1/me/player") == "$before" ]]'
rm -f "$SD/status.json"   # no 6 s trust window from the last transfer
fake "{\"devices\":[$(dev xps XPS true),$(dev px Pixel)],\"playing\":false}"; "$B" status >/dev/null
"$B" to px >/dev/null
ok "paused stays paused: no play flag" '[[ $(put_body | jq -c "has(\"play\")") == false && $(fstate ".devices[] | select(.is_active) | .id") == px ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev tv TV false true)]}"; "$B" status >/dev/null
before=$(logcount "PUT /v1/me/player")
ok "to a restricted device: refused with a reason, no PUT" '[[ $("$B" to tv | jq -r .tooltip) == "Spotify: TV can'"'"'t be controlled from here" && $(logcount "PUT /v1/me/player") == "$before" ]]'
five; "$B" status >/dev/null
g0=$(logcount "GET /v1/me/player/devices"); before=$(logcount "PUT /v1/me/player")
ok "to an id not in the cache: reads the list once, then says it is gone" '[[ $("$B" to nope | jq -r .tooltip) == "Spotify: that device is no longer available" && $(( $(logcount "GET /v1/me/player/devices") - g0 )) == 1 && $(logcount "PUT /v1/me/player") == "$before" ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC'),$(dev px 'Pixel 10 Pro'),$(dev ks 'Kitchen speaker'),$(dev ar Arcade),$(dev new 'New speaker')]}"
ok "to a device that just appeared (not cached yet): found on the re-read, moves" '[[ $("$B" to new | jq -r .device.name) == "New speaker" ]]'
five; "$B" status >/dev/null
fake "{\"devices\":[$(dev xps XPS true),$(dev pc 'gaming PC')]}"
ok "404 (chosen device left): fresh list, no move to another device" 'R=$("$B" to ar); [[ $(jq -r .tooltip <<<"$R") == "Spotify: Arcade is no longer available" && $(jq -r "[.devices[].id] | join(\",\")" <<<"$R") == "pc,xps" && $(fstate ".devices[] | select(.is_active) | .id") == xps ]]'
fake '{"force":{"PUT /v1/me/player":[{"status":403,"body":{"error":{"status":403,"message":"Player command failed: Premium required","reason":"PREMIUM_REQUIRED"}}}]}}'
five; "$B" status >/dev/null
ok "to with 403 Premium -> premium state, reason in the text" '[[ $("$B" to ar | jq -r ".state + \"|\" + .tooltip") == "premium|Spotify: Premium needed to switch devices" ]]'
ok "to without an id: usage, exit 2" '"$B" to >/dev/null 2>&1; [[ $? == 2 ]]'

# --- disabled devices: never switch to them (0.2.1) ---
cp "$CFG" "$TMP/cfg.keep"; rm -f "$SD/status.json"
token "$(fstate .access)" "$(fstate .refresh)" 3600; five; "$B" status >/dev/null
ok "all devices are enabled by default" '"$B" status | jq -e "[.devices[].enabled] | all" >/dev/null'
D=$("$B" disable ar)
ok "disable ar: config gets {id, name}, client_id and order stay" '[[ $(jq -c ".disabled" "$CFG") == "[{\"id\":\"ar\",\"name\":\"Arcade\"}]" && $(jq -r ".client_id" "$CFG") == test-client && $(jq -c .order "$CFG") == "[\"Pixel\",\"gaming PC\",\"XPS\"]" ]]'
ok "  config.json stays mode 600 and valid, no temp file left" '[[ $(perm "$CFG") == 600 ]] && jq -e . "$CFG" >/dev/null && [[ $(ls -A "$(dirname "$CFG")" | wc -l) == 1 ]]'
ok "  the cache shows it at once (Arcade off, next skips it)" '[[ $(jq -r ".devices[] | select(.id == \"ar\") | .enabled" "$SD/status.json") == false && $(jq -r .next.name "$SD/status.json") == "Kitchen speaker" ]]'
ok "  prints what changed" '[[ $(jq -c . <<<"$D") == "{\"id\":\"ar\",\"name\":\"Arcade\",\"enabled\":false}" ]]'
ok "status marks it: only Arcade is disabled" '[[ $("$B" status | jq -r "[.devices[] | select(.enabled | not) | .name] | join(\",\")") == Arcade ]]'
ok "disabling twice adds no second entry" '"$B" disable ar >/dev/null; [[ $(jq ".disabled | length" "$CFG") == 1 ]]'
ok "next skips the disabled device (XPS -> Kitchen speaker, not Arcade)" '[[ $("$B" next | jq -r .device.name) == "Kitchen speaker" ]]'
"$B" disable ks >/dev/null
ok "the active device may be disabled: it stays active and shown" '[[ $("$B" status | jq -r "(.device.name) + \"|\" + (.device.enabled | tostring)") == "Kitchen speaker|false" ]]'
ok "  cycling from it goes to the next enabled one (wraps to Pixel 10 Pro)" '[[ $("$B" next | jq -r .device.name) == "Pixel 10 Pro" ]]'
before=$(logcount "PUT /v1/me/player")
ok "to a disabled device: refused with a reason, no PUT" '[[ $("$B" to ar | jq -r .tooltip) == "Spotify: Arcade is turned off for switching" && $(logcount "PUT /v1/me/player") == "$before" ]]'
ok "enable ar: entry gone, other entries stay" '"$B" enable ar >/dev/null; [[ $(jq -c "[.disabled[].id]" "$CFG") == "[\"ks\"]" ]]'
ok "  next can reach Arcade again" '[[ $("$B" to ar | jq -r .device.name) == Arcade ]]'
ok "enable the last one: the key disappears, the rest of the config stays" '"$B" enable ks >/dev/null; jq -e "has(\"disabled\") | not" "$CFG" >/dev/null && [[ $(jq -r .client_id "$CFG") == test-client ]]'
# The id can change: a name entry matches when its id is not in Spotify's list.
"$B" disable ar >/dev/null
fake "{\"devices\":[$(dev xps XPS true),$(dev ar2 Arcade),$(dev pc 'gaming PC')]}"
ok "id changed (ar -> ar2), same name: still disabled" '[[ $("$B" status | jq -r "[.devices[] | select(.enabled | not) | .id] | join(\",\")") == ar2 ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev ar 'Arcade (renamed)'),$(dev pc 'gaming PC')]}"
ok "name changed, same id: still disabled (the id wins)" '[[ $("$B" status | jq -r "[.devices[] | select(.enabled | not) | .id] | join(\",\")") == ar ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev ar Arcade),$(dev ar3 Arcade)]}"
ok "two devices with one name: the id match wins, the other stays enabled" '[[ $("$B" status | jq -r "[.devices[] | select(.enabled | not) | .id] | join(\",\")") == ar ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev ar2 Arcade)]}"; "$B" status >/dev/null
ok "disable by a new id refreshes the stored id of the name match" '"$B" disable ar2 >/dev/null; [[ $(jq -c "[.disabled[] | .id]" "$CFG") == "[\"ar2\"]" ]]'
ok "a hand-written name entry works too" 'echo "{\"client_id\":\"test-client\",\"disabled\":[\"arcade\"]}" >"$CFG"; [[ $("$B" status | jq -r "[.devices[] | select(.enabled | not) | .id] | join(\",\")") == ar2 ]]'
five; "$B" status >/dev/null
for i in xps pc px ks ar; do "$B" disable $i >/dev/null; done
before=$(logcount "PUT /v1/me/player")
A=$("$B" next)
ok "every device disabled: a right click says so and sends nothing" '[[ $(jq -r ".state + \"|\" + .tooltip" <<<"$A") == "ok|Spotify: all devices are turned off (left click to turn one on)" && $(logcount "PUT /v1/me/player") == "$before" ]]'
ok "  status: playback stays where it is, nothing is next" '"$B" status | jq -e ".device.name == \"XPS\" and .next == null" >/dev/null'
fake "{\"devices\":[$(dev xps XPS false),$(dev pc 'gaming PC')]}"; "$B" status >/dev/null
ok "  nothing active and all disabled: the status text says so" '[[ $("$B" status | jq -r .tooltip) == "Spotify: all devices are turned off" ]]'
five; "$B" status >/dev/null
for i in xps pc px ks ar; do "$B" enable $i >/dev/null; done
"$B" disable pc >/dev/null; "$B" disable px >/dev/null; "$B" disable ks >/dev/null; "$B" disable ar >/dev/null
ok "only the active device enabled: a right click says so" '[[ $("$B" next | jq -r .tooltip) == "Spotify: XPS (only enabled device)" ]]'
for i in pc px ks ar; do "$B" enable $i >/dev/null; done
printf '{"client_id": "test-client", broken' >"$CFG"; cp "$CFG" "$TMP/cfg.bad"
ok "an unreadable config.json is never overwritten" '! "$B" disable ar >/dev/null 2>"$TMP/err" && cmp -s "$CFG" "$TMP/cfg.bad" && grep -q "not valid JSON" "$TMP/err"'
rm -f "$CFG"
ok "no config.json yet: disable creates it, mode 600" '"$B" disable ar >/dev/null && [[ $(jq -c .disabled "$CFG") == "[{\"id\":\"ar\",\"name\":\"Arcade\"}]" && $(perm "$CFG") == 600 ]]'
ok "enable/disable without an id: usage, exit 2" '"$B" disable >/dev/null 2>&1; [[ $? == 2 ]]'
cp "$TMP/cfg.keep" "$CFG"; rm -f "$SD/status.json"; five; "$B" status >/dev/null

# --- serve: the bar's long-lived helper ---
five; token "$(fstate .access)" "$(fstate .refresh)" 300   # expires in 5 min
r0=$(logcount "POST /api/token")
mkfifo "$TMP/in"; SPOTIFY_SWITCH_TIMING=1 "$B" serve <"$TMP/in" >"$TMP/serve.out" 2>"$TMP/serve.err" & SV=$!
exec 7>"$TMP/in"
waitline() { for _ in $(seq 100); do [[ $(grep -c "\"kind\": \"$1\"" "$TMP/serve.out") -ge $2 ]] && return 0; sleep 0.05; done; return 1; }
ok "serve: answers a status line at start" 'waitline status 1'
ok "  background read refreshed a token expiring within 10 min" '[[ $(( $(logcount "POST /api/token") - r0 )) == 1 ]]'
r0=$(logcount "POST /api/token"); n0=$(flog | jq length)
echo "next - $(( $(date +%s%N) / 1000000 ))" >&7
ok "  next: answers a next line" 'waitline next 1'
L=$(grep "\"kind\": \"next\"" "$TMP/serve.out" | tail -1)
ok "  next: XPS -> Arcade, one PUT, no token refresh on the click" '[[ $(jq -r .device.name <<<"$L") == Arcade && $(flog | jq -c "[.[$n0:][] | .req] | .[0]") == "\"PUT /v1/me/player\"" && $(( $(logcount "POST /api/token") - r0 )) == 0 ]]'
echo "seen $(jq -r .click_ms <<<"$L") $(( $(date +%s%N) / 1000000 ))" >&7
ok "  confirms with Spotify 1.5 s later (status line), still Arcade" 'sleep 1.7; waitline status 2 && [[ $(grep "\"kind\": \"status\"" "$TMP/serve.out" | tail -1 | jq -r .device.name) == Arcade ]]'
ok "  keep-alive: the click reused the connection the start-up read opened" '[[ $(flog | jq -r "[.[] | select(.req == \"PUT /v1/me/player\")] | last | .port") == $(flog | jq -r "[.[:$n0][] | select(.req == \"GET /v1/me/player\")] | last | .port") ]]'
echo "next $(jq -r .device.id <<<"$L") 0" >&7; echo "next ks 0" >&7
ok "  two queued clicks run in order (Arcade -> Kitchen speaker -> Pixel)" 'waitline next 3 && [[ $(grep "\"kind\": \"next\"" "$TMP/serve.out" | tail -1 | jq -r .device.name) == "Pixel 10 Pro" ]]'
echo "to ar 0" >&7
ok "  to ar: answers a next line, Arcade active" 'waitline next 4 && [[ $(grep "\"kind\": \"next\"" "$TMP/serve.out" | tail -1 | jq -r ".state + \"|\" + .device.name") == "ok|Arcade" ]]'
"$B" disable ks >/dev/null
echo "next ar 0" >&7
ok "  a device turned off while the helper runs is skipped on the next click (Arcade -> Pixel, not Kitchen speaker)" 'waitline next 5 && [[ $(grep "\"kind\": \"next\"" "$TMP/serve.out" | tail -1 | jq -r ".device.name + \"|\" + (.devices[] | select(.id == \"ks\") | .enabled | tostring)") == "Pixel 10 Pro|false" ]]'
"$B" enable ks >/dev/null
ok "  timing log: click line with stages, no ids or tokens, 600" 'for _ in $(seq 40); do grep -q "\"event\": \"click\"" "$SD/timing.log" 2>/dev/null && break; sleep 0.1; done; grep "\"event\": \"click\"" "$SD/timing.log" | jq -e "has(\"put\") and has(\"click_to_widget\") and has(\"cache_write\")" >/dev/null && ! grep -qE "\"(ar|xps|ks|px)\"|acc-|ref-" "$SD/timing.log" && [[ $(perm "$SD/timing.log") == 600 ]]'
ok "  timing log: handoff line (Spotify reports the target playing)" 'for _ in $(seq 60); do grep -q "\"event\": \"handoff\"" "$SD/timing.log" && break; sleep 0.1; done; grep "\"event\": \"handoff\"" "$SD/timing.log" | head -1 | jq -e ".since_put_done_active != null" >/dev/null'
exec 7>&-
ok "  exits when stdin closes" 'for _ in $(seq 50); do kill -0 $SV 2>/dev/null || break; sleep 0.1; done; ! kill -0 $SV 2>/dev/null'
ok "  nothing on stderr" '[[ ! -s $TMP/serve.err ]]'
# A malformed cache (hand edit, old version) must not kill the helper's click worker.
five; token "$(fstate .access)" "$(fstate .refresh)" 3600; "$B" status >/dev/null
mkfifo "$TMP/in2"; "$B" serve <"$TMP/in2" >"$TMP/serve2.out" 2>"$TMP/serve2.err" & SV2=$!
exec 8>"$TMP/in2"
for _ in $(seq 100); do grep -q '"kind": "status"' "$TMP/serve2.out" && break; sleep 0.05; done
echo "{\"state\":\"ok\",\"updated_ms\":99999999999999,\"read_ms\":$(( $(date +%s%N) / 1000000 + 100000 )),\"playing\":true,\"devices\":[{\"id\":\"xps\",\"active\":true},{\"id\":\"ar\",\"name\":\"Arcade\"}]}" >"$SD/status.json"
echo "next - 1" >&8; echo "next - 2" >&8
ok "malformed cached device list: both clicks still answered (fresh list read)" 'for _ in $(seq 100); do [[ $(grep -c "\"kind\": \"next\"" "$TMP/serve2.out") -ge 2 ]] && break; sleep 0.05; done; [[ $(grep -c "\"kind\": \"next\"" "$TMP/serve2.out") -ge 2 && $(grep "\"kind\": \"next\"" "$TMP/serve2.out" | head -1 | jq -r .state) == ok ]]'
ok "  no traceback" '! grep -q Traceback "$TMP/serve2.err"'
exec 8>&-; wait $SV2 2>/dev/null
ok "timing off by default: no timing.log" 'rm -f "$SD/timing.log"; "$B" status >/dev/null; "$B" next >/dev/null; [[ ! -e $SD/timing.log ]]'

five; "$B" status >/dev/null
jq '.updated_ms = 99999999999999 | .tooltip = "newer"' "$SD/status.json" >"$TMP/c" && mv "$TMP/c" "$SD/status.json"
ok "a run overtaken by a newer cache write prints but keeps the newer cache" '[[ $("$B" status | jq -r .tooltip) == "Spotify: XPS" && $(jq -r .tooltip "$SD/status.json") == newer ]]'
rm -f "$SD/status.json"

# --- login ---
rm -f "$SD/token.json"
LP=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
cat >"$TMP/stub/xdg-open" <<STUB
#!/bin/bash
# The "browser": follow Spotify's redirect back to the loopback listener.
sleep 0.3; curl -sL "\$1" >"$TMP/browser.html"
STUB
chmod +x "$TMP/stub/xdg-open"
fake '{"code":"good-code"}'
ok "login: browser round trip, exit 0" 'PATH="$TMP/stub:$PATH" SPOTIFY_SWITCH_LOGIN_PORT=$LP SPOTIFY_SWITCH_LOGIN_TIMEOUT=10 "$HERE/bin/omarchy-spotify-switch-login" >/dev/null 2>"$TMP/login.err" || { cat "$TMP/login.err"; false; }'
ok "  PKCE S256 verified by the fake, tokens saved" '[[ $(jq -r .access_token "$SD/token.json") == "$(fstate .access)" ]]'
ok "  authorize: S256, scopes, loopback redirect, client ID, no secret" '[[ $(fstate ".authorize | [.code_challenge_method, .scope, .redirect_uri, .client_id, .response_type, (has(\"client_secret\")|tostring)] | join(\"|\")") == "S256|user-read-playback-state user-modify-playback-state|http://127.0.0.1:$LP/callback|test-client|code|false" ]]'
ok "  token.json 600, dir 700" '[[ $(perm "$SD/token.json") == 600 && $(perm "$SD") == 700 ]]'
ok "  browser told it worked" 'grep -q "logged in" "$TMP/browser.html"'
ok "  listener is gone after the callback" '! curl -s -m 1 "http://127.0.0.1:$LP/callback" >/dev/null'
ok "  default redirect URI is 127.0.0.1:8888" 'grep -q "^PORT = int(os.environ.get(\"SPOTIFY_SWITCH_LOGIN_PORT\") or 8888)" "$B"'
rm -f "$SD/token.json"
cat >"$TMP/stub/xdg-open" <<STUB
#!/bin/bash
# A forged callback with the wrong state, never the real one.
sleep 0.3; curl -s "http://127.0.0.1:$LP/callback?code=good-code&state=forged" >/dev/null
STUB
ok "login: wrong state ignored, times out, exit 1, no token" '! PATH="$TMP/stub:$PATH" SPOTIFY_SWITCH_LOGIN_PORT=$LP SPOTIFY_SWITCH_LOGIN_TIMEOUT=2 "$B" login >/dev/null 2>&1 && [[ ! -e $SD/token.json ]]'
python3 -c 'import socket,time,sys; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(); time.sleep(3)' "$LP" & BUSY=$!; sleep 0.3
ok "login: port busy -> exit 1, says busy" '! SPOTIFY_SWITCH_LOGIN_TIMEOUT=3 SPOTIFY_SWITCH_LOGIN_PORT=$LP "$B" login >/dev/null 2>"$TMP/busy.err" && grep -q busy "$TMP/busy.err"'
kill $BUSY 2>/dev/null; wait $BUSY 2>/dev/null
rm -f "$SD/token.json"
cat >"$TMP/stub/xdg-open" <<STUB
#!/bin/bash
sleep 0.5; curl -s -m 7 -L "\$1" >"$TMP/browser2.html"
STUB
python3 -c 'import socket,time,sys
for _ in range(50):
    try: s=socket.create_connection(("127.0.0.1",int(sys.argv[1]))); break
    except OSError: time.sleep(0.05)
time.sleep(9)' "$LP" & IDLE=$!
sleep 0.2
ok "login: an idle local connection cannot block the callback" 'PATH="$TMP/stub:$PATH" SPOTIFY_SWITCH_LOGIN_PORT=$LP SPOTIFY_SWITCH_LOGIN_TIMEOUT=8 "$B" login >/dev/null 2>&1 && [[ -s $SD/token.json ]]'
kill $IDLE 2>/dev/null; wait $IDLE 2>/dev/null
echo '{}' >"$CFG"
ok "login without client ID: exit 1, says where to put it" '! "$B" login >/dev/null 2>"$TMP/nocid.err" && grep -q config.json "$TMP/nocid.err"'
echo '{"client_id":"test-client"}' >"$CFG"; token a r 3600
ok "logout removes the token" '"$B" logout >/dev/null && [[ ! -e $SD/token.json && $("$B" cached | jq -r .state) == need_login ]]'

echo "backend: $pass passed, $fail failed"
(( fail == 0 ))
