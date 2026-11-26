.pragma library
// A device the user turned off ("enabled": false from the backend) is never
// switched to. Old caches have no `enabled`: on.
function isEnabled(dev) {
  return !!dev && dev.enabled !== false
}
function canTarget(dev) {
  return !!dev && !dev.restricted && isEnabled(dev)
}

// The device after `fromId` in the cycle the backend already sorted
// (status.devices), wrapping and skipping restricted and turned-off devices
// (the current one may be off: the cycle still starts from its place); the
// first usable one when `fromId` is unknown or empty. null when there is
// nothing else to switch to. Same rule as next_device() in
// omarchy-spotify-switch; the widget only uses it to show the target at once,
// the backend decides.
function nextDevice(devices, fromId) {
  var list = Array.isArray(devices) ? devices : []
  var usable = list.filter(canTarget)
  if (usable.length === 0) return null
  var i = -1
  for (var k = 0; k < list.length; k++) if (list[k] && list[k].id === fromId) { i = k; break }
  if (i < 0) return usable[0]
  for (var s = 1; s <= list.length; s++) {
    var d = list[(i + s) % list.length]
    if (canTarget(d) && d.id !== fromId) return d
  }
  return null
}

// Why a right click has nowhere to go; the backend's words (no_target_message).
function noTargetNote(devices, current) {
  var list = Array.isArray(devices) ? devices : []
  var free = list.filter(function(d) { return d && !d.restricted })
  var off = free.filter(function(d) { return !isEnabled(d) })
  var who = current && current.name ? String(current.name) : "this device"
  if (off.length > 0 && off.length === free.length) return "Spotify: all devices are turned off (left click to turn one on)"
  if (off.length > 0) return "Spotify: " + who + " (only enabled device)"
  return "Spotify: " + who + " (only device available)"
}

// True when there are controllable devices and every one is turned off.
function allOff(devices) {
  var list = Array.isArray(devices) ? devices : []
  var free = list.filter(function(d) { return d && !d.restricted })
  return free.length > 0 && free.every(function(d) { return !isEnabled(d) })
}

// The one help line under the device list. Always the same text, so the
// popup keeps its size whatever the devices are doing.
function deviceHint(devices) {
  return Array.isArray(devices) && devices.length > 0 ? "Turn a device off to skip it when switching." : ""
}

// Nerd Font (Material Design) glyph for a Spotify Connect device type
// (Spotify's `type`: Computer, Smartphone, Speaker, TV, ...). Unknown types
// get the plugin's own monitor-speaker glyph.
var typeGlyphs = {
  "computer": 0xF0379,     // md-monitor
  "smartphone": 0xF011C,   // md-cellphone
  "tablet": 0xF04F6,       // md-tablet
  "speaker": 0xF04C3,      // md-speaker
  "audiodongle": 0xF04C3,
  "tv": 0xF0502,           // md-television
  "stb": 0xF0502,
  "avr": 0xF093D,          // md-audio_video
  "gameconsole": 0xF0297,  // md-gamepad_variant
  "castvideo": 0xF0118,    // md-cast
  "castaudio": 0xF101E,    // md-cast_audio
  "automobile": 0xF010B    // md-car
}
function deviceGlyph(type) {
  var k = String(type || "").toLowerCase()
  return String.fromCodePoint(typeGlyphs.hasOwnProperty(k) ? typeGlyphs[k] : 0xF0F5F)
}

// The tagline under the popup heading (shown in caps): one short line per
// state, from the backend state, the device the widget shows and a click
// still in flight. Never empty, never more than one line.
//   playing, can switch   Right click the icon to switch
//   paused, can switch    Paused · switching keeps it paused
//   no session            Nothing playing
//   nothing else to use   No other device to switch to
//   every device off      All devices are turned off
//   switching             Switching to <device>
//   logged out / no id    Not logged in / No client ID
//   premium               Premium needed to switch
//   offline, busy, error  Can't reach Spotify
//   no devices            Open Spotify on a device
function heroStatus(st, shown, pending) {
  var s = st || {}
  var state = String(s.state || "unknown")
  var name = shown && shown.name ? String(shown.name) : ""
  if (pending && name) return "Switching to " + name
  if (state === "need_login") return "Not logged in"
  if (state === "no_client_id") return "No client ID"
  if (state === "premium") return "Premium needed to switch"
  if (state === "offline" || state === "rate_limited" || state === "error") return "Can't reach Spotify"
  if (state === "no_device") return "Open Spotify on a device"
  if (state === "unknown") return "Reading Spotify"
  if (allOff(s.devices)) return "All devices are turned off"
  var target = nextDevice(s.devices, name ? shown.id : "")
  if (!name) return "Nothing playing"
  if (!target) return "No other device to switch to"
  return s.playing ? "Right click the icon to switch" : "Paused · switching keeps it paused"
}

// Right-hand value of a device row (next to its switch).
function rowStatus(dev, shownId, pendingId, playing) {
  if (!dev) return ""
  if (pendingId && dev.id === pendingId) return "Switching…"
  if (dev.restricted) return "Not controllable"
  var skipped = isEnabled(dev) ? "" : "Skipped"
  if (shownId && dev.id === shownId) return (playing ? "Playing" : "Active") + (skipped ? " · skipped" : "")
  return skipped
}
