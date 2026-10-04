import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// One kind over a month, a quarter or a year: the shelf, the numbers, when,
// on which weekdays, the calendar, and every item, each opening its own page.
// The same shape as the rolls page in Fiat Lux.

Page {
    id: page

    property int kindId: -1
    property int lookback: 365
    property bool includePrivate: false

    property var st: null
    property var bars: []           // [{ start, value }]
    property var weekdays: []       // Monday first
    property var facts: null
    property real busiest: 1
    property real dayMax: 1
    property real itemMost: 1
    property int gen: 0

    readonly property bool weekly: page.lookback > 90
    readonly property string unit: page.st === null || page.st.kind === null ? "" : page.st.kind.unit

    function refresh() {
        st = Storage.kindStats(kindId, lookback, includePrivate)
        bars = weekly
            ? Storage.weeklyBuckets(st.series)
            : st.series.map(function(d) { return { start: d.day, value: d.value === null ? 0 : d.value } })
        weekdays = Storage.weekdayTotals(st.series)
        facts = Storage.calendarFacts(st.series, false)
        var b = 0
        for (var i = 0; i < bars.length; i++) if (bars[i].value > b) b = bars[i].value
        // The calendar is shaded against the ninth-busiest day in ten rather
        // than the single busiest: one four-hour Sunday would otherwise turn
        // every ordinary evening the same pale green.
        var logged = []
        for (var j = 0; j < st.series.length; j++) if (st.series[j].value !== null) logged.push(st.series[j].value)
        logged.sort(function(x, y) { return x - y })
        var m = logged.length === 0 ? 1 : logged[Math.min(logged.length - 1, Math.floor(logged.length * 0.9))]
        var im = 0
        for (var k = 0; k < st.items.length; k++) if (st.items[k].total > im) im = st.items[k].total
        busiest = Math.max(1, b)
        dayMax = Math.max(1, m)
        itemMost = Math.max(1, im)
        gen++
        chart.requestPaint()
    }

    function amount(v) {
        var r = Math.round(v * 100) / 100
        return page.unit === "" ? String(r) : r + " " + page.unit
    }

    function periodName() {
        if (lookback === 30) return qsTr("the last 30 days")
        if (lookback === 90) return qsTr("the last 90 days")
        return qsTr("the last year")
    }

    function dayLabel(key) {
        if (key === undefined || key === null || key === "") return ""
        return Qt.formatDate(Storage.dateFromDayKey(key), "d MMM")
    }

    function monthName(key) {
        if (key === undefined || key === null || key === "") return ""
        return Qt.locale().monthName(parseInt(key.substr(5, 2), 10) - 1, Locale.LongFormat)
    }

    // In the order they were begun, so the shelf reads left to right like
    // the period itself.
    function shelfOrder() {
        if (page.st === null) return []
        var list = page.st.items.slice()
        list.sort(function(a, b) { return a.first < b.first ? -1 : (a.first > b.first ? 1 : 0) })
        return list
    }

    // Most recent first, the way the Fiat Lux rolls list reads.
    function listOrder() {
        if (page.st === null) return []
        var list = page.st.items.slice()
        list.sort(function(a, b) { return a.last > b.last ? -1 : (a.last < b.last ? 1 : 0) })
        return list
    }

    onLookbackChanged: refresh()
    onIncludePrivateChanged: refresh()
    onStatusChanged: {
        if (status === PageStatus.Active) refresh()
    }

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

            PageHead {
                title: {
                    var _g = page.gen
                    return page.st === null || page.st.kind === null ? "" : page.st.kind.name
                }
                subtitle: page.periodName()
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Repeater {
                    model: [ { label: qsTr("30 days"), value: 30 },
                             { label: qsTr("90 days"), value: 90 },
                             { label: qsTr("a year"), value: 365 } ]
                    Pill {
                        text: modelData.label
                        selected: page.lookback === Number(modelData.value)
                        onClicked: page.lookback = Number(modelData.value)
                    }
                }
            }

            SwitchRow {
                visible: {
                    var _g = page.gen
                    return page.includePrivate || (page.st !== null && page.st.hiddenPrivate > 0)
                }
                text: qsTr("Include private")
                checked: page.includePrivate
                onClicked: page.includePrivate = !page.includePrivate
            }

            // -- The shelf ------------------------------------------------------

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                visible: text !== ""
                text: {
                    var _g = page.gen
                    if (page.st === null || page.st.itemCount === 0) return ""
                    var open = 0
                    for (var i = 0; i < page.st.items.length; i++) {
                        if (Storage.isActiveState(page.st.items[i].state)) open++
                    }
                    var learned = page.st.kind !== null && page.st.kind.doneWord === "learned"
                    var first = learned ? qsTr("%1 learned, %2 on the go.").arg(page.st.finished).arg(open)
                                        : qsTr("%1 finished, %2 on the go.").arg(page.st.finished).arg(open)
                    var second = page.st.days === 1
                        ? qsTr("%1 on one day.").arg(page.amount(page.st.total))
                        : qsTr("%1 on %2 days.").arg(page.amount(page.st.total)).arg(page.st.days)
                    return first + "\n" + second
                }
            }

            Shelf {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                items: {
                    var _g = page.gen
                    return page.shelfOrder()
                }
                onPicked: pageStack.animatorPush(Qt.resolvedUrl("ItemPage.qml"), { itemId: itemId })
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.itemCount > 0
                }
                text: qsTr("Thickness is the length, green is how far in you are. Tap a spine.")
            }

            // -- Four numbers -------------------------------------------------

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

                Repeater {
                    model: {
                        var _g = page.gen
                        if (page.st === null) return []
                        var perDay = page.st.days === 0 ? "–" : String(Math.round(page.st.total / page.st.days * 10) / 10)
                        return [
                            { n: String(page.st.itemCount), what: page.st.itemCount === 1 ? qsTr("item") : qsTr("items"), accent: true },
                            { n: String(page.st.total), what: page.unit === "" ? qsTr("logged") : page.unit, accent: false },
                            { n: String(page.st.days), what: page.st.days === 1 ? qsTr("day") : qsTr("days"), accent: false },
                            { n: perDay, what: qsTr("per day"), accent: false }
                        ]
                    }

                    Column {
                        width: parent.width / 4
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.n
                            font.pixelSize: Theme.fontSizeExtraLarge
                            font.family: FiatMosTheme.serif
                            color: modelData.accent ? FiatMosTheme.accent : FiatMosTheme.primaryText
                        }
                        SectionLabel {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.what
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
                text: qsTr("Days are the days anything was logged, and per day is the total on those days.")
            }

            // -- When ------------------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: {
                    var u = page.unit === "" ? qsTr("logged") : page.unit
                    return page.weekly ? qsTr("%1 per week").arg(u) : qsTr("%1 per day").arg(u)
                }
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Theme.itemSizeExtraLarge * 1.2

                    Label {
                        id: maxLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatMosTheme.secondaryText
                        text: {
                            var _g = page.gen
                            return String(Math.round(page.busiest * 100) / 100)
                        }
                    }
                    Label {
                        id: zeroLabel
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatMosTheme.secondaryText
                        text: "0"
                    }

                    Canvas {
                        id: chart
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width - Math.max(maxLabel.width, zeroLabel.width) - Theme.paddingMedium
                        renderStrategy: Canvas.Immediate

                        Connections {
                            target: Qt.application
                            onStateChanged: {
                                if (Qt.application.state === Qt.ApplicationActive) chart.requestPaint()
                            }
                        }
                        onVisibleChanged: if (visible) requestPaint()
                        onWidthChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.clearRect(0, 0, width, height)
                            var d = page.bars
                            if (!d || d.length === 0) return

                            ctx.strokeStyle = FiatMosTheme.innerBorder
                            ctx.lineWidth = 1
                            ctx.beginPath()
                            ctx.moveTo(0, height - 0.5)
                            ctx.lineTo(width, height - 0.5)
                            ctx.stroke()

                            var bw = width / d.length
                            var gap = bw > 4 ? Math.max(1, bw * 0.15) : 0
                            ctx.fillStyle = FiatMosTheme.accent
                            for (var j = 0; j < d.length; j++) {
                                if (d[j].value <= 0) continue
                                var h = Math.max(2, (d[j].value / page.busiest) * height)
                                ctx.fillRect(j * bw, height - h, Math.max(1, bw - gap), h)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: firstBar.height

                    Label {
                        id: firstBar
                        x: parent.width - chart.width
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatMosTheme.secondaryText
                        text: {
                            var _g = page.gen
                            return page.bars.length > 0 ? page.dayLabel(page.bars[0].start) : ""
                        }
                    }
                    Label {
                        anchors.right: parent.right
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatMosTheme.secondaryText
                        text: qsTr("today")
                    }
                }
            }

            // -- Which weekdays -----------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Which days")
            }

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall / 2

                Repeater {
                    model: 7

                    Item {
                        width: parent.width
                        height: dayName.height

                        readonly property real value: {
                            var _g = page.gen
                            return page.weekdays.length === 7 ? page.weekdays[index] : 0
                        }
                        readonly property real most: {
                            var _g = page.gen
                            var m = 0
                            for (var i = 0; i < page.weekdays.length; i++) if (page.weekdays[i] > m) m = page.weekdays[i]
                            return Math.max(1, m)
                        }

                        Label {
                            id: dayName
                            width: Theme.itemSizeSmall
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                            // Qt counts Sunday as 0; this list starts on Monday.
                            text: Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
                        }

                        Rectangle {
                            anchors.left: dayName.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: (parent.width - dayName.width - dayValue.width - Theme.paddingMedium) * parent.value / parent.most
                            height: Math.max(3, Theme.paddingSmall * 0.7)
                            radius: height / 2
                            color: FiatMosTheme.accent
                            visible: parent.value > 0
                        }

                        Label {
                            id: dayValue
                            anchors.right: parent.right
                            width: Theme.itemSizeSmall
                            horizontalAlignment: Text.AlignRight
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                            text: String(Math.round(parent.value * 100) / 100)
                        }
                    }
                }
            }

            // -- The calendar -------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Calendar")
            }

            Almanac {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                days: {
                    var _g = page.gen
                    return page.st === null ? [] : page.st.series
                }
                maxValue: page.dayMax
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                visible: text !== ""
                text: {
                    var _g = page.gen
                    if (page.facts === null || page.facts.longestRun === 0) return ""
                    var run = page.facts.longestRun === 1
                        ? qsTr("Longest run: 1 day")
                        : qsTr("Longest run: %1 days in a row").arg(page.facts.longestRun)
                    if (page.lookback <= 30) return run + "."
                    return qsTr("%1. Best month: %2, with %3.").arg(run)
                        .arg(page.monthName(page.facts.bestMonth))
                        .arg(page.amount(page.facts.bestMonthValue))
                }
            }

            // -- Every item -------------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: itemRepeater.count > 0
                text: qsTr("Items")
            }

            Repeater {
                id: itemRepeater
                model: {
                    var _g = page.gen
                    return page.listOrder()
                }

                BackgroundItem {
                    width: content.width
                    height: itemColumn.height + Theme.paddingMedium * 2
                    highlightedColor: FiatMosTheme.highlightWash
                    onClicked: pageStack.animatorPush(Qt.resolvedUrl("ItemPage.qml"), { itemId: modelData.id })

                    Column {
                        id: itemColumn
                        x: Theme.horizontalPageMargin
                        width: parent.width - Theme.horizontalPageMargin * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingSmall / 2

                        Item {
                            width: parent.width
                            height: itemTitle.height

                            Label {
                                id: itemTitle
                                anchors.left: parent.left
                                anchors.right: itemAmount.left
                                anchors.rightMargin: Theme.paddingMedium
                                truncationMode: TruncationMode.Fade
                                text: modelData.title
                                font.family: FiatMosTheme.serif
                                font.italic: true
                                color: FiatMosTheme.primaryText
                            }
                            Label {
                                id: itemAmount
                                anchors.right: parent.right
                                anchors.baseline: itemTitle.baseline
                                text: String(modelData.total)
                                font.pixelSize: Theme.fontSizeSmall
                                color: FiatMosTheme.secondaryText
                            }
                        }

                        Rectangle {
                            width: Math.max(2, parent.width * modelData.total / page.itemMost)
                            height: Math.max(2, Theme.paddingSmall / 2)
                            radius: height / 2
                            color: FiatMosTheme.accent
                            opacity: 0.75
                        }

                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: FiatMosTheme.secondaryText
                            text: {
                                var parts = []
                                if (modelData.creator !== "") parts.push(modelData.creator)
                                parts.push(modelData.days === 1 ? qsTr("1 day") : qsTr("%1 days").arg(modelData.days))
                                var a = page.dayLabel(modelData.first), b = page.dayLabel(modelData.last)
                                parts.push(a === b ? a : a + " – " + b)
                                if (Storage.isActiveState(modelData.state)) parts.push(qsTr("on the go"))
                                else if (modelData.finishedHere)
                                    parts.push(page.st.kind !== null && page.st.kind.doneWord === "learned" ? qsTr("learned") : qsTr("finished"))
                                return parts.join("  ·  ")
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
                visible: text !== ""
                text: {
                    var _g = page.gen
                    if (page.st === null) return ""
                    if (page.st.itemCount === 0)
                        return qsTr("Nothing of this kind was logged in %1.").arg(page.periodName())
                    if (!page.includePrivate && page.st.hiddenPrivate > 0)
                        return page.st.hiddenPrivate === 1
                            ? qsTr("1 private item is not shown.")
                            : qsTr("%1 private items are not shown.").arg(page.st.hiddenPrivate)
                    return ""
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
