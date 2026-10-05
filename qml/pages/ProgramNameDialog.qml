import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// A name for a program: a new one (and which workout it is for, when there
// are several), or a new name for an existing one. Two programs never share a
// name.

Dialog {
    id: page

    property int programId: -1
    readonly property bool renaming: programId >= 0
    property int habitId: -1
    property var habitList: []

    readonly property bool nameTaken: nameField.text.trim() !== "" && Storage.programNameTaken(nameField.text, page.programId)

    canAccept: nameField.text.trim() !== "" && !page.nameTaken && (page.renaming || page.habitId >= 0)
    acceptDestinationAction: PageStackAction.Pop

    Component.onCompleted: {
        if (renaming) {
            var p = Storage.programById(programId)
            if (p !== null) nameField.text = p.name
        } else {
            habitList = Storage.workoutHabits()
            if (habitList.length > 0) habitId = habitList[0].id
        }
    }

    onAccepted: {
        if (renaming) Storage.renameProgram(programId, nameField.text)
        else Storage.addProgram(habitId, nameField.text, [])
    }

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

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHead {
                title: page.renaming ? qsTr("Rename") : qsTr("New program")
                acceptEnabled: page.canAccept
                onCancelled: page.reject()
                onAccepted: page.accept()
            }

            TextField {
                id: nameField
                width: parent.width
                label: page.nameTaken ? qsTr("Already a program with that name") : qsTr("Name")
                placeholderText: qsTr("Push day, Legs, Long run…")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: !page.renaming && page.habitList.length > 1
                text: qsTr("For")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: !page.renaming && page.habitList.length > 1
                Repeater {
                    model: page.habitList.length
                    Pill {
                        text: page.habitList[index].name
                        selected: page.habitId === page.habitList[index].id
                        onClicked: page.habitId = page.habitList[index].id
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: !page.renaming && page.habitList.length === 0
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("A program belongs to a Work out habit. Make one on the habit list first.")
            }
        }
        VerticalScrollDecorator { }
    }
}
