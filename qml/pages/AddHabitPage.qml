import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../HabitTypes.js" as HabitTypes

// Creates a habit, and edits one. Pass habitId to edit; leave it at -1 to
// create. One page, and as little of it showing as the choice above needs.
//
// The page asks in the order people think: WHAT kind of habit, then what
// follows from that (a unit, a scale, a kind of thing), then the name, how
// often, and how much makes a day. Everything with a sensible default sits
// folded away under More.
//
// The five kinds of habit are rows, not a menu. A menu hides four of the five
// answers until you open it, and the examples under each row are what tell a
// newcomer which is theirs: nobody arrives wanting "a rating", they arrive
// wanting to sleep better. The chosen row opens to say what it brings with it
// -- so that a reader finds out about ISBN lookups and covers on the day they
// make a reading habit, not months later.
//
// The five live in HabitTypes.js, shared with the empty habit list.

Dialog {
    id: page

    property int habitId: -1
    // Set this instead of habitId to start from an existing habit's setup
    // without inheriting its history. The new habit is genuinely new -- same
    // shape, empty past.
    property int duplicateOfId: -1
    // Set by the empty habit list, whose rows are the same five as here: the
    // page opens with that one chosen.
    property string startType: ""

    readonly property bool editing: habitId >= 0
    readonly property bool duplicating: !editing && duplicateOfId >= 0
    readonly property int sourceId: editing ? habitId : duplicateOfId

    property string valueType: "boolean"
    property string frequency: "daily"
    // Kept only so that editing an old habit writes back what it had. New
    // habits have no profile: a practised thing is measured per thing now.
    property var detailProfile: null
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

    // Whether the habit is counted or checked. Two visible answers, not a
    // field left empty.
    property bool goalCounts: false

    // The folded part of the page.
    property bool more: false

    readonly property var freqKeys: ["daily", "weekly_n", "custom_interval"]

    // The five, in the order they are shown. Shared with the empty habit list.
    readonly property var types: HabitTypes.list()

    // Counted habits sum their entries against the goal; the rest just count
    // how many times you logged.
    readonly property bool sumsValues: valueType === "numeric" || valueType === "reference"
    readonly property bool usesKind: valueType === "reference" || valueType === "structured"
    readonly property string kindNature: valueType === "structured" ? "practise" : "finish"

    // What the goal is measured in. A numeric habit carries its own unit; a
    // shelf habit reads its kind's; everything else counts bare entries.
    readonly property string goalUnit: valueType === "numeric"
        ? unitField.text.trim()
        : (valueType === "reference" ? page.kindUnitText : "")

    canAccept: nameField.text.trim().length > 0
               && (valueType !== "scale" || scaleMax >= 1)
               && (!usesKind || page.kindId >= 0)

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

    // Choosing a type. A kind belongs to one nature, so switching between
    // Finish it and Practise it lets go of a kind that no longer fits -- and
    // when there is exactly one kind that does, it is chosen for you.
    function chooseType(key) {
        if (page.editing) return
        page.valueType = key
        if (!page.usesKind) return
        var k = page.kindId >= 0 ? Storage.kindById(page.kindId) : null
        if (k !== null && k.nature === page.kindNature) return
        page.kindId = -1
        page.refreshKind()
        var list = Storage.kinds({ nature: page.kindNature })
        if (list.length === 1) page.applyKind(list[0].id)
    }

    // animatorPush hands back an operation, not the page, so the signal has to
    // be wired up once the page exists. The fallback covers the case where the
    // operation already IS the page.
    function pickKind() {
        var op = pageStack.animatorPush(Qt.resolvedUrl("KindPage.qml"),
                                        { currentKindId: page.kindId, nature: page.kindNature })
        if (op === null || op === undefined) return
        if (op.pageCompleted !== undefined) {
            op.pageCompleted.connect(function(p) { p.kindPicked.connect(page.applyKind) })
        } else if (op.kindPicked !== undefined) {
            op.kindPicked.connect(page.applyKind)
        }
    }

    Component.onCompleted: {
        if (sourceId < 0) {
            if (page.startType !== "") page.chooseType(page.startType)
            return
        }
        var h = Storage.getHabit(sourceId)
        if (h === null) return

        // A copy needs a name of its own. Prefilled rather than blank.
        nameField.text = duplicating ? qsTr("%1 (copy)").arg(h.name) : h.name
        page.valueType = h.valueType

        page.frequency = h.frequency
        freqCombo.currentIndex = Math.max(0, freqKeys.indexOf(h.frequency))
        if (h.frequencyN > 0) page.frequencyN = h.frequencyN

        page.detailProfile = h.detailProfile
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
        // Open what is already set, so it is not hidden from the person
        // who set it.
        if (h.timeOfDay !== "" || h.targetValue !== null) page.more = true
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

        // A shelf habit has no unit of its own -- it reads the kind's.
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
            detailProfile: valueType === "structured" ? page.detailProfile : null,
            kindId: page.usesKind ? page.kindId : -1,
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

            // -- What kind of habit -------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: page.editing ? qsTr("What it records") : qsTr("What do you want to keep?")
            }

            Column {
                width: parent.width

                Repeater {
                    model: page.types

                    Column {
                        width: parent.width
                        // Once a habit exists, what it records is fixed; only
                        // its own row is shown, and it cannot be changed.
                        visible: !page.editing || modelData.key === page.valueType

                        // The breath between the simple three and the rich
                        // two. Space, not a word.
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                            visible: index === 3 && !page.editing
                        }

                        BackgroundItem {
                            id: typeRow
                            readonly property bool chosen: page.valueType === modelData.key
                            width: parent.width
                            height: typeCol.height + Theme.paddingMedium * 2
                            enabled: !page.editing
                            highlightedColor: FiatMosTheme.highlightWash
                            onClicked: page.chooseType(modelData.key)

                            Column {
                                id: typeCol
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.horizontalPageMargin
                                width: parent.width - Theme.horizontalPageMargin * 2
                                spacing: Theme.paddingSmall / 2

                                Label {
                                    width: parent.width
                                    text: modelData.title
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.bold: typeRow.chosen
                                    color: typeRow.chosen ? FiatMosTheme.accent
                                         : (typeRow.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText)
                                }

                                Label {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: modelData.examples
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: FiatMosTheme.secondaryText
                                }

                                // What the chosen one brings with it. A hairline
                                // in the accent on the left, the lines beside it.
                                Item {
                                    width: parent.width
                                    height: getsCol.height + Theme.paddingSmall
                                    visible: typeRow.chosen

                                    Rectangle {
                                        y: Theme.paddingSmall
                                        width: 2
                                        height: getsCol.height
                                        color: Theme.rgba(FiatMosTheme.accent, 0.45)
                                    }

                                    Column {
                                        id: getsCol
                                        y: Theme.paddingSmall
                                        x: Theme.paddingMedium
                                        width: parent.width - x
                                        spacing: Theme.paddingSmall / 2

                                        Repeater {
                                            model: modelData.gets
                                            Label {
                                                width: getsCol.width
                                                wrapMode: Text.WordWrap
                                                text: modelData
                                                font.pixelSize: Theme.fontSizeExtraSmall
                                                color: FiatMosTheme.primaryText
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
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

            // -- What follows from it -------------------------------------------

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

            // The kind of thing. For Finish it the unit comes with it, which is
            // what makes "one habit, one unit" true by construction: an
            // audiobook is a different kind, so a different habit, and "4200
            // pages in 830 minutes" is a sentence nobody can produce. For
            // Practise it the kind is where the habit's things live.
            ValueRow {
                width: parent.width
                visible: page.usesKind
                label: page.valueType === "structured" ? qsTr("Kind of exercise") : qsTr("Works through")
                placeholder: qsTr("Choose a kind…")
                // A practising habit's things belong to its kind, and their
                // history with them. Moving the habit to another kind would
                // leave every exercise behind, so once made it stays.
                enabled: !(page.editing && page.valueType === "structured")
                opacity: enabled ? 1.0 : 0.6
                value: page.kindName
                detail: page.valueType === "reference" ? page.kindUnitText : ""
                onClicked: page.pickKind()
            }

            // -- Name --------------------------------------------------------------

            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: {
                    if (page.valueType === "reference" && page.kindName !== "")
                        return qsTr("Work through %1").arg(page.kindName)
                    if (page.valueType === "structured") return qsTr("Gym, rehab, stretching…")
                    return qsTr("Name")
                }
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // -- How often -----------------------------------------------------

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

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.frequency !== "daily"

                Label {
                    height: Theme.itemSizeExtraSmall
                    verticalAlignment: Text.AlignVCenter
                    text: page.frequency === "weekly_n" ? qsTr("times a week") : qsTr("days between")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                }

                Repeater {
                    model: page.frequency === "weekly_n" ? [1, 2, 3, 4, 5, 6] : [2, 3, 4, 7, 14, 30]
                    Pill {
                        text: modelData
                        selected: page.frequencyN === Number(modelData)
                        onClicked: page.frequencyN = Number(modelData)
                    }
                }
            }

            // -- A day's worth ---------------------------------------------------
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

            // Says the whole choice back in plain language, with the unit in
            // it. Serif, because it is the one sentence on the page worth
            // reading.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: {
                    var day
                    if (!page.goalCounts) {
                        day = qsTr("One entry and the day is done.")
                    } else {
                        var n = dailyTargetField.text.trim()
                        if (n === "") n = dailyTargetField.placeholderText
                        if (!page.sumsValues) day = qsTr("%1 entries and the day is done.").arg(n)
                        else if (page.goalUnit === "") day = qsTr("%1 a day.").arg(n)
                        else day = qsTr("%1 %2 a day.").arg(n).arg(page.goalUnit)
                    }
                    var f = page.frequency
                    var n2 = page.frequencyN
                    var when = f === "daily"
                             ? qsTr("It counts on any day you do it.")
                             : f === "weekly_n"
                             ? qsTr("It counts in any week you do it at least %1 times.").arg(n2)
                             : qsTr("It counts as long as no more than %1 days pass between logs.").arg(n2)
                    return day + " " + when
                }
            }

            // -- More: everything with a sensible default ------------------------

            BackgroundItem {
                id: moreHead
                width: parent.width
                height: Theme.itemSizeMedium
                highlightedColor: FiatMosTheme.highlightWash
                onClicked: page.more = !page.more

                Rectangle {
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2
                    height: 1
                    color: FiatMosTheme.innerBorder
                }
                Label {
                    id: moreLabel
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("More")
                    color: FiatMosTheme.primaryText
                    font.pixelSize: Theme.fontSizeMedium
                }
                Label {
                    anchors.left: moreLabel.right
                    anchors.leftMargin: Theme.paddingLarge
                    anchors.right: caret.left
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    truncationMode: TruncationMode.Fade
                    text: {
                        if (page.more) return ""
                        var parts = []
                        parts.push(page.timeOfDay === "" ? qsTr("anytime") : page.timeOfDayName(page.timeOfDay))
                        if (page.valueType === "numeric" && targetField.text.trim() !== "")
                            parts.push(qsTr("target %1").arg(targetField.text.trim()))
                        return parts.join(" · ")
                    }
                    color: FiatMosTheme.secondaryText
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    id: caret
                    anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                    text: "›"
                    color: FiatMosTheme.secondaryText
                    font.pixelSize: Theme.fontSizeLarge
                    rotation: page.more ? 270 : 90
                    Behavior on rotation { NumberAnimation { duration: 160 } }
                }
            }

            Item {
                id: morePanel
                width: parent.width
                height: page.more ? moreColumn.height + Theme.paddingLarge : 0
                visible: height > 0.5
                clip: true
                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                Column {
                    id: moreColumn
                    width: parent.width
                    spacing: Theme.paddingSmall

                    SectionLabel {
                        x: Theme.horizontalPageMargin
                        text: qsTr("Time of day")
                    }

                    Flow {
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2
                        spacing: Theme.paddingSmall

                        Repeater {
                            model: ["", "morning", "afternoon", "evening"]
                            Pill {
                                text: modelData === "" ? qsTr("Anytime") : page.timeOfDayName(modelData)
                                selected: page.timeOfDay === modelData
                                onClicked: page.timeOfDay = modelData
                            }
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
                        text: qsTr("Set this and the history view shows how far above or below it you run. It does not affect whether a day counts as done — that is the daily goal.")
                    }
                }
            }
        }

        VerticalScrollDecorator { }
    }

    function timeOfDayName(t) {
        if (t === "morning") return qsTr("Morning")
        if (t === "afternoon") return qsTr("Afternoon")
        if (t === "evening") return qsTr("Evening")
        return qsTr("Anytime")
    }
}
