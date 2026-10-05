import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// One program: its exercises in order. Start a workout from it, add or
// remove exercises, move them, rename it.
//
// A workout is its own copy. Changing the program here changes no workout
// already done.

Page {
    id: page

    property int programId: -1
    property var prog: null
    property var items: []

    function reload() {
        prog = Storage.programById(programId)
        items = Storage.programItems(programId)
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
        model: page.items.length

        header: Column {
            width: listView.width
            PageHead {
                title: page.prog === null ? "" : page.prog.name
                subtitle: page.prog === null ? "" : page.prog.habitName
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                visible: page.items.length > 0
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Hold an exercise to move or remove it. A workout is a copy: changing the program changes no workout you have done.")
            }
            Item { width: 1; height: Theme.paddingMedium }
        }

        footer: Column {
            width: listView.width
            Item { width: 1; height: Theme.paddingLarge }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Add exercises")
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ExercisePickerPage.qml"), { programId: page.programId })
            }
            Item { width: 1; height: Theme.paddingLarge }
        }

        PullDownMenu {
            highlightColor: FiatMosTheme.accent
            MenuItem {
                text: qsTr("Rename")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ProgramNameDialog.qml"), { programId: page.programId })
            }
            MenuItem {
                text: qsTr("Start workout")
                color: FiatMosTheme.primaryText
                visible: page.prog !== null
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("SessionPage.qml"), { habitId: page.prog.habitId, startProgramId: page.programId })
            }
        }

        delegate: ListItem {
            id: row
            width: listView.width
            contentHeight: Math.max(Theme.itemSizeMedium, col.height + Theme.paddingMedium * 2)
            highlightedColor: FiatMosTheme.highlightWash

            menu: ContextMenu {
                highlightColor: FiatMosTheme.accent
                MenuItem {
                    text: qsTr("Move up")
                    color: FiatMosTheme.primaryText
                    visible: index > 0
                    onClicked: { Storage.moveProgramItem(page.programId, page.items[index].itemId, -1); page.reload() }
                }
                MenuItem {
                    text: qsTr("Move down")
                    color: FiatMosTheme.primaryText
                    visible: index < page.items.length - 1
                    onClicked: { Storage.moveProgramItem(page.programId, page.items[index].itemId, 1); page.reload() }
                }
                MenuItem {
                    text: qsTr("Remove from program")
                    color: FiatMosTheme.wrong
                    onClicked: {
                        var id = page.items[index].itemId
                        row.remorseAction(qsTr("Removing"), function() {
                            Storage.removeProgramItem(page.programId, id)
                            page.reload()
                        })
                    }
                }
            }

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
                    color: row.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
                    text: page.items[index].name
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    text: Measures.label(page.items[index].measure)
                }
            }
        }

        VerticalScrollDecorator { }
    }

    EmptyNote {
        enabled: page.items.length === 0
        text: qsTr("No exercises in this program")
        hintText: qsTr("Add the exercises you want in it. Pull down to start a workout from it.")
    }
}
