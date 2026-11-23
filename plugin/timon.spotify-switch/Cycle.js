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
