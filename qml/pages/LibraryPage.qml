import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// The Shelf: the things you finish, whatever kind of thing they are. Books,
// films, study texts, rolls of film, drafts. Things you practise -- exercises,
// pieces -- live on the Practice page instead and never show up here. An item
// has its own lifecycle, so UPDATE is the right verb here, unlike in
// log_entry. (The file keeps its old name so the .pro does not churn.)

Page {
    id: page

    property int filterIndex: 0        // 0 on the go, 1 finished, 2 all
    property var tagsChosen: []
    property bool tagsOpen: false
    property var tagChoices: []
    property int kindFilter: -1
    property var tags: []
    property var kindList: []

    function filter() {
        var f = { includePrivate: true, tags: page.tagsChosen, kindId: page.kindFilter, nature: "finish" }
        if (filterIndex === 0) f.active = true
        else if (filterIndex === 1) f.active = false
        return f
    }

    function toggleTag(t) {
        var next = []
        var had = false
        for (var i = 0; i < tagsChosen.length; i++) {
            if (tagsChosen[i] === t) had = true
            else next.push(tagsChosen[i])
        }
        if (!had) next.push(t)
        tagsChosen = next
    }

    function reload() {
        tags = Storage.allTags()
        var f = filter()
        f.tags = []
        tagChoices = Storage.tagChoices(f, tagsChosen)
        kindList = Storage.kinds({ nature: "finish" })
        Storage.loadItems(itemModel, filter())
    }

    // Statistics are per kind. With a kind chosen, or only one kind in the
    // library, there is no question which; otherwise Totals is the way in.
    function statsKind() {
        if (page.kindFilter >= 0) return page.kindFilter
        if (page.kindList.length === 1) return page.kindList[0].id
        return -1
    }

    onStatusChanged: {
        if (status === PageStatus.Active) reload()
    }

    onFilterIndexChanged: reload()
    onTagsChosenChanged: reload()
    onKindFilterChanged: reload()

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

    ListModel { id: itemModel }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: itemModel

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("Shelf")
                subtitle: itemModel.count === 1
                          ? qsTr("1 item")
                          : qsTr("%1 items").arg(itemModel.count)
            }

            // State filter. Unchanged in spirit -- only the words got looser,
            // because "reading" is wrong for a roll of film.
            Flow {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("On the go")
                    selected: page.filterIndex === 0
                    onClicked: page.filterIndex = 0
                }
                Pill {
                    text: qsTr("Done")
                    selected: page.filterIndex === 1
                    onClicked: page.filterIndex = 1
                }
                Pill {
                    text: qsTr("All")
                    selected: page.filterIndex === 2
                    onClicked: page.filterIndex = 2
                }
            }

            // Kind filter. The kinds are yours, invented as you went.
            Flow {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.kindList.length > 1

                Pill {
                    text: qsTr("Any kind")
                    selected: page.kindFilter < 0
                    onClicked: page.kindFilter = -1
                }

                Repeater {
                    model: page.kindList.length
                    Pill {
                        text: page.kindList[index].name
                        selected: page.kindFilter === page.kindList[index].id
                        onClicked: page.kindFilter = page.kindList[index].id
                    }
                }
            }

            // Tag filter. Tags are invented as you go and soon outnumber what
            // a row of words can hold, so the choice is a row of its own that
            // opens downward. Each tag you choose narrows the list below; the
            // number beside a tag is what you would be left with if you chose
            // it too, and a tag that would leave nothing is dimmed -- so you
            // can see at once whether the filter is enough or there is more to
            // choose.
            ValueRow {
                width: listView.width
                visible: page.tags.length > 0
                label: qsTr("Tag")
                value: page.tagsChosen.length === 0 ? qsTr("any") : page.tagsChosen.join(" + ")
                onClicked: page.tagsOpen = !page.tagsOpen
            }

            Column {
                width: listView.width
                visible: page.tagsOpen && page.tags.length > 0

                Repeater {
                    model: page.tagChoices.length

                    BackgroundItem {
                        width: listView.width
                        height: Theme.itemSizeExtraSmall
                        highlightedColor: FiatMosTheme.highlightWash
                        readonly property var choice: page.tagChoices[index]
                        opacity: (choice.count === 0 && !choice.chosen) ? 0.35 : 1.0
                        onClicked: page.toggleTag(choice.tag)

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.horizontalPageMargin
                            width: parent.width - Theme.horizontalPageMargin * 2 - countLabel.width - Theme.paddingMedium
                            truncationMode: TruncationMode.Fade
                            text: parent.choice.tag
                            font.bold: parent.choice.chosen
                            color: (parent.highlighted || parent.choice.chosen) ? FiatMosTheme.accent : FiatMosTheme.primaryText
                        }
                        Label {
                            id: countLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.horizontalPageMargin
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: parent.choice.chosen
                            color: parent.choice.chosen ? FiatMosTheme.accent : FiatMosTheme.secondaryText
                            text: String(parent.choice.count)
                        }
                    }
                }
            }
        }

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            MenuItem {
                text: qsTr("Totals")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("TagTotalsPage.qml"))
            }
            MenuItem {
                text: qsTr("Statistics")
                color: FiatMosTheme.primaryText
                visible: page.statsKind() >= 0
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("KindStatsPage.qml"), { kindId: page.statsKind() })
            }
            MenuItem {
                text: qsTr("Lookup services")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("LookupServicesPage.qml"), { firstTime: !LookupSettings.chosen })
            }
            MenuItem {
                text: qsTr("Add item")
                color: FiatMosTheme.primaryText
                // Returning here fires PageStatus.Active, which reloads.
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddBookPage.qml"))
            }
        }


        delegate: ListItem {
            id: itemRow
            highlightedColor: FiatMosTheme.highlightWash
            width: listView.width
            contentHeight: Math.max(Theme.itemSizeMedium, itemColumn.height + Theme.paddingMedium * 2,
                                    rowCover.visible ? rowCover.height + Theme.paddingMedium * 2 : 0)

            menu: ContextMenu {
                highlightColor: FiatMosTheme.accent

                MenuItem {
                    text: qsTr("Edit")
                    color: FiatMosTheme.primaryText
                    onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddBookPage.qml"),
                                                      { itemId: model.itemId })
                }
                MenuItem {
                    visible: model.active
                    text: model.doneWord === "learned" ? qsTr("Mark as learned") : qsTr("Mark as finished")
                    color: FiatMosTheme.primaryText
                    onClicked: {
                        Storage.setItemState(model.itemId, "completed")
                        page.reload()
                    }
                }
                MenuItem {
                    visible: !model.active
                    text: qsTr("Pick it up again")
                    color: FiatMosTheme.primaryText
                    onClicked: {
                        Storage.setItemState(model.itemId, "active")
                        page.reload()
                    }
                }
                MenuItem {
                    visible: model.state !== "archived"
                    text: qsTr("Archive")
                    color: FiatMosTheme.primaryText
                    onClicked: itemRow.remorseAction(qsTr("Archiving"), function() {
                        Storage.setItemState(model.itemId, "archived")
                        page.reload()
                    })
                }
            }

            onClicked: pageStack.animatorPush(Qt.resolvedUrl("ItemPage.qml"), { itemId: model.itemId })

            // Only items with an ISBN get a cover slot. A roll of film or a
            // piece of repertoire has no cover, and a row of plain cloth
            // blocks beside them would only be noise.
            BookCover {
                id: rowCover
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.itemSizeSmall * 0.8
                height: width * 1.5
                visible: model.isbn !== undefined && model.isbn !== ""
                isbn: model.isbn === undefined ? "" : model.isbn
                title: model.title === undefined ? "" : model.title
            }

            Column {
                id: itemColumn
                anchors.verticalCenter: parent.verticalCenter
                x: rowCover.visible ? rowCover.x + rowCover.width + Theme.paddingMedium : Theme.horizontalPageMargin
                width: parent.width - x - Theme.horizontalPageMargin

                Row {
                    width: parent.width
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width - (model.isPrivate ? privateMark.width + Theme.paddingSmall : 0)
                        text: model.title
                        truncationMode: TruncationMode.Fade
                        color: itemRow.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
                    }

                    // Drawn, not typed -- a circle is round in every font.
                    Rectangle {
                        id: privateMark
                        anchors.verticalCenter: parent.verticalCenter
                        visible: model.isPrivate
                        width: Theme.paddingSmall
                        height: width
                        radius: width / 2
                        color: FiatMosTheme.secondaryText
                    }
                }

                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    truncationMode: TruncationMode.Fade
                    text: {
                        var parts = []
                        if (model.creator !== "") parts.push(model.creator)
                        if (model.kindName !== "") parts.push(model.kindName)
                        if (model.state === "completed") parts.push(model.doneWord === "learned" ? qsTr("learned") : qsTr("finished"))
                        else if (model.state === "archived") parts.push(qsTr("put away"))
                        if (model.extent > 0) {
                            parts.push(qsTr("%1 of %2").arg(model.soFar).arg(model.extent))
                        } else if (model.loggedDays > 0) {
                            parts.push(model.loggedDays === 1
                                ? qsTr("1 day logged")
                                : qsTr("%1 days logged").arg(model.loggedDays))
                        }
                        return parts.join(" · ")
                    }
                }

                // How far in, when the length is known.
                Rectangle {
                    width: parent.width
                    height: Math.max(2, Theme.paddingSmall / 2)
                    radius: height / 2
                    color: FiatMosTheme.dotIdle
                    visible: model.extent > 0 && model.active

                    Rectangle {
                        width: parent.width * Math.min(1, model.extent > 0 ? model.soFar / model.extent : 0)
                        height: parent.height
                        radius: parent.radius
                        color: FiatMosTheme.accent
                    }
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

        VerticalScrollDecorator { }
    }

    // Outside the list view on purpose: a plain child of a ListView is
    // parented to its contentItem, which has no height when the model is
    // empty -- exactly when this needs to be visible.
    EmptyNote {
        enabled: itemModel.count === 0
        text: page.filterIndex === 1 ? qsTr("Nothing done yet") : qsTr("Nothing here")
        hintText: page.tagsChosen.length > 0
            ? qsTr("No items tagged %1").arg(page.tagsChosen.join(" + "))
            : qsTr("Pull down to add something you are working through")
    }
}
