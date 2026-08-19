import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Creates a habit, and edits one. Pass habitId to edit; leave it at -1 to
// create. One page, conditional fields -- the template combo decides which of
// the blocks below is visible.
//
// The order of the page is deliberate: WHAT KIND OF HABIT first, then the
// things that follow from it, then the name, then the goal. Two reasons.
// Naming a thing you have not described yet is the hardest field on the page,
// so it comes after the description and can be prefilled from it. And the
// goal cannot be worded properly until the unit is known -- "45" means
// nothing, "45 pages" means something.

Dialog {
    id: page

    property int habitId: -1
    // Set this instead of habitId to start from an existing habit's setup
    // without inheriting its history. The new habit is genuinely new -- same
    // shape, empty past.
    property int duplicateOfId: -1

    readonly property bool editing: habitId >= 0
    readonly property bool duplicating: !editing && duplicateOfId >= 0
    readonly property int sourceId: editing ? habitId : duplicateOfId

    property string valueType: "boolean"
    property string frequency: "daily"
    property string detailProfile: "strength"
    property string timeOfDay: ""              // "" means anytime
    property int scaleMax: 3
    property int frequencyN: 3

    // The kind, cached. Storage calls are not bindable, so the name and unit
    // are pulled once whenever the id changes rather than read inside a
    // binding that would never re-evaluate.
    property int kindId: -1
    property string kindName: ""
    property string kindUnitText: ""

    // The last name this page suggested. Kept so a second suggestion can
    // replace the first, but never something the user typed themselves.
    property string suggestedName: ""

    // Whether the habit is counted or checked. This used to be expressed by
    // leaving the goal field empty, which asked the user to say something by
    // NOT doing something -- the one thing a form can never make obvious.
    // Now it is a choice with two visible answers.
    property bool goalCounts: false

    readonly property var typeKeys: ["boolean", "numeric", "scale", "reference", "structured"]
    readonly property var freqKeys: ["daily", "weekly_n", "custom_interval"]
    readonly property var profileKeys: ["strength", "timed", "reps", "free"]

    // Counted habits sum their entries against the goal; the rest just count
    // how many times you logged.
    readonly property bool sumsValues: valueType === "numeric" || valueType === "reference"

    // What the goal is measured in. A numeric habit carries its own unit; a
    // library habit reads its kind's; everything else counts bare entries.
    readonly property string goalUnit: valueType === "numeric"
        ? unitField.text.trim()
        : (valueType === "reference" ? page.kindUnitText : "")

    canAccept: nameField.text.trim().length > 0
               && (valueType !== "scale" || scaleMax >= 1)
               && (valueType !== "reference" || page.kindId >= 0)

    acceptDestinationAction: PageStackAction.Pop

    function refreshKind() {
        var k = page.kindId >= 0 ? Storage.kindById(page.kindId) : null
        page.kindName = k === null ? "" : k.name
        page.kindUnitText = k === null ? "" : k.unit
    }

    // Prefilled rather than blank, so there is something to edit instead of
    // something to invent. Only ever overwrites an empty field or this page's
    // own earlier suggestion.
    function suggestName() {
        if (page.valueType !== "reference" || page.kindName === "") return
        var s = qsTr("Work through %1").arg(page.kindName)
        if (nameField.text.trim() === "" || nameField.text === page.suggestedName) {
            nameField.text = s
        }
        page.suggestedName = s
    }

    function applyKind(id) {
        page.kindId = id
        page.refreshKind()
        page.suggestName()
    }

    // animatorPush hands back an operation, not the page, so the signal has to
    // be wired up once the page exists. The fallback covers the case where the
    // operation already IS the page.
    function pickKind() {
        var op = pageStack.animatorPush(Qt.resolvedUrl("KindPage.qml"),
                                        { currentKindId: page.kindId })
        if (op === null || op === undefined) return
        if (op.pageCompleted !== undefined) {
            op.pageCompleted.connect(function(p) { p.kindPicked.connect(page.applyKind) })
        } else if (op.kindPicked !== undefined) {
            op.kindPicked.connect(page.applyKind)
        }
    }

    Component.onCompleted: {
        if (sourceId < 0) return
        var h = Storage.getHabit(sourceId)
        if (h === null) return

        // A copy needs a name of its own. Prefilled rather than blank.
        nameField.text = duplicating ? qsTr("%1 (copy)").arg(h.name) : h.name
        page.valueType = h.valueType
        typeCombo.currentIndex = Math.max(0, typeKeys.indexOf(h.valueType))

        page.frequency = h.frequency
        freqCombo.currentIndex = Math.max(0, freqKeys.indexOf(h.frequency))
        if (h.frequencyN > 0) page.frequencyN = h.frequencyN

        page.detailProfile = h.detailProfile
        profileCombo.currentIndex = Math.max(0, profileKeys.indexOf(h.detailProfile))

        page.timeOfDay = h.timeOfDay
        if (h.kindId >= 0) {
            page.kindId = h.kindId
            page.refreshKind()
        }
        if (h.scaleMax > 0) {
            page.scaleMax = h.scaleMax
            scaleMaxField.text = String(h.scaleMax)
        }
        if (h.unit !== "") unitField.text = h.unit
        if (h.targetValue !== null) targetField.text = String(h.targetValue)
        if (h.dailyTarget !== null) {
            page.goalCounts = true
            dailyTargetField.text = String(h.dailyTarget)
        }
    }

    onAccepted: {
        var target = null
        if (valueType === "numeric" && targetField.text.trim() !== "") {
            var parsed = parseFloat(targetField.text.replace(",", "."))
            if (!isNaN(parsed)) target = parsed
        }

        // A goal only exists if the user asked for one. An unread number
        // sitting in a hidden field must not become a target.
        var daily = null
        if (page.goalCounts && dailyTargetField.text.trim() !== "") {
            var dp = parseFloat(dailyTargetField.text.replace(",", "."))
            if (!isNaN(dp) && dp > 0) daily = dp
        }

        // A reference habit has no unit of its own -- it reads the kind's.
        var unit = valueType === "numeric" ? unitField.text.trim() : ""

        var payload = {
            id: page.habitId,
            name: nameField.text.trim(),
            valueType: valueType,
            unit: unit,
            scaleMax: valueType === "scale" ? scaleMax : null,
            targetValue: target,
            frequency: frequency,
            frequencyN: frequency === "daily" ? null : frequencyN,
            detailProfile: valueType === "structured" ? detailProfile : null,
            kindId: valueType === "reference" ? page.kindId : -1,
            dailyTarget: daily,
            timeOfDay: timeOfDay
        }

        // Duplicating goes through addHabit like any new habit -- which is
        // exactly why the copy starts with no log entries of its own.
        if (editing) Storage.updateHabit(payload)
        else Storage.addHabit(payload)
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
                title: page.editing ? qsTr("Edit habit")
                     : page.duplicating ? qsTr("Duplicate habit")
                     : qsTr("New habit")
                acceptEnabled: page.canAccept
                onCancelled: page.reject()
                onAccepted: page.accept()
            }

            // -- What gets recorded ------------------------------------------

            ComboBox {
                id: typeCombo
                width: parent.width
                label: qsTr("What do you record?")
                currentIndex: 0
                // Log entries keep their own copy of the type, so old entries
                // would survive a change -- but a habit that means one thing
                // in June and another in July is not worth the confusion.
                enabled: !page.editing
                menu: ContextMenu {
                    highlightColor: FiatMosTheme.accent

                    MenuItem {
                        text: qsTr("Check")
                        color: FiatMosTheme.primaryText
                    }
                    MenuItem {
                        text: qsTr("Number")
                        color: FiatMosTheme.primaryText
                    }
                    MenuItem {
                        text: qsTr("Rating")
                        color: FiatMosTheme.primaryText
                    }
                    MenuItem {
                        text: qsTr("Library")
                        color: FiatMosTheme.primaryText
                    }
                    MenuItem {
                        text: qsTr("Session")
                        color: FiatMosTheme.primaryText
                    }
                }
                onCurrentIndexChanged: page.valueType = page.typeKeys[currentIndex]
            }

            // One word in the list, the explanation underneath. The words
            // have to stand next to each other and still be readable.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: {
                    var vt = page.valueType
                    if (vt === "boolean") return qsTr("Done or not done. One tap and today is finished.")
                    if (vt === "numeric") return qsTr("A number with a unit — minutes run, kilos lifted.")
                    if (vt === "scale") return qsTr("A value on a scale you decide — sleep, mood.")
                    if (vt === "reference") return qsTr("Something you work through, piece by piece. Books, repertoire, rolls of film.")
                    return qsTr("A whole session of exercises and sets — gym, rehab, practice.")
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.editing
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("What a habit records is fixed once it has history. Everything else can change.")
            }

            // -- Number ------------------------------------------------------

            TextField {
                id: unitField
                width: parent.width
                visible: page.valueType === "numeric"
                label: qsTr("Unit")
                placeholderText: qsTr("min, kg, pages…")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            TextField {
                id: targetField
                width: parent.width
                visible: page.valueType === "numeric"
                label: qsTr("Long-run target (optional)")
                placeholderText: qsTr("e.g. 30")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.valueType === "numeric"
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Set this and the history view shows how far above or below it you run. It does not affect whether today counts as done — that is the daily goal below.")
            }

            // -- Scale -------------------------------------------------------

            Column {
                width: parent.width
                visible: page.valueType === "scale"
                spacing: Theme.paddingSmall

                TextField {
                    id: scaleMaxField
                    width: parent.width
                    label: qsTr("Highest value")
                    placeholderText: qsTr("3")
                    text: "3"
                    inputMethodHints: Qt.ImhDigitsOnly
                    color: FiatMosTheme.primaryText
                    EnterKey.iconSource: "image://theme/icon-m-enter-close"
                    EnterKey.onClicked: focus = false
                    onTextChanged: {
                        var n = parseInt(text, 10)
                        page.scaleMax = isNaN(n) ? 0 : Math.max(0, Math.min(n, 100))
                    }
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: page.scaleMax >= 1 ? FiatMosTheme.secondaryText : FiatMosTheme.wrong
                    text: {
                        var m = page.scaleMax
                        if (m < 1) return qsTr("The scale needs a highest value of at least 1.")
                        if (m > 12) return qsTr("The scale will run 0 to %1.").arg(m)
                        var steps = []
                        for (var i = 0; i <= m; i++) steps.push(i)
                        return qsTr("The scale will run %1.").arg(steps.join("  "))
                    }
                }
            }

            // -- Library --------------------------------------------------------
            //
            // The habit is tied to one kind, and the kind owns the unit. That
            // is what makes "one habit, one unit" true by construction rather
            // than by discipline. An audiobook is a different kind, and so a
            // different habit -- which is right, because 4200 pages in 830
            // minutes is a sentence nobody should be able to produce.
            //
            // The choice used to be a row of pills, which worked at three
            // kinds and fell apart at twenty. It is a ValueRow into its own
            // page now: one line here, a searchable list behind it.

            Column {
                width: parent.width
                visible: page.valueType === "reference"
                spacing: Theme.paddingSmall

                ValueRow {
                    width: parent.width
                    label: qsTr("Works through")
                    placeholder: qsTr("Choose a kind…")
                    value: page.kindName
                    detail: page.kindUnitText
                    onClicked: page.pickKind()
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    text: page.kindId >= 0
                        ? qsTr("The unit comes with the kind, which is why this habit can never mix pages and minutes. You add the things themselves from Library.")
                        : qsTr("Pick what this habit works through. The unit comes with it.")
                }
            }

            // -- Structured --------------------------------------------------

            Column {
                width: parent.width
                visible: page.valueType === "structured"
                spacing: Theme.paddingSmall

                ComboBox {
                    id: profileCombo
                    width: parent.width
                    label: qsTr("What does each set record?")
                    currentIndex: 0
                    menu: ContextMenu {
                        highlightColor: FiatMosTheme.accent

                        MenuItem {
                            text: qsTr("Reps and weight — strength training")
                            color: FiatMosTheme.primaryText
                        }
                        MenuItem {
                            text: qsTr("Time — practice, planks, stretches")
                            color: FiatMosTheme.primaryText
                        }
                        MenuItem {
                            text: qsTr("Reps only — rehab, bodyweight")
                            color: FiatMosTheme.primaryText
                        }
                        MenuItem {
                            text: qsTr("Just a note — free form")
                            color: FiatMosTheme.primaryText
                        }
                    }
                    onCurrentIndexChanged: page.detailProfile = page.profileKeys[currentIndex]
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    text: qsTr("A session holds several exercises, and each exercise holds one or more sets. Your first session is free form — when you save it you can turn it into a routine, and the next one starts prefilled from the last.")
                }
            }

            // -- Name ------------------------------------------------------------
            //
            // After the description, not before it: by now the page knows
            // enough to propose something.

            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: page.valueType === "reference" && page.kindName !== ""
                    ? qsTr("Work through %1").arg(page.kindName)
                    : qsTr("Name")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // -- Daily goal ---------------------------------------------------
            //
            // Two answers, both visible. Nothing here is expressed by leaving
            // a field empty.

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Daily goal")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: page.sumsValues ? qsTr("Just tick it") : qsTr("Once a day")
                    selected: !page.goalCounts
                    onClicked: page.goalCounts = false
                }
                Pill {
                    text: page.sumsValues ? qsTr("Reach a number") : qsTr("Several times a day")
                    selected: page.goalCounts
                    onClicked: page.goalCounts = true
                }
            }

            TextField {
                id: dailyTargetField
                width: parent.width
                visible: page.goalCounts
                label: {
                    if (!page.sumsValues) return qsTr("Times a day")
                    return page.goalUnit === ""
                        ? qsTr("How much per day")
                        : qsTr("How much per day (%1)").arg(page.goalUnit)
                }
                placeholderText: page.sumsValues ? qsTr("45") : qsTr("3")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // Says the choice back in plain language, with the unit in it.
            // Serif, because it is the one sentence on the page worth reading.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: {
                    if (!page.goalCounts) {
                        return qsTr("One entry and today is done. The list shows it as a dot.")
                    }
                    var n = dailyTargetField.text.trim()
                    if (n === "") n = dailyTargetField.placeholderText
                    if (!page.sumsValues) {
                        return qsTr("%1 entries and today is done. The list shows a ring filling as you go.").arg(n)
                    }
                    if (page.goalUnit === "") {
                        return qsTr("%1 a day. The list shows a ring filling as you go.").arg(n)
                    }
                    return qsTr("%1 %2 a day. The list shows a ring filling as you go.")
                        .arg(n).arg(page.goalUnit)
                }
            }

            // -- Time of day ---------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Time of day")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("Anytime")
                    selected: page.timeOfDay === ""
                    onClicked: page.timeOfDay = ""
                }
                Pill {
                    text: qsTr("Morning")
                    selected: page.timeOfDay === "morning"
                    onClicked: page.timeOfDay = "morning"
                }
                Pill {
                    text: qsTr("Afternoon")
                    selected: page.timeOfDay === "afternoon"
                    onClicked: page.timeOfDay = "afternoon"
                }
                Pill {
                    text: qsTr("Evening")
                    selected: page.timeOfDay === "evening"
                    onClicked: page.timeOfDay = "evening"
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Only used when you turn on grouping in the list. It is where you want to see the habit, not when you happen to log it.")
            }

            // -- Frequency -----------------------------------------------------

            ComboBox {
                id: freqCombo
                width: parent.width
                label: qsTr("How often?")
                currentIndex: 0
                menu: ContextMenu {
                    highlightColor: FiatMosTheme.accent

                    MenuItem {
                        text: qsTr("Every day")
                        color: FiatMosTheme.primaryText
                    }
                    MenuItem {
                        text: qsTr("A number of times per week")
                        color: FiatMosTheme.primaryText
                    }
                    MenuItem {
                        text: qsTr("Every few days")
                        color: FiatMosTheme.primaryText
                    }
                }
                onCurrentIndexChanged: page.frequency = page.freqKeys[currentIndex]
            }

            Column {
                width: parent.width
                visible: page.frequency !== "daily"
                spacing: Theme.paddingSmall

                SectionLabel {
                    x: Theme.horizontalPageMargin
                    text: page.frequency === "weekly_n"
                        ? qsTr("Times per week")
                        : qsTr("Days between")
                }

                Flow {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    spacing: Theme.paddingSmall

                    Repeater {
                        model: page.frequency === "weekly_n" ? [1, 2, 3, 4, 5, 6] : [2, 3, 4, 7, 14, 30]
                        Pill {
                            text: modelData
                            selected: page.frequencyN === Number(modelData)
                            onClicked: page.frequencyN = Number(modelData)
                        }
                    }
                }
            }

            // -- Plain-language summary ----------------------------------------

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: {
                    var vt = page.valueType
                    var f = page.frequency
                    var n = page.frequencyN
                    var sm = page.scaleMax
                    var what = vt === "boolean" ? qsTr("You tick it off each time.")
                             : vt === "numeric" ? qsTr("You enter a number each time.")
                             : vt === "scale" ? qsTr("You pick a value from 0 to %1 each time.").arg(sm)
                             : vt === "reference" ? qsTr("You pick something from your library each time, and optionally how much.")
                             : qsTr("You record a whole session each time.")
                    var when = f === "daily"
                             ? qsTr("It counts as done on any day you finish it.")
                             : f === "weekly_n"
                             ? qsTr("It counts as done in any week you finish it at least %1 times.").arg(n)
                             : qsTr("It counts as done as long as no more than %1 days pass between logs.").arg(n)
                    return what + " " + when
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
