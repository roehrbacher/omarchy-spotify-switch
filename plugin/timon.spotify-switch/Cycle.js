.pragma library
// The device after `fromId` in the cycle the backend already sorted
// (status.devices), wrapping and skipping restricted devices; the first
// usable one when `fromId` is unknown or empty. null when there is nothing
// else to switch to. Same rule as next_device() in omarchy-spotify-switch;
// the widget only uses it to show the target at once, the backend decides.
function nextDevice(devices, fromId) {
  var list = Array.isArray(devices) ? devices : []
  var usable = list.filter(function(d) { return d && !d.restricted })
  if (usable.length === 0) return null
  var i = -1
  for (var k = 0; k < list.length; k++) if (list[k] && list[k].id === fromId) { i = k; break }
  if (i < 0) return usable[0]
  for (var s = 1; s <= list.length; s++) {
    var d = list[(i + s) % list.length]
    if (d && !d.restricted && d.id !== fromId) return d
  }
  return null
}

// Bar glyph for the "icon" setting: a preset name, "U+XXXX", or a glyph of
// one or two characters (one code point outside the BMP is two). Anything
// else falls back to the Spotify logo.
var presets = {
  "spotify": 0xF1BC,           // nf-fa-spotify (default)
  "devices": 0xF0FB0,          // nf-md-devices
  "monitor-speaker": 0xF0F5F   // nf-md-monitor_speaker
}
function glyph(value) {
  var v = String(value === undefined || value === null ? "" : value).trim()
  var key = v.toLowerCase().replace(/[_ ]/g, "-")
  if (presets.hasOwnProperty(key)) return String.fromCodePoint(presets[key])
  var m = /^u\+([0-9a-f]{4,6})$/i.exec(v)
  if (m) {
    var cp = parseInt(m[1], 16)
    if (cp > 0 && cp <= 0x10FFFF) return String.fromCodePoint(cp)
  }
  if (v.length > 0 && v.length <= 2) return v
  return String.fromCodePoint(presets["spotify"])
}
