import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The period's items as spines on a shelf, in the order they were begun.
//
// A spine's thickness is the item's length when it is known, otherwise how
// much of it was logged, so a shelf still makes sense before anyone has typed
// in a page count. Finished and put-away items stand in cloth. Items on the
// go are drawn open, and fill with the accent from the bottom as far as you
// have got -- which needs the length, so without one the spine stays empty.
//
// A shelf that runs out of room continues on the next one.

Item {
    id: root

    // [{ id, title, state, extent, soFar, total }], in reading order
    property var items: []
    property real shelfHeight: Theme.itemSizeExtraLarge * 1.6
    // How many units fill a whole shelf. 3000 pages is a year of reading for most people.
    property real unitsPerShelf: 3000

    signal picked(int itemId)

    width: parent ? parent.width : 0
    height: shelves.height

    readonly property real gap: Math.max(2, Theme.paddingSmall / 2)
    readonly property var rows: pack(root.items, root.width)

    function spineWidth(it) {
        var amount = it.extent > 0 ? it.extent : Math.max(it.soFar, it.total)
        var w = amount * root.width / root.unitsPerShelf
        return Math.max(Theme.paddingLarge * 1.2, Math.min(root.width * 0.3, w))
    }

    // Same title, same height, every time -- a shelf that rearranged itself on
    // every visit would look like it was measuring something.
    function spineHeight(it) {
        var s = String(it.title)
        var h = 0
        for (var i = 0; i < s.length; i++) h = (h * 17 + s.charCodeAt(i)) % 997
        return root.shelfHeight * (0.78 + (h % 23) / 100)
    }

    function pack(list, width) {
        var out = [], row = [], used = 0
        if (!list || width <= 0) return out
        for (var i = 0; i < list.length; i++) {
            var w = spineWidth(list[i])
            if (row.length > 0 && used + w > width) {
                out.push(row)
                row = []
                used = 0
            }
            var open = list[i].state !== "completed" && list[i].state !== "archived"
            row.push({
                id: list[i].id,
                title: list[i].title,
                w: w,
                h: spineHeight(list[i]),
                open: open,
                fill: (open && list[i].extent > 0) ? Math.min(1, list[i].soFar / list[i].extent) : 0
            })
            used += w + root.gap
        }
        if (row.length > 0) out.push(row)
        return out
    }

    Column {
        id: shelves
        width: parent.width
        spacing: Theme.paddingLarge

        Repeater {
            model: root.rows

            Column {
                width: shelves.width

                Row {
                    height: root.shelfHeight
                    spacing: root.gap

                    Repeater {
                        model: modelData

                        Item {
                            width: modelData.w
                            height: modelData.h
                            y: root.shelfHeight - height

                            Rectangle {
                                anchors.fill: parent
                                radius: Math.max(2, width * 0.06)
                                color: modelData.open ? FiatMosTheme.card : FiatMosTheme.clothFor(modelData.title)
                                border.width: modelData.open ? FiatMosTheme.cardBorderWidth : 0
                                border.color: FiatMosTheme.cardBorder
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: parent.border.width
                                    height: (parent.height - parent.border.width * 2) * modelData.fill
                                    visible: modelData.fill > 0
                                    color: Theme.rgba(FiatMosTheme.accent, 0.5)
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                width: parent.height - Theme.paddingMedium * 2
                                rotation: -90
                                horizontalAlignment: Text.AlignHCenter
                                truncationMode: TruncationMode.Fade
                                text: modelData.title
                                font.family: FiatMosTheme.serif
                                font.pixelSize: Math.min(Theme.fontSizeExtraSmall, parent.width * 0.55)
                                color: modelData.open ? FiatMosTheme.primaryText : FiatMosTheme.clothText
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.picked(modelData.id)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(3, Theme.paddingSmall * 0.6)
                    color: FiatMosTheme.primaryText
                    opacity: 0.8
                }
            }
        }
    }
}
