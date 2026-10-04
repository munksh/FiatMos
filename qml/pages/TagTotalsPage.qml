import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// What you have actually got through. The payoff of the whole generalisation
// -- without it, kinds and tags are decoration.
//
// One row per KIND, because a kind owns exactly one unit. Pages and minutes
// can therefore never end up in the same number: the separation falls out of
// the data model rather than being enforced by a rule somebody has to
// remember.
//
// The tag is a FILTER on top, not the way in. It used to be the way in, and
// that made the page lie by omission -- you read a book, the pages showed up
// in the habit's history, and this page said nothing, because tagging is
// something you do afterwards and often never. "All" is the default now, and
// everything you logged is on it whether or not you ever labelled it.

Page {
    id: page

    property var tags: []
    property string tag: ""             // "" means every tag, and none
    property int lookback: 365          // 0 means all time
    property bool includePrivate: false

    function reload() {
        tags = Storage.allTags()
        Storage.loadKindTotals(totalsModel, page.tag, lookback, includePrivate)
    }

    onTagChanged: reload()
    onLookbackChanged: reload()
    onIncludePrivateChanged: reload()

    onStatusChanged: {
        if (status === PageStatus.Active) reload()
    }

    function periodName() {
        if (lookback === 30) return qsTr("the last 30 days")
        if (lookback === 365) return qsTr("the last year")
        return qsTr("all time")
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

    ListModel { id: totalsModel }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("Totals")
                subtitle: (page.tag === "" ? qsTr("everything") : page.tag) + " · " + page.periodName()
            }

            // -- Period, and privacy -------------------------------------------

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("30 days")
                    selected: page.lookback === 30
                    onClicked: page.lookback = 30
                }
                Pill {
                    text: qsTr("This year")
                    selected: page.lookback === 365
                    onClicked: page.lookback = 365
                }
                Pill {
                    text: qsTr("All time")
                    selected: page.lookback === 0
                    onClicked: page.lookback = 0
                }
            }

            SwitchRow {
                text: qsTr("Include private")
                checked: page.includePrivate
                onClicked: page.includePrivate = !page.includePrivate
            }

            // -- Tag filter ------------------------------------------------------
            //
            // "Any" by default. A filter whose neutral position is missing is
            // not a filter, it is a requirement. A row that opens a list,
            // because tags are invented as you go and soon outnumber a row of
            // words.

            ValueRow {
                width: parent.width
                visible: page.tags.length > 0
                label: qsTr("Tag")
                value: page.tag === "" ? qsTr("any") : page.tag
                onClicked: {
                    var op = pageStack.animatorPush(Qt.resolvedUrl("TagPickerPage.qml"), { current: page.tag })
                    if (op === null || op === undefined) return
                    if (op.pageCompleted !== undefined) {
                        op.pageCompleted.connect(function(p) { p.tagPicked.connect(function(t) { page.tag = t }) })
                    } else if (op.tagPicked !== undefined) {
                        op.tagPicked.connect(function(t) { page.tag = t })
                    }
                }
            }

            // -- The numbers -----------------------------------------------------
            //
            // One big pill per kind. A card each rather than rows inside one
            // card: they are separate answers to separate questions, and
            // stacking them in a single box invited the eye to add them up.

            Repeater {
                model: totalsModel

                Rectangle {
                    x: Theme.horizontalPageMargin
                    width: content.width - Theme.horizontalPageMargin * 2
                    height: rowColumn.height + Theme.paddingLarge * 2
                    radius: FiatMosTheme.cardRadius
                    color: FiatMosTheme.card
                    border.color: cardPress.pressed ? FiatMosTheme.accent : FiatMosTheme.cardBorder
                    border.width: FiatMosTheme.cardBorderWidth

                    // A card opens that kind's statistics. The period and
                    // the private setting go along; "All time" has no
                    // calendar to draw, so it opens on the last year.
                    MouseArea {
                        id: cardPress
                        anchors.fill: parent
                        enabled: model.kindId >= 0
                        onClicked: pageStack.animatorPush(Qt.resolvedUrl("KindStatsPage.qml"), {
                            kindId: model.kindId,
                            lookback: page.lookback === 30 ? 30 : 365,
                            includePrivate: page.includePrivate
                        })
                    }

                    Column {
                        id: rowColumn
                        anchors.centerIn: parent
                        width: parent.width - Theme.paddingLarge * 2
                        spacing: Theme.paddingSmall / 2

                        Row {
                            width: parent.width
                            spacing: Theme.paddingMedium

                            Label {
                                anchors.baseline: unitLabel.baseline
                                text: model.total
                                font.pixelSize: Theme.fontSizeExtraLarge
                                font.family: FiatMosTheme.serif
                                color: FiatMosTheme.accent
                            }

                            Label {
                                id: unitLabel
                                text: model.unit === "" ? qsTr("logged") : model.unit
                                font.pixelSize: Theme.fontSizeMedium
                                color: FiatMosTheme.primaryText
                            }
                        }

                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeSmall
                            color: FiatMosTheme.primaryText
                            text: model.kindName === "" ? qsTr("no kind") : model.kindName
                        }

                        Label {
                            width: parent.width
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                            text: {
                                var d = model.days === 1
                                    ? qsTr("1 day")
                                    : qsTr("%1 days").arg(model.days)
                                var n = model.itemCount === 1
                                    ? qsTr("1 item")
                                    : qsTr("%1 items").arg(model.itemCount)
                                return d + " · " + n
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
                text: totalsModel.count === 0
                    ? (page.tag === ""
                        ? qsTr("Nothing logged against anything on your shelf in %1.").arg(page.periodName())
                        : qsTr("Nothing tagged %1 was logged in %2.").arg(page.tag).arg(page.periodName()))
                    : qsTr("One card per kind, so a unit is never mixed with another. Tap a card for that kind's shelf, calendar and items. Tag things on the shelf to ask narrower questions here.")
            }
        }

        VerticalScrollDecorator { }
    }
}
