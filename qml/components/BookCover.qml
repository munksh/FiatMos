import QtQuick 2.0
import Sailfish.Silica 1.0
import se.munkstolen.fiatmos 1.0
import ".."

// A book's cover: the picture if there is one on the phone, otherwise a plain
// cloth block with the title on it. Never fetches anything by itself -- a
// cover only arrives when a page asks CoverStore for it.

Item {
    id: root

    property string isbn: ""
    property string title: ""
    property string creator: ""
    // Bump after a fetch so the file is looked for again.
    property int revision: 0

    readonly property string picture: {
        var _r = root.revision
        return root.isbn === "" ? "" : store.path(root.isbn)
    }
    readonly property bool hasPicture: root.picture !== ""

    CoverStore { id: store }

    Rectangle {
        anchors.fill: parent
        visible: !root.hasPicture
        radius: Math.max(2, width * 0.04)
        color: FiatMosTheme.clothFor(root.title)

        Column {
            anchors.fill: parent
            anchors.margins: Math.max(3, parent.width * 0.08)
            spacing: Math.max(1, parent.width * 0.03)

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                text: root.title
                color: FiatMosTheme.clothText
                font.family: FiatMosTheme.serif
                font.pixelSize: Math.max(8, root.width * 0.14)
            }

            Label {
                width: parent.width
                truncationMode: TruncationMode.Fade
                visible: root.creator !== "" && root.width > Theme.itemSizeSmall
                text: root.creator
                color: FiatMosTheme.clothText
                opacity: 0.8
                font.pixelSize: Math.max(7, root.width * 0.09)
            }
        }
    }

    Image {
        anchors.fill: parent
        visible: root.hasPicture
        source: root.picture
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: root.width * 2
    }
}
