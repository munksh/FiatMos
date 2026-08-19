import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// What a list says when it is empty.
//
// Not Silica's ViewPlaceholder, which draws its text in Theme.highlightColor
// and its hint in Theme.secondaryHighlightColor and exposes no way to change
// either. Under Fiat colours that is the ambience bleeding through the one
// piece of text on an otherwise empty screen -- the most visible place it
// could possibly show.
//
// Same geometry as Silica's: sat in the upper third, because a placeholder
// centred in an empty page reads as an error message.

Item {
    id: root

    property bool enabled: false
    property string text: ""
    property string hintText: ""

    anchors.fill: parent
    visible: root.enabled
    opacity: root.enabled ? 1.0 : 0.0
    Behavior on opacity { FadeAnimation { } }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.28
        width: parent.width - Theme.horizontalPageMargin * 4
        spacing: Theme.paddingLarge

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.text
            font.pixelSize: Theme.fontSizeLarge
            font.family: FiatMosTheme.serif
            color: FiatMosTheme.primaryText
        }

        Label {
            width: parent.width
            visible: root.hintText !== ""
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.hintText
            font.pixelSize: Theme.fontSizeExtraSmall
            color: FiatMosTheme.secondaryText
        }
    }
}
