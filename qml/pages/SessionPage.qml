import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// A Practise it habit: one session made of things, each made of sets.
//
// Each exercise is a THING you practise -- named once, then found again by
// name, with a history of its own. While you type a name the things you
// already have are offered; under each exercise is what you did last time,
// so you can see what to aim for without leaving the page. How a thing is
// measured (weight × reps, time, time + distance) belongs to the thing, and
// can be changed right here when you name it.
//
// The whole session lives in `comps` as plain UI state until Save. Prefilling
// from the last session copies values into this array only -- nothing is
// written to the database until you save, and the old session is never
// touched.
//
// comps: [{ name, measure, details: [{ reps, weight, minutes, km, note }] }]
// All detail values are strings here; they are parsed on save.
//
// A set is a CARD. It reads as a card, swipes left to reveal Delete, and the
// delete waits three seconds with a way out. Tapping a card turns it into
// fields. That order matters: a row full of live text fields cannot also be a
// swipe target, because every horizontal drag would land on a cursor instead.
//
// Like the log page it works on one day, today or yesterday, and there is
// still only ever one session per day.

Page {
    id: page

    property int habitId: -1
    property var habit: null
    property var comps: []
    property var routineList: []
    property int routineId: -1          // -1 = ad hoc
    // Set by the Practice page: start from this program unless today
    // already has a session.
    property int startProgramId: -1
    // How a new exercise starts out measured: the habit's kind's default.
    property string defaultMeasure: "weight_reps"
    property int kindId: -1
    property int gen: 0
    property int dayOffset: 0           // 0 today, -1 yesterday
    property string day: ""
    // Whether you have changed anything since the page was filled. Only then
    // is there something to save on the way out -- a page prefilled from last
    // Tuesday and left untouched is not a workout.
    property bool touched: false
    property int renamingIndex: -1      // which exercise is being renamed
    // Which set is open as fields. Closing one re-reads the card, because the
    // text fields write straight into `comps` and the reading row is built from
    // a snapshot -- so without this the card still showed 8 after you typed 10,
    // right up until the session was saved. The data was never wrong; only the
    // card was.
    property string editingSet: ""      // "compIndex:setIndex", or empty
    onEditingSetChanged: bump()
    property string pendingSet: ""      // the set counting down to deletion

    function bump() {
        comps = comps.slice()
        gen++
    }

    function key(c, s) {
        return c + ":" + s
    }

    function emptyDetail() {
        return { reps: "", weight: "", minutes: "", km: "", note: "" }
    }

    function copyDetail(d) {
        return { reps: d.reps, weight: d.weight, minutes: d.minutes, km: d.km, note: d.note }
    }

    function measureOf(c) {
        var _g = page.gen
        var m = page.comps[c] === undefined ? "" : page.comps[c].measure
        return (m === undefined || m === "") ? page.defaultMeasure : m
    }

    // A name that is already a thing brings that thing's measure with it --
    // unless a measure was picked by hand while naming it, which then wins
    // and becomes the thing's on save.
    function settleName(c) {
        var n = (page.comps[c].name || "").trim()
        if (n === "" || page.comps[c].measurePicked === true) return
        var id = Storage.thingIdByName(page.kindId, n)
        if (id >= 0) {
            var it = Storage.itemById(id)
            if (it !== null) page.comps[c].measure = it.measure
        }
    }

    // What this exercise was last time, before the day on the page. Said in
    // words, or empty for a thing that is new.
    function lastTimeText(c) {
        var _g = page.gen
        if (page.comps[c] === undefined) return ""
        var n = (page.comps[c].name || "").trim()
        if (n === "" || page.kindId < 0) return ""
        var lt = Storage.lastTimeFor(page.kindId, n, page.day)
        if (lt === null) return qsTr("new")
        if (lt.day === "") return ""
        var when = Qt.formatDate(Storage.dateFromDayKey(lt.day), "ddd d MMM")
        return lt.summary === "" ? qsTr("last time %1").arg(when) : qsTr("last time %1 · %2").arg(when).arg(lt.summary)
    }

    function fromStored(details) {
        var out = []
        for (var i = 0; i < details.length; i++) {
            var d = details[i]
            out.push({
                reps: d.reps === null ? "" : String(d.reps),
                weight: d.weight === null ? "" : String(d.weight),
                minutes: d.duration === null ? "" : String(Math.round(d.duration / 6) / 10),
                km: (d.distance === null || d.distance === undefined) ? "" : String(Math.round(d.distance) / 1000),
                note: d.note === null ? "" : d.note
            })
        }
        if (out.length === 0) out.push(emptyDetail())
        return out
    }

    // Prefill from the most recent session with this routine. UI state only.
    function selectRoutine(id) {
        routineId = id
        renamingIndex = -1
        editingSet = ""
        pendingSet = ""
        var s = (id < 0) ? null : Storage.lastSession(habitId, id)
        var next = []
        if (s !== null) {
            for (var i = 0; i < s.components.length; i++) {
                next.push({ name: s.components[i].name, measure: s.components[i].measure,
                            details: fromStored(s.components[i].details) })
            }
        }
        comps = next
        bump()
    }

    function addExercise() {
        touched = true
        comps.push({ name: "", measure: page.defaultMeasure, details: [emptyDetail()] })
        renamingIndex = comps.length - 1     // a new exercise needs a name first
        bump()
    }

    function duplicateExercise(i) {
        touched = true
        var src = comps[i]
        var copy = { name: src.name, measure: src.measure, details: [] }
        for (var j = 0; j < src.details.length; j++) copy.details.push(copyDetail(src.details[j]))
        comps.splice(i + 1, 0, copy)
        bump()
    }

    function removeExercise(i) {
        touched = true
        comps.splice(i, 1)
        renamingIndex = -1
        editingSet = ""
        pendingSet = ""
        bump()
    }

    function addSet(i) {
        // Start from the previous set rather than from nothing -- the second
        // set of an exercise is almost always the first one again.
        touched = true
        var d = comps[i].details
        comps[i].details.push(d.length > 0 ? copyDetail(d[d.length - 1]) : emptyDetail())
        bump()
    }

    function removeSet(c, s) {
        touched = true
        var d = comps[c].details
        d.splice(s, 1)
        if (d.length === 0) d.push(emptyDetail())
        editingSet = ""
        pendingSet = ""
        bump()
    }

    function num(s) {
        if (s === undefined || s === null) return ""
        var t = String(s).trim().replace(",", ".")
        if (t === "") return ""
        var v = parseFloat(t)
        return isNaN(v) ? "" : v
    }

    function save() {
        if (habit === null) return

        // Only the fields the thing's measure shows are written. What a set
        // already had in another field stays in the database untouched --
        // it is only this page that does not show it.
        var payload = []
        for (var i = 0; i < comps.length; i++) {
            var m = measureOf(i)
            var det = []
            for (var j = 0; j < comps[i].details.length; j++) {
                var d = comps[i].details[j]
                var minutes = num(d.minutes)
                var km = num(d.km)
                det.push({
                    reps: m === "weight_reps" ? num(d.reps) : "",
                    weight: m === "weight_reps" ? num(d.weight) : "",
                    duration: (m !== "weight_reps" && minutes !== "") ? Math.round(minutes * 60) : "",
                    distance: (m === "time_distance" && km !== "") ? Math.round(km * 1000) : "",
                    note: (d.note || "").trim()
                })
            }
            payload.push({ name: comps[i].name, measure: m, details: det })
        }

        var rid = routineId
        var newName = routineNameField.text.trim()
        if (rid < 0 && newName !== "") rid = Storage.addRoutine(habitId, newName)

        Storage.saveSession(habit, rid, payload, sessionNoteField.text.trim(), page.day)
        page.saved = true
        page.touched = false
        page.continuing = true
    }

    // Whether there is anything worth writing. An empty page that was opened
    // and left must not create a session, or every accidental tap becomes a
    // logged workout.
    function worthSaving() {
        for (var i = 0; i < comps.length; i++) {
            if ((comps[i].name || "").trim() === "") continue
            var d = comps[i].details || []
            for (var j = 0; j < d.length; j++) {
                if (num(d[j].reps) !== "" || num(d[j].weight) !== "" || num(d[j].minutes) !== ""
                    || num(d[j].km) !== "" || (d[j].note || "").trim() !== "") return true
            }
        }
        return false
    }

    property bool saved: false

    // Saving on the way out.
    //
    // This is only safe because a save now rewrites today's session instead of
    // adding another one -- so leaving, coming back and leaving again costs
    // nothing. It is what stops the habit of saving every few minutes "so as
    // not to lose it", which was never a feature, only a fear.
    //
    // The Save button stays: it is how you say "this one is finished", and it
    // is the only way to leave with a routine name you just typed.
    function autosave() {
        if (habit === null) return
        if (!touched) return
        if (!worthSaving()) return
        save()
    }

    // Fills the page for the chosen day.
    //
    // That day's session first. If you are already mid-workout, the page
    // continues where you were rather than offering last Tuesday as a
    // template -- and Save then rewrites that same session.
    function loadDay() {
        day = Storage.dayOffsetKey(dayOffset)
        renamingIndex = -1
        editingSet = ""
        pendingSet = ""
        continuing = false

        var existing = Storage.sessionForDay(habitId, day)
        if (existing !== null && existing.components.length > 0) {
            routineId = (existing.routineId === null || existing.routineId === undefined) ? -1 : existing.routineId
            var next = []
            for (var i = 0; i < existing.components.length; i++) {
                next.push({ name: existing.components[i].name,
                            measure: existing.components[i].measure,
                            details: fromStored(existing.components[i].details) })
            }
            comps = next
            continuing = true
            bump()
        } else if (page.startProgramId >= 0) {
            selectRoutine(page.startProgramId)
        } else {
            var last = Storage.lastSession(habitId, null)
            if (last !== null && last.routineId !== null && last.routineId !== undefined) {
                selectRoutine(last.routineId)
            } else {
                routineId = -1
                comps = [{ name: "", measure: page.defaultMeasure, details: [emptyDetail()] }]
                renamingIndex = 0
                bump()
            }
        }
        // Only the first day the page opens on; switching days is your own
        // choice again.
        page.startProgramId = -1
        touched = false
    }

    // Whatever you changed on the day you were on is kept before the page
    // moves to the other one.
    function switchDay(offset) {
        if (offset === dayOffset) return
        autosave()
        dayOffset = offset
        loadDay()
    }

    function weekday(key) {
        if (key === "") return ""
        return Qt.formatDate(Storage.dateFromDayKey(key), "dddd")
    }

    Component.onCompleted: {
        habit = Storage.getHabit(habitId)
        if (habit !== null && habit.kindId >= 0) {
            kindId = habit.kindId
            var k = Storage.kindById(kindId)
            if (k !== null) defaultMeasure = k.measure
        }
        routineList = Storage.routines(habitId)
        loadDay()
    }

    // True when the page opened onto a session that already existed today.
    property bool continuing: false

    // Leaving the page writes what is there. Deactivating covers the back
    // gesture, the home swipe and the app being closed from the switcher.
    onStatusChanged: {
        if (status === PageStatus.Deactivating) autosave()
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: saveArea.top
        contentHeight: content.height + Theme.paddingLarge
        clip: true

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            MenuItem {
                text: qsTr("Past sessions")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("HistoryPage.qml"), { habitId: page.habitId })
            }
            MenuItem {
                text: qsTr("Add exercise")
                color: FiatMosTheme.primaryText
                onClicked: page.addExercise()
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
                // Says which of the two things is happening, because the page
                // looks identical either way and the difference matters.
                subtitle: {
                    if (page.dayOffset === 0) return page.continuing ? qsTr("today's session") : qsTr("new session")
                    return page.continuing ? qsTr("yesterday's session") : qsTr("new session for yesterday")
                }
            }

            // -- Which day ----------------------------------------------------

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("today")
                    selected: page.dayOffset === 0
                    onClicked: page.switchDay(0)
                }
                Pill {
                    text: {
                        var _g = page.gen
                        return qsTr("yesterday · %1").arg(Qt.formatDate(Storage.dateFromDayKey(Storage.dayOffsetKey(-1)), "ddd d"))
                    }
                    selected: page.dayOffset === -1
                    onClicked: page.switchDay(-1)
                }
            }

            // -- Routine ------------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Program")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("Free session")
                    selected: page.routineId < 0
                    onClicked: page.selectRoutine(-1)
                }

                Repeater {
                    model: page.routineList.length
                    Pill {
                        text: page.routineList[index].name
                        selected: page.routineId === page.routineList[index].id
                        onClicked: page.selectRoutine(page.routineList[index].id)
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                visible: page.routineId >= 0
                text: qsTr("Prefilled from your last session with this program. Change whatever you like — the old session is untouched.")
            }

            // -- Exercises ----------------------------------------------------

            Repeater {
                model: page.comps.length

                Column {
                    id: compColumn
                    property int compIndex: index
                    width: content.width
                    spacing: Theme.paddingSmall

                    // The exercise name is a heading you press and hold, not a
                    // field with a bin beside it. Holding is where the several
                    // things you might do to it live. Under the name: what it
                    // was last time, so today has something to aim at.
                    ListItem {
                        id: exerciseItem
                        width: parent.width
                        contentHeight: Math.max(Theme.itemSizeSmall, headCol.height + Theme.paddingMedium * 2)
                        highlightedColor: FiatMosTheme.highlightWash
                        visible: page.renamingIndex !== compColumn.compIndex

                        menu: ContextMenu {
                            highlightColor: FiatMosTheme.accent

                            MenuItem {
                                text: qsTr("Rename or measure")
                                color: FiatMosTheme.primaryText
                                onClicked: page.renamingIndex = compColumn.compIndex
                            }
                            MenuItem {
                                text: qsTr("Duplicate exercise")
                                color: FiatMosTheme.primaryText
                                onClicked: page.duplicateExercise(compColumn.compIndex)
                            }
                            MenuItem {
                                text: qsTr("Delete exercise")
                                color: FiatMosTheme.wrong
                                onClicked: exerciseItem.remorseAction(qsTr("Deleting exercise"), function() {
                                    page.removeExercise(compColumn.compIndex)
                                })
                            }
                        }

                        onClicked: page.renamingIndex = compColumn.compIndex

                        Column {
                            id: headCol
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.horizontalPageMargin
                            width: parent.width - Theme.horizontalPageMargin * 2

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                font.pixelSize: Theme.fontSizeLarge
                                font.family: FiatMosTheme.serif
                                color: {
                                    var _g = page.gen
                                    var n = (page.comps[compColumn.compIndex].name || "").trim()
                                    return n === "" ? FiatMosTheme.secondaryText : FiatMosTheme.primaryText
                                }
                                text: {
                                    var _g = page.gen
                                    var n = (page.comps[compColumn.compIndex].name || "").trim()
                                    return n === "" ? qsTr("Unnamed exercise") : n
                                }
                            }

                            Label {
                                width: parent.width
                                visible: text !== ""
                                truncationMode: TruncationMode.Fade
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: FiatMosTheme.secondaryText
                                text: page.lastTimeText(compColumn.compIndex)
                            }
                        }
                    }

                    // Naming an exercise. The things you already practise are
                    // offered as words while you type, and how this one is
                    // measured sits right under the name -- the plank in a
                    // strength session is timed, and that is said here, once.
                    Column {
                        width: parent.width
                        visible: page.renamingIndex === compColumn.compIndex
                        spacing: Theme.paddingSmall

                        TextField {
                            id: nameField
                            width: parent.width
                            label: qsTr("Exercise")
                            placeholderText: qsTr("Exercise")
                            color: FiatMosTheme.primaryText
                            Component.onCompleted: text = page.comps[compColumn.compIndex].name
                            onTextChanged: {
                                page.comps[compColumn.compIndex].name = text
                                if (activeFocus) page.touched = true
                                suggestions.term = text
                            }
                            EnterKey.iconSource: "image://theme/icon-m-enter-close"
                            EnterKey.onClicked: {
                                focus = false
                                page.settleName(compColumn.compIndex)
                                page.renamingIndex = -1
                                page.bump()
                            }
                        }

                        Flow {
                            id: suggestions
                            property string term: ""
                            x: Theme.horizontalPageMargin
                            width: parent.width - Theme.horizontalPageMargin * 2
                            spacing: Theme.paddingSmall
                            visible: page.kindId >= 0 && sugRepeater.count > 0

                            Repeater {
                                id: sugRepeater
                                model: {
                                    var _g = page.gen
                                    if (page.kindId < 0 || page.renamingIndex !== compColumn.compIndex) return []
                                    var list = Storage.thingSuggestions(page.kindId, suggestions.term, 8)
                                    // Not what is already in today's session.
                                    var inUse = {}
                                    for (var i = 0; i < page.comps.length; i++) {
                                        if (i === compColumn.compIndex) continue
                                        inUse[(page.comps[i].name || "").trim().toLowerCase()] = true
                                    }
                                    var out = []
                                    for (var j = 0; j < list.length; j++) {
                                        if (!inUse[list[j].title.toLowerCase()]) out.push(list[j])
                                    }
                                    return out
                                }
                                Pill {
                                    multi: true
                                    text: modelData.title
                                    onClicked: {
                                        page.comps[compColumn.compIndex].name = modelData.title
                                        page.comps[compColumn.compIndex].measure = modelData.measure
                                        nameField.text = modelData.title
                                        nameField.focus = false
                                        page.touched = true
                                        page.renamingIndex = -1
                                        page.bump()
                                    }
                                }
                            }
                        }

                        Flow {
                            x: Theme.horizontalPageMargin
                            width: parent.width - Theme.horizontalPageMargin * 2
                            spacing: Theme.paddingSmall

                            Label {
                                height: Theme.itemSizeExtraSmall
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("measured in")
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: FiatMosTheme.secondaryText
                            }

                            Repeater {
                                model: Measures.choices()
                                Pill {
                                    text: modelData.label
                                    selected: page.measureOf(compColumn.compIndex) === modelData.value
                                    onClicked: {
                                        page.comps[compColumn.compIndex].measure = modelData.value
                                        page.comps[compColumn.compIndex].measurePicked = true
                                        page.touched = true
                                        page.bump()
                                    }
                                }
                            }
                        }

                        ActionWord {
                            x: Theme.horizontalPageMargin - Theme.paddingMedium
                            text: qsTr("done")
                            onClicked: {
                                nameField.focus = false
                                page.settleName(compColumn.compIndex)
                                page.renamingIndex = -1
                                page.bump()
                            }
                        }
                    }

                    // -- Sets, as cards ----------------------------------------

                    Repeater {
                        model: page.comps[compColumn.compIndex].details.length

                        Item {
                            id: setWrap
                            property int setIndex: index
                            property string myKey: page.key(compColumn.compIndex, index)
                            property bool editingThis: page.editingSet === myKey
                            property bool pendingThis: page.pendingSet === myKey
                            // A quarter of the row width. Low enough not to fight you.
                            property real threshold: width * 0.25

                            x: Theme.horizontalPageMargin
                            width: content.width - Theme.horizontalPageMargin * 2
                            height: card.height
                            // So the card is cut off at the row edge instead of
                            // sliding out over the page margin.
                            clip: true

                            function detail() {
                                return page.comps[compColumn.compIndex].details[setWrap.setIndex]
                            }

                            function close() {
                                card.x = 0
                            }

                            // 1 when the countdown starts, 0 when it runs out.
                            // Drives the shade below, so the time left is a
                            // shape and not just a number nobody is counting.
                            property real countdown: 1

                            function startRemorse() {
                                page.pendingSet = myKey
                                card.x = -width
                                setWrap.countdown = 1
                                countdownAnim.restart()
                                remorseTimer.restart()
                            }

                            function stopRemorse() {
                                countdownAnim.stop()
                                remorseTimer.stop()
                                setWrap.countdown = 1
                            }

                            Timer {
                                id: remorseTimer
                                interval: 3000
                                onTriggered: {
                                    if (page.pendingSet !== setWrap.myKey) return
                                    page.removeSet(compColumn.compIndex, setWrap.setIndex)
                                }
                            }

                            NumberAnimation {
                                id: countdownAnim
                                target: setWrap
                                property: "countdown"
                                from: 1
                                to: 0
                                duration: 3000
                            }

                            // Behind the card. While you drag it is just a
                            // red field; once you let go past the threshold
                            // the card leaves entirely and this becomes the
                            // countdown. No Delete button to aim at, no
                            // second tap -- that is the Sailfish way round.
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.paddingLarge
                                color: FiatMosTheme.wrong
                                visible: card.x < -1 || setWrap.pendingThis
                                clip: true

                                // The time left, as a shape. A darker band
                                // that shrinks away to the left over the three
                                // seconds -- so you can see how long you still
                                // have without reading anything.
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * setWrap.countdown
                                    visible: setWrap.pendingThis
                                    color: Qt.darker(FiatMosTheme.wrong, 1.45)
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.paddingLarge
                                    anchors.rightMargin: Theme.paddingLarge
                                    visible: setWrap.pendingThis

                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - cancelBtn.width
                                        text: qsTr("Deleting set…")
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: FiatMosTheme.markOn(FiatMosTheme.wrong)
                                    }

                                    BackgroundItem {
                                        id: cancelBtn
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: cancelLabel.width + Theme.paddingLarge
                                        height: Theme.itemSizeExtraSmall
                                        onClicked: {
                                            setWrap.stopRemorse()
                                            page.pendingSet = ""
                                            setWrap.close()
                                        }
                                        Label {
                                            id: cancelLabel
                                            anchors.centerIn: parent
                                            text: qsTr("Cancel")
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: FiatMosTheme.markOn(FiatMosTheme.wrong)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: card
                                width: parent.width
                                height: cardColumn.height + Theme.paddingMedium * 2
                                radius: Theme.paddingLarge
                                color: FiatMosTheme.card
                                border.color: FiatMosTheme.cardBorder
                                border.width: 1

                                Behavior on x {
                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }

                                Column {
                                    id: cardColumn
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Theme.paddingLarge
                                    width: parent.width - Theme.paddingLarge * 2
                                    spacing: Theme.paddingSmall

                                    // -- reading the set ----------------------
                                    Row {
                                        width: parent.width
                                        spacing: Theme.paddingLarge
                                        // NOT hidden while the remorse runs.
                                        // A Column ignores invisible children
                                        // when it measures itself, so hiding
                                        // this row took cardColumn's height to
                                        // zero, then card's, then setWrap's --
                                        // and the red field behind, anchored to
                                        // setWrap, collapsed into a strip. The
                                        // card has already slid off screen by
                                        // then; there is nothing to hide.
                                        visible: !setWrap.editingThis

                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Theme.itemSizeExtraSmall / 2
                                            text: setWrap.setIndex + 1
                                            font.pixelSize: Theme.fontSizeExtraSmall
                                            color: FiatMosTheme.secondaryText
                                        }

                                        Repeater {
                                            model: {
                                                var _g = page.gen
                                                var d = setWrap.detail()
                                                var m = page.measureOf(compColumn.compIndex)
                                                var out
                                                if (m === "time")
                                                    out = [{ v: d.minutes, u: qsTr("Minutes") }]
                                                else if (m === "time_distance")
                                                    out = [{ v: d.minutes, u: qsTr("Minutes") }, { v: d.km, u: qsTr("km") }]
                                                else
                                                    out = [{ v: d.reps, u: qsTr("Reps") }, { v: d.weight, u: qsTr("kg") }]
                                                if ((d.note || "") !== "") out.push({ v: d.note, u: qsTr("Note") })
                                                return out
                                            }

                                            Column {
                                                width: (cardColumn.width - Theme.itemSizeExtraSmall / 2 - Theme.paddingLarge * 3) / 3
                                                Label {
                                                    width: parent.width
                                                    truncationMode: TruncationMode.Fade
                                                    text: modelData.v === "" ? "–" : modelData.v
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    color: FiatMosTheme.primaryText
                                                }
                                                Label {
                                                    text: modelData.u
                                                    font.pixelSize: Theme.fontSizeTiny
                                                    color: FiatMosTheme.secondaryText
                                                }
                                            }
                                        }
                                    }

                                    // -- editing the set ----------------------
                                    // The fields the thing's measure asks for,
                                    // then a note, which every set may have.
                                    Row {
                                        width: parent.width
                                        spacing: Theme.paddingSmall
                                        visible: setWrap.editingThis

                                        TextField {
                                            width: (parent.width - Theme.paddingSmall) / 2
                                            visible: page.measureOf(compColumn.compIndex) === "weight_reps"
                                            label: qsTr("Reps")
                                            placeholderText: qsTr("Reps")
                                            inputMethodHints: Qt.ImhDigitsOnly
                                            color: FiatMosTheme.primaryText
                                            Component.onCompleted: text = setWrap.detail().reps
                                            onTextChanged: {
                                                setWrap.detail().reps = text
                                                if (activeFocus) page.touched = true
                                            }
                                            EnterKey.iconSource: "image://theme/icon-m-enter-next"
                                            EnterKey.onClicked: focus = false
                                        }

                                        TextField {
                                            width: (parent.width - Theme.paddingSmall) / 2
                                            visible: page.measureOf(compColumn.compIndex) === "weight_reps"
                                            label: qsTr("kg")
                                            placeholderText: qsTr("kg")
                                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                                            color: FiatMosTheme.primaryText
                                            Component.onCompleted: text = setWrap.detail().weight
                                            onTextChanged: {
                                                setWrap.detail().weight = text
                                                if (activeFocus) page.touched = true
                                            }
                                            EnterKey.iconSource: "image://theme/icon-m-enter-close"
                                            EnterKey.onClicked: focus = false
                                        }

                                        TextField {
                                            width: page.measureOf(compColumn.compIndex) === "time_distance"
                                                   ? (parent.width - Theme.paddingSmall) / 2 : parent.width
                                            visible: page.measureOf(compColumn.compIndex) !== "weight_reps"
                                            label: qsTr("Minutes")
                                            placeholderText: qsTr("Minutes")
                                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                                            color: FiatMosTheme.primaryText
                                            Component.onCompleted: text = setWrap.detail().minutes
                                            onTextChanged: {
                                                setWrap.detail().minutes = text
                                                if (activeFocus) page.touched = true
                                            }
                                            EnterKey.iconSource: "image://theme/icon-m-enter-close"
                                            EnterKey.onClicked: focus = false
                                        }

                                        TextField {
                                            width: (parent.width - Theme.paddingSmall) / 2
                                            visible: page.measureOf(compColumn.compIndex) === "time_distance"
                                            label: qsTr("km")
                                            placeholderText: qsTr("km")
                                            inputMethodHints: Qt.ImhFormattedNumbersOnly
                                            color: FiatMosTheme.primaryText
                                            Component.onCompleted: text = setWrap.detail().km
                                            onTextChanged: {
                                                setWrap.detail().km = text
                                                if (activeFocus) page.touched = true
                                            }
                                            EnterKey.iconSource: "image://theme/icon-m-enter-close"
                                            EnterKey.onClicked: focus = false
                                        }
                                    }

                                    TextField {
                                        width: parent.width
                                        visible: setWrap.editingThis
                                        label: qsTr("Note (optional)")
                                        placeholderText: qsTr("Note")
                                        color: FiatMosTheme.primaryText
                                        Component.onCompleted: text = setWrap.detail().note
                                        onTextChanged: {
                                            setWrap.detail().note = text
                                            if (activeFocus) page.touched = true
                                        }
                                        EnterKey.iconSource: "image://theme/icon-m-enter-close"
                                        EnterKey.onClicked: focus = false
                                    }

                                    BackgroundItem {
                                        width: doneLabel.width + Theme.paddingLarge
                                        height: Theme.itemSizeExtraSmall
                                        visible: setWrap.editingThis
                                        highlightedColor: FiatMosTheme.highlightWash
                                        onClicked: {
                                            page.editingSet = ""
                                            page.bump()
                                        }
                                        Label {
                                            id: doneLabel
                                            anchors.centerIn: parent
                                            text: qsTr("Done")
                                            font.pixelSize: Theme.fontSizeExtraSmall
                                            color: FiatMosTheme.accent
                                        }
                                    }
                                }
                            }

                            // The gesture. Only alive while the card is a card
                            // -- once it is fields, the fields own the touches.
                            MouseArea {
                                anchors.fill: parent
                                enabled: !setWrap.editingThis && !setWrap.pendingThis
                                property real pressX: 0
                                property real baseX: 0
                                property bool moved: false

                                onPressed: {
                                    pressX = mouse.x
                                    baseX = card.x
                                    moved = false
                                }
                                onPositionChanged: {
                                    var dx = mouse.x - pressX
                                    if (Math.abs(dx) > Theme.paddingSmall) moved = true
                                    card.x = Math.min(0, baseX + dx)
                                }
                                onReleased: {
                                    if (!moved) {
                                        page.editingSet = setWrap.myKey
                                        return
                                    }
                                    // Past the threshold, letting go deletes.
                                    // Short of it, the card springs back.
                                    if (card.x < -setWrap.threshold) setWrap.startRemorse()
                                    else card.x = 0
                                }
                                onCanceled: card.x = 0
                            }
                        }
                    }

                    BackgroundItem {
                        x: Theme.horizontalPageMargin
                        width: addSetLabel.width + Theme.paddingLarge
                        height: Theme.itemSizeExtraSmall
                        highlightedColor: FiatMosTheme.highlightWash
                        onClicked: page.addSet(compColumn.compIndex)
                        Label {
                            id: addSetLabel
                            anchors.centerIn: parent
                            text: qsTr("+ Add set")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.accent
                        }
                    }
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Add exercise")
                onClicked: page.addExercise()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Tap a name to change it or how it is measured. Tap a set to edit it, swipe it left to delete — you get a few seconds to change your mind. Press and hold a name for duplicate and delete.")
            }

            // -- Save as routine ----------------------------------------------

            TextField {
                id: routineNameField
                width: parent.width
                visible: page.routineId < 0
                label: qsTr("Save as program (optional)")
                placeholderText: qsTr("Name this session to start from it again")
                color: FiatMosTheme.primaryText
                onTextChanged: if (activeFocus) page.touched = true
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            TextField {
                id: sessionNoteField
                width: parent.width
                label: qsTr("Session note (optional)")
                placeholderText: qsTr("How did it go?")
                color: FiatMosTheme.primaryText
                onTextChanged: if (activeFocus) page.touched = true
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        VerticalScrollDecorator { }
    }

    Item {
        id: saveArea
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.itemSizeLarge

        Button {
            anchors.centerIn: parent
            // "Finish" rather than "Save": the page saves itself on the way
            // out now, so this button is not the thing that keeps your work.
            // It is how you say the workout is over.
            text: {
                if (page.dayOffset !== 0) return qsTr("Save for %1").arg(page.weekday(page.day))
                return page.continuing ? qsTr("Finish session") : qsTr("Save session")
            }
            enabled: {
                var _g = page.gen
                if (page.habit === null) return false
                for (var i = 0; i < page.comps.length; i++) {
                    if ((page.comps[i].name || "").trim() !== "") return true
                }
                return false
            }
            onClicked: {
                page.save()
                pageStack.pop()
            }
        }
    }
}
