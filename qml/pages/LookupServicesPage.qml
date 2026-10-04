import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Lookup.js" as Lookup

// Where Look up may look. One switch per service, and for each what it
// receives and what it can give back, so the choice is an informed one.
//
// Shown the first time Look up is pressed, before anything has been sent, and
// reachable again from the Library, from About and from the item editor.
// Cancel leaves everything as it was; Save is what makes the choice count.

Dialog {
    id: page

    // The first time, the heading says nothing has been sent yet.
    property bool firstTime: false

    // { openlibrary: true, ... } -- replaced, never edited in place, so the
    // rows notice.
    property var choice: ({})

    acceptDestinationAction: PageStackAction.Pop

    function fullName(id) {
        if (id === "dnb") return qsTr("Deutsche Nationalbibliothek (DNB)")
        if (id === "bnf") return qsTr("Bibliothèque nationale de France (BnF)")
        return Lookup.serviceName(id)
    }

    // What each one is, receives and gives. The first two sentences differ,
    // the middle one is the same for all and is said every time on purpose.
    function blurb(id) {
        if (id === "openlibrary")
            return qsTr("Run by the Internet Archive. Receives the ISBN and your IP address. Can give title, author, pages and cover; covers are downloaded from the same place.")
        if (id === "libris")
            return qsTr("Run by the National Library of Sweden. Receives the ISBN and your IP address. Gives title and author, never pages or a cover.")
        if (id === "dnb")
            return qsTr("Run by the German National Library. Receives the ISBN and your IP address. Gives title, author and, when its record has them, pages. No covers.")
        if (id === "bnf")
            return qsTr("Run by the National Library of France. Receives the ISBN and your IP address. Gives title, author and, when its record has them, pages. No covers.")
        if (id === "google")
            return qsTr("Run by Google. Receives the ISBN and your IP address. Can give title, author, pages and cover. Asked without an account or a key, so Google may refuse when it is busy. Off unless you switch it on.")
        return ""
    }

    function toggle(id) {
        var c = {}
        for (var k in page.choice) c[k] = page.choice[k]
        c[id] = !page.choice[id]
        page.choice = c
    }

    Component.onCompleted: {
        var c = {}
        for (var i = 0; i < Lookup.SERVICES.length; i++) c[Lookup.SERVICES[i].id] = LookupSettings.wanted(Lookup.SERVICES[i].id)
        page.choice = c
    }

    onAccepted: LookupSettings.apply(page.choice)

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
                title: qsTr("Where to look")
                acceptText: page.firstTime ? qsTr("Use these") : qsTr("Save")
                onCancelled: page.reject()
                onAccepted: page.accept()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                visible: page.firstTime
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: qsTr("Nothing has been sent yet. Choose where Fiat Mos may look.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Looking a book up sends its ISBN to each service you switch on, together with your phone's IP address, which any website you visit sees too. Nothing else leaves the phone: no habits, no other books, no history. A service that is off is never contacted, and its covers are never downloaded.")
            }

            // One row per service, and the row is the switch: the dot says on
            // or off, the name and what it is sent sit beside it.
            Repeater {
                model: Lookup.SERVICES.length

                SwitchRow {
                    id: row
                    readonly property string serviceId: Lookup.SERVICES[index].id
                    width: content.width
                    serifText: true
                    text: page.fullName(row.serviceId)
                    description: page.blurb(row.serviceId)
                    checked: page.choice[row.serviceId] === true
                    onClicked: page.toggle(row.serviceId)
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Open Library is asked first, then the national library that matches the ISBN, then the others, and Google last. It stops as soon as it has a title, an author and a length; only what is still missing is asked of the next one. After a lookup, the page tells you which services were asked and which one supplied what.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("This choice stays on this phone. It is not part of Backup, so a new phone asks again.")
            }
        }

        VerticalScrollDecorator { }
    }
}
