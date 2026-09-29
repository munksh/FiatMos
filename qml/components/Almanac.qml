import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The period as small month calendars, one square per day, Monday first.
// A day with something logged is filled, shaded by how much; a day in the
// period with nothing is an empty outline; days outside the period are not
// drawn at all, so a 30-day window shows exactly 30 squares.
//
// Squares that are not drawn are transparent rather than invisible. A Grid
// skips invisible children, and every date after them would slide into the
// wrong weekday.

Item {
    id: root

    property var days: []          // [{ day: "YYYY-MM-DD", value }], oldest first
    property real maxValue: 1
    property int columns: 3

    width: parent ? parent.width : 0
    height: grid.height

    readonly property var months: build(root.days)

    function build(d) {
        if (!d || d.length === 0) return []
        var values = {}
        for (var i = 0; i < d.length; i++) values[d[i].day] = d[i].value
        var first = d[0].day, last = d[d.length - 1].day

        function pad(n) { return (n < 10 ? "0" : "") + n }

        var out = []
        var y = parseInt(first.substr(0, 4), 10), m = parseInt(first.substr(5, 2), 10) - 1
        var ly = parseInt(last.substr(0, 4), 10), lm = parseInt(last.substr(5, 2), 10) - 1
        var firstMonth = true
        while (y < ly || (y === ly && m <= lm)) {
            var inMonth = new Date(y, m + 1, 0).getDate()
            var offset = (new Date(y, m, 1).getDay() + 6) % 7
            var cells = []
            for (var p = 0; p < offset; p++) cells.push({ s: 0, v: 0 })
            for (var day = 1; day <= inMonth; day++) {
                var key = y + "-" + pad(m + 1) + "-" + pad(day)
                if (key < first || key > last) cells.push({ s: 0, v: 0 })
                else if (values[key] === null || values[key] === undefined) cells.push({ s: 1, v: 0 })
                else cells.push({ s: 2, v: values[key] })
            }
            var name = Qt.locale().monthName(m, Locale.ShortFormat)
            out.push({ label: (firstMonth || m === 0) ? name + " " + y : name, cells: cells })
            firstMonth = false
            m++
            if (m > 11) { m = 0; y++ }
        }
        return out
    }

    Grid {
        id: grid
        width: parent.width
        columns: root.columns
        columnSpacing: Theme.paddingMedium
        rowSpacing: Theme.paddingMedium

        Repeater {
            model: root.months

            Column {
                width: (root.width - grid.columnSpacing * (root.columns - 1)) / root.columns
                spacing: Theme.paddingSmall / 2

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: modelData.label
                    font.pixelSize: Theme.fontSizeTiny
                    color: FiatMosTheme.secondaryText
                }

                Grid {
                    id: cellGrid
                    width: parent.width
                    columns: 7
                    spacing: Math.max(1, Math.round(Theme.paddingSmall / 3))

                    Repeater {
                        model: modelData.cells

                        Rectangle {
                            width: (cellGrid.width - cellGrid.spacing * 6) / 7
                            height: width
                            radius: width * 0.2
                            color: modelData.s === 2 ? FiatMosTheme.accent : "transparent"
                            opacity: modelData.s === 2
                                ? Math.max(0.3, Math.min(1, modelData.v / Math.max(0.000001, root.maxValue)))
                                : 1
                            border.width: modelData.s === 1 ? 1 : 0
                            border.color: FiatMosTheme.dotIdle
                        }
                    }
                }
            }
        }
    }
}
