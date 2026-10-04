.pragma library

// How a practised thing is measured, said in words. The keys are the ones
// Storage.js keeps in item.measure and item_kind.measure.

var KEYS = ["weight_reps", "time", "time_distance"]

function label(m) {
    if (m === "time") return qsTr("time")
    if (m === "time_distance") return qsTr("time + distance")
    return qsTr("weight × reps")
}

// For a Flow of Pills: [{ label, value }]
function choices() {
    var out = []
    for (var i = 0; i < KEYS.length; i++) out.push({ label: label(KEYS[i]), value: KEYS[i] })
    return out
}
