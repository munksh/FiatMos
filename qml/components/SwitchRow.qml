import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// Something that is on or off. The whole row is the switch.
//
// The mark is the habit list's own dot, smaller: an empty ring, or filled in
// the accent with a tick. Not Silica's TextSwitch, whose glass light is drawn
// in the ambience's colour and stays that colour under Fiat colours; and not
// a pill, which said "chosen" and "on" with the same shape.
//
//   SwitchRow { text: "Keep private"; checked: page.isPrivate
//               onClicked: page.isPrivate = !page.isPrivate }
//
// `description` is optional and sits under the text, for the cases where on
// and off need explaining -- what a lookup service is sent, say.

BackgroundItem {
    id: root

    property string text: ""
    property string description: ""
    property bool checked: false
    // The text in the house serif, for a row that names something (a service)
    // rather than a setting.
    property bool serifText: false

    width: parent ? parent.width : implicitWidth
    height: Math.max(Theme.itemSizeSmall, col.height + Theme.paddingMedium * 2)
    highlightedColor: FiatMosTheme.highlightWash

    readonly property real dotSize: Theme.itemSizeSmall * 0.36

    Rectangle {
        id: dot
        x: Theme.horizontalPageMargin
        y: col.y + Math.max(0, (titleLabel.height - height) / 2)
        width: root.dotSize
        height: width
        radius: width / 2
        color: root.checked ? FiatMosTheme.accent : "transparent"
        border.width: 1
        border.color: root.checked ? FiatMosTheme.accent : FiatMosTheme.pillBorder

        Label {
            anchors.centerIn: parent
            visible: root.checked
            text: "✓"
            color: FiatMosTheme.markOn(FiatMosTheme.accent)
            font.pixelSize: Theme.fontSizeTiny
        }
    }

    Column {
        id: col
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: dot.right
        anchors.leftMargin: Theme.paddingLarge
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        spacing: Theme.paddingSmall / 2

        Label {
            id: titleLabel
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.text
            font.pixelSize: root.serifText ? Theme.fontSizeMedium : Theme.fontSizeSmall
            font.family: root.serifText ? FiatMosTheme.serif : Theme.fontFamily
            color: root.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
        }

        Label {
            width: parent.width
            visible: root.description !== ""
            wrapMode: Text.WordWrap
            text: root.description
            font.pixelSize: Theme.fontSizeExtraSmall
            color: FiatMosTheme.secondaryText
        }
    }
}
