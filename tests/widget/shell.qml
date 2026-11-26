import Quickshell
import QtQuick
import qs.Commons
// See run.sh. A bar strip with the real widget (two entries) in a plain
// window so it renders with the offscreen platform and the software backend.
// The popup is the widget's own KeyboardPanel content, drawn by a stub card
// (tests/stubs/KeyboardPanel.qml) right under the icon. The bar stub counts
// tooltips the way Omarchy's Bar does (empty text shows nothing).
ShellRoot {
  id: shell
  property var w: null
  property var w2: null
  property bool ok: true

  QtObject {
    id: barStub
    property color foreground: "#e6e6e6"; property color barForeground: "#e6e6e6"; property color urgent: "#f38ba8"
    property string fontFamily: "JetBrainsMono Nerd Font"; property bool vertical: false; property int barSize: 30
    property string position: "top"
    property string tipText: ""
    property int tipShows: 0
    function showTooltip(a, t) { if (String(t || "") === "") return; tipText = String(t); tipShows++ }
    function hideTooltip(a) {}
    function run(c) {}
    function registerClickTarget(t) {} function unregisterClickTarget(t) {}
    function moduleWidgets(id) { return [] }
    function switchPanelFrom(p, d) { return false }
  }

  FloatingWindow {
    id: win
    implicitWidth: 520; implicitHeight: 560
    color: "#1e1e2e"
    Rectangle { id: canvas; anchors.fill: parent; color: "#1e1e2e"
      Rectangle { id: strip; width: parent.width; height: 30; color: "#181825"
        Item { id: slot; x: 452; y: 0; width: 27; height: 30 }
        // A second entry with a leftover "icon" setting, which is ignored.
        Item { id: slot2; x: 479; y: 0; width: 27; height: 30 }
      }
    }
  }

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var r = find(kids[i], name); if (r) return r }
    return null
  }
  function btn() { return find(w, "spotifySwitchButton") }
  function card() { for (var i = 0; i < w.children.length; i++) if (w.children[i].loadedContent !== undefined) return w.children[i]; return null }
  function btn2() { return find(w2, "spotifySwitchButton") }
  function rows() {
    var col = find(w, "spotifySwitchDevices")
    var out = []
    if (!col) return out
    for (var i = 0; i < col.children.length; i++) if (col.children[i].dev !== undefined) out.push(col.children[i])
    return out
  }
  function rowByName(n) { var r = rows(); for (var i = 0; i < r.length; i++) if (r[i].dev && r[i].dev.name === n) return r[i]; return null }
  function rowClick(r) { for (var i = 0; i < r.children.length; i++) if (r.children[i].hoverEnabled !== undefined) { r.children[i].clicked(null); return } }
  function vis(name) { var o = find(w, name); return !!o && o.visible && o.height > 0 }
  function glyph() { return find(w, "spotifySwitchHeroGlyph") }
  function metaLabel() {
    var want = String(find(w, "spotifySwitchHero").meta || "").toUpperCase()
    function walk(item) {
      if (!item) return null
      if (item.truncated !== undefined && String(item.text || "") === want) return item
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) { var r = walk(kids[i]); if (r) return r }
      return null
    }
    return walk(find(w, "spotifySwitchHero"))
  }
  // Popup size per state: a message must never change it.
  property var heights: ({})
  function hgt(label) { var h = heights; h[label] = Math.round(card().height) + "x" + Math.round(card().width) + "/" + Math.round(find(w, "spotifySwitchHero").height); heights = h }
  function leftX(o) { return Math.round(o.mapToItem(canvas, 0, 0).x) }
  function expect(name, got, want) {
    var good = got === want
    console.log("SW " + name + " got=" + got + " want=" + want + (good ? " ok" : " FAIL"))
    if (!good) ok = false
  }
  // The offscreen software window only syncs the scene graph when a frame is
  // drawn, so the first grab after a change can show the frame before it.
  // Grab once to sync, then save the second grab.
  function shot(name) {
    var g = canvas.grabToImage(function() {
      canvas.grabToImage(function(r) { var s = r.saveToFile(Quickshell.env("SW_SHOTS") + "/" + name + ".png"); console.log("SW SHOT " + name + " saved=" + s) })
    })
    console.log("SW SHOT " + name + " requested=" + g)
  }
  // Pretend the pointer sits on the icon: WidgetButton asks the bar to show
  // its tooltipText on enter.
  function hover() { barStub.showTooltip(btn(), btn().tooltipText) }

  Component.onCompleted: {
    var c = Qt.createComponent(Quickshell.env("SW_SRC") + "/SpotifySwitch.qml")
    if (c.status !== Component.Ready) { console.log("SW ERR " + c.errorString()); console.log("SW RESULT FAIL"); return }
    w = c.createObject(slot, { bar: barStub })
    w.anchors.fill = slot
    w2 = c.createObject(slot2, { bar: barStub, settings: { icon: "spotify" } }); w2.anchors.fill = slot2
    var nc = [Quickshell.env("SW_NOTIFY")]
    w.notifyCommand = nc; w2.notifyCommand = nc
    // The suite drives reads itself; the 10 s open timer is tested in one step.
    w.openRefreshMs = 0; w2.openRefreshMs = 0
    t0.start()
  }

  // ---------------- bar icon ----------------
  // The first Spotify read is slow (1.5 s in the fake): the cache shows first.
  Timer { id: t0; interval: 400; onTriggered: {
    expect("cached device shown before Spotify answers", w.shown ? w.shown.name : "", "XPS")
    expect("Spotify read still running (shown without waiting)", w.reading, true)
    expect("icon lit", btn().dimmed, false)
    expect("helper (serve) running", w.helperUp, true)
    expect("glyph nf-md-monitor_speaker (fixed)", btn().text, String.fromCodePoint(0xF0F5F))
    expect("2nd entry: leftover icon setting ignored", btn2().text, String.fromCodePoint(0xF0F5F))
    expect("glyph really drawn (Nerd Font found, not a fallback box)", btn().glyphPaintedWidth >= 10, true)
    expect("both entries show the cached device", w2.shown ? w2.shown.name : "", "XPS")
    expect("both entries same slot width", btn2().width === btn().width, true)
    console.log("SW geometry: slots " + [btn(), btn2()].map(function(b) { var p = b.mapToItem(canvas, 0, 0); return Math.round(p.x) + "," + Math.round(p.y) + " " + Math.round(b.width) + "x" + Math.round(b.height) + " glyph " + Math.round(b.glyphPaintedWidth * 10) / 10 + "px wide, " + b.glyphFontSize + "px font, centre error " + Math.round(b.opticalCenterErrorX * 10) / 10 }).join(" | "))
    expect("icon slot width (stock BarIconButton)", btn().width, Style.bar.iconSlot)
    hover()
    expect("no hover tooltip (empty tooltipText)", btn().tooltipText, "")
    expect("hover shows nothing", barStub.tipShows, 0)
    expect("popup closed at start", w.opened, false)
    expect("no notification at start", w.noticeCount, 0)
    t1.start() } }
  Timer { id: t1; interval: 1800; onTriggered: { shot("1-bar"); t1b.start() } }
  Timer { id: t1b; interval: 300; onTriggered: {
    btn().pressed(Qt.RightButton)
    expect("right click: next device at once (optimistic)", w.shown.name, "Arcade")
    expect("right click: popup stays closed", w.opened, false)
    t2.start() } }
  Timer { id: t2; interval: 1800; onTriggered: {
    expect("backend agrees", w.st.device ? w.st.device.name : "", "Arcade")
    expect("the other entry follows the click via the cache file", w2.shown ? w2.shown.name : "", "Arcade")
    expect("not pending", w.pending, false)
    expect("successful switch: no notification", w.noticeCount, 0)
    btn().pressed(Qt.RightButton); btn().pressed(Qt.RightButton); btn().pressed(Qt.RightButton)
    expect("3 rapid right clicks: shows the third target at once (wraps)", w.shown.name, "gaming PC")
    t3.start() } }
  Timer { id: t3; interval: 3500; onTriggered: {
    expect("3 rapid right clicks: ends on gaming PC", w.st.device ? w.st.device.name : "", "gaming PC")
    var r0 = w.lastRead
    btn().pressed(Qt.LeftButton)
    expect("left click opens the popup", w.opened, true)
    expect("opening reads Spotify (an event, not a poll)", w.lastRead > r0, true)
    p1.start() } }

  // ---------------- popup: devices ----------------
  Timer { id: p1; interval: 900; onTriggered: {
    var col = find(w, "spotifySwitchPanelColumn"), hero = find(w, "spotifySwitchHero")
    expect("popup: card width = stock Bluetooth popup (Style.space(380))", card() ? Math.round(card().width) : -1, Style.space(380))
    expect("popup: column spacing Style.space(14)", col.spacing, Style.space(14))
    expect("popup: heading is Spotify Device Switcher", hero.title, "Spotify Device Switcher")
    expect("popup: tagline while playing with another device to switch to", hero.meta, "Right click the icon to switch")
    expect("popup still open", w.opened, true)
    var r = rows()
    expect("popup: lists every device in cycle order", r.map(function(x) { return x.dev.name }).join(","), "Pixel 10 Pro,gaming PC,XPS,Arcade,Kitchen speaker")
    expect("popup: the active device is the current row", r.filter(function(x) { return x.current }).map(function(x) { return x.dev.name }).join(","), "gaming PC")
    expect("popup: active row says Playing", rowByName("gaming PC").statusText, "Playing")
    expect("popup: other rows have no value", rowByName("XPS").statusText, "")
    expect("popup: flush left (hero, header, rows share the left edge)", leftX(hero) === leftX(find(w, "spotifySwitchDevices")) && leftX(hero) === leftX(col), true)
    expect("popup: no message line above the list (messages use the tagline)", find(w, "spotifySwitchProblem"), null)
    hgt("devices")
    expect("popup: no login row", vis("spotifySwitchLogin"), false)
    expect("popup open: still no tooltip", barStub.tipShows, 0)
    console.log("SW popup geometry: card " + Math.round(card().width) + "x" + Math.round(card().height) + ", rows " + r.map(function(x) { return Math.round(x.height) }).join("/") + " px")
    var xs = r.map(function(x) { var n = find(x, "spotifySwitchRowName"); return Math.round(n.mapToItem(canvas, 0, 0).x) })
    expect("popup: device names line up whatever the glyph", xs.every(function(v) { return v === xs[0] }), true)
    shot("5-popup-devices")
    console.log("SW CTL pause")
    live.start() } }

  // Tagline must follow a status change while the popup stays open (0.2.3).
  // Wait out the backend's 6 s transfer-trust window from the earlier clicks,
  // and give the test harness time to flip the fake Spotify state.
  Timer { id: live; interval: 4000; onTriggered: {
    expect("still open before the live read", w.opened, true)
    w.refresh()
    live2.start() } }
  Timer { id: live2; interval: 1500; onTriggered: {
    expect("tagline updates while open (play -> pause), no reopen", w.opened + " | " + w.heroStatusText, "true | Paused · switching keeps it paused")
    expect("active row now says Active (paused)", rowByName("gaming PC").statusText, "Active")
    hgt("paused")
    shot("14-popup-paused")
    console.log("SW CTL play")
    live3.start() } }
  Timer { id: live3; interval: 400; onTriggered: { w.refresh(); live4.start() } }
  Timer { id: live4; interval: 1500; onTriggered: {
    expect("tagline updates while open (pause -> play), no reopen", w.opened + " | " + w.heroStatusText, "true | Right click the icon to switch")
    // The 10 s timer itself: a short interval, a device drops off, no manual refresh, no reopen.
    console.log("SW CTL drop-arcade")
    live5a.start() } }
  Timer { id: live5a; interval: 800; onTriggered: {
    w.openRefreshMs = 600
    live5.start() } }
  Timer { id: live5; interval: 1800; onTriggered: {
    expect("open timer re-reads on its own (Arcade gone), popup stayed open", w.opened + " | " + rows().map(function(x) { return x.dev.name }).join(","), "true | Pixel 10 Pro,gaming PC,XPS,Kitchen speaker")
    expect("tagline still the playing hint (others on)", w.heroStatusText, "Right click the icon to switch")
    w.openRefreshMs = 0
    console.log("SW CTL restore")
    live6.start() } }
  Timer { id: live6; interval: 400; onTriggered: { w.refresh(); live7.start() } }
  Timer { id: live7; interval: 1500; onTriggered: {
    expect("list restored, still open", w.opened + " | " + rows().length, "true | 5")
    egg0.start() } }

  // ---------------- popup: right click the heading glyph (easter egg) ----------------
  readonly property var eggLines: [
    "Wrong icon, captain · try the one up top",
    "Not this one · right click the bar icon",
    "Almost · the little one up top switches",
    "This one's for show · try the bar icon",
    "Nice try · the icon up top is the one"
  ]
  Timer { id: egg0; interval: 200; onTriggered: {
    expect("heading glyph is a click target", !!glyph(), true)
    var shown = w.shown.name, gen = w.clickGen, n = w.noticeCount, tips = barStub.tipShows
    var h0 = Math.round(card().height)
    glyph().pressButton(Qt.LeftButton)
    expect("left click on heading glyph: popup stays open, nothing switches", w.opened + " | " + w.shown.name + " | " + w.pending + " | " + w.clickGen, "true | " + shown + " | false | " + gen)
    expect("left click on heading glyph: tagline unchanged", w.heroStatusText, "Right click the icon to switch")
    expect("left click on heading glyph: no notification or tooltip", (w.noticeCount - n) + " " + (barStub.tipShows - tips), "0 0")
    w.noteMs = 400
    glyph().pressButton(Qt.RightButton)
    expect("right click heading glyph: first joke in the tagline", w.heroStatusText, eggLines[0])
    expect("right click heading glyph: nothing switches", w.shown.name + " | " + w.pending + " | " + w.clickGen, shown + " | false | " + gen)
    expect("right click heading glyph: no notification or tooltip", (w.noticeCount - n) + " " + (barStub.tipShows - tips), "0 0")
    expect("joke tagline is not elided", metaLabel() && !metaLabel().truncated, true)
    expect("joke keeps the popup height", Math.round(card().height), h0)
    hgt("egg")
    egg1.h0 = h0; egg1.shown = shown; egg1.gen = gen
    egg1.start() } }
  Timer { id: egg1; interval: 700; property int h0: 0; property string shown: ""; property int gen: 0; onTriggered: {
    expect("joke reverts to the real tagline after a short wait", w.heroStatusText, "Right click the icon to switch")
    expect("reverted joke: still the same device, popup open", w.opened + " | " + w.shown.name + " | " + w.pending, "true | " + shown + " | false")
    w.noteMs = 4000
    w.eggAt = 0
    var n = w.noticeCount, tips = barStub.tipShows
    for (var i = 0; i < eggLines.length; i++) {
      glyph().pressButton(Qt.RightButton)
      expect("heading glyph joke " + (i + 1) + " of " + eggLines.length, w.heroStatusText, eggLines[i])
      expect("  not elided", metaLabel() && !metaLabel().truncated, true)
    }
    glyph().pressButton(Qt.RightButton)
    expect("heading glyph jokes wrap to the first line", w.heroStatusText, eggLines[0])
    expect("rotated jokes: nothing switched, no notice or tooltip", w.shown.name + " | " + w.pending + " | " + w.clickGen + " | " + (w.noticeCount - n) + " " + (barStub.tipShows - tips), shown + " | false | " + gen + " | 0 0")
    expect("rotated jokes: popup height unchanged", Math.round(card().height), h0)
    shot("15-popup-header-egg")
    console.log("SW CTL slowput")
    p1b.start() } }
  Timer { id: p1b; interval: 400; onTriggered: {
    expect("egg still showing just before a real switch", w.heroStatusText, eggLines[0])
    rowClick(rowByName("Pixel 10 Pro"))
    expect("row click: shows the choice at once", w.shown ? w.shown.name : "", "Pixel 10 Pro")
    expect("row click: row says Switching…", rowByName("Pixel 10 Pro").statusText, "Switching…")
    expect("row click: egg gives way at once to Switching to …", find(w, "spotifySwitchHero").meta, "Switching to Pixel 10 Pro")
    expect("row click: popup stays open", w.opened, true)
    p1c.start() } }
  Timer { id: p1c; interval: 350; onTriggered: {
    expect("row click: still switching (slow PUT), choice is the current row", rowByName("Pixel 10 Pro").statusText + " " + rowByName("Pixel 10 Pro").current, "Switching… true")
    hgt("switching")
    shot("6-popup-switching")
    p2.start() } }
  Timer { id: p2; interval: 1800; onTriggered: {
    expect("row click: backend moved playback to the choice", w.st.device ? w.st.device.name : "", "Pixel 10 Pro")
    expect("row click: not the cycle's next (that was XPS)", w.st.device ? w.st.device.id : "", "px")
    expect("row click: Pixel is now the current row", rowByName("Pixel 10 Pro").current && !rowByName("gaming PC").current, true)
    expect("row click: no notification", w.noticeCount, 0)
    var before = w.clickGen
    rowClick(rowByName("Pixel 10 Pro"))
    expect("click on the active row: nothing sent", w.clickGen === before && !w.pending, true)
    // Keyboard: the first j/k shows the cursor, the next ones move it, Enter picks.
    var kc = card().loadedContent
    kc.moveRequested(0, 1)
    expect("keyboard: first move shows the cursor on the active row", w.cursorActive + " " + w.selectedIndex, "true 0")
    kc.moveRequested(0, 1); kc.moveRequested(0, 1)
    expect("keyboard: j j moves to XPS", rows()[w.selectedIndex].dev.name + " " + rows()[w.selectedIndex].hasCursor, "XPS true")
    kc.returnRequested(); kc.activateRequested()   // what Enter sends
    expect("keyboard: Enter picks it at once", w.shown ? w.shown.name : "", "XPS")
    expect("keyboard: Enter on a row does not touch its switch", rowByName("XPS").allowed, true)
    d1.start() } }

  // ---------------- popup: a switch per device (never switch to it) ----------------
  function sw(name) { return find(rowByName(name), "spotifySwitchRowToggle") }
  function backendActive() { return w.st.device ? w.st.device.name : "" }
  Timer { id: d1; interval: 1800; onTriggered: {
    var r = rows()
    expect("switches: one per row, all on by default", r.map(function(x) { var t = find(x, "spotifySwitchRowToggle"); return t && t.checked ? "on" : "off" }).join(","), "on,on,on,on,on")
    expect("switches: hint under the list", find(w, "spotifySwitchHelp").text, "Turn a device off to skip it when switching.")
    var rights = r.map(function(x) { var t = find(x, "spotifySwitchRowToggle"); return Math.round(t.mapToItem(canvas, t.width, 0).x) })
    expect("switches: line up on the right edge", rights.every(function(v) { return v === rights[0] }), true)
    expect("switches: inside the card", rights[0] <= Math.round(card().mapToItem(canvas, card().width, 0).x), true)
    expect("switches: no tooltip on the bar icon", barStub.tipShows, 0)
    shot("5b-popup-switches-on")
    d1b.start() } }
  Timer { id: d1b; interval: 400; onTriggered: {
    // Mouse: the Arcade switch (Kurt's Fire TV in real life).
    var n = w.noticeCount
    sw("Arcade").toggled()
    expect("switch click: the row follows at once, off", rowByName("Arcade").allowed + " " + sw("Arcade").checked, "false false")
    expect("switch click: row says Skipped, dimmed", rowByName("Arcade").statusText + " " + rowByName("Arcade").bright, "Skipped false")
    expect("switch click: the row was not picked (XPS still plays)", w.shown.name + " " + w.pending, "XPS false")
    expect("switch click: same hint text (one text for every state)", find(w, "spotifySwitchHelp").text, "Turn a device off to skip it when switching.")
    hgt("one-off")
    expect("switch click: no notification", w.noticeCount - n, 0)
    d2.start() } }
  Timer { id: d2; interval: 900; onTriggered: {
    expect("backend saved it: the cache agrees (Arcade off, others on)", w.st.devices.map(function(x) { return x.enabled === false ? "off" : "on" }).join(","), "on,on,on,off,on")
    rowClick(rowByName("Arcade"))
    expect("a click on a turned-off row: no text, nothing moves", "[" + w.panelNote + "] " + w.heroStatusText + " | " + w.shown.name + " " + w.pending, "[] Right click the icon to switch | XPS false")
    hgt("click-on-off-row")
    w.setNote("A long note that is a good deal longer than the tagline line can hold at once")
    expect("a note replaces the tagline (one line, elided)", find(w, "spotifySwitchHero").meta.indexOf("A long note") === 0, true)
    hgt("long-note")
    w.setNote("")
    btn().pressed(Qt.RightButton)
    expect("right click skips the turned-off device (XPS -> Kitchen speaker, not Arcade)", w.shown.name, "Kitchen speaker")
    d3.start() } }
  Timer { id: d3; interval: 1800; onTriggered: {
    expect("  backend agrees", backendActive(), "Kitchen speaker")
    // Keyboard: Right moves to the switch, Space (or Enter there) toggles, Enter on the row picks.
    var kc = card().loadedContent
    kc.moveRequested(0, 1); kc.moveRequested(0, 1); kc.moveRequested(0, 1); kc.moveRequested(0, 1)
    expect("keyboard: cursor on the Kitchen speaker row", rows()[w.selectedIndex].dev.name + " " + rowByName("Kitchen speaker").hasCursor + " " + sw("Kitchen speaker").hasCursor, "Kitchen speaker true false")
    kc.moveRequested(1, 0)
    expect("keyboard: Right puts the cursor on the switch", rowByName("Kitchen speaker").hasCursor + " " + sw("Kitchen speaker").hasCursor, "false true")
    kc.activateRequested()   // Space
    expect("keyboard: Space on the switch turns the active device off", rowByName("Kitchen speaker").allowed, false)
    expect("  the active device stays highlighted and normal, says Playing · skipped", rowByName("Kitchen speaker").current + " " + rowByName("Kitchen speaker").bright + " " + rowByName("Kitchen speaker").statusText, "true true Playing · skipped")
    expect("  tagline still offers the right click (others are on)", find(w, "spotifySwitchHero").meta, "Right click the icon to switch")
    hgt("active-off")
    shot("11-popup-active-off")
    d3b.start() } }
  Timer { id: d3b; interval: 400; onTriggered: {
    var kc = card().loadedContent
    kc.returnRequested(); kc.activateRequested()   // Enter on the switch
    expect("keyboard: Enter on the switch turns it on again", rowByName("Kitchen speaker").allowed, true)
    kc.moveRequested(-1, 0)
    expect("keyboard: Left goes back to the row", rowByName("Kitchen speaker").hasCursor + " " + sw("Kitchen speaker").hasCursor, "true false")
    kc.activateRequested()   // Space on the row
    expect("keyboard: Space on the row turns it off too", rowByName("Kitchen speaker").allowed, false)
    d4.start() } }
  Timer { id: d4; interval: 900; onTriggered: {
    var kc = card().loadedContent
    expect("backend saved both: Arcade and Kitchen speaker off", w.st.devices.map(function(x) { return x.enabled === false ? "off" : "on" }).join(","), "on,on,on,off,off")
    btn().pressed(Qt.RightButton)
    expect("right click from a turned-off active device: next enabled one (wraps to Pixel 10 Pro)", w.shown.name, "Pixel 10 Pro")
    d5.start() } }
  Timer { id: d5; interval: 1800; onTriggered: {
    expect("  backend agrees", backendActive(), "Pixel 10 Pro")
    expect("popup open: no notification for any of it", w.noticeCount, 0)
    hgt("two-off")
    shot("10-popup-two-off")
    d5a.start() } }
  Timer { id: d5a; interval: 400; onTriggered: {
    // Everything off.
    sw("Pixel 10 Pro").toggled(); sw("gaming PC").toggled(); sw("XPS").toggled()
    expect("all off: tagline says so", find(w, "spotifySwitchHero").meta, "All devices are turned off")
    expect("all off: icon greyed out", btn().dimmed, true)
    d5b.start() } }
  Timer { id: d5b; interval: 900; onTriggered: {
    expect("all off: saved, the cache agrees", w.st.devices.map(function(x) { return x.enabled === false ? "off" : "on" }).join(","), "off,off,off,off,off")
    btn().pressed(Qt.RightButton)
    expect("all off: right click stays put, no note (the tagline says it)", w.shown.name + " | [" + w.panelNote + "]", "Pixel 10 Pro | []")
    expect("  and is not a notification (popup open)", w.noticeCount, 0)
    d6.start() } }
  Timer { id: d6; interval: 1500; onTriggered: {
    expect("all off: nothing moved, playback still on Pixel 10 Pro", backendActive() + " " + w.pending, "Pixel 10 Pro false")
    hgt("all-off")
    expect("all off: told once (the answer does not repeat it)", w.noticeCount, 0)
    shot("12-popup-all-off")
    d6b.start() } }
  Timer { id: d6b; interval: 400; onTriggered: {
    // Back to normal, Arcade stays off for the rest of the run.
    sw("Pixel 10 Pro").toggled(); sw("gaming PC").toggled(); sw("XPS").toggled(); sw("Kitchen speaker").toggled()
    d7.start() } }
  Timer { id: d7; interval: 900; onTriggered: {
    expect("turned back on: icon lit again", btn().dimmed, false)
    expect("turned back on: only Arcade is off", w.st.devices.map(function(x) { return x.enabled === false ? "off" : "on" }).join(","), "on,on,on,off,on")
    rowClick(rowByName("XPS"))
    d8.start() } }
  Timer { id: d8; interval: 1800; onTriggered: {
    expect("a turned-on device can be picked again (XPS)", backendActive(), "XPS")
    btn().pressed(Qt.LeftButton)
    expect("left click again closes the popup", w.opened, false)
    p3.start() } }
  Timer { id: p3; interval: 1800; onTriggered: {
    expect("choice made right before closing still lands", w.st.device ? w.st.device.name : "", "XPS")
    console.log("SW CTL premium")
    t4.start() } }

  // ---------------- problems ----------------
  Timer { id: t4; interval: 600; onTriggered: {
    btn().pressed(Qt.RightButton)
    t5.start() } }
  Timer { id: t5; interval: 1800; onTriggered: {
    expect("403 Premium: message says so", w.message, "Spotify: Premium needed to switch devices")
    expect("403 Premium (popup closed): notified once", w.noticeCount + " " + w.lastNotice, "1 Spotify: Premium needed to switch devices")
    expect("403 Premium: icon dimmed", btn().dimmed, true)
    btn().pressed(Qt.LeftButton)
    t5b.start() } }
  Timer { id: t5b; interval: 1500; onTriggered: {
    expect("popup opened after a failed click: reads Spotify again (state ok)", w.st.state, "ok")
    console.log("SW CTL premium2")
    t5c.start() } }
  Timer { id: t5c; interval: 600; onTriggered: {
    var n = w.noticeCount
    rowClick(rowByName("Pixel 10 Pro"))
    t5d.n = n
    t5d.start() } }
  Timer { id: t5d; property int n: 0; interval: 1500; onTriggered: {
    expect("popup: a refused choice shows in the tagline, no extra line", find(w, "spotifySwitchHero").meta, "Premium needed to switch")
    hgt("premium")
    var hs = shell.heights, names = Object.keys(hs)
    console.log("SW popup sizes (card WxH/hero): " + names.map(function(k) { return k + "=" + hs[k] }).join(" "))
    expect("popup size is identical in every state with the five devices (" + names.length + " states)", names.map(function(k) { return hs[k] }).filter(function(v, i, a) { return a.indexOf(v) === i }).length, 1)
    expect("popup: last known devices still listed, XPS still current", rows().length + " " + (rowByName("XPS") && rowByName("XPS").current), "5 true")
    expect("popup open: no notification for it", w.noticeCount - n, 0)
    shot("7-popup-premium")
    t5e.start() } }
  Timer { id: t5e; interval: 400; onTriggered: {
    btn().pressed(Qt.LeftButton)
    console.log("SW CTL single")
    t6.start() } }
  Timer { id: t6; interval: 600; onTriggered: {
    w.refresh(); t7.start() } }
  Timer { id: t7; interval: 1500; onTriggered: {
    expect("one device (nothing to switch to): icon greyed out", btn().dimmed, true)
    expect("one device: tagline", w.heroStatusText, "No other device to switch to")
    btn().pressed(Qt.RightButton)
    expect("one device: right click says so at once", w.message, "Spotify: XPS (only device available)")
    expect("one device: notified", w.lastNotice, "Spotify: XPS (only device available)")
    t8.start() } }
  Timer { id: t8; interval: 1500; onTriggered: {
    expect("one device: still XPS", w.shown ? w.shown.name : "", "XPS")
    shot("13-bar-nothing-to-switch")
    expect("one device: one notice for the click", w.noticeCount, 2)
    console.log("SW CTL empty")
    e1.start() } }
  Timer { id: e1; interval: 600; onTriggered: { btn().pressed(Qt.LeftButton); e2.start() } }
  Timer { id: e2; interval: 1500; onTriggered: {
    expect("no devices: state no_device", w.st.state, "no_device")
    expect("popup empty: no rows", rows().length, 0)
    expect("popup empty: help text", vis("spotifySwitchHelp") ? find(w, "spotifySwitchHelp").text : "", "No Spotify Connect devices. Open Spotify on a phone, computer or speaker and it shows up here.")
    expect("popup empty: tagline", find(w, "spotifySwitchHero").meta, "Open Spotify on a device")
    expect("no devices: icon dimmed", btn().dimmed, true)
    shot("8-popup-empty")
    e3.start() } }
  Timer { id: e3; interval: 400; onTriggered: {
    btn().pressed(Qt.LeftButton)
    console.log("SW CTL logout")
    t9.start() } }

  // ---------------- logged out ----------------
  Timer { id: t9; interval: 1500; onTriggered: {
    expect("logged out (cache event, no poll): state", w.st.state + " | " + w.message, "need_login | Spotify: not logged in (run omarchy-spotify-switch-login)")
    expect("logged out: icon dimmed", btn().dimmed, true)
    btn().pressed(Qt.RightButton)
    expect("logged out right click: notified", w.lastNotice, "Spotify: opening the login in your browser")
    t9b.start() } }
  Timer { id: t9b; interval: 1500; onTriggered: {
    expect("logged out right click: login helper ran", w.noticeCount >= 4, true)
    btn().pressed(Qt.LeftButton)
    t9c.start() } }
  Timer { id: t9c; interval: 400; onTriggered: {
    expect("popup logged out: login row", vis("spotifySwitchLogin"), true)
    expect("popup logged out: no device list", vis("spotifySwitchDevices"), false)
    expect("popup logged out: tagline", find(w, "spotifySwitchHero").meta, "Not logged in")
    shot("9-popup-logged-out")
    t9e.start() } }
  Timer { id: t9e; interval: 400; onTriggered: {
    var n = w.noticeCount
    rowClick(find(w, "spotifySwitchLogin"))
    expect("popup login row: told in the tagline, not as a notification", w.heroStatusText + " | " + (w.noticeCount - n), "Opening login in your browser | 0")
    t9d.start() } }
  Timer { id: t9d; interval: 1500; onTriggered: {
    expect("popup login row: a failed login is told in the popup", w.panelNote, "Login did not finish")
    expect("popup login note is in the tagline slot", find(w, "spotifySwitchHero").meta, "Login did not finish")
    expect("still no tooltip shown, whole run", barStub.tipShows, 0)
    t10.start() } }
  Timer { id: t10; interval: 600; onTriggered: { console.log("SW RESULT " + (shell.ok ? "PASS" : "FAIL")) } }
}
