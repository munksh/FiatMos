import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import ".."
import "../Durations.js" as Durations

// A time written the way you say it: hours, minutes, seconds -- two or three
// of them, the ones you choose. 7 h and 30 min for a night's sleep, 40 s for
// a hang, 1 h 5 min for a run. Nothing is turned into anything else in your
// head; the whole is handed on in the habit's own unit.
//
//   unit    the unit the whole is kept in: "h", "min" or "s"
//   value   the whole, in that unit, as text; empty when nothing is written
//   edited  something was typed
//
// Which fields show is one choice for the whole app, kept on the phone, and
// until it is made it follows the unit: hours and minutes for a unit of
// hours, minutes and seconds for anything smaller.
Column {
    id: root

    property string unit: "min"
    property string value: ""
    property bool showChoice: true
    signal edited()

    width: parent ? parent.width : 0

    ConfigurationValue {
        id: pref
        key: "/apps/harbour-fiatmos/timefields"
        defaultValue: ""
    }

    readonly property string preset: pref.value ? pref.value : Durations.defaultPreset(root.unit)
    readonly property var fields: Durations.fieldsOf(root.preset)
    property bool loading: false

    // Writes a whole into the fields. Used to start from an old value, and
    // again when the choice of fields changes so nothing written is lost.
    function setValue(v) {
        loading = true
        var p = Durations.split(v, root.unit, root.fields)
        hField.text = p.h
        mField.text = p.min
        sField.text = p.s
        loading = false
        root.value = Durations.join(p, root.unit, root.fields)
    }

    function recompute() {
        if (loading) return
        root.value = Durations.join({ h: hField.text, min: mField.text, s: sField.text }, root.unit, root.fields)
        root.edited()
    }

    onPresetChanged: setValue(root.value)

    Row {
        width: parent.width

        TextField {
            id: hField
            visible: root.fields.indexOf("h") >= 0
            width: root.width / root.fields.length
            label: qsTr("h")
            placeholderText: qsTr("h")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            color: FiatMosTheme.primaryText
            onTextChanged: root.recompute()
            EnterKey.iconSource: "image://theme/icon-m-enter-close"
            EnterKey.onClicked: focus = false
        }
        TextField {
            id: mField
            visible: root.fields.indexOf("min") >= 0
            width: root.width / root.fields.length
            label: qsTr("min")
            placeholderText: qsTr("min")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            color: FiatMosTheme.primaryText
            onTextChanged: root.recompute()
            EnterKey.iconSource: "image://theme/icon-m-enter-close"
            EnterKey.onClicked: focus = false
        }
        TextField {
            id: sField
            visible: root.fields.indexOf("s") >= 0
            width: root.width / root.fields.length
            label: qsTr("s")
            placeholderText: qsTr("s")
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            color: FiatMosTheme.primaryText
            onTextChanged: root.recompute()
            EnterKey.iconSource: "image://theme/icon-m-enter-close"
            EnterKey.onClicked: focus = false
        }
    }

    // Which fields. Words, like every other choice in the app.
    Flow {
        x: Theme.horizontalPageMargin
        width: parent.width - Theme.horizontalPageMargin * 2
        visible: root.showChoice

        Repeater {
            model: Durations.PRESETS

            Pill {
                text: Durations.presetLabel(modelData)
                selected: root.preset === modelData
                onClicked: pref.value = modelData
            }
        }
    }
}
