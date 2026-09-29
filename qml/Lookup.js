// Fiat Mos -- looking a book up by its ISBN
//
// Pure functions only: what an ISBN is, which services exist, where to ask
// each of them, and how to read the answer. The asking itself (XMLHttpRequest)
// happens in components/LookupRunner.qml, and the cover download in C++
// (CoverStore), because QML cannot write a binary file.
//
// Five services can be asked, and every one of them is the user's choice
// (LookupSettings.qml). A service that is switched off is never contacted:
// not for the book, and not for its cover either.
//
//   Open Library   Run by the Internet Archive. Title, authors, pages, cover.
//   Libris         The Swedish national library. Title and author only.
//   DNB            The German national library. Title, author, pages.
//   BnF            The French national library. Title, author, pages.
//   Google Books   Title, authors, pages, cover. Off unless switched on.
//
// The order is: Open Library, then the library of the ISBN's own language
// area, then the other libraries, and Google last. It stops as soon as it has
// a title, an author and a length; anything still missing is asked of the
// next service, and what is already found is never overwritten.
//
// Every answer is checked against the ISBN that was asked for. A service that
// answers with some other book, or with a page of unrelated results, is
// treated as not knowing the ISBN. Nothing but the ISBN is ever sent.
//
// ES5 only: this runs on whatever QML engine the phone has.

.pragma library

// The services, in the order they are listed to the user. `on` is what the
// switch shows before the user has chosen anything -- Google is the one that
// starts off.
var SERVICES = [
    { id: "openlibrary", name: "Open Library", on: true },
    { id: "libris", name: "Libris", on: true },
    { id: "dnb", name: "DNB", on: true },
    { id: "bnf", name: "BnF", on: true },
    { id: "google", name: "Google Books", on: false }
]

function serviceName(id) {
    for (var i = 0; i < SERVICES.length; i++) {
        if (SERVICES[i].id === id) return SERVICES[i].name
    }
    return String(id)
}

function has(list, id) {
    if (!list) return false
    for (var i = 0; i < list.length; i++) {
        if (list[i] === id) return true
    }
    return false
}

// ---- ISBNs -------------------------------------------------------------------

// An ISBN in, one canonical 13-digit key out, or "" when it is not an ISBN.
//
// Hyphens and spaces are ignored, and an ISBN-10 is converted, so the same
// book always ends up under the same key -- which matters, because the key is
// also the name of its cover file.
function normaliseIsbn(text) {
    var s = String(text === undefined || text === null ? "" : text).toUpperCase().replace(/[^0-9X]/g, "")
    if (s.length === 10) {
        if (!/^[0-9]{9}[0-9X]$/.test(s)) return ""
        var sum = 0
        for (var i = 0; i < 10; i++) sum += (10 - i) * (s.charAt(i) === "X" ? 10 : parseInt(s.charAt(i), 10))
        if (sum % 11 !== 0) return ""
        return withCheckDigit("978" + s.substr(0, 9))
    }
    if (s.length === 13) {
        if (!/^97[89][0-9]{10}$/.test(s)) return ""
        return withCheckDigit(s.substr(0, 12)) === s ? s : ""
    }
    return ""
}

function withCheckDigit(twelve) {
    var sum = 0
    for (var i = 0; i < 12; i++) sum += parseInt(twelve.charAt(i), 10) * (i % 2 === 0 ? 1 : 3)
    return twelve + ((10 - sum % 10) % 10)
}

// The ten-digit form of a 978 ISBN, or "" for one that has none. The French
// national library only knows books from before 2007 under this form.
function toIsbn10(isbn13) {
    var s = String(isbn13)
    if (!/^978[0-9]{10}$/.test(s)) return ""
    var nine = s.substr(3, 9)
    var sum = 0
    for (var i = 0; i < 9; i++) sum += (10 - i) * parseInt(nine.charAt(i), 10)
    var c = (11 - sum % 11) % 11
    return nine + (c === 10 ? "X" : String(c))
}

