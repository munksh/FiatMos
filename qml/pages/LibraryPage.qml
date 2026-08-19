import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// The things you work through, whatever kind of thing they are. Books,
// repertoire, study texts, rolls of film, drafts. An item has its own
// lifecycle, so UPDATE is the right verb here, unlike in log_entry.

Page {
    id: page

    property int filterIndex: 0        // 0 on the go, 1 finished, 2 all
    property string tagFilter: ""
    property int kindFilter: -1
    property var tags: []
    property var kindList: []

    function filter() {
        var f = { includePrivate: true, tag: page.tagFilter, kindId: page.kindFilter }
        if (filterIndex === 0) f.active = true
        else if (filterIndex === 1) f.active = false
        return f
    }

    function reload() {
        tags = Storage.allTags()
        kindList = Storage.kinds()
        Storage.loadItems(itemModel, filter())
    }

    onStatusChanged: {
        if (status === PageStatus.Active) reload()
    }

    onFilterIndexChanged: reload()
    onTagFilterChanged: reload()
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
                title: qsTr("Library")
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
                    text: qsTr("Finished")
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

            // Tag filter, built from the tags actually in use. Never a fixed
            // list -- the whole point is that you invent them as you go.
            Flow {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.tags.length > 0

                Pill {
                    text: qsTr("Any tag")
                    selected: page.tagFilter === ""
                    onClicked: page.tagFilter = ""
                }

                Repeater {
                    model: page.tags.length
                    Pill {
                        text: page.tags[index]
                        selected: page.tagFilter === page.tags[index]
                        onClicked: page.tagFilter = page.tags[index]
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
            contentHeight: Theme.itemSizeMedium

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
                    text: qsTr("Mark as finished")
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

            onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddBookPage.qml"),
                                              { itemId: model.itemId })

            Column {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

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
                        if (!model.active) parts.push(model.state)
                        if (model.loggedDays > 0) {
                            parts.push(model.loggedDays === 1
                                ? qsTr("1 day logged")
                                : qsTr("%1 days logged").arg(model.loggedDays))
                        }
                        return parts.join(" · ")
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
        text: page.filterIndex === 1 ? qsTr("Nothing finished yet") : qsTr("Nothing here")
        hintText: page.tagFilter !== ""
            ? qsTr("No items tagged %1").arg(page.tagFilter)
            : qsTr("Pull down to add something you are working through")
    }
}
