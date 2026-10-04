import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The family's button, copied from Fiat Ratio. Filled: the one thing this
// page is for. Outlined: the second thing.
//
// Mos has very few of these on purpose -- Sailfish acts through rows and
// pull-down menus, not buttons. The backup page is the exception: choosing a
// file and replacing everything are deliberate acts that deserve a shape.
//
// A rounded rectangle, not a pill: the corners are the card radius, not half
// the height.

BackgroundItem {
    id: root

    property string text: ""
    property string detail: ""        // small, after the text
    property bool filled: true

    width: parent ? parent.width : implicitWidth
    height: Theme.itemSizeMedium + Theme.paddingMedium
    highlightedColor: "transparent"
    opacity: enabled ? 1.0 : 0.35

    readonly property color ink: filled ? FiatMosTheme.markOn(FiatMosTheme.accent) : FiatMosTheme.primaryText

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: Theme.itemSizeMedium
        radius: Theme.paddingLarge
        color: root.filled
               ? (root.highlighted ? Qt.darker(FiatMosTheme.accent, 1.2) : FiatMosTheme.accent)
               : (root.highlighted ? FiatMosTheme.highlightWash : Theme.rgba(FiatMosTheme.card, 0.6))
        border.color: FiatMosTheme.accent
        border.width: root.filled ? 0 : 1

        Row {
            anchors.centerIn: parent
            spacing: Theme.paddingMedium
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                color: root.ink
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatMosTheme.serif
                font.italic: true
                font.bold: root.filled
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.detail !== ""
                text: root.detail
                color: root.ink
                opacity: 0.9
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
