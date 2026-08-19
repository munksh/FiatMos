import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import se.munkstolen.fiatmos 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Moving your history to another phone.
//
// One JSON file, written where you can find it and read back from wherever
// you put it. Nothing is uploaded, there is no account, and the file is yours
// the moment it is written -- which is the only backup model that survives
// the app being abandoned.
//
// Import REPLACES. There is no merge, and pretending otherwise would be worse
// than not offering it: log entries have no natural key, so "the same entry"
// is a guess, and a guess that quietly drops a day of your life is not a
// feature. Replace is a sentence you can finish out loud.

Page {
    id: page

    property string lastExport: ""
    property string message: ""
    property string messageFrom: ""     // "export" or "import"
    property bool failed: false

    FileIO { id: fileIO }

    // Every outcome goes through here, and every outcome names WHICH half of
    // the page it came from. The first version had one message label at the
    // bottom of a page taller than the screen: press Export at the top, and
    // the answer appeared somewhere you were not looking. Silence and success
    // looked identical, which is the worst thing a confirmation can do.
    function report(from, bad, text) {
        page.messageFrom = from
        page.failed = bad
        page.message = text
    }

    function stamp() {
        var d = new Date()
        function two(n) { return n < 10 ? "0" + n : String(n) }
        return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate())
    }

    function doExport() {
        var dir = fileIO.documentsPath()
        if (dir === "") {
            page.report("export", true, qsTr("Cannot reach the Documents folder."))
            return
        }
        var path = dir + "/fiat-mos-" + stamp() + ".json"
        var text = JSON.stringify(Storage.exportAll(), null, 1)
        if (!fileIO.write(path, text)) {
            page.report("export", true, qsTr("Could not write it: %1").arg(fileIO.lastError()))
            return
        }
        page.lastExport = path
        page.report("export", false,
                    qsTr("Saved as fiat-mos-%1.json in Documents.").arg(stamp()))
    }

    function pickFile() {
        // The picker reports back from INSIDE the component, where `page` is
        // already in scope. The first version wired the signal up from out
        // here through pageCompleted, which is two indirections that both
        // have to fire in the right order -- and when they did not, nothing
        // happened and nothing said so.
        pageStack.animatorPush(filePickerComponent)
    }

    // Read and DESCRIBE, without touching the database. The user sees what
    // the file claims to hold before anything of theirs is at risk.
    function offerImport(path) {
        var text = fileIO.read(path)
        if (text === "") {
            page.report("import", true, qsTr("Could not read that file: %1").arg(fileIO.lastError()))
            return
        }

        var data = null
        try {
            data = JSON.parse(text)
        } catch (e) {
            page.report("import", true, qsTr("That file is not readable as a Fiat Mos export."))
            return
        }

        var info = Storage.describeImport(data)
        if (!info.ok) {
            page.report("import", true, info.reason === "too-new"
                ? qsTr("That file was written by a newer version of Fiat Mos.")
                : qsTr("That file is not a Fiat Mos export."))
            return
        }

        pending = data
        pendingInfo = info
        page.report("import", false, "")
    }

    property var pending: null
    property var pendingInfo: null

    function commitImport() {
        var res = Storage.importAll(page.pending)
        page.pending = null
        page.pendingInfo = null
        if (!res.ok) {
            page.report("import", true, qsTr("The import was refused."))
            return
        }
        page.report("import", false,
                    qsTr("Replaced with %1 habits and %2 entries.").arg(res.habits).arg(res.entries))
        app.touchData()
    }

    // RemorsePopup, not RemorseItem. RemorseItem covers a single list row and
    // its execute() takes that row as its first argument; this is a page-level
    // action with no row to cover, and the popup is what Silica uses for those.
    RemorsePopup {
        id: importRemorse
    }

    Component {
        id: filePickerComponent
        FilePickerPage {
            nameFilters: ["*.json"]
            title: qsTr("Pick an export file")
            onSelectedContentPropertiesChanged: {
                if (selectedContentProperties.filePath !== undefined) {
                    page.offerImport(selectedContentProperties.filePath)
                }
            }
        }
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

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("Backup")
                subtitle: qsTr("move your history")
            }

            // -- Export ---------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Export")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Writes everything — habits, entries, library, sessions — to one file in your Documents folder. Nothing leaves the phone unless you send it yourself.")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("Export now")
                    selected: true
                    onClicked: page.doExport()
                }
            }

            // Directly under the button that caused it. Not at the bottom of
            // the page, where the answer to "did that work" is a scroll away.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.message !== "" && page.messageFrom === "export"
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: page.failed ? FiatMosTheme.wrong : FiatMosTheme.accent
                text: page.message
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.lastExport !== ""
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeTiny
                color: FiatMosTheme.secondaryText
                text: page.lastExport
            }

            // -- Import ---------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Import")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Import replaces everything on this phone with the contents of the file. It does not merge. Export first if there is anything here worth keeping — that export is the only undo there is.")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.pending === null

                Pill {
                    text: qsTr("Choose a file…")
                    onClicked: page.pickFile()
                }
            }

            // What the file says it holds. Shown before anything is touched,
            // so the confirmation is about a real thing and not a shrug.
            Rectangle {
                x: Theme.horizontalPageMargin
                width: content.width - Theme.horizontalPageMargin * 2
                height: pendingColumn.height + Theme.paddingLarge * 2
                radius: FiatMosTheme.cardRadius
                color: FiatMosTheme.card
                border.color: FiatMosTheme.cardBorder
                border.width: FiatMosTheme.cardBorderWidth
                visible: page.pending !== null

                Column {
                    id: pendingColumn
                    anchors.centerIn: parent
                    width: parent.width - Theme.paddingLarge * 2
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatMosTheme.serif
                        color: FiatMosTheme.primaryText
                        text: page.pendingInfo === null ? "" :
                            qsTr("%1 habits, %2 entries, %3 library items.")
                                .arg(page.pendingInfo.habits)
                                .arg(page.pendingInfo.entries)
                                .arg(page.pendingInfo.items)
                    }

                    Label {
                        width: parent.width
                        visible: page.pendingInfo !== null && page.pendingInfo.exportedAt !== ""
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                        text: page.pendingInfo === null ? "" :
                            qsTr("Exported %1").arg(page.pendingInfo.exportedAt)
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.wrong
                        text: qsTr("Everything currently on this phone will be removed.")
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Pill {
                            text: qsTr("Cancel")
                            onClicked: { page.pending = null; page.pendingInfo = null }
                        }
                        Pill {
                            text: qsTr("Replace everything")
                            selected: true
                            onClicked: importRemorse.execute(
                                qsTr("Replacing everything"),
                                function() { page.commitImport() })

                        }
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                visible: page.message !== "" && page.messageFrom === "import"
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: page.failed ? FiatMosTheme.wrong : FiatMosTheme.accent
                text: page.message
            }

            Item { width: 1; height: Theme.paddingLarge }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeTiny
                color: FiatMosTheme.secondaryText
                text: qsTr("The file is plain text. You can open it, read it, and keep a copy anywhere you like — it does not need Fiat Mos to stay readable.")
            }
        }

        VerticalScrollDecorator { }
    }
}