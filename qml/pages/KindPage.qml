import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage
import "../Measures.js" as Measures

// Picks what a habit — or an item — works through, or practises.
//
// `nature` says which: "finish" lists the shelf's kinds (book, roll of film),
// "practise" the kinds of things that keep coming back (exercises, pieces).
// The two never mix on this page, so a habit that finishes things can never
// be pointed at a kind of things you practise.
//
// This used to be a row of pills on the page above. A pill row is right for
// four fixed values and wrong for a list that grows every time the user
// invents something: at twenty kinds it is a wall. So it became its own page,
// which is what Silica does for every long choice.
//
// Two sections. YOURS is what already exists in item_kind. COMMON is the
// starter list from Storage.js, which lives in code and has no rows behind it
// — a starter kind becomes a row the moment somebody picks it, and not
// before. That is why the library never fills with kinds nobody used.

Page {
    id: page

    // The caller connects to this. It fires with a real item_kind id: a
    // starter kind is written to the database here, so by the time the caller
    // hears about it there is a row.
    signal kindPicked(int kindId)

    property int currentKindId: -1
    property string nature: "finish"
    readonly property bool practising: page.nature === "practise"
    property string term: ""
    property bool inventing: false
    // For a new practise kind: how its things start out being measured.
    property string newMeasure: "weight_reps"

    function detailOf(unit, measure) {
        if (page.practising) return qsTr("each starts as %1").arg(Measures.label(measure))
        return unit === "" ? qsTr("no unit") : qsTr("measured in %1").arg(unit)
    }

    ListModel { id: kindModel }

    function matches(name) {
        return page.term === "" || name.toLowerCase().indexOf(page.term.toLowerCase()) >= 0
    }

    function reload() {
        kindModel.clear()
        var anyShown = 0

        var mine = Storage.kinds({ nature: page.nature })
        for (var i = 0; i < mine.length; i++) {
            if (!matches(mine[i].name)) continue
            kindModel.append({ kindId: mine[i].id,
                               name: mine[i].name,
                               unit: mine[i].unit,
                               measure: mine[i].measure,
                               section: "yours" })
            anyShown++
        }

        var starters = Storage.starterKinds(page.nature)
        for (var j = 0; j < starters.length; j++) {
            if (!matches(starters[j].name)) continue
            // id -1 means "not a row yet". It becomes one when picked.
            kindModel.append({ kindId: -1,
                               name: starters[j].name,
                               unit: starters[j].unit,
                               measure: starters[j].measure === undefined ? "weight_reps" : starters[j].measure,
                               section: "common" })
            anyShown++
        }

        // Typing something nobody has heard of is itself the answer: the
        // invent-a-kind form opens with the name already filled in.
        if (anyShown === 0 && page.term !== "" && !page.inventing) {
            page.inventing = true
            newName.text = page.term
        }
    }

    function choose(kindId, name, unit, measure) {
        var id = kindId
        if (id < 0) id = Storage.addKind(name, unit, page.nature, measure)
        if (id < 0) return
        page.kindPicked(id)
        pageStack.pop()
    }

    Component.onCompleted: reload()
    onTermChanged: reload()

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
        model: kindModel

        header: Column {
            width: listView.width
            spacing: Theme.paddingMedium

            PageHead {
                title: qsTr("Kind")
                subtitle: page.practising ? qsTr("things you practise") : qsTr("things you finish")
            }

            TextField {
                id: searchField
                width: parent.width
                label: qsTr("Search")
                placeholderText: qsTr("Search, or type a new kind")
                color: FiatMosTheme.primaryText
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
                onTextChanged: page.term = text.trim()
            }
        }

        section.property: "section"
        // An Item wrapping the label rather than padding on the label itself:
        // Text.topPadding is newer than the QtQuick 2.0 import this file uses,
        // and a property that silently does nothing is worse than a spacer.
        section.delegate: Item {
            width: listView.width
            height: Theme.itemSizeExtraSmall

            SectionLabel {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.paddingSmall
                text: String(section) === "yours" ? qsTr("Yours") : qsTr("Common")
            }
        }

        delegate: BackgroundItem {
            id: kindRow
            width: listView.width
            height: Theme.itemSizeSmall
            highlightedColor: FiatMosTheme.highlightWash
            onClicked: page.choose(model.kindId, model.name, model.unit, model.measure)

            readonly property bool current: model.kindId >= 0 && model.kindId === page.currentKindId

            Column {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2 - Theme.paddingLarge

                Label {
                    width: parent.width
                    text: model.name
                    truncationMode: TruncationMode.Fade
                    color: (kindRow.highlighted || kindRow.current)
                        ? FiatMosTheme.accent : FiatMosTheme.primaryText
                }

                Label {
                    width: parent.width
                    text: page.detailOf(model.unit, model.measure)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: FiatMosTheme.secondaryText
                    truncationMode: TruncationMode.Fade
                }
            }

            // Drawn, not typed. Marks the one already chosen.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                visible: kindRow.current
                width: Theme.paddingSmall
                height: width
                radius: width / 2
                color: FiatMosTheme.accent
            }
        }

        footer: Column {
            width: listView.width
            spacing: Theme.paddingMedium

            Item { width: 1; height: Theme.paddingMedium }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                height: 1
                color: FiatMosTheme.innerBorder
            }

            BackgroundItem {
                id: inventRow
                width: listView.width
                height: Theme.itemSizeSmall
                highlightedColor: FiatMosTheme.highlightWash
                onClicked: {
                    page.inventing = true
                    if (newName.text === "" && page.term !== "") newName.text = page.term
                    newName.focus = true
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2

                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        color: inventRow.highlighted ? FiatMosTheme.accent : FiatMosTheme.primaryText
                        text: page.term === ""
                            ? qsTr("Something else…")
                            : qsTr("Create “%1”").arg(page.term)
                    }

                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                        text: page.practising ? qsTr("Your own kind of thing to practise")
                                              : qsTr("Your own kind, your own unit")
                    }
                }
            }

            TextField {
                id: newName
                width: listView.width
                visible: page.inventing
                label: qsTr("What kind of thing is it?")
                placeholderText: page.practising ? qsTr("katas, scales, poses…") : qsTr("sketch, letter, lecture…")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: newUnit.focus = true
            }

            TextField {
                id: newUnit
                width: listView.width
                visible: page.inventing && !page.practising
                label: qsTr("Measured in")
                placeholderText: qsTr("pages, minutes, frames…")
                color: FiatMosTheme.primaryText
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                visible: page.inventing && !page.practising
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Set once, now. The unit is never changed afterwards — that would reinterpret every number already logged against it.")
            }

            // A thing you practise has no unit: each thing is measured its
            // own way. This is only how a new one starts, and can be changed
            // on any of them later.
            SectionLabel {
                x: Theme.horizontalPageMargin
                visible: page.inventing && page.practising
                text: qsTr("Each new one is measured in")
            }

            Flow {
                x: Theme.horizontalPageMargin
                width: listView.width - Theme.horizontalPageMargin * 2
                spacing: Theme.paddingSmall
                visible: page.inventing && page.practising

                Repeater {
                    model: Measures.choices()
                    Pill {
                        text: modelData.label
                        selected: page.newMeasure === modelData.value
                        onClicked: page.newMeasure = modelData.value
                    }
                }
            }

            ActionWord {
                x: Theme.horizontalPageMargin - Theme.paddingMedium
                visible: page.inventing
                text: qsTr("use this kind")
                enabled: newName.text.trim() !== "" && (page.practising || newUnit.text.trim() !== "")
                onClicked: page.choose(-1, newName.text.trim(), page.practising ? "" : newUnit.text.trim(), page.newMeasure)
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator { }
    }
}
