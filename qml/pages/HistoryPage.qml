import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

Page {
    id: page

    property int habitId: -1
    property var habit: null
    property int lookback: 30

    // NOT `data`. `data` is Item's default property -- the list every child
    // object gets appended to. Declaring a property with that name silently
    // steals the page's own children, so the background and the flickable
    // were being assigned into a JavaScript array instead of the scene. The
    // page rendered nothing at all and QML said not one word about it.
    property var days: []
    property int gen: 0

    // Which of the three numbers is on show. A pill each, one figure -- the
    // sentence that said all three at once was more text than fact.
    property string stat: "sum"

    // The top of both the grid's shading and the chart's Y axis. Computed once
    // here rather than inside a delegate, where it was an O(n) loop per cell.
    property real chartMax: 1

    // "2026-08-18" is what the database stores and what it should keep
    // storing. What the screen shows is a different question, and it belongs
    // to whoever is reading it.
    function dayLabel(iso) {
        if (iso === undefined || iso === null || iso === "") return ""
        var d = new Date(iso.substr(0, 4), parseInt(iso.substr(5, 2), 10) - 1, iso.substr(8, 2))
        return Qt.formatDate(d, Qt.DefaultLocaleShortDate)
    }

    function refresh() {
        habit = Storage.getHabit(habitId)
        if (habit === null) return
        days = Storage.series(habit, lookback)

        var m = habit.valueType === "scale" ? Math.max(1, habit.scaleMax) : 1
        for (var i = 0; i < days.length; i++) {
            if (days[i].value !== null && days[i].value > m) m = days[i].value
        }
        if (habit.targetValue !== null && habit.targetValue > m) m = habit.targetValue
        chartMax = m
        if (habit.valueType === "structured") Storage.loadSessionHistory(sessionModel, habitId, 20)
        gen++
        chart.requestPaint()
    }

    ListModel { id: sessionModel }

    onLookbackChanged: refresh()
    Component.onCompleted: refresh()

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

            PageHead {
                title: {
                    var _g = page.gen
                    return page.habit === null ? "" : page.habit.name
                }
                subtitle: qsTr("History")
            }

            // -- Range ------------------------------------------------------

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Repeater {
                    model: [30, 90, 365]
                    Pill {
                        // Number(), because a Repeater over a JS array hands
                        // the delegate an untyped value. The comparison works
                        // either way; the static analyser only stops calling
                        // it constant once the type is spelled out.
                        text: qsTr("%1 d").arg(modelData)
                        selected: page.lookback === Number(modelData)
                        onClicked: page.lookback = Number(modelData)
                    }
                }
            }

            // -- The card ---------------------------------------------------
            //
            // Dense readouts sit on a solid card so they stay legible over an
            // arbitrary wallpaper. The list rows elsewhere do not need one --
            // Silica already handles a plain list over an ambience.

            Rectangle {
                x: Theme.horizontalPageMargin
                width: content.width - Theme.horizontalPageMargin * 2
                height: cardColumn.height + Theme.paddingLarge * 2
                radius: FiatMosTheme.cardRadius
                color: FiatMosTheme.card
                border.color: FiatMosTheme.cardBorder
                border.width: FiatMosTheme.cardBorderWidth

                Column {
                    id: cardColumn
                    anchors.centerIn: parent
                    width: parent.width - Theme.paddingLarge * 2
                    spacing: Theme.paddingMedium

                    // -- Key numbers ----------------------------------------

                    Row {
                        width: parent.width
                        spacing: Theme.paddingLarge

                        Column {
                            width: (parent.width - Theme.paddingLarge * 2) / 3
                            Label {
                                text: {
                                    var _g = page.gen
                                    return page.habit === null ? "–" : Storage.streak(page.habit)
                                }
                                font.pixelSize: Theme.fontSizeExtraLarge
                                font.family: FiatMosTheme.serif
                                color: FiatMosTheme.accent
                            }
                            SectionLabel { text: qsTr("streak") }
                        }

                        Column {
                            width: (parent.width - Theme.paddingLarge * 2) / 3
                            Label {
                                text: {
                                    var _g = page.gen
                                    var _l = page.lookback
                                    if (page.habit === null) return "–"
                                    return Math.round(Storage.completionRate(page.habit, _l) * 100) + "%"
                                }
                                font.pixelSize: Theme.fontSizeExtraLarge
                                font.family: FiatMosTheme.serif
                                color: FiatMosTheme.primaryText
                            }
                            SectionLabel { text: qsTr("done") }
                        }

                        Column {
                            width: (parent.width - Theme.paddingLarge * 2) / 3
                            visible: {
                                var _g = page.gen
                                return page.habit !== null && page.habit.valueType === "numeric" && page.habit.targetValue !== null
                            }
                            Label {
                                text: {
                                    var _g = page.gen
                                    var _l = page.lookback
                                    if (page.habit === null) return "–"
                                    var d = Storage.deviationFromTarget(page.habit, _l)
                                    if (d === null) return "–"
                                    var r = Math.round(d * 10) / 10
                                    return (r > 0 ? "+" : "") + r
                                }
                                font.pixelSize: Theme.fontSizeExtraLarge
                                font.family: FiatMosTheme.serif
                                // The one place this app passes a verdict.
                                color: {
                                    var _g = page.gen
                                    var _l = page.lookback
                                    if (page.habit === null) return FiatMosTheme.primaryText
                                    var d = Storage.deviationFromTarget(page.habit, _l)
                                    if (d === null) return FiatMosTheme.primaryText
                                    return Math.abs(d) > (page.habit.targetValue * 0.25)
                                        ? FiatMosTheme.wrong
                                        : FiatMosTheme.primaryText
                                }
                            }
                            SectionLabel { text: qsTr("vs target") }
                        }
                    }

                    // -- Sum / Avg / Med --------------------------------------
                    //
                    // All three are per LOGGED day. A mean that divides by 90
                    // when you logged on nine of them is a fact about the
                    // window, not about the habit -- and the grid below
                    // already says how often you turned up.

                    Item {
                        width: parent.width
                        height: statBlock.visible ? statBlock.height : 0
                        visible: statBlock.visible

                        Column {
                            id: statBlock
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: {
                                var _g = page.gen
                                if (page.habit === null) return false
                                return page.habit.valueType === "numeric" || page.habit.valueType === "reference"
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.paddingSmall

                                Pill {
                                    text: qsTr("Sum")
                                    selected: page.stat === "sum"
                                    onClicked: page.stat = "sum"
                                }
                                Pill {
                                    text: qsTr("Avg")
                                    selected: page.stat === "mean"
                                    onClicked: page.stat = "mean"
                                }
                                Pill {
                                    text: qsTr("Med")
                                    selected: page.stat === "median"
                                    onClicked: page.stat = "median"
                                }
                            }

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                font.pixelSize: Theme.fontSizeExtraLarge
                                font.family: FiatMosTheme.serif
                                color: FiatMosTheme.primaryText
                                text: {
                                    var _g = page.gen
                                    var _l = page.lookback
                                    var _s = page.stat
                                    if (page.habit === null) return "–"
                                    var t = Storage.habitTotal(page.habit, _l)
                                    if (t.days === 0) return "–"
                                    var v = _s === "sum" ? t.total : (_s === "mean" ? t.mean : t.median)
                                    return t.unit === "" ? String(v) : v + " " + t.unit
                                }
                            }

                            SectionLabel {
                                width: parent.width
                                text: {
                                    var _g = page.gen
                                    var _l = page.lookback
                                    var _s = page.stat
                                    if (page.habit === null) return ""
                                    var t = Storage.habitTotal(page.habit, _l)
                                    if (t.days === 0) return qsTr("nothing logged in this period")
                                    var days = t.days === 1
                                        ? qsTr("over 1 logged day")
                                        : qsTr("over %1 logged days").arg(t.days)
                                    if (_s === "sum") return qsTr("in total, %1").arg(days)
                                    if (_s === "mean") return qsTr("on average, %1").arg(days)
                                    return qsTr("median, %1").arg(days)
                                }
                            }
                        }
                    }

                    // -- Day grid -------------------------------------------
                    //
                    // One square per day, oldest top-left, today last. Same
                    // direction as the chart's axis below -- the two must never
                    // disagree about which way time runs, and left-to-right is
                    // what a time axis means. The empty squares at the start
                    // are the days you did not log, not a rendering fault.

                    SectionLabel { text: qsTr("Days") }

                    Grid {
                        width: parent.width
                        columns: 14
                        spacing: Theme.paddingSmall

                        Repeater {
                            model: page.days.length

                            Rectangle {
                                property var point: page.days[index]

                                width: (parent.width - parent.spacing * (parent.columns - 1)) / parent.columns
                                height: width
                                radius: width * 0.25
                                color: point.value === null ? "transparent" : FiatMosTheme.accent
                                opacity: point.value === null
                                    ? 1.0
                                    : Math.max(0.35, Math.min(1.0, point.value / Math.max(1, page.chartMax)))
                                border.width: point.value === null ? 1 : 0
                                border.color: FiatMosTheme.dotIdle
                            }
                        }
                    }

                    // -- Chart ----------------------------------------------
                    //
                    // Bars, and time runs LEFT TO RIGHT: oldest at the left,
                    // today at the right. That is what a time axis means
                    // everywhere else, and the empty stretch on the left is
                    // not a fault -- it is the part of the window you did not
                    // log, drawn honestly.
                    //
                    // The Y numbers sit on the left, under the unit label, so
                    // the scale and its name are the same column.

                    SectionLabel {
                        visible: chartBlock.visible
                        text: {
                            var _g = page.gen
                            if (page.habit === null) return ""
                            if (page.habit.valueType === "scale") return qsTr("Rating")
                            var u = Storage.unitForHabit(page.habit)
                            return u === "" ? qsTr("Value") : qsTr("Value (%1)").arg(u)
                        }
                    }

                    Column {
                        id: chartBlock
                        width: parent.width
                        spacing: Theme.paddingSmall
                        visible: {
                            var _g = page.gen
                            return page.habit !== null && (page.habit.valueType === "numeric" || page.habit.valueType === "scale" || page.habit.valueType === "reference")
                        }

                        Item {
                            width: parent.width
                            height: Theme.itemSizeExtraLarge * 1.4

                            Label {
                                id: maxLabel
                                anchors.left: parent.left
                                anchors.top: parent.top
                                font.pixelSize: Theme.fontSizeTiny
                                color: FiatMosTheme.secondaryText
                                text: {
                                    var _g = page.gen
                                    return String(Math.round(page.chartMax * 100) / 100)
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

                                // One bar per day. A gap is simply no bar --
                                // nothing is drawn across a day that did not
                                // happen, which is the whole reason a bar chart
                                // is honest here and a line needed rules.
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.clearRect(0, 0, width, height)

                                    var d = page.days
                                    if (!d || d.length === 0 || page.habit === null) return

                                    var maxV = Math.max(1, page.chartMax)
                                    var target = page.habit.targetValue

                                    function py(v) { return height - (v / maxV) * height }

                                    // The baseline, so the 0 on the left has
                                    // something to name. No ceiling line: the
                                    // tallest bar already draws the top.
                                    ctx.strokeStyle = FiatMosTheme.innerBorder
                                    ctx.lineWidth = 1
                                    ctx.beginPath()
                                    ctx.moveTo(0, height - 0.5)
                                    ctx.lineTo(width, height - 0.5)
                                    ctx.stroke()

                                    // Target line before the bars, so the bars
                                    // sit on top of it.
                                    if (target !== null && page.habit.valueType === "numeric") {
                                        ctx.strokeStyle = FiatMosTheme.cardBorder
                                        ctx.lineWidth = 1
                                        ctx.beginPath()
                                        ctx.moveTo(0, py(target))
                                        ctx.lineTo(width, py(target))
                                        ctx.stroke()
                                    }

                                    // Index 0 is the oldest day and goes on the
                                    // left; the last index is today, on the right.
                                    var bw = width / d.length
                                    var gap = bw > 4 ? 1 : 0

                                    ctx.fillStyle = FiatMosTheme.accent
                                    for (var j = 0; j < d.length; j++) {
                                        if (d[j].value === null) continue
                                        var h = Math.max(1, (d[j].value / maxV) * height)
                                        ctx.fillRect(j * bw, height - h, Math.max(1, bw - gap), h)
                                    }
                                }
                            }
                        }

                        // -- X axis ------------------------------------------
                        //
                        // Named, and with both ends dated, because an
                        // unlabelled axis is decoration. Dates through Qt's
                        // locale formatter rather than the stored ISO string --
                        // the database keeps ISO, the screen shows your format.
                        Item {
                            width: parent.width
                            height: oldestLabel.height

                            Label {
                                id: oldestLabel
                                anchors.left: parent.left
                                font.pixelSize: Theme.fontSizeTiny
                                color: FiatMosTheme.secondaryText
                                text: {
                                    var _g = page.gen
                                    if (page.days.length === 0) return ""
                                    return page.dayLabel(page.days[0].day)
                                }
                            }

                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.pixelSize: Theme.fontSizeTiny
                                color: FiatMosTheme.secondaryText
                                text: qsTr("Time")
                            }

                            Label {
                                anchors.right: parent.right
                                font.pixelSize: Theme.fontSizeTiny
                                color: FiatMosTheme.secondaryText
                                text: {
                                    var _g = page.gen
                                    if (page.days.length === 0) return ""
                                    return page.dayLabel(page.days[page.days.length - 1].day)
                                }
                            }
                        }
                    }
                }
            }

            // -- Sessions ---------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: sessionModel.count > 0
                text: qsTr("Sessions")
            }

            Repeater {
                model: sessionModel

                Row {
                    x: Theme.horizontalPageMargin
                    width: content.width - Theme.horizontalPageMargin * 2
                    height: Theme.itemSizeExtraSmall
                    spacing: Theme.paddingMedium

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.dayLabel
                        color: FiatMosTheme.secondaryText
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.routineName === "" ? qsTr("Free session") : model.routineName
                        color: FiatMosTheme.primaryText
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.componentCount === 1
                            ? qsTr("1 exercise")
                            : qsTr("%1 exercises").arg(model.componentCount)
                        color: FiatMosTheme.secondaryText
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: {
                    var _g = page.gen
                    var _l = page.lookback
                    if (page.habit === null) return ""
                    var logged = 0
                    for (var i = 0; i < page.days.length; i++) if (page.days[i].value !== null) logged++
                    return qsTr("%1 logged days out of %2. Everything here is recalculated from the raw entries each time — no totals are stored.").arg(logged).arg(_l)
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
