import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Cycle.js" as Cycle

// Spotify Switcher: one bar icon. Left click moves Spotify playback to the
// next Spotify Connect device in a fixed cycle (omarchy-spotify-switch next).
// The tooltip names the current device.
//
// Speed: the last known status is read from the backend's cache file at
// once, and every backend run rewrites it (watched, no polling). A click
// shows its target device at once (optimistic) and the backend's answer
// follows. Fresh reads from Spotify happen at start, after each click, on
// hover (at most every 20 s) and every `refreshMinutes` (default 5, 0 = off),
// so a device picked on the phone shows up without the bar hammering the API.
BarWidget {
  id: root

  readonly property string cli: "omarchy-spotify-switch"
  readonly property string cacheFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/timon-spotify-switch/status.json"
  readonly property real refreshMinutes: Number(root.setting("refreshMinutes", 5))
  readonly property int hoverThrottleMs: 20000

  // Last status from the backend: {state, device, next, devices, tooltip}.
  property var st: ({ state: "unknown", devices: [], tooltip: "Spotify" })
  // What the icon shows right now: the backend's device, or a click's target.
  property var shown: null
  // Set by a click until the backend answers; reads in between are ignored
  // so they cannot undo the optimistic switch.
  property bool pending: false
  property string pendingFrom: ""
  property bool hasPendingFrom: false
  property string clickNote: ""
  property real lastRead: 0
  // Bumped by every click; a status read started before a click is stale.
  property int clickGen: 0

  readonly property bool reading: statusProc.running
  readonly property bool loggedOut: st.state === "need_login" || st.state === "no_client_id"
  readonly property bool lit: !!root.shown && (st.state === "ok" || root.pending)
  readonly property string tip: root.clickNote !== "" ? root.clickNote : String(st.tooltip || "Spotify")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function apply(text, fromClick) {
    var s
    try { s = JSON.parse(String(text || "").trim()) } catch (e) { return }
    if (!s || typeof s !== "object") return
    if (root.pending && !fromClick) return
    if (!Array.isArray(s.devices)) s.devices = []
    root.st = s
    root.shown = s.device || null
    root.clickNote = ""
  }

  function refresh() {
    root.lastRead = Date.now()
    if (statusProc.running) { statusProc.again = true; return }
    statusProc.gen = root.clickGen
    statusProc.running = true
  }

  function click() {
    root.clickGen++
    if (st.state === "no_client_id") { root.clickNote = String(st.tooltip || "Spotify: no client ID set"); return }
    if (st.state === "need_login") {
      root.clickNote = "Spotify: opening the login in your browser"
      Quickshell.execDetached(["omarchy-spotify-switch-login"])
      return
    }
    var from = root.shown ? root.shown.id : ""
    var target = Cycle.nextDevice(st.devices, from)
    if (target) {
      root.shown = target
      root.clickNote = "Spotify: " + target.name
    } else if (root.shown) {
      root.clickNote = "Spotify: " + root.shown.name + " (only device available)"
    }
    root.pending = true
    if (nextProc.running) { root.pendingFrom = from; root.hasPendingFrom = true; return }
    root.runNext(from)
  }

  function runNext(from) {
    nextProc.command = from !== "" ? [root.cli, "next", "--from", from] : [root.cli, "next"]
    nextProc.running = true
  }

  onTipChanged: if (button.tooltipHovered && root.bar) root.bar.showTooltip(button, root.tip)

  Process {
    id: statusProc
    property bool again: false
    property int gen: 0
    property string out: ""
    command: [root.cli, "status"]
    stdout: StdioCollector { onStreamFinished: statusProc.out = String(text || "") }
    onExited: {
      if (gen === root.clickGen) root.apply(out, false)
      out = ""
      if (again) { again = false; gen = root.clickGen; running = true }
    }
  }

  Process {
    id: nextProc
    property string out: ""
    command: [root.cli, "next"]
    stdout: StdioCollector { onStreamFinished: nextProc.out = String(text || "") }
    onExited: {
      var text = out
      out = ""
      if (root.hasPendingFrom) {
        // More clicks came in: run once more from where the last one started.
        var from = root.pendingFrom
        root.hasPendingFrom = false
        root.runNext(from)
        return
      }
      root.pending = false
      root.apply(text, true)
    }
  }

  // Every backend run (this bar, another monitor's bar, the CLI) rewrites
  // the cache file atomically; that is the event this widget follows.
  FileView {
    id: cache
    path: root.cacheFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(cache.text(), false)
  }

  // Slow safety net, see the header. Never a tight loop.
  Timer {
    interval: Math.max(1, root.refreshMinutes) * 60000
    running: root.refreshMinutes > 0
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  BarIconButton {
    id: button
    objectName: "spotifySwitchButton"
    bar: root.bar
    text: "\uf1bc"   // nf-fa-spotify
    dimmed: !root.lit
    tooltipText: root.tip
    onTooltipHoveredChanged: if (tooltipHovered && Date.now() - root.lastRead > root.hoverThrottleMs) root.refresh()
    onPressed: function(b) { if (b === Qt.LeftButton) root.click() }
  }
}
