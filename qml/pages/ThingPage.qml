import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// One thing you practise, over its whole life: every day it was done, what
// you did, and how that compares with half a year ago.
//
// The line is drawn through one number per day -- the heaviest weight, or
// the reps while there is no weight yet, the minutes, the distance -- because
// one number is what the eye can follow across months. The days themselves,
// set by set, are listed underneath.
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

    function dayLabel(key) {
        if (key === undefined || key === null || key === "") return ""
        if (key === Storage.dayOffsetKey(0)) return qsTr("today")
        if (key === Storage.dayOffsetKey(-1)) return qsTr("yesterday")
        return Qt.formatDate(Storage.dateFromDayKey(key.substr(0, 10)), "ddd d MMM yyyy")
    }

    function amount(v) {
        var r = Math.round(v * 10) / 10
        var u = page.st === null ? "" : page.st.unit
        return u === "" ? String(r) : r + " " + u
    }

    // "+20 kg", "−3 min", "the same"
    function change(from, to) {
        var d = Math.round((to - from) * 10) / 10
        if (d === 0) return qsTr("the same")
        var u = page.st === null ? "" : page.st.unit
        return (d > 0 ? "+" : "−") + Math.abs(d) + (u === "" ? "" : " " + u)
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

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.count === 0
                }
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.secondaryText
                text: qsTr("Not done yet. Its history starts with the first session that includes it.")
            }

            // -- Last time, and then ---------------------------------------------

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.latest !== null
                }

                SectionLabel {
                    text: {
                        var _g = page.gen
                        return page.st === null || page.st.latest === null ? "" : qsTr("Last time · %1").arg(page.dayLabel(page.st.latest.day))
                    }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeLarge
                    font.family: FiatMosTheme.serif
                    color: FiatMosTheme.primaryText
                    text: {
                        var _g = page.gen
                        if (page.st === null || page.st.latest === null) return ""
                        return page.st.latest.summary === "" ? qsTr("done") : page.st.latest.summary
                    }
                }
                // The comparison the page is for. Half a year back when there
                // is that much history; the first time when there is not.
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: FiatMosTheme.secondaryText
                    text: {
                        var _g = page.gen
                        if (page.st === null || page.st.then === null || page.st.latest === null) return ""
                        var t = page.st.then
                        var lead = page.st.halfYear ? qsTr("Half a year ago, %1").arg(page.dayLabel(t.day))
                                                    : qsTr("The first time, %1").arg(page.dayLabel(t.day))
                        var what = t.summary === "" ? "" : ": " + t.summary
                        return lead + what + ". " + qsTr("Since then: %1.").arg(page.change(t.value, page.st.latest.value))
                    }
                }
            }

            // -- Four numbers -------------------------------------------------

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
                        if (page.st === null || page.st.count === 0) return []
                        var m = page.st.measure
                        var out = [
                            { n: String(page.st.count), what: page.st.count === 1 ? qsTr("day") : qsTr("days"), accent: true },
                            { n: page.st.best === null ? "–" : String(page.st.best.value), what: qsTr("best, %1").arg(page.st.unit), accent: false }
                        ]
                        var maxEst = 0, sets = 0
                        for (var i = 0; i < page.st.days.length; i++) {
                            if (page.st.days[i].best > maxEst) maxEst = page.st.days[i].best
                            sets += page.st.days[i].sets
                        }
                        out.push({ n: String(sets), what: sets === 1 ? qsTr("set") : qsTr("sets"), accent: false })
                        if (m === "weight_reps" && maxEst > 0) out.push({ n: String(maxEst), what: qsTr("est. max, kg"), accent: false })
                        else if (m !== "weight_reps") {
                            var total = 0
                            for (var j = 0; j < page.st.days.length; j++) total += (m === "time" ? page.st.days[j].minutes : page.st.days[j].km)
                            out.push({ n: String(Math.round(total * 10) / 10), what: m === "time" ? qsTr("min in all") : qsTr("km in all"), accent: false })
                        }
                        return out
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

            // -- Over time ------------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: chartBlock.visible
                text: {
                    var _g = page.gen
                    return page.st === null ? "" : qsTr("Over time, %1").arg(page.st.unit)
                }
            }

            Column {
                id: chartBlock
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.count > 1
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
                        // A flat history still gets a visible line, in the middle.
                        if (hi === lo) { hi = hi + 1; lo = Math.max(0, lo - 1) }
                        var pad = Theme.paddingSmall * 1.5
                        // Spaced by date, not by index: three sessions in one
                        // week and then a month's gap should look like that.
                        var t0 = Storage.dateFromDayKey(d[0].day).getTime()
                        var t1 = Storage.dateFromDayKey(d[d.length - 1].day).getTime()
                        var span = Math.max(1, t1 - t0)
                        function px(k) { return pad + (Storage.dateFromDayKey(d[k].day).getTime() - t0) / span * (width - pad * 2) }
                        function py(v) { return height - pad - (v - lo) / (hi - lo) * (height - pad * 2) }

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
                    height: Math.max(dayName.height, daySummary.height) + Theme.paddingSmall

                    Label {
                        id: dayName
                        width: parent.width * 0.4
                        truncationMode: TruncationMode.Fade
                        text: page.dayLabel(modelData.day)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                    }
                    Label {
                        id: daySummary
                        anchors.right: parent.right
                        width: parent.width * 0.6
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        text: modelData.summary === "" ? qsTr("done") : modelData.summary
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: page.st !== null && page.st.best !== null && modelData.day === page.st.best.day
                               ? FiatMosTheme.accent : FiatMosTheme.primaryText
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.measure === "weight_reps" && page.st.count > 0
                }
                font.pixelSize: Theme.fontSizeTiny
                color: FiatMosTheme.secondaryText
                text: qsTr("The best day is in the accent. The estimated max is worked out from the strongest set (weight × (1 + reps / 30)), to compare 5 × 100 with 8 × 90 — not a claim about what you could lift.")
            }
        }

        VerticalScrollDecorator { }
    }
}