// Which language area registered the ISBN: "se", "de", "fr", "ru", or "".
// Only used to decide which national library to ask first.
function registrationGroup(isbn) {
    var s = String(isbn)
    if (s.substr(0, 3) === "979") return s.substr(3, 2) === "10" ? "fr" : ""
    if (s.substr(3, 2) === "91") return "se"
    var g = s.charAt(3)
    if (g === "3") return "de"
    if (g === "2") return "fr"
    if (g === "5") return "ru"
    return ""
}

// The national libraries, the ISBN's own first.
function libraryOrder(isbn) {
    var base = ["libris", "dnb", "bnf"]
    var group = registrationGroup(isbn)
    var first = group === "se" ? "libris" : group === "de" ? "dnb" : group === "fr" ? "bnf" : ""
    if (first === "") return base
    var out = [first]
    for (var i = 0; i < base.length; i++) {
        if (base[i] !== first) out.push(base[i])
    }
    return out
}

// ---- Where to ask ------------------------------------------------------------

function openLibraryUrls(isbn) {
    // The bare path is the documented one and is reported to answer 404 since
    // late September; the .json path is reported to work. Both are tried.
    return [
        "https://openlibrary.org/api/books?bibkeys=ISBN:" + isbn + "&jscmd=data&format=json",
        "https://openlibrary.org/api/books.json?bibkeys=ISBN:" + isbn + "&jscmd=data"
    ]
}

function openLibraryUrl(isbn) {
    return openLibraryUrls(isbn)[0]
}

function openLibraryCoverUrl(isbn) {
    return "https://covers.openlibrary.org/b/isbn/" + isbn + "-M.jpg?default=false"
}

function librisUrl(isbn) {
    return "https://libris.kb.se/xsearch?query=isbn:" + isbn + "&format=json"
}

// The German index for numbers is not something the documentation states
// plainly, so two spellings are tried. A wrong one answers with results that
// are not about this ISBN, and the check on the ISBN throws those away.
function dnbUrls(isbn) {
    var base = "https://services.dnb.de/sru/dnb?version=1.1&operation=searchRetrieve&recordSchema=MARC21-xml&maximumRecords=3&query="
    return [base + "isbn%3D" + isbn, base + "num%3D" + isbn]
}

// Records made before 2007 carry only the ten-digit ISBN, so both are asked.
function bnfUrls(isbn) {
    var base = "https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&recordSchema=unimarcxchange&maximumRecords=3&query="
    var urls = [base + "bib.isbn%20adj%20%22" + isbn + "%22"]
    var ten = toIsbn10(isbn)
    if (ten !== "") urls.push(base + "bib.isbn%20adj%20%22" + ten + "%22")
    return urls
}

// Asked without an account or a key.
function googleUrl(isbn) {
    return "https://www.googleapis.com/books/v1/volumes?q=isbn:" + isbn + "&maxResults=3&printType=books"
}

function urlsFor(service, isbn) {
    if (service === "openlibrary") return openLibraryUrls(isbn)
    if (service === "libris") return [librisUrl(isbn)]
    if (service === "dnb") return dnbUrls(isbn)
    if (service === "bnf") return bnfUrls(isbn)
    if (service === "google") return [googleUrl(isbn)]
    return []
}

// What to ask, in order: [{ service, urls }]. Only services in `enabled` appear.
// Each service's urls are alternatives for the same question; the next one is
// used only when the one before found nothing.
function plan(isbn, enabled) {
    var order = ["openlibrary"].concat(libraryOrder(isbn)).concat(["google"])
    var steps = []
    for (var i = 0; i < order.length; i++) {
        if (has(enabled, order[i])) steps.push({ service: order[i], urls: urlsFor(order[i], isbn) })
    }
    return steps
}

// ---- Reading the answers -----------------------------------------------------
//
// Each parser gives { title, creator, extent, cover, source, service }, or null.
// extent is 0 when the service does not say; cover is "" when there is none.

function parseOpenLibrary(text, isbn) {
    var data
    try { data = JSON.parse(text) } catch (e) { return null }
    if (data === null || typeof data !== "object") return null
    var rec = data["ISBN:" + isbn]
    if (rec === undefined || rec === null || !rec.title) return null

    var names = []
    var authors = rec.authors || []
    for (var i = 0; i < authors.length; i++) {
        if (authors[i] && authors[i].name) names.push(String(authors[i].name).trim())
    }
    var pages = Number(rec.number_of_pages)
    var cover = rec.cover ? (rec.cover.medium || rec.cover.large || rec.cover.small || "") : ""

    return {
        title: String(rec.title).trim(),
        creator: names.join(", "),
        extent: (isNaN(pages) || pages <= 0) ? 0 : pages,
        cover: String(cover),
        source: "Open Library",
        service: "openlibrary"
    }
}

