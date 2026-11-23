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

  function test_glyphDefault() { compare(Cycle.glyph(""), "\uf1bc"); compare(Cycle.glyph(undefined), "\uf1bc") }
  function test_glyphPresets() {
    compare(Cycle.glyph("spotify"), "\uf1bc")
    compare(Cycle.glyph("devices"), String.fromCodePoint(0xF0FB0))
    compare(Cycle.glyph("monitor-speaker"), String.fromCodePoint(0xF0F5F))
    compare(Cycle.glyph("Monitor_Speaker"), String.fromCodePoint(0xF0F5F))
  }
  function test_glyphCodepoint() { compare(Cycle.glyph("U+F0FB0"), String.fromCodePoint(0xF0FB0)) }
  function test_glyphLiteral() { compare(Cycle.glyph(String.fromCodePoint(0xF04C3)), String.fromCodePoint(0xF04C3)) }
  function test_glyphJunk() { compare(Cycle.glyph("not an icon"), "\uf1bc"); compare(Cycle.glyph("U+110000"), "\uf1bc") }
}
