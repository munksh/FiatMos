import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Handles check, number, rating and reference habits. Structured habits get
// their own page (SessionPage) -- HabitListPage routes them there directly.
//
// The page works on one day: today, or yesterday for whatever did not get
// logged before midnight. Yesterday is as far back as it goes, on purpose --
// a page that could log any date would be a page for rewriting history.

Page {
    id: page

    property int habitId: -1
    property var habit: null
    property int gen: 0                      // bumped on every write
    property int scaleValue: -1
    property int bookId: -1
    property var readingItems: []
    property int dayOffset: 0                // 0 today, -1 yesterday
    property string day: ""                  // the day key dayOffset points at

    // Pills stay readable up to about a dozen steps. Above that a slider is
    // the right control -- a Flow of 40 pills is not a scale, it's a wall.
    readonly property bool scaleUsesPills: {
        var _g = page.gen
        return page.habit !== null && page.habit.scaleMax <= 12
    }

    function refresh() {
        habit = Storage.getHabit(habitId)
        day = Storage.dayOffsetKey(dayOffset)
        Storage.loadEntriesForDay(entryModel, habitId, day)
        if (habit !== null && habit.valueType === "reference") {
            // Only this habit's kind. Logging a roll of film under Reading
            // is not something you have to remember not to do.
            readingItems = Storage.itemsForHabit(habit)
            if (bookId >= 0) {
                var stillThere = false
                for (var i = 0; i < readingItems.length; i++) {
                    if (readingItems[i].id === bookId) stillThere = true
                }
                if (!stillThere) bookId = -1
            }
            if (bookId < 0 && readingItems.length === 1) bookId = readingItems[0].id
        }
        gen++
    }

    function saveEntry() {
        if (habit === null) return
        var note = noteField.text.trim()

        if (habit.valueType === "reference") {
            if (bookId < 0) return
            var amount = null
            if (numberField.text.trim() !== "") {
                var a = parseFloat(numberField.text.replace(",", "."))
                if (!isNaN(a)) amount = a
            }
            Storage.addReferenceEntry(habit, bookId, amount, note, page.day)
        } else {
            var values = { note: note, loggedAt: Storage.loggedAtFor(page.day) }
            if (habit.valueType === "numeric") {
                var parsed = parseFloat(numberField.text.replace(",", "."))
                if (isNaN(parsed)) return
                values.numeric = parsed
            } else if (habit.valueType === "scale") {
                if (page.scaleValue < 0) return
                values.scale = page.scaleValue
            }
            Storage.addEntry(habit, values)
        }

        numberField.text = ""
        noteField.text = ""
        page.scaleValue = -1
        refresh()
    }

    // "Sunday 27 September", in the phone's own language.
    function dayName(key) {
        if (key === "") return ""
        return Qt.formatDate(Storage.dateFromDayKey(key), "dddd d MMMM")
    }

    function weekday(key) {
        if (key === "") return ""
        return Qt.formatDate(Storage.dateFromDayKey(key), "dddd")
    }

    onDayOffsetChanged: refresh()
    Component.onCompleted: refresh()

    // Left open across midnight, "today" has to move with the clock.
    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive) page.refresh()
        }
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

    ListModel { id: entryModel }

    SilicaFlickable {
        id: flick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: saveArea.top
        contentHeight: content.height + Theme.paddingLarge
        clip: true

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            MenuItem {
                color: FiatMosTheme.primaryText
                visible: {
                    var _g = page.gen
                    return page.habit !== null && page.habit.valueType === "reference"
                }
                text: qsTr("Shelf")
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("LibraryPage.qml"))
            }
            MenuItem {
                text: qsTr("History")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("HistoryPage.qml"), { habitId: page.habitId })
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHead {
                title: {
                    var _g = page.gen
                    return page.habit === null ? "" : page.habit.name
                }
                subtitle: {
                    var _g = page.gen
                    if (page.habit === null) return ""
                    var s = Storage.streak(page.habit)
                    if (s === 0) return qsTr("No streak yet")
                    if (page.habit.frequency === "weekly_n")
                        return s === 1 ? qsTr("1 week in a row") : qsTr("%1 weeks in a row").arg(s)
                    return s === 1 ? qsTr("1 time in a row") : qsTr("%1 times in a row").arg(s)
                }
            }

            // -- Which day -----------------------------------------------------

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("today")
                    selected: page.dayOffset === 0
                    onClicked: page.dayOffset = 0
                }
                Pill {
                    text: {
                        var _g = page.gen
                        return qsTr("yesterday · %1").arg(Qt.formatDate(Storage.dateFromDayKey(Storage.dayOffsetKey(-1)), "ddd d"))
                    }
                    selected: page.dayOffset === -1
                    onClicked: page.dayOffset = -1
                }
            }

            // -- Check --------------------------------------------------------

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: {
                    var _g = page.gen
                    return page.habit !== null && page.habit.valueType === "boolean"
                }
                wrapMode: Text.WordWrap
                color: FiatMosTheme.secondaryText
                font.pixelSize: Theme.fontSizeSmall
                text: {
                    var _g = page.gen
                    if (page.dayOffset === 0) return entryModel.count > 0 ? qsTr("Logged today.") : qsTr("Not logged today.")
                    return entryModel.count > 0 ? qsTr("Logged yesterday.") : qsTr("Not logged yesterday.")
                }
            }

            // -- Reference: which book ----------------------------------------

            Column {
                width: parent.width
                spacing: Theme.paddingSmall
                visible: {
                    var _g = page.gen
                    return page.habit !== null && page.habit.valueType === "reference"
                }

                SectionLabel {
                    x: Theme.horizontalPageMargin
                    text: qsTr("Item")
                }

                Flow {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    spacing: Theme.paddingSmall

                    Repeater {
                        model: {
                            var _g = page.gen
                            return page.readingItems.length
                        }
                        Pill {
                            text: page.readingItems[index].title
                            selected: page.bookId === page.readingItems[index].id
                            onClicked: page.bookId = page.readingItems[index].id
                        }
                    }
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    visible: {
                        var _g = page.gen
                        return page.readingItems.length === 0
                    }
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    text: qsTr("Nothing on the go. Add something from the Shelf in the pull-down menu.")
                }
            }

            // -- Number (numeric habits, and the optional amount for books) ----

            TextField {
                id: numberField
                width: parent.width
                visible: {
                    var _g = page.gen
                    if (page.habit === null) return false
                    return page.habit.valueType === "numeric" || page.habit.valueType === "reference"
                }
                label: {
                    var _g = page.gen
                    if (page.habit === null) return ""
                    if (page.habit.valueType === "reference") {
                        var u = Storage.unitForHabit(page.habit)
                        return u === "" ? qsTr("Amount (optional)") : qsTr("%1 (optional)").arg(u)
                    }
                    return page.habit.unit === "" ? qsTr("Value") : qsTr("Value (%1)").arg(page.habit.unit)
                }
                placeholderText: {
                    var _g = page.gen
                    if (page.habit === null) return qsTr("Value")
                    if (page.habit.valueType === "reference") return qsTr("Leave empty to just mark it read")
                    if (page.habit.targetValue === null) return qsTr("Value")
                    return qsTr("Target: %1").arg(page.habit.targetValue)
                }
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // -- Scale ---------------------------------------------------------

            Column {
                width: parent.width
                spacing: Theme.paddingSmall
                visible: {
                    var _g = page.gen
                    return page.habit !== null && page.habit.valueType === "scale"
                }

                SectionLabel {
                    x: Theme.horizontalPageMargin
                    visible: page.scaleUsesPills
                    text: {
                        var _g = page.gen
                        if (page.habit === null) return ""
                        return qsTr("Value 0–%1").arg(page.habit.scaleMax)
                    }
                }

                Flow {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    spacing: Theme.paddingSmall
                    visible: page.scaleUsesPills

                    Repeater {
                        model: {
                            var _g = page.gen
                            if (page.habit === null || !page.scaleUsesPills) return 0
                            return page.habit.scaleMax + 1
                        }
                        Pill {
                            text: index
                            selected: page.scaleValue === index
                            onClicked: page.scaleValue = index
                        }
                    }
                }

                Slider {
                    width: parent.width
                    visible: !page.scaleUsesPills
                    minimumValue: 0
                    maximumValue: {
                        var _g = page.gen
                        return page.habit === null ? 1 : page.habit.scaleMax
                    }
                    stepSize: 1
                    label: qsTr("Value")
                    valueText: Math.round(value)
                    onValueChanged: if (!page.scaleUsesPills) page.scaleValue = Math.round(value)
                }
            }

            // -- Note ----------------------------------------------------------

            TextField {
                id: noteField
                width: parent.width
                label: qsTr("Note (optional)")
                placeholderText: qsTr("Note")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // -- The day's entries ---------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: entryModel.count > 0
                text: {
                    var _g = page.gen
                    return page.dayOffset === 0 ? qsTr("Today") : page.dayName(page.day)
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.dayOffset !== 0 && entryModel.count === 0
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: {
                    var _g = page.gen
                    return qsTr("Nothing logged on %1.").arg(page.dayName(page.day))
                }
            }

            Repeater {
                model: entryModel

                ListItem {

                    highlightedColor: FiatMosTheme.highlightWash
                    width: content.width
                    contentHeight: Theme.itemSizeSmall

                    menu: ContextMenu {
                        highlightColor: FiatMosTheme.accent
                        MenuItem {
                            text: qsTr("Undo")
                            color: FiatMosTheme.primaryText
                            onClicked: {
                                // Never a DELETE. A new row supersedes this one.
                                Storage.voidEntry(page.habitId, model.entryId)
                                page.refresh()
                            }
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2
                        spacing: Theme.paddingMedium

                        // A late entry's clock time is a stand-in, so it
                        // says when it was written instead.
                        Label {
                            text: model.late ? qsTr("later") : model.timeLabel
                            color: FiatMosTheme.secondaryText
                            font.pixelSize: Theme.fontSizeSmall
                            width: Theme.itemSizeSmall
                        }

                        Label {
                            color: FiatMosTheme.primaryText
                            font.pixelSize: Theme.fontSizeSmall
                            truncationMode: TruncationMode.Fade
                            text: {
                                var _g = page.gen
                                if (page.habit === null) return ""
                                if (page.habit.valueType === "boolean") return "✓"
                                if (page.habit.valueType === "numeric") {
                                    var v = Math.round(model.valueNumeric * 100) / 100
                                    return page.habit.unit === "" ? v : v + " " + page.habit.unit
                                }
                                if (page.habit.valueType === "scale") {
                                    return model.valueScale + "/" + page.habit.scaleMax
                                }
                                if (page.habit.valueType === "reference") {
                                    if (!model.hasNumeric) return model.bookTitle
                                    var a = Math.round(model.valueNumeric * 100) / 100
                                    var u = Storage.unitForHabit(page.habit)
                                    var amt = u === "" ? a : a + " " + u
                                    return model.bookTitle === "" ? String(amt) : model.bookTitle + " · " + amt
                                }
                                return "✓"
                            }
                        }

                        Label {
                            color: FiatMosTheme.secondaryText
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                            text: model.note
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator { }
    }

    // Save sits in the thumb zone, not at the end of the form.
    Item {
        id: saveArea
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.itemSizeLarge

        Button {
            anchors.centerIn: parent
            text: {
                var _g = page.gen
                if (page.habit === null) return qsTr("Log")
                if (page.dayOffset !== 0) {
                    return (page.habit.valueType === "boolean" && entryModel.count > 0)
                        ? qsTr("Log %1 again").arg(page.weekday(page.day))
                        : qsTr("Log for %1").arg(page.weekday(page.day))
                }
                if (page.habit.valueType === "boolean" && entryModel.count > 0) return qsTr("Log again")
                return qsTr("Log")
            }
            enabled: {
                var _g = page.gen
                var _s = page.scaleValue
                var _b = page.bookId
                var _n = numberField.text
                if (page.habit === null) return false
                if (page.habit.valueType === "numeric") return _n.trim() !== ""
                if (page.habit.valueType === "scale") return _s >= 0
                if (page.habit.valueType === "reference") return _b >= 0
                return true
            }
            onClicked: page.saveEntry()
        }
    }
}
