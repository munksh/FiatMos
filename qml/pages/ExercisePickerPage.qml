import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// Which exercises are in a program. A switch per exercise: it takes effect
// the moment you flip it, so there is nothing to save and nothing to lose.

Page {
    id: page

    property int programId: -1
    property int kindId: -1
    property var things: []
    property var inProgram: ({})

    function reload() {
        var p = Storage.programById(programId)
        if (p === null) return
        kindId = p.kindId >= 0 ? p.kindId : Storage.habitPractiseKind(p.habitId)
        things = Storage.things(kindId)
        var m = {}
        var cur = Storage.programItems(programId)
        for (var i = 0; i < cur.length; i++) m[cur[i].itemId] = true
        inProgram = m
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
        model: page.things.length

        header: PageHead {
            title: qsTr("Add exercises")
            subtitle: qsTr("Tap to put in or take out")
        }

        PullDownMenu {
            highlightColor: FiatMosTheme.accent
            MenuItem {
                text: qsTr("New exercise")
                color: FiatMosTheme.primaryText
                visible: page.kindId >= 0
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ThingDialog.qml"), { kindId: page.kindId })
            }
        }

        delegate: SwitchRow {
            width: listView.width
            text: page.things[index].title
            description: Measures.label(page.things[index].measure)
            checked: page.inProgram[page.things[index].id] === true
            onClicked: {
                var id = page.things[index].id
                if (checked) Storage.removeProgramItem(page.programId, id)
                else Storage.addProgramItem(page.programId, id)
                page.reload()
            }
        }

        VerticalScrollDecorator { }
    }

    EmptyNote {
        enabled: page.things.length === 0
        text: qsTr("No exercises yet")
        hintText: qsTr("Pull down to make one. It will show up here at once.")
    }
}
