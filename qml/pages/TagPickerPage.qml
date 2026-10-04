import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Picks one tag to narrow a list by, or none.
//
// Tags are invented as you go, so there is no telling how many there will be.
// A row of words was fine at five and a wall at forty; a page of its own is
// what Silica does with every long choice.

Page {
    id: page

    // The caller connects to this. "" means any tag.
    signal tagPicked(string tag)

    property string current: ""
    property var tags: []

    Component.onCompleted: tags = Storage.allTags()

    function choose(t) {
        page.tagPicked(t)
        pageStack.pop()
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

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.tags.length + 1

        header: PageHead {
            title: qsTr("Tag")
            subtitle: qsTr("narrow the list to one")
        }

        delegate: BackgroundItem {
            id: row
            width: listView.width
            height: Theme.itemSizeSmall
            highlightedColor: FiatMosTheme.highlightWash

            readonly property string tag: index === 0 ? "" : page.tags[index - 1]
            readonly property bool current: row.tag === page.current

            onClicked: page.choose(row.tag)

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2 - Theme.paddingLarge
                truncationMode: TruncationMode.Fade
                text: index === 0 ? qsTr("Any tag") : row.tag
                color: (row.highlighted || row.current) ? FiatMosTheme.accent : FiatMosTheme.primaryText
            }

            // Drawn, not typed. Marks the one already chosen.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                visible: row.current
                width: Theme.paddingSmall
                height: width
                radius: width / 2
                color: FiatMosTheme.accent
            }
        }

        VerticalScrollDecorator { }
    }
}
