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
ok "nothing was playing: play:false" '[[ $(put_body | jq -c .play) == false ]]'
fake "{\"devices\":[$(dev xps XPS true)],\"playing\":true}"
before=$(logcount "PUT /v1/me/player")
ok "single active device: tooltip says so" '[[ $("$B" next | jq -r .tooltip) == "Spotify: XPS (only device available)" ]]'
ok "single active device: no transfer" '[[ $(logcount "PUT /v1/me/player") == "$before" ]]'
fake "{\"devices\":[$(dev xps XPS)]}"
ok "single inactive device: next plays there" '[[ $("$B" next | jq -r .device.name) == XPS ]]'
fake '{"devices":[]}'
before=$(logcount "PUT /v1/me/player")
ok "no devices: no_device, no transfer" '[[ $("$B" next | jq -r .state) == no_device && $(logcount "PUT /v1/me/player") == "$before" ]]'
fake "{\"devices\":[$(dev xps XPS true),$(dev tv TV false true),$(dev px Pixel)]}"
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
fake '{"force":{"PUT /v1/me/player":[{"status":404,"body":{"error":{"status":404,"message":"Device not found"}}}]}}'
ok "404 on transfer (device gone) -> says so" '[[ $("$B" next | jq -r .tooltip) == "Spotify: Arcade is no longer available" ]]'
fake '{"force":{"GET /v1/me/player/devices":[{"status":502}]}}'
ok "5xx -> error" '[[ $("$B" status | jq -r .state) == error ]]'
"$B" status >/dev/null
DEAD=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
R=$(SPOTIFY_SWITCH_API=http://127.0.0.1:$DEAD "$B" status)
ok "network down -> offline, last device in tooltip" '[[ $(jq -r .state <<<"$R") == offline && $(jq -r .tooltip <<<"$R") == "Spotify: XPS (offline, last known)" ]]'

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
echo '{}' >"$CFG"
ok "login without client ID: exit 1, says where to put it" '! "$B" login >/dev/null 2>"$TMP/nocid.err" && grep -q config.json "$TMP/nocid.err"'
echo '{"client_id":"test-client"}' >"$CFG"; token a r 3600
ok "logout removes the token" '"$B" logout >/dev/null && [[ ! -e $SD/token.json && $("$B" cached | jq -r .state) == need_login ]]'

echo "backend: $pass passed, $fail failed"
(( fail == 0 ))
