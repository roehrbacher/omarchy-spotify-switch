import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test-only stand-in for qs.Ui KeyboardPanel: the real one is a Wayland
// layer-shell PanelWindow, which the offscreen platform cannot show. Same
// API the widget uses (anchorItem, owner, bar, open, focusTarget,
// contentWidth/Height, content, loadedContent, loadedContentHeight,
// fittedContent*). It draws the card like the real one (popup background,
// border, Style.cornerRadius, Style.spacing.popupPadding) right under the
// anchor, right-aligned to it, inside the test window.
Item {
  id: root
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property var focusTarget: null
  property int padding: Style.spacing.popupPadding
  readonly property int border: Math.max(1, Style.space(2))
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property Component content: null
  property bool contentRequested: false
  readonly property Item loadedContent: loader.item
  readonly property real loadedContentHeight: loader.item ? loader.item.implicitHeight : 0
  readonly property int verticalContentInset: 2 * (padding + border)

  function fittedContentWidth(w, cap) {
    var d = Math.max(1, Number(w) || 1)
    if (cap !== undefined && Number(cap) > 0) d = Math.min(d, Number(cap))
    return Math.round(d)
  }
  function fittedContentHeight(h, cap) {
    var d = Math.max(verticalContentInset, (Number(h) || 0) + verticalContentInset)
    if (cap !== undefined && Number(cap) > 0) d = Math.min(d, Number(cap))
    return Math.round(d)
  }

  visible: open
  z: 100
  width: contentWidth
  height: contentHeight
  // Under the bar strip (30 px in the test) plus Style.gapsOut, right edge
  // on the anchor's right edge.
  x: anchorItem ? anchorItem.width - width : 0
  y: anchorItem ? anchorItem.height + Style.gapsOut : 0

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.popups.background
    border.color: Commons.Color.popups.border
    border.width: root.border
    radius: Style.cornerRadius
  }

  Item {
    x: root.padding + root.border
    y: root.padding + root.border
    width: root.contentWidth - 2 * (root.padding + root.border)
    height: root.contentHeight - 2 * (root.padding + root.border)
    Loader {
      id: loader
      anchors.fill: parent
      active: !!root.content && (root.open || root.contentRequested)
      sourceComponent: root.content
    }
  }
}
