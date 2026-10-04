import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// One item over its whole life: how far in you are, every sitting, and how
// many more it will take at the pace you actually keep.

Page {
    id: page

    property int itemId: -1
    property var st: null
    property int gen: 0
    property int coverRevision: 0
    property string fetchState: ""       // "", "busy", "failed", "none"
    // Fetch cover was pressed before the list of lookup services had been
    // confirmed; when it is, carry on.
    property bool fetchAfterChoice: false

    readonly property var it: page.st === null ? null : page.st.item

    function refresh() {
        st = Storage.itemStats(itemId)
        gen++
        sittingChart.requestPaint()
    }

    function amount(v) {
        var r = Math.round(v * 100) / 100
        var u = page.st === null ? "" : page.st.unit
        return u === "" ? String(r) : r + " " + u
    }

    function dayLabel(key) {
        if (key === undefined || key === null || key === "") return ""
        return Qt.formatDate(Storage.dateFromDayKey(key.substr(0, 10)), Qt.DefaultLocaleShortDate)
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            page.fetchAfterChoice = false
            refresh()
        }
    }

    // Only the services the user has switched on are asked, and the list is
    // shown first if it has never been confirmed.
    function fetchCover() {
        if (!LookupSettings.chosen) {
            page.fetchAfterChoice = true
            pageStack.animatorPush(Qt.resolvedUrl("LookupServicesPage.qml"), { firstTime: true })
            return
        }
        if (LookupSettings.enabledIds().length === 0) {
            page.fetchState = "none"
            return
        }
        page.fetchState = "busy"
        runner.fetchCover(page.it.isbn)
    }

    LookupRunner {
        id: runner
        onCoverDone: {
            page.fetchState = ok ? "" : "failed"
            if (ok) page.coverRevision++
        }
    }

    Connections {
        target: LookupSettings
        onChosenChanged: {
            if (page.fetchAfterChoice && LookupSettings.chosen) {
                page.fetchAfterChoice = false
                page.fetchCover()
            }
        }
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

        PullDownMenu {
            highlightColor: FiatMosTheme.accent

            MenuItem {
                text: qsTr("Fetch cover")
                color: FiatMosTheme.primaryText
                visible: {
                    var _g = page.gen
                    var _r = page.coverRevision
                    return page.it !== null && page.it.isbn !== "" && !cover.hasPicture
                }
                onClicked: page.fetchCover()
            }
            MenuItem {
                text: qsTr("Edit")
                color: FiatMosTheme.primaryText
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("AddBookPage.qml"), { itemId: page.itemId })
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
                    var state = page.it.state === "completed" ? qsTr("finished")
                              : page.it.state === "archived" ? qsTr("put away")
                              : qsTr("on the go")
                    return page.it.creator === "" ? state : page.it.creator + " · " + state
                }
            }

            // -- Cover and progress -------------------------------------------

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge * 1.5

                BookCover {
                    id: cover
                    width: Theme.itemSizeExtraLarge * 1.1
                    height: width * 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    visible: {
                        var _g = page.gen
                        return page.it !== null && (page.it.isbn !== "" || page.st.fraction === null)
                    }
                    isbn: {
                        var _g = page.gen
                        return page.it === null ? "" : page.it.isbn
                    }
                    title: {
                        var _g = page.gen
                        return page.it === null ? "" : page.it.title
                    }
                    creator: {
                        var _g = page.gen
                        return page.it === null ? "" : page.it.creator
                    }
                    revision: page.coverRevision
                }

                Item {
                    width: Theme.itemSizeExtraLarge * 1.5
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    visible: {
                        var _g = page.gen
                        return page.st !== null && page.st.fraction !== null
                    }

                    ProgressRing {
                        anchors.fill: parent
                        lineWidth: width * 0.08
                        value: {
                            var _g = page.gen
                            return page.st === null || page.st.fraction === null ? 0 : page.st.fraction
                        }
                    }

                    Column {
                        anchors.centerIn: parent

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                var _g = page.gen
                                if (page.st === null || page.st.fraction === null) return ""
                                return Math.round(page.st.fraction * 100) + "%"
                            }
                            font.pixelSize: Theme.fontSizeExtraLarge
                            font.family: FiatMosTheme.serif
                            color: FiatMosTheme.primaryText
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                var _g = page.gen
                                if (page.st === null || page.it === null) return ""
                                return qsTr("%1 of %2").arg(Math.round(page.st.total * 100) / 100).arg(page.it.extent)
                            }
                            font.pixelSize: Theme.fontSizeTiny
                            color: FiatMosTheme.secondaryText
                        }
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeExtraSmall
                color: (page.fetchState === "failed" || page.fetchState === "none") ? FiatMosTheme.wrong : FiatMosTheme.secondaryText
                visible: text !== ""
                text: {
                    var _g = page.gen
                    if (page.fetchState === "busy") return qsTr("Fetching the cover…")
                    if (page.fetchState === "failed")
                        return qsTr("No cover found for this ISBN, or the phone is offline.") + (runner.askedText === "" ? "" : " " + runner.askedText)
                    if (page.fetchState === "none")
                        return qsTr("All lookup services are switched off. Switch one on under About, or in the Shelf menu.")
                    if (page.st !== null && page.st.fraction === null)
                        return qsTr("Add its length with Edit to see how far in you are.")
                    return ""
                }
            }

            // -- Four numbers -------------------------------------------------

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2

                Repeater {
                    model: {
                        var _g = page.gen
                        if (page.st === null) return []
                        return [
                            { n: String(page.st.total), what: page.st.unit === "" ? qsTr("logged") : page.st.unit, accent: true },
                            { n: String(page.st.days), what: page.st.days === 1 ? qsTr("sitting") : qsTr("sittings"), accent: false },
                            { n: page.st.median === null ? "–" : String(page.st.median), what: qsTr("median"), accent: false },
                            { n: String(page.st.best), what: qsTr("best"), accent: false }
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

            // -- Each sitting ---------------------------------------------------
            //
            // One bar per day it was logged, oldest on the left, with the
            // median drawn across as a broken line: the evening you actually
            // have, against the evenings you had.

            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: sittingBlock.visible
                text: qsTr("Each sitting")
            }

            Column {
                id: sittingBlock
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: {
                    var _g = page.gen
                    return page.st !== null && page.st.sittings.length > 0
                }

                Canvas {
                    id: sittingChart
                    width: parent.width
                    height: Theme.itemSizeExtraLarge
                    renderStrategy: Canvas.Immediate

                    Connections {
                        target: Qt.application
                        onStateChanged: {
                            if (Qt.application.state === Qt.ApplicationActive) sittingChart.requestPaint()
                        }
                    }
                    onVisibleChanged: if (visible) requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        if (page.st === null) return
                        var s = page.st.sittings
                        if (s.length === 0) return
                        var maxV = Math.max(1, page.st.best)

                        ctx.strokeStyle = FiatMosTheme.innerBorder
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(0, height - 0.5)
                        ctx.lineTo(width, height - 0.5)
                        ctx.stroke()

                        var bw = width / s.length
                        var gap = bw > 4 ? Math.max(1, bw * 0.2) : 0
                        ctx.fillStyle = FiatMosTheme.accent
                        for (var i = 0; i < s.length; i++) {
                            var h = Math.max(2, (s[i].value / maxV) * height)
                            ctx.fillRect(i * bw, height - h, Math.max(1, bw - gap), h)
                        }

                        // Drawn as dashes by hand: Canvas here has no setLineDash.
                        if (page.st.median !== null) {
                            var y = Math.round(height - (page.st.median / maxV) * height) + 0.5
                            var dash = Theme.paddingSmall
                            ctx.strokeStyle = FiatMosTheme.primaryText
                            ctx.beginPath()
                            for (var x = 0; x < width; x += dash * 2) {
                                ctx.moveTo(x, y)
                                ctx.lineTo(Math.min(width, x + dash), y)
                            }
                            ctx.stroke()
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: firstSitting.height

                    Label {
                        id: firstSitting
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

            // -- The pace -------------------------------------------------------

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                visible: text !== ""
                text: {
                    var _g = page.gen
                    if (page.st === null || page.it === null) return ""
                    if (page.it.state === "completed" && page.it.finishedAt)
                        return qsTr("Finished %1, after %2.").arg(page.dayLabel(page.it.finishedAt))
                            .arg(page.st.days === 1 ? qsTr("1 sitting") : qsTr("%1 sittings").arg(page.st.days))
                    if (page.st.estimate === null) return ""
                    return qsTr("%1 left. At your median of %2, that is about %3 more.")
                        .arg(page.amount(page.st.left))
                        .arg(page.amount(page.st.median))
                        .arg(page.st.estimate === 1 ? qsTr("1 sitting") : qsTr("%1 sittings").arg(page.st.estimate))
                }
            }

            // -- Details ----------------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Details")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                lineHeight: 1.3
                text: {
                    var _g = page.gen
                    if (page.st === null || page.it === null) return ""
                    var lines = []
                    if (page.st.first !== "") lines.push(qsTr("First logged %1").arg(page.dayLabel(page.st.first)))
                    lines.push(qsTr("Kind: %1").arg(page.it.kindName === "" ? qsTr("none") : Storage.kindLabel({ name: page.it.kindName, unit: page.it.unit })))
                    if (page.st.tags.length > 0) lines.push(qsTr("Tags: %1").arg(page.st.tags.join(", ")))
                    if (page.it.isbn !== "") lines.push(qsTr("ISBN %1").arg(page.it.isbn))
                    if (page.it.private) lines.push(qsTr("Private"))
                    return lines.join("\n")
                }
            }
        }

        VerticalScrollDecorator { }
    }
}
