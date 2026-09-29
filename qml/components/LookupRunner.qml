import QtQuick 2.0
import se.munkstolen.fiatmos 1.0
import ".."
import "../Lookup.js" as Lookup

// Asks the lookup services about one ISBN, one after another, and keeps what
// they say together with who said it.
//
// Only services the user has switched on (LookupSettings) are ever asked, and
// the same goes for covers: a cover is fetched from a service only if that
// service is on. A service is asked only while something is still missing;
// once there is a title, an author and a length, nothing more is sent to
// anyone.
//
// Start it with lookUp() (the book, and then its cover) or fetchCover() (the
// cover alone). Nothing here runs unless a page calls one of them.

Item {
    id: root

    // "idle" | "busy" | "done"   (not called `state`: Item already has one)
    property string phase: "idle"
    property string isbn: ""

    // { title, creator, extent, from: {...}, covers: [...] } -- see Lookup.js
    property var result: Lookup.emptyResult()
    // [{ service, outcome }] in the order they were asked
    property var asked: []
    // Bumped whenever something above changes, for bindings that read them.
    property int gen: 0

    property string currentService: ""

    property bool coverBusy: false
    property string coverService: ""
    property int coverRevision: 0

    signal infoDone()
    signal coverDone(bool ok)

    // ---- what to tell the user ----------------------------------------------

    readonly property string busyText: {
        var _g = root.gen
        return root.currentService === "" ? ""
            : qsTr("Looking up… asking %1").arg(Lookup.serviceName(root.currentService))
    }

    readonly property string askedText: {
        var _g = root.gen
        if (root.asked.length === 0) return ""
        var parts = []
        for (var i = 0; i < root.asked.length; i++) {
            var n = Lookup.serviceName(root.asked[i].service)
            if (root.asked[i].outcome === "declined") n = qsTr("%1 (declined)").arg(n)
            else if (root.asked[i].outcome === "failed") n = qsTr("%1 (no answer)").arg(n)
            parts.push(n)
        }
        return qsTr("Asked: %1.").arg(parts.join(", "))
    }

    // Nobody answered at all: the phone is probably offline.
    readonly property bool offline: {
        var _g = root.gen
        if (root.asked.length === 0) return false
        for (var i = 0; i < root.asked.length; i++) {
            if (root.asked[i].outcome !== "failed") return false
        }
        return true
    }

    function whatWord(w) {
        if (w === "title") return qsTr("title")
        if (w === "creator") return qsTr("author")
        if (w === "extent") return qsTr("pages")
        return qsTr("cover")
    }

    function joinWords(words) {
        if (words.length === 1) return words[0]
        var init = words.slice(0, words.length - 1)
        return qsTr("%1 and %2").arg(init.join(", ")).arg(words[words.length - 1])
    }

    function capital(s) {
        return s.length === 0 ? s : s.charAt(0).toUpperCase() + s.substr(1)
    }

    // "Title and author: Libris · Pages: DNB · Cover: Open Library", and what
    // nobody had: "Not found: pages".
    readonly property string foundText: {
        var _g = root.gen
        if (root.result === null || root.result.title === "") return ""
        var p = Lookup.provenance(root.result, root.coverService)
        var groups = []
        var i
        for (i = 0; i < p.groups.length; i++) {
            var words = []
            for (var j = 0; j < p.groups[i].what.length; j++) words.push(root.whatWord(p.groups[i].what[j]))
            groups.push(root.capital(root.joinWords(words)) + ": " + Lookup.serviceName(p.groups[i].service))
        }
        var missing = []
        for (i = 0; i < p.missing.length; i++) {
            // A cover that is still on its way is not missing, and one that
            // was never asked for (the item already had a picture) is not either.
            if (p.missing[i] === "cover" && (root.coverBusy || !root._wantCover)) continue
            missing.push(root.whatWord(p.missing[i]))
        }
        var text = groups.join(" · ")
        if (missing.length > 0) text += (text === "" ? "" : " · ") + qsTr("Not found: %1").arg(missing.join(", "))
        return text
    }

    // ---- private state ---------------------------------------------------------

    property var _steps: []
    property int _si: 0
    property int _ui: 0
    property bool _saw200: false
    property bool _declined: false
    property bool _foundThis: false
    property bool _wantCover: false
    // Every run gets a number, so a slow answer to an old one is ignored.
    property int _token: 0
    property var _askedList: []
    property var _enabled: []
    property var _cands: []
    property int _ci: 0
    property string _coverCurrent: ""

    // ---- starting and stopping -------------------------------------------------

    function cancel() {
        root._token++
        guard.stop()
        coverGuard.stop()
        root.coverBusy = false
        root.currentService = ""
        root.phase = "idle"
        root.gen++
    }

    function _begin(isbn, wantCover) {
        root.cancel()
        root.isbn = isbn
        root._enabled = LookupSettings.enabledIds()
        root.result = Lookup.emptyResult()
        root._askedList = []
        root.asked = []
        root.coverService = ""
        root._wantCover = wantCover
        root._si = 0
        root._ui = 0
        root._saw200 = false
        root._declined = false
        root._foundThis = false
    }

    // The book, and then -- if asked for -- its cover.
    function lookUp(isbn, wantCover) {
        root._begin(isbn, wantCover)
        root._steps = Lookup.plan(isbn, root._enabled)
        root.phase = "busy"
        root.gen++
        root._request()
    }

    // The cover alone, for a book already in the library.
    function fetchCover(isbn) {
        root._begin(isbn, true)
        root._steps = []
        root.phase = "done"
        root.gen++
        root._startCover()
    }

    // ---- the book -----------------------------------------------------------------

    function _get(url, done) {
        var token = root._token
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            // The answer can arrive after the page is gone, and then `root` is null.
            if (!root || token !== root._token) return
            done(xhr.status, xhr.responseText)
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function _request() {
        if (root._si >= root._steps.length || Lookup.complete(root.result)) {
            root._infoDone()
            return
        }
        var step = root._steps[root._si]
        root.currentService = step.service
        root.gen++
        guard.restart()
        root._get(step.urls[root._ui], function(status, text) {
            guard.stop()
            root._answer(status, text)
        })
    }

    function _answer(status, text) {
        var step = root._steps[root._si]
        var found = status === 200 ? Lookup.parseFor(step.service, text, root.isbn) : null
        if (status === 200) root._saw200 = true
        if (status === 429 || status === 403) root._declined = true
        if (found !== null) {
            Lookup.merge(root.result, found, step.service)
            root._foundThis = true
            root._closeStep()
        } else if (root._ui + 1 < step.urls.length) {
            root._ui++
            root._request()
        } else {
            root._closeStep()
        }
    }

    function _closeStep() {
        var step = root._steps[root._si]
        root._askedList.push({ service: step.service,
                               outcome: Lookup.outcomeOf(root._foundThis, root._saw200, root._declined) })
        root._si++
        root._ui = 0
        root._saw200 = false
        root._declined = false
        root._foundThis = false
        root._request()
    }

    function _infoDone() {
        guard.stop()
        root.currentService = ""
        root.asked = root._askedList.slice(0)
        root.phase = "done"
        root.gen++
        root.infoDone()
        // Asked for even when the answer had no picture: Open Library often has
        // a cover for a book another service knew and it did not. Nothing is
        // fetched for a book nobody knew.
        if (root._wantCover && root.result.title !== "") root._startCover()
    }

    // ---- the cover ------------------------------------------------------------------

    function _noteAsked(service, outcome) {
        var found = false
        for (var i = 0; i < root._askedList.length; i++) {
            if (root._askedList[i].service !== service) continue
            found = true
            // A service that could not give the book but did give the cover
            // did answer.
            if (outcome === "found" && root._askedList[i].outcome !== "found") root._askedList[i].outcome = "nothing"
            else if (outcome === "declined" && root._askedList[i].outcome === "failed") root._askedList[i].outcome = "declined"
        }
        if (!found) root._askedList.push({ service: service, outcome: outcome === "found" ? "nothing" : outcome })
        root.asked = root._askedList.slice(0)
        root.gen++
    }

    function _askedIds() {
        var ids = []
        for (var i = 0; i < root._askedList.length; i++) ids.push(root._askedList[i].service)
        return ids
    }

    function _startCover() {
        root._cands = Lookup.coverCandidates(root.isbn, root._enabled, root.result, root._askedIds())
        root._ci = 0
        if (root._cands.length === 0) {
            root.coverDone(false)
            return
        }
        root.coverBusy = true
        root.gen++
        root._coverNext()
    }

    function _coverEnd(ok) {
        coverGuard.stop()
        root.coverBusy = false
        root.gen++
        root.coverDone(ok)
    }

    function _coverNext() {
        if (root._ci >= root._cands.length) {
            root._coverEnd(false)
            return
        }
        var c = root._cands[root._ci]
        root._coverCurrent = c.service
        coverGuard.restart()
        if (c.url) {
            store.fetch(root.isbn, c.url)
            return
        }
        // Google has to be asked for the address of its cover.
        root._get(Lookup.googleUrl(root.isbn), function(status, text) {
            coverGuard.stop()
            var found = status === 200 ? Lookup.parseFor("google", text, root.isbn) : null
            root._noteAsked("google", found !== null ? "found" : status === 200 ? "nothing"
                                     : (status === 429 || status === 403) ? "declined" : "failed")
            if (found !== null && found.cover !== "") {
                coverGuard.restart()
                store.fetch(root.isbn, found.cover)
            } else {
                root._ci++
                root._coverNext()
            }
        })
    }

    function _fetched(isbn, ok) {
        if (isbn !== root.isbn) return
        coverGuard.stop()
        if (ok) {
            root._noteAsked(root._coverCurrent, "found")
            root.coverService = root._coverCurrent
            root.coverRevision++
            root.coverBusy = false
            root.gen++
            // Also when it arrives after the wait gave up: it is still a cover.
            root.coverDone(true)
            return
        }
        if (!root.coverBusy) return
        root._noteAsked(root._coverCurrent, "nothing")
        root._ci++
        root._coverNext()
    }

    CoverStore {
        id: store
        onFetched: root._fetched(isbn, ok)
    }

    // A request that never comes back must not hold the page: after this long
    // that service counts as not answering, and the next one is asked.
    Timer {
        id: guard
        interval: 12000
        onTriggered: {
            root._token++
            root._answer(0, "")
        }
    }

    Timer {
        id: coverGuard
        interval: 15000
        onTriggered: {
            root._token++
            root._coverEnd(false)
        }
    }
}
