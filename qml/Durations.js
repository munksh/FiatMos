.pragma library

// Time, said and written the way a person does: 7 h 30 min, 40 s, 1 h 5 min.
//
// A number with a unit (sleep in hours, a plank in minutes) is stored in that
// unit, as it always has been. What this file does is let you write it in
// hours, minutes and seconds -- whichever you like -- and read it back the
// same way, so nobody has to turn 7 h 30 into 450 in their head.
//
// Not translated on purpose: h, min and s are the same everywhere.

// How many seconds one of the words a time unit goes by is. 0 for anything
// that is not a time (kg, pages, km).
function unitSeconds(unit) {
    if (unit === undefined || unit === null) return 0
    var u = String(unit).toLowerCase().replace(/\./g, "").trim()
    if (u === "s" || u === "sec" || u === "secs" || u === "second" || u === "seconds"
        || u === "sek" || u === "sekund" || u === "sekunder") return 1
    if (u === "min" || u === "mins" || u === "minute" || u === "minutes"
        || u === "minut" || u === "minuter") return 60
    if (u === "h" || u === "hr" || u === "hrs" || u === "hour" || u === "hours"
        || u === "tim" || u === "timme" || u === "timmar") return 3600
    return 0
}

function isTime(unit) { return unitSeconds(unit) > 0 }

// A whole number of seconds, said short: "7 h 30 min", "40 s", "1 h 5 min 10 s".
function formatSeconds(total) {
    var t = Math.round(Number(total))
    if (isNaN(t) || t < 0) return ""
    if (t === 0) return "0 s"
    var h = Math.floor(t / 3600)
    var m = Math.floor((t % 3600) / 60)
    var s = t % 60
    var out = []
    if (h > 0) out.push(h + " h")
    if (m > 0) out.push(m + " min")
    if (s > 0) out.push(s + " s")
    return out.join(" ")
}

// A value in its unit, said short. "" when the unit is not a time, so the
// caller can say it the ordinary way.
function format(value, unit) {
    var f = unitSeconds(unit)
    if (f <= 0 || value === undefined || value === null || value === "") return ""
    var v = Number(value)
    if (isNaN(v)) return ""
    return formatSeconds(v * f)
}

// ---- the fields you write it in ---------------------------------------------

// Which fields to show: two or three of hours, minutes, seconds. The words
// are the choices a person makes; the default follows the unit.
var PRESETS = ["h,min", "min,s", "h,min,s"]

function presetLabel(p) { return p.replace(/,/g, " · ") }

function defaultPreset(unit) {
    return unitSeconds(unit) >= 3600 ? "h,min" : "min,s"
}

function fieldsOf(preset) {
    for (var i = 0; i < PRESETS.length; i++) if (PRESETS[i] === preset) return preset.split(",")
    return ["min", "s"]
}

function fieldSeconds(f) { return f === "h" ? 3600 : (f === "min" ? 60 : 1) }

function trimNumber(x, places) {
    var k = Math.pow(10, places)
    return String(Math.round(x * k) / k)
}

// A value in its unit, spread over the fields. The largest field takes as
// much as it can; the smallest takes what is left, with a decimal if it must.
// { h: "7", min: "30", s: "" } -- a field that comes to nothing is empty.
function split(value, unit, fields) {
    var out = { h: "", min: "", s: "" }
    var f = unitSeconds(unit)
    if (f <= 0 || value === undefined || value === null || value === "") return out
    var v = Number(value)
    if (isNaN(v)) return out
    var rest = Math.round(v * f)
    if (rest === 0) { out[fields[0]] = "0"; return out }
    for (var i = 0; i < fields.length; i++) {
        var fs = fieldSeconds(fields[i])
        if (i === fields.length - 1) {
            var last = rest / fs
            if (last > 0) out[fields[i]] = trimNumber(last, fs === 1 ? 1 : 2)
        } else {
            var whole = Math.floor(rest / fs)
            if (whole > 0) out[fields[i]] = String(whole)
            rest -= whole * fs
        }
    }
    return out
}

// What was written in the fields, as a value in the unit. "" when nothing was.
function join(parts, unit, fields) {
    if (!fields || !parts) return ""
    var f = unitSeconds(unit)
    if (f <= 0) return ""
    var total = 0, any = false
    for (var i = 0; i < fields.length; i++) {
        var raw = parts[fields[i]]
        if (raw === undefined || raw === null) continue
        var t = String(raw).trim().replace(",", ".")
        if (t === "") continue
        var n = parseFloat(t)
        if (isNaN(n)) continue
        any = true
        total += n * fieldSeconds(fields[i])
    }
    if (!any) return ""
    return String(Math.round(total / f * 1000000) / 1000000)
}
