import QtQuick 2.0
import Sailfish.Silica 1.0
import ".."
import "../components"
import "../Storage.js" as Storage

// Workouts: where the workout side of the app starts. The week, and two ways
// in -- the exercises you do, and the programs you do them in.
//
// Kept to a few lines on purpose. Each of the two is a list of its own, and a
// page with a list on it is a page you have to scroll to find the rest of.

Page {
    id: page

    property int exerciseCount: 0
    property int programCount: 0
    property var week: ({ days: [false, false, false, false, false, false, false], thisWeek: 0, lastWeek: 0, todayIndex: 0 })

    function accent(t) {
        return "<font color=\"" + FiatMosTheme.accent + "\">" + t + "</font>"
    }

    // "This week: 4 workouts, 3 more than last."
    function weekSentence() {
        var w = page.week
        var n = w.thisWeek === 1 ? qsTr("1 workout") : qsTr("%1 workouts").arg(w.thisWeek)
        var head = qsTr("This week: %1").arg(page.accent(n))
        var d = w.thisWeek - w.lastWeek
        if (w.lastWeek === 0 && w.thisWeek === 0) return qsTr("No workouts this week yet.")
        if (d === 0) return head + qsTr(", as many as last week.")
        if (d > 0) return head + (d === 1 ? qsTr(", 1 more than last week.") : qsTr(", %1 more than last week.").arg(d))
        return head + (d === -1 ? qsTr(", 1 fewer than last week.") : qsTr(", %1 fewer than last week.").arg(-d))
    }

    function reload() {
        var kinds = Storage.kinds({ nature: "practise" })
        var n = 0
        for (var i = 0; i < kinds.length; i++) n += Storage.things(kinds[i].id).length
        exerciseCount = n
        programCount = Storage.programs().length
        week = Storage.workoutWeek()
    }

    onStatusChanged: {
        if (status === PageStatus.Active) reload()
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

            PageHead { title: qsTr("Workouts") }

            // The week first: one sentence, and the habit list's own dots for
            // the seven days, filled where there was a workout.
            Label {
                x: Theme.horizontalPageMargin
                width: content.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                font.pixelSize: Theme.fontSizeMedium
                font.family: FiatMosTheme.serif
                color: FiatMosTheme.primaryText
                text: page.weekSentence()
            }

            Row {
                x: Theme.horizontalPageMargin
                width: content.width - Theme.horizontalPageMargin * 2
                readonly property real cell: width / 7

                Repeater {
                    model: 7
                    Column {
                        width: parent.cell
                        spacing: Theme.paddingSmall / 2
                        readonly property bool on: page.week.days[index] === true
                        readonly property bool future: index > page.week.todayIndex

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Theme.itemSizeSmall * 0.45
                            height: width
                            radius: width / 2
                            color: parent.on ? FiatMosTheme.accent : "transparent"
                            border.width: 1
                            border.color: parent.on ? FiatMosTheme.accent
                                        : (parent.future ? FiatMosTheme.dotIdle : FiatMosTheme.pillBorder)
                            Label {
                                anchors.centerIn: parent
                                visible: parent.parent.on
                                text: "✓"
                                color: FiatMosTheme.markOn(FiatMosTheme.accent)
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            // Monday first, in the phone's own language.
                            text: Qt.locale().dayName((index + 1) % 7, Locale.NarrowFormat)
                            font.pixelSize: Theme.fontSizeTiny
                            color: index === page.week.todayIndex ? FiatMosTheme.accent : FiatMosTheme.secondaryText
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }

            ValueRow {
                width: content.width
                label: qsTr("Exercises")
                value: page.exerciseCount === 0 ? qsTr("none yet") : String(page.exerciseCount)
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ExercisesPage.qml"))
            }

            ValueRow {
                width: content.width
                label: qsTr("Programs")
                value: page.programCount === 0 ? qsTr("none yet") : String(page.programCount)
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("ProgramsPage.qml"))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: content.width - Theme.horizontalPageMargin * 2
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: FiatMosTheme.secondaryText
                text: qsTr("An exercise keeps its own history. A program is a list of exercises to start a workout from.")
            }
        }

        VerticalScrollDecorator { }
    }
}
