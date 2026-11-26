import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Cycle.js" as Cycle

// Spotify Switcher: one bar icon with a popup.
//   Left click   opens the popup: the Spotify Connect devices, the active one
//                marked; a click on a device moves playback there. Each row
//                ends in a switch: off = never switch to that device (saved
//                in config.json, see "disabled" in the backend).
//   Right click  moves playback to the next enabled device in a fixed cycle.
// The play state is kept either way (playing stays playing, paused stays
// paused).
//
// No hover tooltip (vanilla Omarchy bar icons have none). Feedback: the icon
// is lit while a device has the session and there is another enabled device
// to switch to, and dimmed otherwise (errors, logged out, no device, nothing
// to switch to). The popup's size never depends on a message: the tagline
// under the heading names the state, and a short note replaces it for a few
// seconds. A right click that cannot switch, or a switch that fails while the
// popup is closed, shows a desktop notification with the reason. A right click while
// logged out opens the login in the browser.
//
// Speed: a long-lived helper (`omarchy-spotify-switch serve`) keeps the
// token fresh, one HTTPS connection to Spotify open and the device list and
// play state cached, so a switch is one PUT with no process start. The widget
// shows the target at once and keeps it unless the PUT fails. The last known
// status comes from the backend's cache file at once (watched, no polling).
// Spotify is read at start, ~1.5 s after a switch (confirm), when the popup
// opens, every 10 s while it stays open, and every `refreshMinutes` (default
// 5, 0 = off) while it is closed. If the helper is down, switches fall back
// to one-shot `next` / `to` runs.
Panel {
  id: root
  moduleName: "timon.spotify-switch"
  // Several bar entries are allowed, so no shared IPC target.
  manageIpc: false

  readonly property string cli: "omarchy-spotify-switch"
  readonly property string cacheFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/timon-spotify-switch/status.json"
  readonly property real refreshMinutes: Number(root.setting("refreshMinutes", 5))
  // Fixed icon: nf-md-monitor_speaker (U+F0F5F) from the bar's Nerd Font.
  readonly property string icon: String.fromCodePoint(0xF0F5F)
  // Desktop notification for click feedback; the text is appended.
  property var notifyCommand: ["notify-send", "--app-name=Spotify Switcher", "Spotify Switcher"]
  property string lastNotice: ""
  property int noticeCount: 0

  // Last status from the backend: {state, device, next, devices, playing, tooltip}.
  property var st: ({ state: "unknown", devices: [], tooltip: "Spotify" })
  // What the icon shows right now: the backend's device, or a click's target.
  property var shown: null
  // Clicks sent and not answered yet; while > 0, status reads are ignored
  // so they cannot undo the optimistic switch.
  property int inFlight: 0
  readonly property bool pending: root.inFlight > 0
  // The popup's choice still in flight (its row says "Switching…").
  property string pendingId: ""
  property string clickNote: ""
  // A note for the open popup (a choice that could not be made, a click's
  // answer); cleared when it opens again.
  property string panelNote: ""
  // Clears the note so the state's tagline comes back. Tests may shorten noteMs.
  property int noteMs: 4000
  property bool eggOn: false
  property int eggAt: 0
  Timer { id: noteTimer; interval: Math.max(1, root.noteMs); onTriggered: { root.panelNote = ""; root.eggOn = false } }
  // What a click already told at once (so its answer does not tell it twice).
  property string toldForClick: ""
  property real lastRead: 0
  // Bumped by every click or row switch; a status read started before that is stale.
  property int clickGen: 0
  property int dataGen: 0
  // The dataGen at the moment this widget last asked for a status read.
  property int readGen: 0
  // One-shot fallback queue (helper down): argument lists for the CLI.
  property var oneShotQueue: []

  readonly property bool helperUp: helper.running
  readonly property bool reading: statusProc.running || root.helperReading
  property bool helperReading: false
  readonly property bool loggedOut: st.state === "need_login" || st.state === "no_client_id"
  // Another enabled, controllable device exists to switch to.
  readonly property bool canSwitch: Cycle.nextDevice(st.devices, root.shown ? root.shown.id : "") !== null
  readonly property bool lit: !!root.shown && root.canSwitch && (root.pending || st.state === "ok")
  // The current state in words (backend text, or a click's note). Not shown on
  // hover; used for notifications and tests.
  readonly property string message: root.clickNote !== "" ? root.clickNote : String(st.tooltip || "Spotify")

  // ---- popup state ----
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: bar && bar.urgent !== undefined ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: Style.font.menuFamily
  readonly property color hoverFill: Style.hoverFillFor(foreground, Commons.Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Commons.Color.accent)
  readonly property var devices: root.loggedOut || !Array.isArray(st.devices) ? [] : st.devices
  readonly property string shownId: root.shown ? String(root.shown.id || "") : ""
  // Primitive deps so the tagline rebinds when play state, the device list or
  // a toggle changes: a `var` object (`st`) alone does not notify on new fields.
  readonly property string stState: String(st && st.state || "")
  readonly property bool stPlaying: !!(st && st.playing)
  readonly property int enabledCount: {
    var list = Array.isArray(st.devices) ? st.devices : []
    var n = 0
    for (var i = 0; i < list.length; i++) if (Cycle.canTarget(list[i])) n++
    return n
  }
  readonly property string heroStatusText: {
    var _ = root.stState, __ = root.stPlaying, ___ = root.enabledCount, ____ = root.shownId
    return root.panelNote !== "" ? root.panelNote : Cycle.heroStatus(root.st, root.shown, root.pending)
  }
  readonly property bool showLogin: st.state === "need_login"
  // Keyboard/mouse cursor: one highlighted row (login row or a device).
  property bool cursorActive: false
  property int selectedIndex: 0
  // The keyboard cursor sits on the row's switch (Right), not on the row (Left).
  property bool toggleFocused: false
  // The switch changes still to save (argument lists for the CLI, in order).
  property var toggleQueue: []
  readonly property int rowCount: root.showLogin ? 1 : root.devices.length

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

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
    // Replacing the object (not mutating fields) is what makes the tagline
    // and the list rebind.
    var prev = Cycle.heroStatus(root.st, root.shown, false)
    root.st = s
    root.shown = s.device || null
    root.clickNote = ""
    if (root.eggOn && Cycle.heroStatus(root.st, root.shown, false) !== prev) root.setNote("")
  }

  function notice(text) {
    root.lastNotice = String(text || "")
    root.noticeCount++
    Quickshell.execDetached(root.notifyCommand.concat([root.lastNotice.replace(/^Spotify: /, "")]))
  }

  // Feedback: in the open popup a short note replaces the tagline for a few
  // seconds (never a new line: the popup keeps its size); "" for `brief`
  // says the tagline already tells it. Closed: a notification with the text.
  function setNote(t) {
    root.panelNote = String(t || "")
    root.eggOn = false
    if (root.panelNote !== "") noteTimer.restart()
    else noteTimer.stop()
  }
  // Right click on the popup heading glyph: a joke, then the real tagline
  // comes back (4 s, or at once on a real switch or status change).
  function headerEgg() {
    var lines = Cycle.headerEggLines()
    var i = ((root.eggAt % lines.length) + lines.length) % lines.length
    root.eggAt = i + 1
    root.setNote(lines[i])
    root.eggOn = true
  }
  function tell(text, brief) {
    if (!root.opened) { root.notice(String(text || "")); return }
    var t = brief !== undefined ? brief : String(text || "").replace(/^Spotify: /, "")
    root.setNote(t === "" ? "" : t.charAt(0).toUpperCase() + t.slice(1))
  }

  // A click's answer: anything but a successful switch is told once. A
  // problem state shows in the popup by itself (hero + problem line).
  function clickAnswer(s) {
    if (!s) return
    if (s.state !== "ok") {
      if (!root.opened) root.notice(String(s.tooltip || "Spotify: switch failed"))
      return
    }
    var plain = s.device ? "Spotify: " + s.device.name : ""
    if (!s.transfer && s.tooltip && s.tooltip !== plain && s.tooltip !== root.toldForClick) root.tell(s.tooltip)
  }

  // Skip when a switch or a row switch is in flight, or a read is already
  // running, so a later answer cannot overwrite the optimistic state.
  function busyForRead() {
    return root.pending || toggleProc.running || root.toggleQueue.length > 0
  }
  function refresh() {
    if (root.busyForRead()) return
    root.lastRead = Date.now()
    root.readGen = root.dataGen
    if (root.helperUp) { root.helperReading = true; helper.write("status\n"); return }
    if (statusProc.running) { statusProc.again = true; return }
    statusProc.gen = root.dataGen
    statusProc.running = true
  }

  function login() {
    if (loginProc.running) { root.tell("Spotify: the login is already open in your browser", "Login is already open"); return }
    root.clickNote = "Spotify: opening the login in your browser"
    root.tell(root.clickNote, "Opening login in your browser")
    loginProc.running = true
  }

  // Right click: the next device in the cycle.
  function click() {
    root.setNote("")
    root.clickGen++
    root.dataGen++
    root.toldForClick = ""
    if (st.state === "no_client_id") { root.clickNote = String(st.tooltip || "Spotify: no client ID set"); root.tell(root.clickNote, ""); return }
    if (st.state === "need_login") { root.login(); return }
    var from = root.shown ? root.shown.id : ""
    var target = Cycle.nextDevice(st.devices, from)
    if (target) {
      root.shown = target
      root.clickNote = "Spotify: " + target.name
    } else if (root.shown || (st.devices && st.devices.length > 0)) {
      root.clickNote = Cycle.noTargetNote(st.devices, root.shown)
      root.toldForClick = root.clickNote
      // In the popup the switches are right there: say what to do with them.
      root.tell(root.clickNote, "")   // the popup's tagline says it
    }
    root.inFlight++
    if (root.helperUp) {
      helper.write("next " + (from !== "" ? from : "-") + " " + Date.now() + "\n")
      return
    }
    root.runOneShot(from !== "" ? ["next", "--from", from] : ["next"])
  }

  // The popup's choice: move playback to this device.
  function transferTo(dev) {
    if (!dev || !dev.id) return
    root.setNote("")
    // A restricted or turned-off row does nothing: it is dimmed and says why.
    if (dev.restricted || !Cycle.isEnabled(dev)) return
    if (root.shownId === dev.id && !root.pending) return
    root.clickGen++
    root.dataGen++
    root.toldForClick = ""
    root.shown = dev
    root.pendingId = String(dev.id)
    root.clickNote = "Spotify: " + dev.name
    root.inFlight++
    if (root.helperUp) {
      helper.write("to " + dev.id + " " + Date.now() + "\n")
      return
    }
    root.runOneShot(["to", String(dev.id)])
  }

  // The row's switch: turn a device on or off for switching. The row follows
  // at once; the backend saves it (config.json, the cache) and the cache file
  // event confirms. A failed save is told and Spotify is read again.
  function setEnabled(dev, on) {
    if (!dev || !dev.id || Cycle.isEnabled(dev) === on) return
    var id = String(dev.id)
    root.dataGen++
    var list = Array.isArray(root.st.devices) ? root.st.devices : []
    root.st = Object.assign({}, root.st, { devices: list.map(function(d) {
      return d && d.id === id ? Object.assign({}, d, { enabled: on }) : d
    }) })
    root.setNote("")
    var args = [on ? "enable" : "disable", id]
    if (toggleProc.running) { root.toggleQueue = root.toggleQueue.concat([args]); return }
    toggleProc.command = [root.cli].concat(args)
    toggleProc.running = true
  }

  function runOneShot(args) {
    if (nextProc.running) { root.oneShotQueue = root.oneShotQueue.concat([args]); return }
    nextProc.command = [root.cli].concat(args)
    nextProc.running = true
  }

  function onHelperLine(line) {
    var s = root.parse(line)
    if (!s) return
    if (s.kind === "next") {
      root.inFlight = Math.max(0, root.inFlight - 1)
      if (s.click_ms) helper.write("seen " + s.click_ms + " " + Date.now() + "\n")
      // A later click is still in flight: keep showing its target.
      if (root.inFlight === 0) { root.apply(s, true); root.pendingId = "" }
      root.clickAnswer(s)
    } else {
      root.helperReading = false
      // Drop a read that started before a click or a row switch.
      if (root.readGen === root.dataGen) root.apply(s, false)
    }
  }

  // ---- cursor (keyboard and mouse share it) ----
  function moveCursor(dy) {
    if (root.rowCount === 0) return
    root.toggleFocused = false
    root.selectedIndex = Math.max(0, Math.min(root.rowCount - 1, root.selectedIndex + dy))
  }
  // Enter picks the row's device; Space, or Enter while the cursor is on the
  // switch, turns the device on or off.
  function activateCursor(fromReturn) {
    if (root.showLogin) { root.login(); return }
    if (root.selectedIndex < 0 || root.selectedIndex >= root.devices.length) return
    var dev = root.devices[root.selectedIndex]
    if (root.toggleFocused || !fromReturn) root.setEnabled(dev, !Cycle.isEnabled(dev))
    else root.transferTo(dev)
  }
  // The row the keyboard cursor starts on: the active device, else the first.
  function activeIndex() {
    for (var k = 0; k < root.devices.length; k++) if (root.devices[k].id === root.shownId) return k
    return 0
  }
  function setRowCursor(index, onToggle) {
    root.cursorActive = true
    root.selectedIndex = index
    root.toggleFocused = !!onToggle
  }

  onOpenedChanged: if (opened) {
    root.cursorActive = false
    root.toggleFocused = false
    root.setNote("")
    root.selectedIndex = root.activeIndex()
    if (root.panelFlick) root.panelFlick.contentY = 0
    root.refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }
  onRowCountChanged: if (root.selectedIndex >= root.rowCount) root.selectedIndex = Math.max(0, root.rowCount - 1)

  // Guard: if an answer never comes (helper hung or lost the line), leave
  // the "click in flight" state after 15 s and read Spotify again.
  Timer {
    id: inFlightGuard
    interval: 15000
    running: root.inFlight > 0
    onTriggered: { root.inFlight = 0; root.pendingId = ""; root.clickNote = ""; root.refresh() }
  }

  // The login helper; a login that does not finish is told.
  Process {
    id: loginProc
    command: [root.cli + "-login"]
    onExited: function(code) {
      if (code !== 0) root.tell("Spotify: login did not finish (run omarchy-spotify-switch-login)", "Login did not finish")
      root.refresh()
    }
  }

  // Saves a row switch (enable / disable ID), one at a time.
  Process {
    id: toggleProc
    property string err: ""
    command: [root.cli, "disable"]
    stderr: StdioCollector { onStreamFinished: toggleProc.err = String(text || "").trim() }
    onExited: function(code) {
      var failedText = code !== 0 ? (err !== "" ? err : "Spotify: could not save the setting") : ""
      err = ""
      if (root.toggleQueue.length > 0) {
        var args = root.toggleQueue[0]
        root.toggleQueue = root.toggleQueue.slice(1)
        command = [root.cli].concat(args)
        running = true
      }
      if (failedText !== "") { root.tell(failedText, "Could not save the setting"); root.refresh() }
    }
  }

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
      root.pendingId = ""
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
      if (gen === root.dataGen) root.apply(root.parse(out), false)
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
      if (root.oneShotQueue.length > 0) {
        var args = root.oneShotQueue[0]
        root.oneShotQueue = root.oneShotQueue.slice(1)
        command = [root.cli].concat(args)
        running = true
        return
      }
      root.inFlight = 0
      root.pendingId = ""
      var s = root.parse(text)
      root.apply(s, true)
      root.clickAnswer(s || { state: "error", tooltip: "Spotify: switch failed" })
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

  // Slow safety net while the popup is closed. Never a tight loop.
  Timer {
    interval: Math.max(1, root.refreshMinutes) * 60000
    running: root.refreshMinutes > 0 && !root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // While the popup is open: re-read Spotify every 10 s so play/pause and
  // devices coming or going show up in the list and the tagline at once.
  // Tests may set openRefreshMs (0 = off) so the full suite does not wait.
  property int openRefreshMs: 10000
  Timer {
    id: openRefresh
    interval: Math.max(200, root.openRefreshMs)
    running: root.opened && root.openRefreshMs > 0
    repeat: true
    onTriggered: if (!root.reading && !root.busyForRead()) root.refresh()
  }

  BarIconButton {
    id: button
    objectName: "spotifySwitchButton"
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    dimmed: !root.lit
    onPressed: function(b) {
      if (b === Qt.RightButton) root.click()
      else if (b === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.selectedIndex = root.activeIndex(); root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (root.devices.length > 0 && !root.showLogin) root.toggleFocused = dx > 0
      }
      // Enter also arrives as an activate; the flag tells it from Space.
      property bool returnHandled: false
      onReturnRequested: returnHandled = true
      onActivateRequested: {
        var fromReturn = returnHandled
        returnHandled = false
        if (root.cursorActive) root.activateCursor(fromReturn)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          objectName: "spotifySwitchPanelColumn"
          width: panelFlick.width
          spacing: Style.space(14)

          // ---------- Hero: glyph · name · status ----------
          PanelHero {
            id: hero
            objectName: "spotifySwitchHero"
            width: parent.width
            title: "Spotify Device Switcher"
            meta: root.heroStatusText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                implicitWidth: glyph.implicitWidth
                implicitHeight: glyph.implicitHeight
                width: implicitWidth
                height: implicitHeight
                Text {
                  id: glyph
                  anchors.fill: parent
                  textFormat: Text.PlainText
                  text: root.icon
                  color: root.lit ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
                MouseArea {
                  id: glyphHit
                  objectName: "spotifySwitchHeroGlyph"
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  hoverEnabled: false
                  function pressButton(b) {
                    if (b === Qt.RightButton) root.headerEgg()
                  }
                  onPressed: function(mouse) { pressButton(mouse.button) }
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          // ---------- Login (logged out) ----------
          Column {
            visible: root.showLogin
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ACCOUNT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            LoginRow {
              objectName: "spotifySwitchLogin"
              width: parent.width
            }
          }

          // ---------- Devices ----------
          Column {
            id: deviceSection
            visible: !root.loggedOut
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: deviceColumn
              objectName: "spotifySwitchDevices"
              visible: root.devices.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.devices
                DeviceRow {
                  required property var modelData
                  required property int index
                  width: deviceColumn.width
                  dev: modelData
                  rowIndex: index
                }
              }
            }
          }

          // Empty / no client ID help.
          Text {
            objectName: "spotifySwitchHelp"
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: root.st.state === "no_client_id"
                ? "Add your Spotify client ID to ~/.config/timon-spotify-switch/config.json (see the README), then run omarchy-spotify-switch-login."
                : root.showLogin
                  ? "Spotify asks you to log in once in your browser. The switcher keeps the login until you log out."
                  : root.devices.length === 0 && root.st.state !== "unknown"
                    ? "No Spotify Connect devices. Open Spotify on a phone, computer or speaker and it shows up here."
                    : Cycle.deviceHint(root.devices)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // One device: glyph, name, and on the right its state. The active device
  // is the current (selected-fill) row; a click moves playback here.
  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    readonly property bool isActive: !!dev && dev.id === root.shownId
    readonly property bool allowed: Cycle.isEnabled(dev)
    readonly property bool usable: !!dev && !dev.restricted && allowed
    // Dimmed when it can't be picked; the device playing now always reads normal.
    readonly property bool bright: usable || isActive
    readonly property string statusText: Cycle.rowStatus(dev, root.shownId, root.pendingId, !!root.st.playing || root.pending)

    hasCursor: root.cursorActive && root.selectedIndex === rowIndex && !root.toggleFocused
    current: isActive
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.usable && !row.isActive ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) root.setRowCursor(row.rowIndex, false)
      onClicked: root.transferTo(row.dev)
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(deviceIcon.implicitHeight, nameText.implicitHeight, rowSwitch.implicitHeight)

      Text {
        id: deviceIcon
        textFormat: Text.PlainText
        text: Cycle.deviceGlyph(row.dev ? row.dev.type : "")
        color: row.bright ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        // One column for every glyph, so the names line up.
        width: Math.ceil(Style.font.heading * 1.25)
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: nameText
        objectName: "spotifySwitchRowName"
        textFormat: Text.PlainText
        text: row.dev ? String(row.dev.name || "Unknown device") : ""
        color: row.bright ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.isActive
        elide: Text.ElideRight
        anchors.left: deviceIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: valueText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueText
        textFormat: Text.PlainText
        text: row.statusText
        color: row.isActive ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.right: rowSwitch.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
      }

      // On = the switcher may move playback to this device. Its own hit area:
      // the row's click picks the device, the switch only turns it on or off.
      // Same stock ToggleSwitch the Bluetooth/Wi-Fi/audio panels use, with the
      // ring cursor and a tooltip.
      ToggleSwitch {
        id: rowSwitch
        objectName: "spotifySwitchRowToggle"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        cursorPad: Style.space(3)
        checked: row.allowed
        hasCursor: root.cursorActive && root.selectedIndex === row.rowIndex && root.toggleFocused
        foreground: root.foreground
        onToggled: root.setEnabled(row.dev, !row.allowed)
        onHovered: function(on) {
          if (on) root.setRowCursor(row.rowIndex, true)
          else if (rowMouse.containsMouse) root.toggleFocused = false
        }

        PanelToolTip {
          visible: rowSwitch.containsMouse
          text: row.allowed ? "Turn off to never switch to this device" : "Turn on to switch to this device again"
          fontFamily: root.fontFamily
        }
      }
    }
  }

  // Logged out: one row that opens the Spotify login in the browser.
  component LoginRow: CursorSurface {
    id: loginRow
    hasCursor: root.cursorActive && root.selectedIndex === 0
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: loginContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.setRowCursor(0)
      onClicked: root.login()
    }

    Item {
      id: loginContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(loginIcon.implicitHeight, loginText.implicitHeight)

      Text {
        id: loginIcon
        textFormat: Text.PlainText
        text: String.fromCodePoint(0xF0342)   // md-login
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        width: Math.ceil(Style.font.heading * 1.25)
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: loginText
        textFormat: Text.PlainText
        text: loginProc.running ? "Waiting for the browser…" : "Log in to Spotify"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: loginIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