// Libris writes a name the way a catalogue card does: "Söderberg, Hjalmar,
// 1869-1941". Turned round, and the dates dropped. The same card style is used
// by the German and (for the surname) French records.
function librisName(s) {
    var parts = String(s === undefined || s === null ? "" : s).split(",")
    var keep = []
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].trim()
        if (p !== "" && !/^[0-9]/.test(p)) keep.push(p)
    }
    if (keep.length >= 2) return keep[1] + " " + keep[0]
    return keep.length === 1 ? keep[0] : ""
}

// A Libris title can carry its statement of responsibility after a slash:
// "Doktor Glas / Hjalmar Söderberg". The author already has a field.
function librisTitle(s) {
    var t = String(s === undefined || s === null ? "" : s)
    var slash = t.indexOf(" / ")
    return (slash >= 0 ? t.substr(0, slash) : t).trim()
}

function parseLibris(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { return null }
    if (data === null || typeof data !== "object" || !data.xsearch) return null
    var list = data.xsearch.list || []
    if (list.length === 0 || !list[0].title) return null
    var rec = list[0]
    var creator = rec.creator
    if (creator !== undefined && creator !== null && typeof creator === "object" && creator.length !== undefined) {
        creator = creator.length > 0 ? creator[0] : ""
    }
    return {
        title: librisTitle(rec.title),
        creator: librisName(creator),
        extent: 0,
        cover: "",
        source: "Libris",
        service: "libris"
    }
}

// ---- MARC, for the German and French libraries ---------------------------------
//
// Both answer with MARC records wrapped in SRU. A small reader is enough, and
// it is a regular expression rather than a DOM because it has to run the same
// under the QML engine and under the tests, and because a record that is not
// quite well formed should still give up what it has.

