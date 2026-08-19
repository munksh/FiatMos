import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The house dialog header: Cancel, title, Save.
//
// Not Silica's DialogHeader, which draws both actions in Theme.highlightColor
// -- light on light under Fiat colours plus a dark ambience. You lose the
// drag-to-accept flourish; back-swipe still cancels.
//
// The two actions sit in the very top corners, on the same line as the
// system's own indicators. They are short words in the corners of the screen
// and a centred cutout never reaches them, so there is no reason to push them
// down -- and lining them up with the lights makes them read as part of that
// row rather than as a second, nearly-aligned one. The title is what needs the
// notch clearance, so the title alone takes the inset -- and because it is
// width-capped it cannot slide under either button.

Item {
    id: root

    property string title: ""
    property bool acceptEnabled: true
    property string acceptText: qsTr("Save")
    property string cancelText: qsTr("Cancel")

    signal cancelled()
    signal accepted()

    width: parent ? parent.width : 0
    height: Math.max(FiatMosTheme.statusRowCenter + cancelBtn.height / 2,
                     FiatMosTheme.headerTopInset + titleLabel.height) + Theme.paddingLarge

    BackgroundItem {
        id: cancelBtn
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, FiatMosTheme.statusRowCenter - height / 2)
        height: Theme.itemSizeExtraSmall
        width: cancelLabel.width + Theme.horizontalPageMargin * 2
        highlightedColor: FiatMosTheme.highlightWash
        onClicked: root.cancelled()

        Label {
            id: cancelLabel
            anchors.centerIn: parent
            text: root.cancelText
            font.pixelSize: Theme.fontSizeSmall
            color: cancelBtn.highlighted ? FiatMosTheme.accent : FiatMosTheme.secondaryText
        }
    }

    BackgroundItem {
        id: acceptBtn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, FiatMosTheme.statusRowCenter - height / 2)
        height: Theme.itemSizeExtraSmall
        width: acceptLabel.width + Theme.horizontalPageMargin * 2
        enabled: root.acceptEnabled
        highlightedColor: FiatMosTheme.highlightWash
        onClicked: root.accepted()

        Label {
            id: acceptLabel
            anchors.centerIn: parent
            text: root.acceptText
            font.pixelSize: Theme.fontSizeSmall
            color: !root.acceptEnabled
                ? FiatMosTheme.dotIdle
                : (acceptBtn.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText)
        }
    }

    Label {
        id: titleLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: FiatMosTheme.headerTopInset
        // Centred, so the cap is twice the wider button: that is how much
        // room the title has before it reaches one of them.
        width: Math.max(0, parent.width - 2 * Math.max(cancelBtn.width, acceptBtn.width))
        horizontalAlignment: Text.AlignHCenter
        truncationMode: TruncationMode.Fade
        text: root.title
        font.pixelSize: Theme.fontSizeLarge
        font.family: FiatMosTheme.serif
        color: FiatMosTheme.primaryText
    }
}
