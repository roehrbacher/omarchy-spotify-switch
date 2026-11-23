#!/bin/bash
# No secret ever lands in the repo: no token/cache/config files tracked or
# lying in the tree, gitleaks clean on the files and the history, the real
# client ID (if this machine has one) appears nowhere, and the pre-commit
# hook fails closed and blocks token files and token-looking lines.
#   bash tests/secrets.test.sh
#   SPOTIFY_SWITCH_CHECK_ID_FILE=<file>   also check this client ID file
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0
ok() { if eval "$2"; then echo "ok   $1"; pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi; }
cd "$HERE"
ok "no token/status/config.json tracked" '! git ls-files | grep -qE "(^|/)(token|status|config)\.json$"'
ok "no token/status/config.json anywhere in the tree" '[[ -z $(find . -path ./.git -prune -o \( -name token.json -o -name status.json -o -name config.json \) -print) ]]'
ok ".gitignore covers token.json, status.json, config.json" 'for f in token.json status.json config.json; do git check-ignore -q "x/$f" || exit 1; done'
mkdir -p "$TMP/files"; git ls-files -z --cached --others --exclude-standard | xargs -0 -I{} cp --parents {} "$TMP/files/"
ok "gitleaks: files clean" 'gitleaks dir "$TMP/files" --no-banner --redact >/dev/null 2>&1'
if git rev-parse -q --verify HEAD >/dev/null; then
  ok "gitleaks: history clean" 'gitleaks git . --no-banner --redact >/dev/null 2>&1'
fi
ids=()
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/timon-spotify-switch/config.json
[[ -r $cfg ]] && ids+=("$(jq -r '.client_id // empty' "$cfg" 2>/dev/null)")
[[ -n ${SPOTIFY_SWITCH_CHECK_ID_FILE:-} && -r $SPOTIFY_SWITCH_CHECK_ID_FILE ]] && ids+=("$(tr -d '[:space:]' <"$SPOTIFY_SWITCH_CHECK_ID_FILE")")
for id in "${ids[@]}"; do
  [[ -n $id ]] || continue
  ok "real client ID not in files (value not printed)" '! grep -rqF "$id" "$TMP/files"'
  if git rev-parse -q --verify HEAD >/dev/null; then
    ok "real client ID not in history" '! git log -p --all | grep -qF "$id"'
  fi
done
ok "no Spotify-looking tokens in files" '! grep -rqE "(BQ|AQ)[A-Za-z0-9_-]{60,}" "$TMP/files"'

# The hook, in a throwaway repo.
R=$TMP/repo; git init -q "$R"; cp -r .githooks "$R/"; git -C "$R" config core.hooksPath .githooks
git -C "$R" config user.name t; git -C "$R" config user.email t@example.invalid
echo hi >"$R/a.txt"; git -C "$R" add a.txt
ok "hook: clean change passes" '(cd "$R" && .githooks/pre-commit >/dev/null 2>&1)'
ok "hook: no gitleaks -> blocked (fails closed)" '! (cd "$R" && PATH=/usr/bin:/bin .githooks/pre-commit >/dev/null 2>&1)'
mkdir -p "$R/s"; echo '{}' >"$R/s/token.json"; git -C "$R" add -f s/token.json
ok "hook: staged token.json blocked" '! (cd "$R" && .githooks/pre-commit >/dev/null 2>&1)'
git -C "$R" rm -q --cached s/token.json
fake="BQ$(head -c 90 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 80)"
echo "token = \"$fake\"" >"$R/b.txt"; git -C "$R" add b.txt
ok "hook: Spotify-looking access token blocked" '! (cd "$R" && .githooks/pre-commit >/dev/null 2>&1)'
echo "backup=$(printf "gh%s_%s" p "$(head -c 60 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 36)")" >"$R/b.txt"; git -C "$R" add b.txt
ok "hook: GitHub token blocked" '! (cd "$R" && .githooks/pre-commit >/dev/null 2>&1)'
echo "secrets: $pass passed, $fail failed"
(( fail == 0 ))
