#!/bin/bash
# Every test. Widget test needs quickshell + Omarchy's shell sources
# (OMARCHY_SHELL); it is skipped (exit 77) without them.
#   bash tests/run-all.sh [shots-dir]
here=$(cd "$(dirname "$0")" && pwd); rc=0
for t in "$here"/backend.test.sh "$here"/install.test.sh; do bash "$t" | tail -1; (( PIPESTATUS[0] == 0 )) || rc=1; done
if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
  out=$(QT_QPA_PLATFORM=offscreen timeout 60 /usr/lib/qt6/bin/qmltestrunner -input "$here/tst_cycle.qml" 2>&1); r=$?
  echo "qml: $(grep '^Totals' <<<"$out")"; (( r == 0 )) || rc=1
else echo "qml: SKIP (no qmltestrunner)"; fi
bash "$here/widget/run.sh" "$@" | tail -1; r=${PIPESTATUS[0]}; (( r == 0 || r == 77 )) || rc=1
bash "$here/secrets.test.sh" | tail -1; (( PIPESTATUS[0] == 0 )) || rc=1   # last: nothing the others left behind
pgrep -f "fake_spotify.py|qs/shell.qml" >/dev/null && { echo "FAIL leftover test processes"; rc=1; }
exit $rc
