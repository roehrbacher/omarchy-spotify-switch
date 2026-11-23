import Quickshell
import QtQuick
import qs.Commons
// See run.sh. A bar strip with the widget and a stand-in for the bar's
// tooltip (the real one belongs to Omarchy's Bar), in a plain window so it
// renders with the offscreen platform and the software backend.
ShellRoot {
  id: shell
  property var w: null
  property bool ok: true
  property int step: 0

  QtObject {
    id: barStub
    property color foreground: "#e6e6e6"; property color barForeground: "#e6e6e6"; property color urgent: "red"
    property string fontFamily: "JetBrainsMono Nerd Font"; property bool vertical: false; property int barSize: 30
    property string position: "top"
    property string tipText: ""
    property int tipShows: 0
    function showTooltip(a, t) { tipText = String(t); tipShows++ }
    function hideTooltip(a) {}
    function run(c) {}
    function registerClickTarget(t) {} function unregisterClickTarget(t) {}
    function moduleWidgets(id) { return [] }
  }

  FloatingWindow {
    id: win
    implicitWidth: 360; implicitHeight: 96
    color: "#1e1e2e"
    Rectangle { id: canvas; anchors.fill: parent; color: "#1e1e2e"
    Rectangle { id: strip; width: parent.width; height: 30; color: "#181825"
      Item { id: slot; x: 300; y: 0; width: 30; height: 30 }
    }
    // Tooltip stand-in under the icon, like Omarchy's bar tooltip card.
    Rectangle {
      id: tipCard
      visible: barStub.tipText !== ""
      anchors.top: strip.bottom; anchors.topMargin: 8
      x: Math.min(win.width - width - 6, slot.x + 15 - width / 2)
      width: tipLabel.implicitWidth + 20; height: tipLabel.implicitHeight + 12
      radius: 4; color: "#313244"; border.color: "#45475a"
      Text { id: tipLabel; anchors.centerIn: parent; text: barStub.tipText; color: "#e6e6e6"
        font.family: Style.font.menuFamily; font.pixelSize: Style.font.body }
    }
    }
  }

  function btn() { return w.children[0] }
  function expect(name, got, want) {
    var good = got === want
    console.log("SW " + name + " got=" + got + " want=" + want + (good ? " ok" : " FAIL"))
    if (!good) ok = false
  }
  function shot(name) {
    var g = canvas.grabToImage(function(r) { var s = r.saveToFile(Quickshell.env("SW_SHOTS") + "/" + name + ".png"); console.log("SW SHOT " + name + " saved=" + s) })
    console.log("SW SHOT " + name + " requested=" + g + " visible=" + win.visible + " size=" + canvas.width + "x" + canvas.height)
  }
  // Pretend the pointer sits on the icon: the bar shows its tooltip text.
  function hover() { barStub.showTooltip(btn(), btn().tooltipText) }

  Component.onCompleted: {
    var c = Qt.createComponent(Quickshell.env("SW_SRC") + "/SpotifySwitch.qml")
    if (c.status !== Component.Ready) { console.log("SW ERR " + c.errorString()); console.log("SW RESULT FAIL"); return }
    w = c.createObject(slot, { bar: barStub })
    w.anchors.centerIn = slot
    t0.start()
  }
  // The first Spotify read is slow (1.5 s in the fake): the cache shows first.
  Timer { id: t0; interval: 400; onTriggered: {
    expect("cached device shown before Spotify answers", w.shown ? w.shown.name : "", "XPS")
    expect("Spotify read still running (shown without waiting)", w.reading, true)
    expect("icon lit", btn().dimmed, false)
    expect("glyph nf-fa-spotify", btn().text, "\uf1bc")
    expect("icon slot width (stock BarIconButton)", btn().width, Style.bar.iconSlot)
    hover()
    expect("tooltip names the device", barStub.tipText, "Spotify: XPS")
    t1.start() } }
  Timer { id: t1; interval: 1800; onTriggered: { shot("1-xps"); t1b.start() } }
  Timer { id: t1b; interval: 300; onTriggered: {
    var n = barStub.tipShows
    btn().pressed(Qt.LeftButton)
    expect("click: next device at once (optimistic)", w.shown.name, "Arcade")
    expect("click: tooltip at once", w.tip, "Spotify: Arcade")
    hover()
    t2.start() } }
  Timer { id: t2; interval: 1800; onTriggered: {
    expect("backend agrees", w.st.device ? w.st.device.name : "", "Arcade")
    expect("not pending", w.pending, false)
    shot("2-arcade")
    btn().pressed(Qt.LeftButton); btn().pressed(Qt.LeftButton); btn().pressed(Qt.LeftButton)
    expect("3 rapid clicks: shows the third target at once (wraps)", w.shown.name, "gaming PC")
    t3.start() } }
  Timer { id: t3; interval: 3500; onTriggered: {
    expect("3 rapid clicks: ends on gaming PC", w.st.device ? w.st.device.name : "", "gaming PC")
    console.log("SW CTL premium")
    t4.start() } }
  Timer { id: t4; interval: 600; onTriggered: {
    btn().pressed(Qt.LeftButton)
    t5.start() } }
  Timer { id: t5; interval: 1800; onTriggered: {
    expect("403 Premium: tooltip says so", w.tip, "Spotify: Premium needed to switch devices")
    expect("403 Premium: icon dimmed", btn().dimmed, true)
    expect("403 Premium: last known device kept", w.shown ? w.shown.name : "", "gaming PC")
    hover(); shot("3-premium")
    console.log("SW CTL single")
    t6.start() } }
  Timer { id: t6; interval: 600; onTriggered: { w.refresh(); t7.start() } }
  Timer { id: t7; interval: 1500; onTriggered: {
    btn().pressed(Qt.LeftButton)
    expect("one device: click says so at once", w.tip, "Spotify: XPS (only device available)")
    t8.start() } }
  Timer { id: t8; interval: 1500; onTriggered: {
    expect("one device: still XPS", w.shown ? w.shown.name : "", "XPS")
    console.log("SW CTL logout")
    t9.start() } }
  Timer { id: t9; interval: 1500; onTriggered: {
    expect("logged out (cache event, no poll): tooltip", w.tip, "Spotify: not logged in (run omarchy-spotify-switch-login)")
    expect("logged out: icon dimmed", btn().dimmed, true)
    hover(); shot("4-logged-out")
    t10.start() } }
  Timer { id: t10; interval: 600; onTriggered: { console.log("SW RESULT " + (shell.ok ? "PASS" : "FAIL")) } }
}
