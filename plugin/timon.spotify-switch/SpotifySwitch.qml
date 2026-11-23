import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Cycle.js" as Cycle

// Spotify Switcher: one bar icon. Left click moves Spotify playback to the
// next Spotify Connect device in a fixed cycle. The tooltip names the
// current device.
//
// Speed: a long-lived helper (`omarchy-spotify-switch serve`) keeps the
// token fresh, one HTTPS connection to Spotify open and the device list and
// play state cached, so a click is one PUT with no process start. The icon
// and tooltip show the target at once and stay there unless the PUT fails.
// The last known status comes from the backend's cache file at once (watched,
// no polling). Spotify is read at start, ~1.5 s after a click (confirm), on
// hover (at most every 10 s) and every `refreshMinutes` (default 5, 0 = off).
// If the helper is down, clicks fall back to one-shot `next` runs.
BarWidget {
  id: root

  readonly property string cli: "omarchy-spotify-switch"
  readonly property string cacheFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/timon-spotify-switch/status.json"
  readonly property string configFile: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
    + "/timon-spotify-switch/config.json"
  readonly property real refreshMinutes: Number(root.setting("refreshMinutes", 5))
  // Icon: this bar entry's "icon" setting (shell.json), else "icon" in
  // config.json, else the Spotify logo. A preset name, "U+XXXX", or a glyph.
  property string configIcon: ""
  readonly property string icon: Cycle.glyph(root.setting("icon", "") || root.configIcon)
  readonly property int hoverThrottleMs: 10000

  // Last status from the backend: {state, device, next, devices, tooltip}.
  property var st: ({ state: "unknown", devices: [], tooltip: "Spotify" })
  // What the icon shows right now: the backend's device, or a click's target.
  property var shown: null
  // Clicks sent and not answered yet; while > 0, status reads are ignored
  // so they cannot undo the optimistic switch.
  property int inFlight: 0
  readonly property bool pending: root.inFlight > 0
  property string clickNote: ""
  property real lastRead: 0
  // Bumped by every click; a one-shot status read started before a click is stale.
  property int clickGen: 0
  // One-shot fallback queue (helper down).
  property string pendingFrom: ""
  property bool hasPendingFrom: false

  readonly property bool helperUp: helper.running
  readonly property bool reading: statusProc.running || root.helperReading
  property bool helperReading: false
  readonly property bool loggedOut: st.state === "need_login" || st.state === "no_client_id"
  readonly property bool lit: !!root.shown && (st.state === "ok" || root.pending)
  readonly property string tip: root.clickNote !== "" ? root.clickNote : String(st.tooltip || "Spotify")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function parse(text) {
    try {
      var s = JSON.parse(String(text || "").trim())
      return s && typeof s === "object" ? s : null
    } catch (e) { return null }
  }

  function apply(s, fromClick) {
    if (!s) return
    if (root.pending && !fromClick) return
    if (!Array.isArray(s.devices)) s.devices = []
    root.st = s
    root.shown = s.device || null
    root.clickNote = ""
  }

  function refresh() {
    root.lastRead = Date.now()
    if (root.helperUp) { root.helperReading = true; helper.write("status\n"); return }
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
    root.inFlight++
    if (root.helperUp) {
      helper.write("next " + (from !== "" ? from : "-") + " " + Date.now() + "\n")
      return
    }
    if (nextProc.running) { root.pendingFrom = from; root.hasPendingFrom = true; return }
    root.runNext(from)
  }

  function runNext(from) {
    nextProc.command = from !== "" ? [root.cli, "next", "--from", from] : [root.cli, "next"]
    nextProc.running = true
  }

  function onHelperLine(line) {
    var s = root.parse(line)
    if (!s) return
    if (s.kind === "next") {
      root.inFlight = Math.max(0, root.inFlight - 1)
      if (s.click_ms) helper.write("seen " + s.click_ms + " " + Date.now() + "\n")
      // A later click is still in flight: keep showing its target.
      if (root.inFlight === 0) root.apply(s, true)
    } else {
      root.helperReading = false
      root.apply(s, false)
    }
  }

  // Guard: if an answer never comes (helper hung or lost the line), leave
  // the "click in flight" state after 15 s and read Spotify again.
  Timer {
    id: inFlightGuard
    interval: 15000
    running: root.inFlight > 0
    onTriggered: { root.inFlight = 0; root.clickNote = ""; root.refresh() }
  }

  onTipChanged: if (button.tooltipHovered && root.bar) root.bar.showTooltip(button, root.tip)

  // The long-lived helper; restarted a moment after it ends.
  Process {
    id: helper
    command: [root.cli, "serve"]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.onHelperLine(line) } }
    // It reads Spotify as soon as it starts.
    onRunningChanged: if (running) root.helperReading = true
    onExited: {
      root.helperReading = false
      root.inFlight = 0
      helperRestart.start()
    }
  }
  Timer { id: helperRestart; interval: 3000; onTriggered: helper.running = true }

  Process {
    id: statusProc
    property bool again: false
    property int gen: 0
    property string out: ""
    command: [root.cli, "status"]
    stdout: StdioCollector { onStreamFinished: statusProc.out = String(text || "") }
    onExited: {
      if (gen === root.clickGen) root.apply(root.parse(out), false)
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
      root.inFlight = Math.max(0, root.inFlight - 1)
      if (root.hasPendingFrom) {
        var from = root.pendingFrom
        root.hasPendingFrom = false
        root.runNext(from)
        return
      }
      root.inFlight = 0
      root.apply(root.parse(text), true)
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
    onLoaded: root.apply(root.parse(cache.text()), false)
  }

  FileView {
    id: configView
    path: root.configFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.configIcon = String(JSON.parse(configView.text()).icon || "") } catch (e) { root.configIcon = "" }
    }
  }

  // Slow safety net, see the header. Never a tight loop.
  Timer {
    interval: Math.max(1, root.refreshMinutes) * 60000
    running: root.refreshMinutes > 0
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    objectName: "spotifySwitchButton"
    bar: root.bar
    text: root.icon
    dimmed: !root.lit
    tooltipText: root.tip
    onTooltipHoveredChanged: if (tooltipHovered && Date.now() - root.lastRead > root.hoverThrottleMs) root.refresh()
    onPressed: function(b) { if (b === Qt.LeftButton) root.click() }
  }
}
