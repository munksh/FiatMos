import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// Practice: the things you practise. Exercises, pieces, stretches, routes.
//
// The counterpart of the Shelf. Nothing here is ever finished; what a thing
// has instead is a history, and each row says the last of it -- so before a
// session you can see where you left off without opening anything. A thing
// is made the first time a session names it, or here from the pull-down.
//
// One kind at a time. Kinds never share a list: a stretch and a bench press
// have nothing to say to each other, and the choice of kind is a row of words
// because there are only ever a few.
//
// Programs -- sessions saved to start from -- are listed at the bottom, and
// one tap starts a session from one.

Page {
    id: page

    property var kindList: []
    property int kindId: -1
    property var programList: []

    function reload() {
        kindList = Storage.kinds({ nature: "practise" })
        var still = false
        for (var i = 0; i < kindList.length; i++) if (kindList[i].id === kindId) still = true
        if (!still) kindId = kindList.length > 0 ? kindList[0].id : -1
        Storage.loadThings(thingModel, kindId)
        programList = Storage.programs()
    }

    function dayLabel(key) {
        if (key === "") return ""
        if (key === Storage.dayOffsetKey(0)) return qsTr("today")
        if (key === Storage.dayOffsetKey(-1)) return qsTr("yesterday")
        return Qt.formatDate(Storage.dateFromDayKey(key), "ddd d MMM")
    }

    function editThing(itemId) {
        pageStack.animatorPush(Qt.resolvedUrl("ThingDialog.qml"), { itemId: itemId, kindId: page.kindId })
    }

    onKindIdChanged: Storage.loadThings(thingModel, kindId)

    onStatusChanged: {
        if (status === PageStatus.Active) reload()
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

    ListModel { id: thingModel }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: thingModel

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("Practice")
                subtitle: thingModel.count === 1 ? qsTr("1 thing") : qsTr("%1 things").arg(thingModel.count)
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.kindList.length > 1

                Repeater {
                    model: page.kindList.length
                    Pill {
                        text: page.kindList[index].name
                        selected: page.kindId === page.kindList[index].id
                        onClicked: page.kindId = page.kindList[index].id
                    }
                }
            }

            Item { width: 1; height: Theme.paddingSmall }
        }

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            MenuItem {
                text: qsTr("Add something to practise")
                color: FiatMosTheme.primaryText
                visible: page.kindId >= 0
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ThingDialog.qml"), { kindId: page.kindId })
            }
        }

        delegate: ListItem {
            id: thingRow
            width: listView.width
            contentHeight: Math.max(Theme.itemSizeMedium, thingCol.height + Theme.paddingMedium * 2)
            highlightedColor: FiatMosTheme.highlightWash

            menu: ContextMenu {
                highlightColor: FiatMosTheme.accent

                MenuItem {
                    text: qsTr("Edit")
                    color: FiatMosTheme.primaryText
                    onClicked: page.editThing(model.itemId)
                }
                MenuItem {
                    text: qsTr("Put away")
                    color: FiatMosTheme.primaryText
                    onClicked: thingRow.remorseAction(qsTr("Putting away"), function() {
                        Storage.setItemState(model.itemId, "archived")
                        page.reload()
                    })
                }
            }

            onClicked: pageStack.animatorPush(Qt.resolvedUrl("ThingPage.qml"), { itemId: model.itemId })

            Column {
                id: thingCol
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

                Label {
                    width: parent.width
                    text: model.title
                    truncationMode: TruncationMode.Fade
                    color: thingRow.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
                }

                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    truncationMode: TruncationMode.Fade
                    text: model.lastDay === ""
                        ? qsTr("not done yet · %1").arg(Measures.label(model.measure))
                        : page.dayLabel(model.lastDay) + (model.lastSummary !== "" ? " · " + model.lastSummary : "")
                }

                Label {
                    width: parent.width
                    visible: model.tagList !== ""
                    font.pixelSize: Theme.fontSizeTiny
                    color: FiatMosTheme.accent
                    truncationMode: TruncationMode.Fade
                    text: model.tagList
                }
            }
        }

        footer: Column {
            width: listView.width
            spacing: Theme.paddingSmall
            visible: page.programList.length > 0
            height: visible ? implicitHeight : 0

            Item { width: 1; height: Theme.paddingLarge }

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Programs")
            }

            Repeater {
                model: page.programList.length

                BackgroundItem {
                    id: programRow
                    readonly property var program: page.programList[index]
                    width: listView.width
                    height: Theme.itemSizeMedium
                    highlightedColor: FiatMosTheme.highlightWash
                    onClicked: pageStack.animatorPush(Qt.resolvedUrl("SessionPage.qml"),
                                                      { habitId: programRow.program.habitId,
                                                        startProgramId: programRow.program.id })

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2

                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: programRow.program.name
                            color: programRow.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                            text: {
                                var p = programRow.program
                                var parts = [p.habitName]
                                parts.push(p.sessions === 1 ? qsTr("1 session") : qsTr("%1 sessions").arg(p.sessions))
                                if (p.last !== "") parts.push(qsTr("last %1").arg(page.dayLabel(p.last)))
                                return parts.join(" · ")
                            }
                        }
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Tap a program to start a session from it, with last time's sets filled in.")
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }

    // Outside the list view on purpose: a plain child of a ListView is
    // parented to its contentItem, which has no height when the model is
    // empty -- exactly when this needs to be visible.
    EmptyNote {
        enabled: thingModel.count === 0
        text: qsTr("Nothing to practise yet")
        hintText: page.kindId < 0
            ? qsTr("A Practise it habit adds its things here as you log sessions.")
            : qsTr("Things appear here as your sessions name them. Pull down to add one now.")
    }
}
