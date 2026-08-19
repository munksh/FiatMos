import QtQuick 2.0
import Sailfish.Silica 1.0
import "."
import "pages"
import "cover"
import "Storage.js" as Storage

ApplicationWindow {
    id: app

    // Bumped by any page that changes the database, so other pages can
    // re-read. QML bindings only track properties they read directly, so a
    // page that wants to refresh must read app.dataGen in the binding body.
    property int dataGen: 0

    function touchData() {
        dataGen++
    }

    Component.onCompleted: {
        var v = Storage.init()
        console.log("FiatMos: schema at version " + v)
        // Once, here: palette is inherited, so every Silica control in every
        // page below picks it up.
        FiatMosTheme.applyPalette(app)
    }

    // Re-applied rather than reverted -- under an ambience the function feeds
    // Silica back its own Theme.* values, so the round trip is clean.
    Connections {
        target: FiatMosTheme
        onAmbientChanged: FiatMosTheme.applyPalette(app)
    }

    initialPage: Component { HabitListPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
}
