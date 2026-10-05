import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// Exercises: every exercise of every Work out habit. Exercises, stretches,
// routes. (Music and texts are not here: you learn a piece the way you read a
// book, so they live on the Shelf.)
//
// Nothing here is ever finished; what an exercise has instead is a history,
// and each row says the last of it -- so before a workout you can see where
// you left off without opening anything. An exercise is made the first time a
// workout names it, or here from the pull-down.
//
// One kind at a time. Kinds never share a list: a stretch and a bench press
// have nothing to say to each other, and the choice of kind is a row of words
// because there are only ever a few.

Page {
    id: page

    property var kindList: []
    property int kindId: -1

    function valueText(v, unit) {
        var n = String(Math.round(v * 10) / 10)
        return n
    }

    function unitText(unit) {
        if (unit === "set") return qsTr("in a set")
        if (unit === "reps") return qsTr("reps")
        if (unit === "min") return qsTr("min")
        if (unit === "km") return qsTr("km")
        return qsTr("kg")
    }

    function changeText(change, unit, firstDay) {
        if (change === 0) return qsTr("steady")
        var n = Math.round(Math.abs(change) * 10) / 10
        var u = unit === "set" ? qsTr("reps") : page.unitText(unit)
        var since = Qt.formatDate(Storage.dateFromDayKey(firstDay), "MMM")
        return (change > 0 ? qsTr("+%1 %2 since %3") : qsTr("−%1 %2 since %3")).arg(n).arg(u).arg(since)
    }

    function reload() {
        kindList = Storage.kinds({ nature: "practise" })
        var still = false
        for (var i = 0; i < kindList.length; i++) if (kindList[i].id === kindId) still = true
        if (!still) kindId = kindList.length > 0 ? kindList[0].id : -1
        Storage.loadThings(thingModel, kindId)
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
                title: qsTr("Exercises")
                subtitle: thingModel.count === 1 ? qsTr("1 exercise") : qsTr("%1 exercises").arg(thingModel.count)
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
                text: qsTr("Add exercise")
                color: FiatMosTheme.primaryText
                visible: page.kindId >= 0
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ThingDialog.qml"), { kindId: page.kindId })
            }
        }

        delegate: ListItem {
            id: thingRow
            width: listView.width
            contentHeight: Math.max(Theme.itemSizeMedium, rowBody.height + Theme.paddingMedium * 2)
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

            // Three parts: the name and last time, a little line through the
            // recent days, and where it stands now. The line has the same
            // width on every row, so a long name wraps instead.
            Item {
                id: rowBody
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                height: Math.max(thingCol.height, valueCol.height)

                Column {
                    id: thingCol
                    anchors.left: parent.left
                    anchors.right: spark.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: model.title
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
                }

                Sparkline {
                    id: spark
                    anchors.right: valueCol.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    visible: model.count > 1
                    values: JSON.parse(model.spark)
                }

                Column {
                    id: valueCol
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.itemSizeMedium
                    visible: model.count > 0

                    Row {
                        anchors.right: parent.right
                        spacing: Theme.paddingSmall / 2
                        Label {
                            id: bigValue
                            text: page.valueText(model.value, model.unit)
                            font.pixelSize: Theme.fontSizeLarge
                            font.family: FiatMosTheme.serif
                            color: FiatMosTheme.primaryText
                        }
                        Label {
                            anchors.baseline: bigValue.baseline
                            text: page.unitText(model.unit)
                            font.pixelSize: Theme.fontSizeTiny
                            color: FiatMosTheme.secondaryText
                        }
                    }
                    Label {
                        anchors.right: parent.right
                        text: page.changeText(model.change, model.unit, model.firstDay)
                        font.pixelSize: Theme.fontSizeTiny
                        color: model.change > 0 ? FiatMosTheme.accent : FiatMosTheme.secondaryText
                    }
                }
            }
        }

        VerticalScrollDecorator { }
    }

    // Outside the list view on purpose: a plain child of a ListView is
    // parented to its contentItem, which has no height when the model is
    // empty -- exactly when this needs to be visible.
    EmptyNote {
        enabled: thingModel.count === 0
        text: qsTr("No exercises yet")
        hintText: page.kindId < 0
            ? qsTr("A Work out habit adds its exercises here as you log workouts.")
            : qsTr("Exercises appear here as your workouts name them. Pull down to add one now.")
    }
}
