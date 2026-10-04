import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// Adds a thing to practise, or edits one: its name and how it is measured.
//
// Changing the measure changes how the thing is logged from now on. Nothing
// already logged is touched -- a set keeps every number it was saved with,
// and the history shows what was there.
//
// A name another thing of the same kind already has is not accepted: two
// things answering to one name would split one history in two.

Dialog {
    id: page

    property int itemId: -1
    property int kindId: -1
    readonly property bool editing: itemId >= 0

    property string measure: "weight_reps"
    property var kindList: []

    readonly property bool nameTaken: {
        var t = nameField.text.trim()
        if (t === "" || page.kindId < 0) return false
        var other = Storage.thingIdByName(page.kindId, t)
        return other >= 0 && other !== page.itemId
    }

    canAccept: nameField.text.trim() !== "" && page.kindId >= 0 && !page.nameTaken
    acceptDestinationAction: PageStackAction.Pop

    Component.onCompleted: {
        kindList = Storage.kinds({ nature: "practise" })
        if (editing) {
            var it = Storage.itemById(itemId)
            if (it !== null) {
                nameField.text = it.title
                page.kindId = it.kindId
                page.measure = it.measure
            }
        } else {
            if (page.kindId < 0 && kindList.length > 0) page.kindId = kindList[0].id
            var k = page.kindId >= 0 ? Storage.kindById(page.kindId) : null
            if (k !== null) page.measure = k.measure
        }
    }

    onAccepted: {
        if (editing) Storage.updateThing({ id: page.itemId, title: nameField.text, measure: page.measure })
        else Storage.addThing({ title: nameField.text, kindId: page.kindId, measure: page.measure })
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
                title: page.editing ? qsTr("Edit") : qsTr("Something to practise")
                acceptEnabled: page.canAccept
                onCancelled: page.reject()
                onAccepted: page.accept()
            }

            TextField {
                id: nameField
                width: parent.width
                label: page.nameTaken ? qsTr("Already there under that name") : qsTr("Name")
                placeholderText: qsTr("Bench press, Toccata, Pigeon pose…")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // Only when adding, and only when there is a choice: a thing does
            // not move between kinds once it has a history.
            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: !page.editing && page.kindList.length > 1
                text: qsTr("Kind")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: !page.editing && page.kindList.length > 1

                Repeater {
                    model: page.kindList.length
                    Pill {
                        text: page.kindList[index].name
                        selected: page.kindId === page.kindList[index].id
                        onClicked: {
                            page.kindId = page.kindList[index].id
                            page.measure = page.kindList[index].measure
                        }
                    }
                }
            }

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Measured in")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Repeater {
                    model: Measures.choices()
                    Pill {
                        text: modelData.label
                        selected: page.measure === modelData.value
                        onClicked: page.measure = modelData.value
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: page.measure === "weight_reps"
                    ? qsTr("Reps, and a weight. Leave the weight empty while there is none — the day you add one, nothing else has to change.")
                    : page.measure === "time"
                    ? qsTr("Minutes, once or per set.")
                    : qsTr("Minutes and kilometres.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.editing
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("A new name or measure applies from now on and everywhere this thing appears. Sets already logged keep every number they were saved with.")
            }
        }

        VerticalScrollDecorator { }
    }
}
