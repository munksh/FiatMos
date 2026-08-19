import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

Page {
    id: page

    allowedOrientations: Qt.application.state === Qt.ApplicationActive ? defaultAllowedOrientations : Qt.PortraitOrientation

    property int localGen: 0
    property var today: ({ completed: 0, total: 0, fraction: 0 })

    // Remembered between runs, same pattern as the Fiat colours switch.
    ConfigurationValue {
        id: groupConfig
        key: "/apps/harbour-fiatmos/groupByTime"
        defaultValue: false
    }
    readonly property bool grouped: groupConfig.value === true

    function reload() {
        Storage.loadHabits(habitModel, page.grouped)
        today = Storage.dayCompletion()
        localGen++
    }

    onGroupedChanged: reload()

    onStatusChanged: {
        if (status === PageStatus.Active) reload()
    }

    function sectionTitle(s) {
        if (s === "morning") return qsTr("Morning")
        if (s === "afternoon") return qsTr("Afternoon")
        if (s === "evening") return qsTr("Evening")
        return qsTr("Anytime")
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

    ListModel { id: habitModel }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: habitModel

        // Sections only exist while grouping is on. Storage sorts the rows
        // into the right order in the same call, so the headers land where
        // they should.
        section.property: page.grouped ? "section" : ""
        section.criteria: ViewSection.FullString
        section.delegate: Item {
            width: listView.width
            height: Theme.itemSizeExtraSmall

            Label {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.bottom: parent.bottom
                text: page.sectionTitle(section)
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
            }
        }

        header: Column {
            width: listView.width

            // The wordmark. Lowercase, serif, italic, top-left, always -- and
            // on the same line as the system's own indicators. It takes NO
            // notch inset on purpose: it lives in the left corner, it is two
            // short words, and a centred cutout never reaches it. The name of
            // the app is never too long and never in the way, so it does not
            // have to duck.
            Item {
                width: parent.width
                height: FiatMosTheme.statusRowCenter + wordmark.height / 2 + Theme.paddingMedium

                Text {
                    id: wordmark
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.top: parent.top
                    anchors.topMargin: Math.max(0, FiatMosTheme.statusRowCenter - height / 2)
                    text: "fiat mos"
                    color: FiatMosTheme.primaryText
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatMosTheme.serif
                    font.italic: true
                }
            }

            // Today, as one ring. This is the same component the cover tile
            // and the dashboard will use -- it knows nothing about habits.
            Item {
                width: parent.width
                height: Theme.itemSizeExtraLarge * 1.5

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingLarge

                    ProgressRing {
                        id: dayRing
                        width: Theme.itemSizeExtraLarge * 1.1
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        value: {
                            var _g = page.localGen
                            return page.today.fraction
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            text: {
                                var _g = page.localGen
                                return page.today.completed + " / " + page.today.total
                            }
                            font.pixelSize: Theme.fontSizeExtraLarge
                            font.family: FiatMosTheme.serif
                            color: FiatMosTheme.primaryText
                        }

                        Label {
                            text: {
                                var _g = page.localGen
                                if (page.today.total === 0) return qsTr("nothing due today")
                                if (page.today.completed === page.today.total) return qsTr("all done today")
                                return qsTr("done today")
                            }
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                        }
                    }
                }
            }

            // Grouping is off by default and stays where you left it.
            Item {
                width: parent.width
                height: groupPill.height + Theme.paddingLarge
                visible: habitModel.count > 0

                Pill {
                    id: groupPill
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.top: parent.top
                    text: qsTr("Group by time of day")
                    selected: page.grouped
                    onClicked: groupConfig.value = !page.grouped
                }
            }
        }

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            // Always first, and it names where you are going.
            MenuItem {
                text: FiatMosTheme.ambient ? qsTr("Fiat colours") : qsTr("Follow ambience")
                color: FiatMosTheme.primaryText
                onClicked: FiatMosTheme.setAmbient(!FiatMosTheme.ambient)
            }
            // Low in the menu on purpose: rarely wanted, and one of the two
            // things in this app that can lose data.
            MenuItem {
                text: qsTr("Backup")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("BackupPage.qml"))
            }
            MenuItem {
                text: qsTr("Library")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("LibraryPage.qml"))
            }
            MenuItem {
                text: qsTr("New habit")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddHabitPage.qml"))
            }
        }


        delegate: ListItem {
            id: delegateItem
            highlightedColor: FiatMosTheme.highlightWash
            width: listView.width
            contentHeight: Theme.itemSizeMedium

            function openHabit() {
                pageStack.animatorPush(
                    model.valueType === "structured"
                        ? Qt.resolvedUrl("SessionPage.qml")
                        : Qt.resolvedUrl("LogPage.qml"),
                    { habitId: model.habitId })
            }

            menu: ContextMenu {
                highlightColor: FiatMosTheme.accent
                MenuItem {
                    text: qsTr("Edit")
                    color: FiatMosTheme.primaryText
                    onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddHabitPage.qml"),
                                                      { habitId: model.habitId })
                }
                MenuItem {
                    text: qsTr("Duplicate")
                    color: FiatMosTheme.primaryText
                    // Same setup, new habit, empty history. For when a habit
                    // took a while to get right and you want another like it.
                    onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddHabitPage.qml"),
                                                      { duplicateOfId: model.habitId })
                }
                MenuItem {
                    text: qsTr("History")
                    color: FiatMosTheme.primaryText
                    onClicked: pageStack.animatorPush(Qt.resolvedUrl("HistoryPage.qml"),
                                                      { habitId: model.habitId })
                }
                MenuItem {
                    text: qsTr("Archive")
                    color: FiatMosTheme.primaryText
                    // Remorse, not a confirmation dialog: the row steps aside
                    // and you get a few seconds to change your mind.
                    onClicked: delegateItem.remorseAction(qsTr("Archiving"), function() {
                        Storage.archiveHabit(model.habitId)
                        page.reload()
                    })
                }
            }

            onClicked: openHabit()

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                // The indicator. A habit is either counted or checked, and
                // the SHAPE says which -- a ring you can be part-way round,
                // or a dot that is filled or not. Never merge the two: colour
                // alone would be the only difference left, and colour alone
                // is not a distinction everyone can see.
                Item {
                    id: indicator
                    width: Theme.itemSizeSmall * 0.6
                    height: width
                    anchors.verticalCenter: parent.verticalCenter

                    ProgressRing {
                        anchors.fill: parent
                        visible: model.counted
                        // A dozen rings sweeping in at once is noise. The
                        // header ring is the one that gets to perform.
                        animated: false
                        value: model.fraction
                        lineWidth: Math.max(2, width * 0.16)
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !model.counted
                        radius: width / 2
                        color: model.loggedToday ? FiatMosTheme.accent : "transparent"
                        border.width: 1
                        border.color: model.loggedToday
                            ? FiatMosTheme.accent
                            : (model.dueToday ? FiatMosTheme.pillBorder : FiatMosTheme.dotIdle)
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: !model.counted && model.loggedToday
                        text: "✓"
                        color: FiatMosTheme.markOn(FiatMosTheme.accent)
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (model.valueType === "boolean" && !model.counted && !model.loggedToday) {
                                Storage.addEntry(Storage.getHabit(model.habitId), {})
                                page.reload()
                            } else {
                                delegateItem.openHabit()
                            }
                        }
                    }
                }

                Column {
                    width: parent.width - indicator.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        width: parent.width
                        text: model.name
                        truncationMode: TruncationMode.Fade
                        color: delegateItem.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
                    }

                    // Streak-forward. The streak is the thing worth
                    // protecting, so it gets the line every time the app
                    // opens; today's numbers only surface when there is no
                    // streak left to lose.
                    Row {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: model.streak > 0
                            width: Theme.paddingSmall
                            height: width
                            radius: width / 2
                            color: FiatMosTheme.streakMark
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                            truncationMode: TruncationMode.Fade
                            text: {
                                if (model.streak > 0) {
                                    if (model.frequency === "weekly_n") {
                                        return model.streak === 1
                                            ? qsTr("1 week streak")
                                            : qsTr("%1 week streak").arg(model.streak)
                                    }
                                    return model.streak === 1
                                        ? qsTr("1 day streak")
                                        : qsTr("%1 day streak").arg(model.streak)
                                }
                                if (model.counted) {
                                    var d = Math.round(model.doneToday * 100) / 100
                                    var t = Math.round(model.dailyTarget * 100) / 100
                                    return model.unit === ""
                                        ? qsTr("%1/%2 today").arg(d).arg(t)
                                        : qsTr("%1/%2 %3 today").arg(d).arg(t).arg(model.unit)
                                }
                                return qsTr("not started")
                            }
                        }
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
        enabled: habitModel.count === 0
        text: qsTr("No habits")
        // The motto lives here rather than in the icon. It is a sentence,
        // and a sentence needs room.
        hintText: qsTr("Gutta cavat lapidem, non vi sed saepe cadendo — the drop hollows the stone, not by force but by falling often.\n\nPull down to create the first one")
    }
}
