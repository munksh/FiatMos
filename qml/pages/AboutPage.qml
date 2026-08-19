import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"

// Who made this, what it does with your data, and where it came from.
//
// Four questions in that order, and nothing else. No changelog -- that belongs
// in the store listing and the repository, where it can be corrected. No
// donation button. Two links.
//
// The lead is three examples rather than a summary. "A habit tracker where
// each habit sets its own detail" is accurate and says nothing; flossing,
// running and a gym session say the same thing and can be pictured.
//
// The privacy paragraph is the only place in the app that makes a claim about
// itself, and it is written flat on purpose. Every app says it respects your
// privacy; this one can point at one permission and a package with no network
// access, so it should read as a fact and not as a promise.

Page {
    id: page

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
                title: qsTr("about")
                subtitle: "fiat mos"
            }

            // -- What it is -----------------------------------------------

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: qsTr("Flossing is yes or no. Running is a number. A gym session is a whole page of its own.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Most habit trackers pick one of those shapes and make everything else fit it. Fiat Mos lets every habit be its own size — a tick, a number with a unit, a rating on a scale you invent, something you work through piece by piece, or a full session with exercises and sets. Nothing gets padded out, and nothing gets squeezed.")
            }

            // -- The name --------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("The name")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                textFormat: Text.StyledText
                linkColor: FiatMosTheme.accent
                text: qsTr("<b>fiat</b> — Latin, <i>let there be</i>. From <i>fiat lux</i> in the Vulgate: let there be light, and there was light. The first app took the phrase. The rest of the family kept the verb.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                textFormat: Text.StyledText
                text: qsTr("<b>mos</b> — Latin, <i>custom</i>, the way a thing is usually done. Its plural, <i>mores</i>, is where morals come from. A habit is a custom you keep with yourself.")
            }

            // -- The motto -------------------------------------------------
            //
            // It stands on its own. It does NOT explain the icon -- the icon is
            // a tally cut into a stone, and there is no drop in it. Two good
            // things next to each other is enough; a connection asserted where
            // none exists is worse than none claimed.

            Item { width: 1; height: Theme.paddingMedium }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: content.width - Theme.horizontalPageMargin * 2
                height: mottoColumn.height + Theme.paddingLarge * 2
                radius: FiatMosTheme.cardRadius
                color: FiatMosTheme.card
                border.color: FiatMosTheme.cardBorder
                border.width: FiatMosTheme.cardBorderWidth

                Column {
                    id: mottoColumn
                    anchors.centerIn: parent
                    width: parent.width - Theme.paddingLarge * 2
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatMosTheme.serif
                        font.italic: true
                        color: FiatMosTheme.primaryText
                        text: "Gutta cavat lapidem,\nnon vi sed saepe cadendo"
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                        text: qsTr("The drop hollows the stone, not by force but by falling often.")
                    }
                }
            }

            // -- Privacy ---------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Your data")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Everything stays on this phone, in one file. There is no account, no network access, and nothing is measured or reported. Fiat Mos asks for one permission — the Documents folder — and only so that Backup can write an export you can carry to another phone.")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("Nothing is ever deleted behind your back either. Undo writes a new entry rather than removing one, and habits are archived instead of erased.")
            }

            // -- Who ---------------------------------------------------------

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Made by")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: "Munkstolen"
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: "Caesar Prometheus Ivarsson"
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                highlightedColor: FiatMosTheme.highlightWash
                onClicked: Qt.openUrlExternally("https://munkstolen.se")

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2

                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        color: FiatMosTheme.accent
                        font.pixelSize: Theme.fontSizeSmall
                        text: "munkstolen.se"
                    }

                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                        text: qsTr("Everything else I make")
                    }
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                highlightedColor: FiatMosTheme.highlightWash
                onClicked: Qt.openUrlExternally("https://github.com/munksh/FiatMos")

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.horizontalPageMargin
                    width: parent.width - Theme.horizontalPageMargin * 2

                    Label {
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        color: FiatMosTheme.accent
                        font.pixelSize: Theme.fontSizeSmall
                        text: "github.com/munksh/FiatMos"
                    }

                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                        text: qsTr("Source and issues · MIT licence")
                    }
                }
            }

            // -- The family ---------------------------------------------------
            //
            // Every name translates itself, and the translation explains the
            // app. That is worth more than a tagline.

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("The Fiat family")
            }

            Repeater {
                model: [
                    { name: "fiat lux", what: qsTr("let there be light — a light meter for film") },
                    { name: "fiat vox", what: qsTr("let there be voice — a chromatic tuner") },
                    { name: "fiat cor", what: qsTr("let there be heart — a metronome, after the first one anybody owns") },
                    { name: "fiat mos", what: qsTr("let there be habit — this one") }
                ]

                Column {
                    x: Theme.horizontalPageMargin
                    width: content.width - Theme.horizontalPageMargin * 2

                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: FiatMosTheme.serif
                        color: FiatMosTheme.primaryText
                        text: modelData.name
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: FiatMosTheme.secondaryText
                        text: modelData.what
                    }
                }
            }

            Item { width: 1; height: Theme.paddingMedium }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeTiny
                color: FiatMosTheme.secondaryText
                text: qsTr("Four instruments that measure something you would otherwise guess at. They share a look, a palette and a stubbornness about staying on your own phone.")
            }

            // -- Version ---------------------------------------------------
            //
            // Last, because it is support and not identity. The number comes
            // from the rpm spec by way of qmake, so it is the one the package
            // was actually built with rather than one written down twice.

            SectionLabel {
                x: Theme.horizontalPageMargin
                text: qsTr("Version")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                font.pixelSize: Theme.fontSizeSmall
                color: FiatMosTheme.primaryText
                text: typeof appVersion !== "undefined" ? appVersion : qsTr("unknown")
            }

            // -- Colophon --------------------------------------------------
            //
            // A printer's mark at the end of a book: a short rule, the mark,
            // the wordmark. Nothing here is tappable -- the links are up under
            // "made by". This is the signature, not a button.

            Item { width: 1; height: Theme.itemSizeExtraSmall }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.itemSizeSmall
                height: 1
                color: FiatMosTheme.innerBorder
            }

            Item { width: 1; height: Theme.paddingLarge }

            MunkstolenMark {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.itemSizeMedium
                frame: "ring"
                color: FiatMosTheme.makerMark
            }

            Item { width: 1; height: Theme.paddingSmall }

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "munkstolen"
                font.pixelSize: Theme.fontSizeSmall
                font.family: FiatMosTheme.serif
                font.italic: true
                color: FiatMosTheme.makerMark
            }
        }

        VerticalScrollDecorator { }
    }
}
