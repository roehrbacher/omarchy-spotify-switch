import QtQuick
import QtTest
import "../plugin/timon.spotify-switch/Cycle.js" as Cycle

// The widget's optimistic "next device" (Cycle.js) on the backend's
// already-sorted list.
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_cycle.qml
TestCase {
  name: "Cycle"
  function d(id, restricted) { return { id: id, name: id, restricted: !!restricted } }
  readonly property var five: [d("px"), d("pc"), d("xps"), d("ar"), d("ks")]

  function test_next() { compare(Cycle.nextDevice(five, "xps").id, "ar") }
  function test_wrap() { compare(Cycle.nextDevice(five, "ks").id, "px") }
  function test_noneActive() { compare(Cycle.nextDevice(five, "").id, "px") }
  function test_unknownFrom() { compare(Cycle.nextDevice(five, "gone").id, "px") }
  function test_singleActive() { compare(Cycle.nextDevice([d("xps")], "xps"), null) }
  function test_singleInactive() { compare(Cycle.nextDevice([d("xps")], "").id, "xps") }
  function test_empty() { compare(Cycle.nextDevice([], ""), null); compare(Cycle.nextDevice(undefined, "x"), null) }
  function test_skipRestricted() { compare(Cycle.nextDevice([d("a"), d("tv", true), d("b")], "a").id, "b") }
  function test_restrictedActive() { compare(Cycle.nextDevice([d("a"), d("tv", true), d("b")], "tv").id, "b") }
  function test_onlyRestricted() { compare(Cycle.nextDevice([d("tv", true)], ""), null) }
  function test_fullCycleVisitsAll() {
    var seen = [], cur = "xps"
    for (var i = 0; i < 5; i++) { cur = Cycle.nextDevice(five, cur).id; seen.push(cur) }
    compare(seen.join(","), "ar,ks,px,pc,xps")
  }

  // 0.2.0: the popup's words and glyphs
  function test_deviceGlyph() {
    compare(Cycle.deviceGlyph("Computer"), String.fromCodePoint(0xF0379))
    compare(Cycle.deviceGlyph("Smartphone"), String.fromCodePoint(0xF011C))
    compare(Cycle.deviceGlyph("Speaker"), String.fromCodePoint(0xF04C3))
    compare(Cycle.deviceGlyph("TV"), String.fromCodePoint(0xF0502))
    compare(Cycle.deviceGlyph("something new"), String.fromCodePoint(0xF0F5F))
    compare(Cycle.deviceGlyph(undefined), String.fromCodePoint(0xF0F5F))
  }
  function test_heroStatus() {
    var xps = { id: "xps", name: "XPS" }
    var two = [{ id: "xps", name: "XPS" }, { id: "px", name: "Pixel" }]
    compare(Cycle.heroStatus({ state: "ok", playing: true, devices: two }, xps, false), "Right click the icon to switch")
    compare(Cycle.heroStatus({ state: "ok", playing: false, devices: two }, xps, false), "Paused · switching keeps it paused")
    compare(Cycle.heroStatus({ state: "ok", playing: true, devices: [xps] }, xps, false), "No other device to switch to")
    compare(Cycle.heroStatus({ state: "ok", playing: false, devices: [xps] }, xps, false), "No other device to switch to")
    compare(Cycle.heroStatus({ state: "ok", devices: two }, null, false), "Nothing playing")
    compare(Cycle.heroStatus({ state: "ok", devices: [] }, null, false), "Nothing playing")
    compare(Cycle.heroStatus({ state: "ok", playing: true, devices: two }, xps, true), "Switching to XPS")
    compare(Cycle.heroStatus({ state: "need_login" }, null, false), "Not logged in")
    compare(Cycle.heroStatus({ state: "no_client_id" }, null, false), "No client ID")
    compare(Cycle.heroStatus({ state: "no_device" }, null, false), "Open Spotify on a device")
    compare(Cycle.heroStatus({ state: "premium", devices: two }, xps, false), "Premium needed to switch")
    compare(Cycle.heroStatus({ state: "offline", devices: two }, xps, false), "Can't reach Spotify")
    compare(Cycle.heroStatus({ state: "rate_limited" }, xps, false), "Can't reach Spotify")
    compare(Cycle.heroStatus({ state: "error" }, xps, false), "Can't reach Spotify")
    compare(Cycle.heroStatus(null, null, false), "Reading Spotify")
  }
  function test_heroStatusWithTurnedOffDevices() {
    var xps = { id: "xps", name: "XPS" }
    var tv = { id: "tv", name: "TV", enabled: false }
    compare(Cycle.heroStatus({ state: "ok", playing: true, devices: [xps, tv] }, xps, false), "No other device to switch to")
    compare(Cycle.heroStatus({ state: "ok", playing: true, devices: [tv, { id: "px", name: "Pixel" }, xps] }, tv, false), "Right click the icon to switch")
  }
  function test_rowStatus() {
    compare(Cycle.rowStatus(d("xps"), "xps", "", true), "Playing")
    compare(Cycle.rowStatus(d("xps"), "xps", "", false), "Active")
    compare(Cycle.rowStatus(d("px"), "xps", "px", true), "Switching…")
    compare(Cycle.rowStatus(d("tv", true), "xps", "", true), "Not controllable")
    compare(Cycle.rowStatus(d("pc"), "xps", "", true), "")
  }

  // 0.2.1: devices the user turned off (enabled: false) are never switched to
  function off(id) { return { id: id, name: id, restricted: false, enabled: false } }
  function test_enabledDefault() {
    compare(Cycle.isEnabled(d("a")), true)             // old cache: no field
    compare(Cycle.isEnabled(off("a")), false)
    compare(Cycle.isEnabled(null), false)
  }
  function test_nextSkipsOff() {
    var l = [d("px"), d("pc"), off("xps"), off("ar"), d("ks")]
    compare(Cycle.nextDevice(l, "pc").id, "ks")
    compare(Cycle.nextDevice(l, "ks").id, "px")
  }
  function test_nextFromAnOffDevice() {
    var l = [d("px"), d("pc"), off("xps"), d("ar"), d("ks")]
    compare(Cycle.nextDevice(l, "xps").id, "ar")        // the cycle starts from its place
    compare(Cycle.nextDevice([d("px"), off("ks")], "ks").id, "px")
  }
  function test_nothingNextWhenOthersAreOff() {
    compare(Cycle.nextDevice([d("a"), off("b")], "a"), null)
    compare(Cycle.nextDevice([off("a"), off("b")], ""), null)
    compare(Cycle.nextDevice([off("a"), d("b")], "").id, "b")
  }
  function test_noTargetNote() {
    compare(Cycle.noTargetNote([d("XPS")], d("XPS")), "Spotify: XPS (only device available)")
    compare(Cycle.noTargetNote([d("XPS"), off("TV")], d("XPS")), "Spotify: XPS (only enabled device)")
    compare(Cycle.noTargetNote([off("XPS"), off("TV")], d("XPS")), "Spotify: all devices are turned off (left click to turn one on)")
    compare(Cycle.noTargetNote([d("XPS"), { id: "x", name: "x", restricted: true, enabled: false }], d("XPS")), "Spotify: XPS (only device available)")
  }
  function test_allOffAndHint() {
    compare(Cycle.allOff([off("a"), off("b")]), true)
    compare(Cycle.allOff([off("a"), d("b")]), false)
    compare(Cycle.allOff([]), false)
    compare(Cycle.deviceHint([]), "")
    compare(Cycle.deviceHint([d("a")]), "Turn a device off to skip it when switching.")
    compare(Cycle.deviceHint([d("a"), off("b")]), Cycle.deviceHint([d("a")]))      // one text for every state
    compare(Cycle.deviceHint([off("a")]), Cycle.deviceHint([d("a")]))
  }
  function test_rowStatusOff() {
    compare(Cycle.rowStatus(off("tv"), "xps", "", true), "Skipped")
    compare(Cycle.rowStatus(off("xps"), "xps", "", true), "Playing · skipped")
    compare(Cycle.rowStatus(off("xps"), "xps", "", false), "Active · skipped")
    compare(Cycle.rowStatus({ id: "tv", name: "tv", restricted: true, enabled: false }, "xps", "", true), "Not controllable")
  }
  function test_heroAllOff() {
    compare(Cycle.heroStatus({ state: "ok", devices: [off("a"), off("b")] }, null, false), "All devices are turned off")
    compare(Cycle.heroStatus({ state: "ok", devices: [off("a"), d("b")] }, null, false), "Nothing playing")
    compare(Cycle.heroStatus({ state: "ok", playing: true, devices: [off("xps")] }, { id: "xps", name: "XPS" }, false), "All devices are turned off")
    compare(Cycle.heroStatus({ state: "ok", playing: false, devices: [d("a"), d("b")] }, { id: "a", name: "A" }, false), "Paused · switching keeps it paused")
  }
}
