import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The house pill. Deliberately not TextSwitch, which is tall and stacks
// awkwardly when you want a row of selectable values. Wrap these in a Flow
// (not a Grid) so they reflow to content width.

MouseArea {
    id: root

    property string text: ""
    property bool selected: false

    implicitWidth: label.width + Theme.paddingLarge * 2
    implicitHeight: label.height + Theme.paddingMedium
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.selected ? FiatMosTheme.pillFillActive : FiatMosTheme.pillFill
        border.color: root.selected ? FiatMosTheme.pillBorderActive : FiatMosTheme.pillBorder
        border.width: 1
        opacity: root.pressed ? 0.6 : 1.0
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Theme.fontSizeExtraSmall
        font.weight: Font.Bold
        color: root.selected ? FiatMosTheme.accent : FiatMosTheme.primaryText
    }
}
