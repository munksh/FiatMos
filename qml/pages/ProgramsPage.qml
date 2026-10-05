import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Programs: lists of exercises to start a workout from. A program can be
// built before it is ever run -- it is only a list. What a workout from it
// looked like last time shows when you start one.

Page {
    id: page

    property var list: []

    function reload() { list = Storage.programs() }

    function lastText(p) {
        var n = p.exercises === 1 ? qsTr("1 exercise") : qsTr("%1 exercises").arg(p.exercises)
        var w = p.sessions === 1 ? qsTr("1 workout") : qsTr("%1 workouts").arg(p.sessions)
        var t = n + " · " + w
        if (p.last !== "") t += " · " + Qt.formatDate(Storage.dateFromDayKey(p.last), "d MMM")
        return t
    }

    onStatusChanged: if (status === PageStatus.Active) reload()

    // Fiat colours paint their own paper. Under an ambience there is no
    // background at all -- the wallpaper is the background.
    Rectangle {
        anchors.fill: parent
        visible: !FiatMosTheme.ambient
        gradient: Gradient {
            GradientStop { position: 0.0; color: FiatMosTheme.backgroundHigh }
            GradientStop { position: 1.0; color: FiatMosTheme.backgroundLow }
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.list.length

        header: PageHead {
            title: qsTr("Programs")
            subtitle: page.list.length === 1 ? qsTr("1 program") : qsTr("%1 programs").arg(page.list.length)
        }

        PullDownMenu {
            highlightColor: FiatMosTheme.accent
            MenuItem {
                text: qsTr("New program")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ProgramNameDialog.qml"))
            }
        }

        delegate: ListItem {
            width: listView.width
            contentHeight: Math.max(Theme.itemSizeMedium, col.height + Theme.paddingMedium * 2)
            highlightedColor: FiatMosTheme.highlightWash
            onClicked: pageStack.animatorPush(Qt.resolvedUrl("ProgramPage.qml"), { programId: page.list[index].id })

            Column {
                id: col
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.family: FiatMosTheme.serif
                    font.pixelSize: Theme.fontSizeLarge
                    color: FiatMosTheme.primaryText
                    text: page.list[index].name
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    text: page.lastText(page.list[index])
                }
            }
        }

        VerticalScrollDecorator { }
    }

    EmptyNote {
        enabled: page.list.length === 0
        text: qsTr("No programs yet")
        hintText: qsTr("A program is a list of exercises. Pull down to make one — you can build it before you ever run it.")
    }
}
