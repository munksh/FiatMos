import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."

// The house version of Silica's ValueButton: a label, the current value, and
// a chevron saying there is a page behind it.
//
// Not Silica's own, for the usual reason -- ValueButton draws its value in
// Theme.highlightColor, which under Fiat colours plus a dark ambience is
// light text on light paper. This one also carries the underline itself, so
// it lines up with the TextFields it sits between.
//
// Use it wherever a choice has more options than a row of pills can hold.
// A pill row is right for four fixed values; it is wrong for a list that
// grows every time the user invents something.

BackgroundItem {
    id: root

    property string label: ""
    property string value: ""
    property string placeholder: qsTr("Choose…")

    // The part of the value that names the unit, drawn in the accent so the
    // eye can separate "book" from "pages" at a glance. Optional.
    property string detail: ""

    readonly property bool empty: value === ""

    width: parent ? parent.width : 0
    height: col.height + Theme.paddingMedium * 2
    highlightedColor: FiatMosTheme.highlightWash

    Column {
        id: col
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin
        width: parent.width - Theme.horizontalPageMargin * 2 - chevron.width - Theme.paddingMedium
        spacing: 2

        Label {
            width: parent.width
            visible: root.label !== ""
            text: root.label
            font.pixelSize: Theme.fontSizeExtraSmall
            color: FiatMosTheme.secondaryText
            truncationMode: TruncationMode.Fade
        }

        Row {
            width: parent.width
            spacing: Theme.paddingSmall

            Label {
                id: valueLabel
                text: root.empty ? root.placeholder : root.value
                font.pixelSize: Theme.fontSizeMedium
                color: root.empty
                    ? FiatMosTheme.dotIdle
                    : (root.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText)
                truncationMode: TruncationMode.Fade
            }

            Label {
                anchors.baseline: valueLabel.baseline
                visible: !root.empty && root.detail !== ""
                text: "· " + root.detail
                font.pixelSize: Theme.fontSizeSmall
                color: FiatMosTheme.accent
                truncationMode: TruncationMode.Fade
            }
        }
    }

    // Drawn, not typed. A theme icon would be the ambience's colour, and a
    // text glyph is a different shape in every font.
    Canvas {
        id: chevron
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        width: Theme.paddingMedium
        height: Theme.paddingLarge
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = FiatMosTheme.dotIdle
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(1, 1)
            ctx.lineTo(width - 1, height / 2)
            ctx.lineTo(1, height - 1)
            ctx.stroke()
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        x: Theme.horizontalPageMargin
        width: parent.width - Theme.horizontalPageMargin * 2
        height: 1
        color: FiatMosTheme.innerBorder
    }
}
