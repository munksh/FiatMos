import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../Storage.js" as Storage

CoverBackground {
    id: cover

    property int unlogged: 0
    property int total: 0

    function refresh() {
        unlogged = Storage.unloggedTodayCount()
        total = Storage.activeHabitCount()
    }

    Component.onCompleted: refresh()
    onStatusChanged: {
        if (status === Cover.Active) refresh()
    }

    Connections {
        target: Qt.application
        onStateChanged: cover.refresh()
    }

    // No background here on purpose. A cover is drawn by the home screen,
    // and CoverBackground already provides the right backdrop for it. The
    // Fiat gradient belongs to the app's own pages.

    Column {
        anchors.centerIn: parent
        spacing: Theme.paddingSmall
        width: parent.width - Theme.paddingLarge * 2

        // Serif, to match the wordmark. A grotesque numeral under a serif
        // wordmark reads as two unrelated typefaces.
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: cover.total === 0 ? "–" : cover.unlogged
            font.pixelSize: Theme.fontSizeHuge
            font.family: FiatMosTheme.serif
            color: cover.unlogged > 0 ? FiatMosTheme.accent : FiatMosTheme.secondaryText
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: FiatMosTheme.secondaryText
            text: cover.total === 0 ? qsTr("no habits")
                : cover.unlogged === 0 ? qsTr("all done") : qsTr("left today")
        }
    }

    // The wordmark, lowercase serif italic, same as the app.
    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.paddingMedium
        horizontalAlignment: Text.AlignHCenter
        text: "fiat mos"
        font.pixelSize: Theme.fontSizeTiny
        font.family: FiatMosTheme.serif
        font.italic: true
        color: FiatMosTheme.secondaryText
    }

    // No CoverActionList yet. A "log the next due habit" action would be the
    // obvious one, but cover icon names need verifying on the device first.
}
