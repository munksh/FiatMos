import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Adds and edits a library item. The file is still called AddBookPage so the
// .pro does not churn; nothing in it says "book" any more.
//
// The kind is chosen on its own page, the same one the habit editor uses. It
// is never a fixed list -- a new kind of thing must never need a schema
// migration -- but it is not a wall of pills either.

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

    canAccept: titleField.text.trim().length > 0 && page.kindId >= 0
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
                                        { currentKindId: page.kindId })
        if (op === null || op === undefined) return
        if (op.pageCompleted !== undefined) {
            op.pageCompleted.connect(function(p) { p.kindPicked.connect(page.applyKind) })
        } else if (op.kindPicked !== undefined) {
            op.kindPicked.connect(page.applyKind)
        }
    }

    Component.onCompleted: {
        knownTags = Storage.allTags()

        // A new item usually belongs to the same kind as the last one, so the
        // first existing kind is a better opening bid than nothing at all.
        var mine = Storage.kinds()
        if (mine.length > 0 && page.kindId < 0) page.kindId = mine[0].id

        if (editing) {
            var list = Storage.items({ includePrivate: true })
            var it = null
            for (var i = 0; i < list.length; i++) if (list[i].id === itemId) it = list[i]
            if (it !== null) {
                titleField.text = it.title
                creatorField.text = it.creator
                page.kindId = it.kindId
                page.isPrivate = it.private
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

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("The kind decides what a log entry counts. You never set a unit on the item itself.")
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
                    Pill {
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

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall

                Pill {
                    text: qsTr("Keep private")
                    selected: page.isPrivate
                    onClicked: page.isPrivate = !page.isPrivate
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("A private item stays in your library and keeps logging normally, but is left out of Totals unless you ask for it. Nothing is hidden from you, only from anything you might share.")
            }
        }

        VerticalScrollDecorator { }
    }
}
