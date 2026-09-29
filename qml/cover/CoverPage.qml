import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../Storage.js" as Storage

CoverBackground {
    id: cover

    property int unlogged: 0
    property int total: 0
    property string shownDay: ""

    function refresh() {
        unlogged = Storage.unloggedTodayCount()
        total = Storage.activeHabitCount()
        shownDay = Storage.dayKey(new Date())
    }

    Component.onCompleted: refresh()
    onStatusChanged: {
        if (status === Cover.Active) refresh()
    }

    Connections {
        target: Qt.application
        onStateChanged: cover.refresh()
    }

    // The count is about today, and today ends at midnight whether or not the
    // app is opened. While it sits in the background the clock is checked
    // once a minute, and the count redone only when the date has changed.
    Timer {
        interval: 60000
        repeat: true
        running: Qt.application.state !== Qt.ApplicationActive
        onTriggered: {
            if (Storage.dayKey(new Date()) !== cover.shownDay) cover.refresh()
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !FiatMosTheme.ambient
        gradient: Gradient {
            GradientStop { position: 0.0; color: FiatMosTheme.backgroundHigh }
            GradientStop { position: 1.0; color: FiatMosTheme.backgroundLow }
        }
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: FiatMosTheme.coverWordmarkTop
        text: "fiat mos"
        color: FiatMosTheme.secondaryText
        font.pixelSize: Theme.fontSizeTiny
        font.family: FiatMosTheme.serif
        font.italic: true
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: FiatMosTheme.coverSideMargin
        anchors.rightMargin: FiatMosTheme.coverSideMargin
        anchors.topMargin: cover.height * FiatMosTheme.coverFigureFraction
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: cover.total === 0 ? "–" : cover.unlogged
            color: cover.unlogged > 0 ? FiatMosTheme.accent : FiatMosTheme.secondaryText
            font.pixelSize: FiatMosTheme.coverFigureSize
            font.family: FiatMosTheme.serif
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: cover.total === 0 ? qsTr("no habits")
                : cover.unlogged === 0 ? qsTr("all done") : qsTr("left today")
            color: FiatMosTheme.secondaryText
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.WordWrap
        }
    }
}