function xmlDecode(s) {
    return String(s)
        .replace(/&#x([0-9a-fA-F]+);/g, function(m, h) { return String.fromCharCode(parseInt(h, 16)) })
        .replace(/&#([0-9]+);/g, function(m, d) { return String.fromCharCode(parseInt(d, 10)) })
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'")
        .replace(/&amp;/g, "&")
}

// One chunk of text per record. The MARC record sits inside SRU's recordData,
// and the chunks before the first one are the envelope.
function marcRecords(text) {
    var parts = String(text).split(/<(?:[A-Za-z0-9_]+:)?recordData[\s>]/)
    if (parts.length < 2) return []
    return parts.slice(1)
}

// Every datafield with this tag, each as a list of { code, value }.
function marcFields(record, tag) {
    var out = []
    var fieldRe = new RegExp("<(?:[A-Za-z0-9_]+:)?datafield\\b[^>]*\\btag=[\"']" + tag + "[\"'][^>]*>([\\s\\S]*?)</(?:[A-Za-z0-9_]+:)?datafield>", "g")
    var subRe = /<(?:[A-Za-z0-9_]+:)?subfield\b[^>]*\bcode=["'](.)["'][^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_]+:)?subfield>/g
    var m
    while ((m = fieldRe.exec(record)) !== null) {
        var subs = []
        var s
        subRe.lastIndex = 0
        while ((s = subRe.exec(m[1])) !== null) subs.push({ code: s[1], value: xmlDecode(s[2]) })
        out.push(subs)
    }
    return out
}

function marcSub(field, code) {
    for (var i = 0; i < field.length; i++) {
        if (field[i].code === code) return field[i].value
    }
    return ""
}

// Non-sorting markers ("¬Der¬ Prozess") and the punctuation cataloguing rules
// leave at the end of a field ("Title :").
function tidyMarc(s) {
    return String(s)
        .replace(/[¬\u0088\u0089\u0098\u009C]/g, "")
        .replace(/\s+/g, " ")
        .replace(/[\s\/:;=,]+$/, "")
        .replace(/^\s+/, "")
}

// Does any of these ISBN subfields hold the ISBN that was asked for? The value
// may be hyphenated, may be a ten-digit ISBN, and may be followed by a price.
function marcHasIsbn(record, tag, codes, isbn) {
    var fields = marcFields(record, tag)
    for (var i = 0; i < fields.length; i++) {
        for (var j = 0; j < fields[i].length; j++) {
            if (codes.indexOf(fields[i][j].code) < 0) continue
            var m = String(fields[i][j].value).match(/[0-9][0-9\- ]{8,}[0-9Xx]/)
            if (m !== null && normaliseIsbn(m[0]) === isbn) return true
        }
    }
    return false
}

// "160 Seiten", "XII, 384 Seiten : Illustrationen", "1 vol. (159 p.)": the
// biggest number that sits next to a word for pages. 0 when there is none
// ("1 Band (unpaginiert)").
function pagesFrom(text) {
    var re = /([0-9]+)\s*(?:Seiten|Seite|S\.|Bl\.|Blätter|pages|page|pp\.|p\.|feuillets|f\.|ff\.)/gi
    var best = 0
    var m
    while ((m = re.exec(String(text))) !== null) {
        var n = parseInt(m[1], 10)
        if (n > best) best = n
    }
    return best
}

function parseDnb(text, isbn) {
    var recs = marcRecords(text)
    for (var r = 0; r < recs.length; r++) {
        var rec = recs[r]
        if (!marcHasIsbn(rec, "020", ["a", "9"], isbn)) continue
        var t = marcFields(rec, "245")
        var title = t.length > 0 ? tidyMarc(marcSub(t[0], "a")) : ""
        if (title === "") continue
        var a = marcFields(rec, "100")
        if (a.length === 0) a = marcFields(rec, "700")
        var creator = a.length > 0 ? librisName(tidyMarc(marcSub(a[0], "a"))) : ""
        var p = marcFields(rec, "300")
        return {
            title: title,
            creator: creator,
            extent: p.length > 0 ? pagesFrom(marcSub(p[0], "a")) : 0,
            cover: "",
            source: "DNB",
            service: "dnb"
        }
    }
    return null
}

// UNIMARC, which is what the French library speaks by default: the title is in
// 200, the author in 700 as surname ($a) and forename ($b), the ISBN in 010 and
// the extent in 215.
function parseBnf(text, isbn) {
    var recs = marcRecords(text)
    for (var r = 0; r < recs.length; r++) {
        var rec = recs[r]
        if (!marcHasIsbn(rec, "010", ["a"], isbn)) continue
        var t = marcFields(rec, "200")
        var title = t.length > 0 ? tidyMarc(marcSub(t[0], "a")) : ""
        if (title === "") continue
        var a = marcFields(rec, "700")
        if (a.length === 0) a = marcFields(rec, "701")
        var creator = ""
        if (a.length > 0) {
            var surname = tidyMarc(marcSub(a[0], "a"))
            var forename = tidyMarc(marcSub(a[0], "b"))
            creator = forename !== "" ? (surname !== "" ? forename + " " + surname : forename) : surname
        }
        var p = marcFields(rec, "215")
        return {
            title: title,
            creator: creator,
            extent: p.length > 0 ? pagesFrom(marcSub(p[0], "a")) : 0,
            cover: "",
            source: "BnF",
            service: "bnf"
        }
    }
    return null
}

// Google answers with a list; the first volume that really carries this ISBN
// is the one. A volume with no identifiers at all is not trusted.
function googleHasIsbn(ids, isbn) {
    if (!ids) return false
    for (var i = 0; i < ids.length; i++) {
        if (ids[i] && ids[i].identifier && normaliseIsbn(ids[i].identifier) === isbn) return true
    }
    return false
}

function parseGoogle(text, isbn) {
    var data
    try { data = JSON.parse(text) } catch (e) { return null }
    if (data === null || typeof data !== "object") return null
    var items = data.items || []
    for (var i = 0; i < items.length; i++) {
        var v = items[i] ? items[i].volumeInfo : null
        if (!v || !v.title || !googleHasIsbn(v.industryIdentifiers, isbn)) continue
        var pages = Number(v.pageCount)
        var links = v.imageLinks || {}
        var cover = String(links.thumbnail || links.smallThumbnail || "")
        // Google hands out http links. Only https is ever fetched, and the
        // page-curl effect is not wanted on a spine-side thumbnail.
        cover = cover.replace(/^http:/, "https:").replace(/&edge=curl/, "")
        var authors = v.authors || []
        var names = []
        for (var a = 0; a < authors.length; a++) {
            if (authors[a]) names.push(String(authors[a]).trim())
        }
        return {
            title: String(v.title).trim(),
            creator: names.join(", "),
            extent: (isNaN(pages) || pages <= 0) ? 0 : pages,
            cover: cover,
            source: "Google Books",
            service: "google"
        }
    }
    return null
}

function parseFor(service, text, isbn) {
    try {
        if (service === "openlibrary") return parseOpenLibrary(text, isbn)
        if (service === "libris") return parseLibris(text)
        if (service === "dnb") return parseDnb(text, isbn)
        if (service === "bnf") return parseBnf(text, isbn)
        if (service === "google") return parseGoogle(text, isbn)
    } catch (e) {
        return null
    }
    return null
}

// ---- Putting answers together --------------------------------------------------

function emptyResult() {
    return {
        title: "", creator: "", extent: 0,
        from: { title: "", creator: "", extent: "" },
        covers: []
    }
}

// What one service found joins what is already there. Nothing that is already
// filled in is replaced, and each part remembers who supplied it.
function merge(result, found, service) {
    if (found === null || found === undefined) return result
    if (result.title === "" && found.title) { result.title = found.title; result.from.title = service }
    if (result.creator === "" && found.creator) { result.creator = found.creator; result.from.creator = service }
    if (!(result.extent > 0) && found.extent > 0) { result.extent = found.extent; result.from.extent = service }
    if (found.cover) result.covers.push({ service: service, url: found.cover })
    return result
}

// Enough that nothing more needs asking.
function complete(result) {
    return result.title !== "" && result.creator !== "" && result.extent > 0
}

// Where a cover might come from, in the order to try: covers the answers named,
// then Open Library's cover-by-ISBN if Open Library is on, and Google's if it
// is on and has not been asked yet. A candidate with `ask` still needs one
// request to Google to learn its cover address.
function coverCandidates(isbn, enabled, result, asked) {
    var out = []
    var seen = {}
    function add(c) {
        var key = c.service + "|" + (c.url || "ask")
        if (seen[key]) return
        seen[key] = true
        out.push(c)
    }
    var i
    if (result) {
        for (i = 0; i < result.covers.length; i++) {
            if (has(enabled, result.covers[i].service)) add(result.covers[i])
        }
    }
    if (has(enabled, "openlibrary")) add({ service: "openlibrary", url: openLibraryCoverUrl(isbn) })
    if (has(enabled, "google") && !has(asked, "google")) add({ service: "google", ask: true })
    return out
}

// How a service's turn ended, from what its requests came back with.
//   found      it knew the book
//   nothing    it answered, and did not know this ISBN
//   declined   it refused to answer (too many requests, or no key)
//   failed     no usable answer: offline, an error, or too slow
function outcomeOf(foundAny, saw200, declined) {
    if (foundAny) return "found"
    if (saw200) return "nothing"
    if (declined) return "declined"
    return "failed"
}

// Who supplied what, for the line under the ISBN field:
// [{ service, what: ["title", "creator"] }, ...] in order of first appearance,
// and the parts nobody supplied as `missing`.
function provenance(result, coverService) {
    var parts = [
        { what: "title", service: result.from.title },
        { what: "creator", service: result.from.creator },
        { what: "extent", service: result.from.extent },
        { what: "cover", service: coverService || "" }
    ]
    var groups = []
    var missing = []
    for (var i = 0; i < parts.length; i++) {
        if (parts[i].service === "") { missing.push(parts[i].what); continue }
        var g = null
        for (var j = 0; j < groups.length; j++) {
            if (groups[j].service === parts[i].service) g = groups[j]
        }
        if (g === null) { g = { service: parts[i].service, what: [] }; groups.push(g) }
        g.what.push(parts[i].what)
    }
    return { groups: groups, missing: missing }
}
