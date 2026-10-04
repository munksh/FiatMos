import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// A small line through a few values, for a row in a list. It shows which way
// things are going, not how much: the line spans from the lowest value to the
// highest, so a few kilos are visible. A run with no change at all is a level
// line through the middle. The last point is marked; that is today's.
//
// Every sparkline in a list has the same width, so the lines line up.

Canvas {
    id: root

    property var values: []

    width: Theme.itemSizeExtraLarge
    height: Theme.itemSizeExtraSmall * 0.6
    renderStrategy: Canvas.Immediate

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    // A Canvas loses its texture when the app goes to the background.
    Connections {
        target: Qt.application
        onStateChanged: if (Qt.application.state === Qt.ApplicationActive) root.requestPaint()
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        var v = root.values
        if (v === undefined || v === null || v.length === 0) return
        var r = Math.max(2, Theme.paddingSmall / 2)
        var lo = v[0], hi = v[0]
        for (var i = 1; i < v.length; i++) { if (v[i] < lo) lo = v[i]; if (v[i] > hi) hi = v[i] }
        function px(k) { return v.length === 1 ? width - r : r + k / (v.length - 1) * (width - r * 2) }
        function py(x) { return hi === lo ? height / 2 : height - r - (x - lo) / (hi - lo) * (height - r * 2) }

        ctx.strokeStyle = FiatMosTheme.accent
        ctx.globalAlpha = 0.8
        ctx.lineWidth = Math.max(1.5, Theme.paddingSmall / 4)
        ctx.lineJoin = "round"
        ctx.beginPath()
        for (var k = 0; k < v.length; k++) {
            if (k === 0) ctx.moveTo(px(k), py(v[k]))
            else ctx.lineTo(px(k), py(v[k]))
        }
        ctx.stroke()

        ctx.globalAlpha = 1
        ctx.fillStyle = FiatMosTheme.accent
        ctx.beginPath()
        ctx.arc(px(v.length - 1), py(v[v.length - 1]), r, 0, Math.PI * 2)
        ctx.fill()
    }
}
