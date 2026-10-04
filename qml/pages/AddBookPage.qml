import QtQuick 2.0
import Sailfish.Silica 1.0
import se.munkstolen.fiatmos 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Lookup.js" as Lookup

// Adds and edits a library item. The file is still called AddBookPage so the
// .pro does not churn; nothing in it says "book" any more.
//
// The kind is chosen on its own page, the same one the habit editor uses. It
// is never a fixed list -- a new kind of thing must never need a schema
// migration -- but it is not a wall of pills either.
//
// A book can be looked up by its ISBN. That is the only thing in the app that
// goes online, it only happens when Look up is pressed, only the ISBN is sent,
// and only to the services the user has switched on (LookupServicesPage,
// Lookup.js). The first time, that list is shown before anything is sent. What
// comes back fills the fields and nothing more; nothing is saved until the
// dialog is accepted.

Dialog {
    id: page

    property int itemId: -1
    readonly property bool editing: itemId >= 0

    property bool isPrivate: false
    property var knownTags: []

    // Cached, because Storage calls are not bindable.
    property int kindId: -1
    property string kindName: ""
    property string kindUnitText: ""

    // "" | "busy" | "found" | "notfound" | "offline" | "invalid" | "none"
    property string lookupState: ""
    // Look up was pressed before the list of services had been confirmed; when
    // it is, carry on. Cleared if the list is dismissed instead.
    property bool lookupAfterChoice: false

    readonly property string isbn: Lookup.normaliseIsbn(isbnField.text)
    readonly property bool isbnOk: isbnField.text.trim() === "" || page.isbn !== ""

    canAccept: titleField.text.trim().length > 0 && page.kindId >= 0 && page.isbnOk
    acceptDestinationAction: PageStackAction.Pop

    function addTag(t) {
        var current = tagsField.text.trim()
        if (current === "") tagsField.text = t
        else if (current.indexOf(t) < 0) tagsField.text = current + ", " + t
    }

    function refreshKind() {
        var k = page.kindId >= 0 ? Storage.kindById(page.kindId) : null
        page.kindName = k === null ? "" : k.name
        page.kindUnitText = k === null ? "" : k.unit
    }

    function applyKind(id) {
        page.kindId = id
        page.refreshKind()
    }

    // animatorPush hands back an operation, not the page, so the signal has to
    // be wired up once the page exists. The fallback covers the case where the
    // operation already IS the page.
    function pickKind() {
        var op = pageStack.animatorPush(Qt.resolvedUrl("KindPage.qml"),
                                        { currentKindId: page.kindId, nature: "finish" })
        if (op === null || op === undefined) return
        if (op.pageCompleted !== undefined) {
            op.pageCompleted.connect(function(p) { p.kindPicked.connect(page.applyKind) })
        } else if (op.kindPicked !== undefined) {
            op.kindPicked.connect(page.applyKind)
        }
    }

    function openServices(first) {
        pageStack.animatorPush(Qt.resolvedUrl("LookupServicesPage.qml"), { firstTime: first })
    }

    // The services do the asking, one after another, in LookupRunner. This
    // only decides whether it may start at all.
    function lookUp() {
        if (page.isbn === "") {
            page.lookupState = "invalid"
            return
        }
        // Nothing is sent until the person has seen what each service gets.
        if (!LookupSettings.chosen) {
            page.lookupAfterChoice = true
            page.openServices(true)
            return
        }
        if (LookupSettings.enabledIds().length === 0) {
            page.lookupState = "none"
            return
        }
        isbnField.focus = false
        page.lookupState = "busy"
        runner.lookUp(page.isbn, !preview.hasPicture)
    }

    function showResult() {
        var r = runner.result
        if (r.title === "") {
            page.lookupState = runner.offline ? "offline" : "notfound"
            return
        }
        titleField.text = r.title
        if (r.creator !== "") creatorField.text = r.creator
        if (r.extent > 0) extentField.text = String(r.extent)
        page.lookupState = "found"
    }

    LookupRunner {
        id: runner
        onInfoDone: page.showResult()
    }

    Connections {
        target: LookupSettings
        onChosenChanged: {
            if (page.lookupAfterChoice && LookupSettings.chosen) {
                page.lookupAfterChoice = false
                page.lookUp()
            }
        }
    }

    // Coming back from the list without having confirmed it: do not look up.
    onStatusChanged: {
        if (status === PageStatus.Active) page.lookupAfterChoice = false
    }

    Component.onCompleted: {
        knownTags = Storage.allTags()

        // A new item usually belongs to the same kind as the last one, so the
        // first existing kind is a better opening bid than nothing at all.
        var mine = Storage.kinds()
        if (mine.length > 0 && page.kindId < 0) page.kindId = mine[0].id

        if (editing) {
            var it = Storage.itemById(itemId)
            if (it !== null) {
                titleField.text = it.title
                creatorField.text = it.creator
                page.kindId = it.kindId
                page.isPrivate = it.private
                isbnField.text = it.isbn
                extentField.text = it.extent > 0 ? String(it.extent) : ""
                tagsField.text = Storage.itemTags(itemId).join(", ")
            }
        }

        page.refreshKind()
    }

    onAccepted: {
        // A kind invented on the picker page already exists by the time it
        // comes back, so there is nothing left to create here.
        var payload = {
            id: page.itemId,
            title: titleField.text.trim(),
            creator: creatorField.text.trim(),
            kindId: page.kindId,
            private: page.isPrivate,
            extent: extentField.text.trim().replace(",", "."),
            isbn: page.isbn,
            tags: Storage.parseTags(tagsField.text)
        }
        if (editing) Storage.updateItem(payload)
        else Storage.addItem(payload)
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

            DialogHead {
                title: page.editing ? qsTr("Edit item") : qsTr("New item")
                acceptEnabled: page.canAccept
                onCancelled: page.reject()
                onAccepted: page.accept()
            }

            // -- ISBN ------------------------------------------------------------

            Item {
                width: parent.width
                height: isbnField.height

                TextField {
                    id: isbnField
                    width: parent.width - lookupPill.width - Theme.horizontalPageMargin
                    label: qsTr("ISBN (optional, books only)")
                    placeholderText: qsTr("ISBN, to look the book up")
                    inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText
                    color: FiatMosTheme.primaryText
                    onTextChanged: {
                        // Another ISBN: what is still coming back is about the old one.
                        if (runner.phase === "busy" || runner.coverBusy) {
                            runner.cancel()
                            page.lookupState = ""
                        }
                        if (page.lookupState === "invalid" || page.lookupState === "notfound"
                                || page.lookupState === "none") page.lookupState = ""
                    }
                    EnterKey.iconSource: "image://theme/icon-m-search"
                    EnterKey.onClicked: page.lookUp()
                }

                // A word in the accent, like Save in the header: it acts
                // once. Faded until there is an ISBN to act on.
                ActionWord {
                    id: lookupPill
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    anchors.top: parent.top
                    anchors.topMargin: Theme.paddingMedium
                    text: page.lookupState === "busy" ? qsTr("looking…") : qsTr("look up")
                    opacity: page.isbn !== "" ? 1.0 : 0.35
                    onClicked: if (page.lookupState !== "busy") page.lookUp()
                }
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingLarge
                visible: lookupNote.text !== "" || preview.hasPicture

                BookCover {
                    id: preview
                    width: Theme.itemSizeLarge
                    height: width * 1.5
                    visible: hasPicture
                    isbn: page.isbn
                    title: titleField.text
                    revision: runner.coverRevision
                }

                Label {
                    id: lookupNote
                    width: parent.width - (preview.visible ? preview.width + parent.spacing : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: (page.lookupState === "invalid" || (!page.isbnOk && isbnField.text.trim().length >= 10))
                           ? FiatMosTheme.wrong : FiatMosTheme.secondaryText
                    text: {
                        var _g = runner.gen
                        var lines = []
                        if (page.lookupState === "busy") {
                            return runner.busyText !== "" ? runner.busyText : qsTr("Looking up…")
                        }
                        if (page.lookupState === "found") {
                            lines.push(runner.foundText)
                            if (runner.askedText !== "") lines.push(runner.askedText)
                            if (runner.coverBusy) lines.push(qsTr("Fetching the cover…"))
                            lines.push(qsTr("Check the fields below before you save."))
                            return lines.join("\n")
                        }
                        if (page.lookupState === "notfound") {
                            lines.push(qsTr("None of the services asked knows this ISBN. Fill in the fields yourself."))
                            if (runner.askedText !== "") lines.push(runner.askedText)
                            return lines.join("\n")
                        }
                        if (page.lookupState === "offline") {
                            lines.push(qsTr("No answer. Is the phone online?"))
                            if (runner.askedText !== "") lines.push(runner.askedText)
                            return lines.join("\n")
                        }
                        if (page.lookupState === "none")
                            return qsTr("All lookup services are switched off. Choose where to look, below.")
                        if (page.lookupState === "invalid" || (!page.isbnOk && isbnField.text.trim().length >= 10))
                            return qsTr("That is not a valid ISBN. Check the digits.")
                        return ""
                    }
                }
            }

            ValueRow {
                width: parent.width
                label: qsTr("Lookup services")
                value: LookupSettings.chosen ? qsTr("%1 on").arg(LookupSettings.enabledCount) : ""
                placeholder: qsTr("not chosen yet")
                onClicked: page.openServices(false)
            }

            TextField {
                id: titleField
                width: parent.width
                label: qsTr("Title")
                placeholderText: qsTr("Title")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: creatorField.focus = true
            }

            TextField {
                id: creatorField
                width: parent.width
                label: qsTr("Creator (optional)")
                placeholderText: qsTr("Author, composer, whoever")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            // -- Kind -----------------------------------------------------------
            //
            // The kind owns the unit. That is the whole reason a habit can
            // never mix pages and minutes: it is tied to a kind, and a kind
            // is measured in one thing.

            ValueRow {
                width: parent.width
                label: qsTr("Kind")
                placeholder: qsTr("Choose a kind…")
                value: page.kindName
                detail: page.kindUnitText
                onClicked: page.pickKind()
            }

            TextField {
                id: extentField
                width: parent.width
                label: page.kindUnitText === ""
                    ? qsTr("Length (optional)")
                    : qsTr("Length in %1 (optional)").arg(page.kindUnitText)
                placeholderText: page.kindUnitText === ""
                    ? qsTr("Length")
                    : qsTr("How many %1 in all").arg(page.kindUnitText)
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("The kind decides what a log entry counts. You never set a unit on the item itself. The length is optional: with it, the item shows how far in you are.")
            }

            // -- Tags ----------------------------------------------------------

            TextField {
                id: tagsField
                width: parent.width
                label: qsTr("Tags, comma separated")
                placeholderText: qsTr("french, language-study")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.knownTags.length > 0

                Repeater {
                    model: page.knownTags.length
                    // Several can be on, so no bar under them -- bold and in
                    // the accent says "in the field", nothing more.
                    Pill {
                        multi: true
                        text: page.knownTags[index]
                        selected: tagsField.text.indexOf(page.knownTags[index]) >= 0
                        onClicked: page.addTag(page.knownTags[index])
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("The kind says what this is and how it is measured. The tag is what you will actually ask about later — pages in French this year, minutes on organ this month.")
            }

            // -- Private --------------------------------------------------------

            SwitchRow {
                text: qsTr("Keep private")
                checked: page.isPrivate
                onClicked: page.isPrivate = !page.isPrivate
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("A private item stays on your shelf and keeps logging normally, but is left out of Totals unless you ask for it. Nothing is hidden from you, only from anything you might share.")
            }
        }

        VerticalScrollDecorator { }
    }
}
