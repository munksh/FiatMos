import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// One ring, used at every size: the big one on the habit list header, the
// small one on a counted row, and — when the cover and the dashboard arrive —
// on those too. Nothing here knows about habits, so it can be reused without
// dragging the list's logic along.
//
// Usage:
//     ProgressRing { width: 200; height: 200; value: 0.7 }
//
// The fill animates from empty on first show. Set `animated: false` for rows
// where a dozen rings sweeping at once would be noise rather than delight.

Item {
    id: root

    property real value: 0                                   // 0..1, clamped
    property real lineWidth: Math.max(2, Math.min(width, height) * 0.09)
    property color fillColor: FiatMosTheme.accent
    property color trackColor: FiatMosTheme.dotIdle
    property bool animated: true
    property int duration: 800

    // What is actually drawn. Separate from `value` so the Behavior has
    // something to interpolate.
    property real shown: 0

    function clamped(v) {
        return Math.max(0, Math.min(1, v))
    }

    Behavior on shown {
        enabled: root.animated
        NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic }
    }

    onValueChanged: shown = clamped(value)
    Component.onCompleted: shown = clamped(value)


    // A Canvas keeps its pixels in a texture, and the scene graph is free to
    // drop that texture while the application is not showing. Nothing repaints
    // it on the way back, so the ring simply is not there any more -- which is
    // exactly what it looks like: an empty row where a ring used to be.
    //
    // Repaint when the application becomes active again, and whenever the item
    // becomes visible. Cheap, and the alternative is a drawing that silently
    // disappears once a day.
    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive) canvas.requestPaint()
        }
    }

    onVisibleChanged: {
        if (visible) canvas.requestPaint()
    }

    onShownChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Immediate
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            var r = Math.min(width, height) / 2 - root.lineWidth / 2
            if (r <= 0) return
            var cx = width / 2
            var cy = height / 2

            ctx.lineWidth = root.lineWidth
            ctx.lineCap = "round"

            // The track, always a full circle, so an empty ring still reads
            // as a ring rather than as nothing.
            ctx.strokeStyle = root.trackColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()

            if (root.shown <= 0) return

            // The fill, clockwise from twelve o'clock.
            ctx.strokeStyle = root.fillColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.shown)
            ctx.stroke()
        }
    }
}
