import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// One exercise over its whole life.
//
// It starts with one sentence: where you are now, and how that compares with
// half a year ago (or the first time, while there is no half year yet). Then
// three numbers, a line through the days once there are enough of them to
// make a line, and every day on a row of its own.
//
// The line is drawn through one number per day -- the heaviest weight, the
// reps while there is no weight yet, the minutes, the distance -- from the
// lowest day to the highest, so that change is visible. What it spans is
// written above it, so the size of the change is never left to the eye.
//
// Nothing here is stored. It is all worked out from the sessions each time.

Page {
    id: page

    property int itemId: -1
    property var st: null
    property int gen: 0

    readonly property var it: page.st === null ? null : page.st.item

    function refresh() {
        st = Storage.thingStats(itemId)
        gen++
        lineChart.requestPaint()
    }

    // "today", "yesterday", "20 Aug" -- and the year only when it is not this one.
    function dayLabel(key) {
        if (key === undefined || key === null || key === "") return ""
        if (key === Storage.dayOffsetKey(0)) return qsTr("today")
        if (key === Storage.dayOffsetKey(-1)) return qsTr("yesterday")
        var d = Storage.dateFromDayKey(key.substr(0, 10))
        return Qt.formatDate(d, d.getFullYear() === new Date().getFullYear() ? "d MMM" : "d MMM yyyy")
    }

    function accent(t) {
        return "<font color=\"" + FiatMosTheme.accent + "\">" + t + "</font>"
    }

    function num(v) {
        return String(Math.round(v * 10) / 10)
    }

    // The value of a day, with what it is counted in.
    function said(v) {
        if (page.st === null) return ""
        var m = page.st.measure
        if (m === "time") return qsTr("%1 min").arg(page.num(v))
        if (m === "time_distance") return page.st.unit === "km" ? qsTr("%1 km").arg(page.num(v)) : qsTr("%1 min").arg(page.num(v))
        if (page.st.bodyweight) return qsTr("%1 reps").arg(page.num(v))
        return qsTr("%1 kg").arg(page.num(v))
    }

    // "+5 kg since 20 Aug", "the same as on 20 Aug"
    function since(then, now) {
        var d = Math.round((now.value - then.value) * 10) / 10
        var when = page.dayLabel(then.day)
        if (d === 0) return qsTr("the same as on %1").arg(when)
        var amount = page.said(Math.abs(d))
        return (d > 0 ? qsTr("+%1 since %2") : qsTr("−%1 since %2")).arg(amount).arg(when)
    }

    function headline() {
        var s = page.st
        if (s === null || s.latest === null) return ""
        // The name is the title right above; the sentence starts with the fact.
        var lead
        if (s.bodyweight) {
            lead = qsTr("%1, %2 at most in a day.")
                .arg(page.accent(qsTr("%1 in a set").arg(s.maxSet))).arg(s.maxDayReps)
        } else {
            lead = qsTr("%1 last time.").arg(page.accent(page.said(s.latest.value)))
        }
        if (s.then === null) return lead
        // "Since" compares like with like: for bodyweight it is the most reps
        // in a day, for everything else the line's own value.
        return lead + " " + page.since(s.then, s.latest).charAt(0).toUpperCase() + page.since(s.then, s.latest).substr(1) + "."
    }

    onStatusChanged: {
        if (status === PageStatus.Active) refresh()
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

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            MenuItem {
                text: {
                    var _g = page.gen
                    return page.it !== null && page.it.state === "archived" ? qsTr("Take it up again") : qsTr("Put away")
                }
                color: FiatMosTheme.primaryText
                onClicked: {
                    Storage.setItemState(page.itemId, page.it.state === "archived" ? "active" : "archived")
                    page.refresh()
                }
            }
            MenuItem {
                text: qsTr("Edit")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ThingDialog.qml"), { itemId: page.itemId })
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHead {
                title: {
                    var _g = page.gen
                    return page.it === null ? "" : page.it.title
                }
                subtitle: {
                    var _g = page.gen
                    if (page.it === null) return ""
                    var parts = []
                    if (page.it.kindName !== "") parts.push(page.it.kindName)
                    parts.push(Measures.label(page.st.measure))
                    if (page.it.state === "archived") parts.push(qsTr("put away"))
                    return parts.join(" · ")
                }
            }

            // The one sentence the page is for.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: {
                    var _g = page.gen
                    if (page.st === null) return ""
                    if (page.st.count === 0) return qsTr("Not done yet. Its history starts with the first workout that includes it.")
                    return page.headline()
                }
            }

            // -- Three numbers --------------------------------------------------

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.count > 0
                }

                Repeater {
                    model: {
                        var _g = page.gen
                        var s = page.st
                        if (s === null || s.count === 0) return []
                        var out = [{ n: String(s.count), what: s.count === 1 ? qsTr("day") : qsTr("days"), accent: true }]
                        if (s.bodyweight) {
                            out.push({ n: String(s.maxSet), what: qsTr("most in a set"), accent: false })
                            out.push({ n: String(s.maxDayReps), what: qsTr("most in a day"), accent: false })
                        } else if (s.measure === "weight_reps") {
                            out.push({ n: page.num(s.best.top), what: qsTr("heaviest, kg"), accent: false })
                            out.push({ n: String(s.sets), what: s.sets === 1 ? qsTr("set") : qsTr("sets"), accent: false })
                        } else {
                            out.push({ n: page.num(s.best.value), what: s.unit === "km" ? qsTr("furthest, km") : qsTr("longest, min"), accent: false })
                            var total = 0
                            for (var j = 0; j < s.days.length; j++) total += (s.unit === "km" ? s.days[j].km : s.days[j].minutes)
                            out.push({ n: page.num(total), what: s.unit === "km" ? qsTr("km in all") : qsTr("min in all"), accent: false })
                        }
                        return out
                    }

                    Column {
                        width: parent.width / 3

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

            // -- Over time ------------------------------------------------------
            //
            // From four days on. Before that a line says less than the rows.

            Column {
                id: chartBlock
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.count >= 4
                }

                // What the line spans, said once above it, so the size of
                // the change is never left to the eye.
                Label {
                    anchors.right: parent.right
                    font.pixelSize: Theme.fontSizeTiny
                    color: FiatMosTheme.secondaryText
                    text: {
                        var _g = page.gen
                        if (page.st === null || page.st.days.length === 0) return ""
                        var d = page.st.days, lo = d[0].value, hi = d[0].value
                        for (var i = 1; i < d.length; i++) { if (d[i].value < lo) lo = d[i].value; if (d[i].value > hi) hi = d[i].value }
                        return lo === hi ? qsTr("level at %1").arg(page.said(hi))
                                         : qsTr("from %1 to %2").arg(page.num(lo)).arg(page.said(hi))
                    }
                }

                Canvas {
                    id: lineChart
                    width: parent.width
                    height: Theme.itemSizeExtraLarge
                    renderStrategy: Canvas.Immediate

                    // See ProgressRing: a Canvas loses its texture when the
                    // app goes to the background, so it repaints on return.
                    Connections {
                        target: Qt.application
                        onStateChanged: {
                            if (Qt.application.state === Qt.ApplicationActive) lineChart.requestPaint()
                        }
                    }
                    onVisibleChanged: if (visible) requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        if (page.st === null || page.st.days.length < 2) return
                        var d = page.st.days
                        var lo = d[0].value, hi = d[0].value
                        for (var i = 1; i < d.length; i++) {
                            if (d[i].value < lo) lo = d[i].value
                            if (d[i].value > hi) hi = d[i].value
                        }
                        var pad = Theme.paddingSmall * 1.5
                        // Spaced by date, not by index: three sessions in one
                        // week and then a month's gap should look like that.
                        var t0 = Storage.dateFromDayKey(d[0].day).getTime()
                        var t1 = Storage.dateFromDayKey(d[d.length - 1].day).getTime()
                        var span = Math.max(1, t1 - t0)
                        function px(k) { return pad + (Storage.dateFromDayKey(d[k].day).getTime() - t0) / span * (width - pad * 2) }
                        // No change at all is a level line through the middle.
                        function py(v) { return hi === lo ? height / 2 : height - pad - (v - lo) / (hi - lo) * (height - pad * 2) }

                        ctx.strokeStyle = FiatMosTheme.innerBorder
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(0, height - 0.5)
                        ctx.lineTo(width, height - 0.5)
                        ctx.stroke()

                        ctx.strokeStyle = FiatMosTheme.accent
                        ctx.lineWidth = Math.max(2, Theme.paddingSmall / 3)
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        for (var k = 0; k < d.length; k++) {
                            if (k === 0) ctx.moveTo(px(k), py(d[k].value))
                            else ctx.lineTo(px(k), py(d[k].value))
                        }
                        ctx.stroke()

                        ctx.fillStyle = FiatMosTheme.accent
                        var r = Math.max(2, Theme.paddingSmall / 2)
                        for (var j = 0; j < d.length; j++) {
                            ctx.beginPath()
                            ctx.arc(px(j), py(d[j].value), r, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }

                }

                Item {
                    width: parent.width
                    height: firstDay.height

                    Label {
                        id: firstDay
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatMosTheme.secondaryText
                        text: {
                            var _g = page.gen
                            return page.st === null ? "" : page.dayLabel(page.st.first)
                        }
                    }
                    Label {
                        anchors.right: parent.right
                        font.pixelSize: Theme.fontSizeTiny
                        color: FiatMosTheme.secondaryText
                        text: {
                            var _g = page.gen
                            return page.st === null ? "" : page.dayLabel(page.st.last)
                        }
                    }
                }
            }

            // -- Every day ------------------------------------------------------
            //
            // One row a day, newest first. A long day fades at the edge rather
            // than wrapping into a paragraph; the best one is in the accent.

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.count > 0
                }
                text: qsTr("Every day")
            }

            Repeater {
                model: {
                    var _g = page.gen
                    if (page.st === null) return []
                    return page.st.days.slice().reverse()
                }

                Item {
                    x: Theme.horizontalPageMargin
                    width: content.width - Theme.horizontalPageMargin * 2
                    height: dayName.height + Theme.paddingSmall

                    Label {
                        id: dayName
                        width: Theme.itemSizeExtraLarge
                        text: page.dayLabel(modelData.day)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                    }
                    Label {
                        anchors.left: dayName.right
                        anchors.leftMargin: Theme.paddingMedium
                        anchors.right: parent.right
                        horizontalAlignment: Text.AlignRight
                        truncationMode: TruncationMode.Fade
                        text: modelData.summary === "" ? qsTr("done") : modelData.summary
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: page.st !== null && page.st.best !== null && modelData.day === page.st.best.day
                               ? FiatMosTheme.accent : FiatMosTheme.primaryText
                    }
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
