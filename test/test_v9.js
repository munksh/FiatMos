// Fiat Mos 1.2: yesterday, the library's statistics, and ISBN lookups.
const { S, L, sqlite, mkModel } = require('./harness')
let fails = 0
function ok(name, cond, extra) {
  if (!cond) { fails++; console.log('FAIL ' + name + (extra !== undefined ? '  -> ' + JSON.stringify(extra) : '')) }
  else console.log('ok   ' + name)
}
const onDay = n => S.dayKey(S.addDays(new Date(), n))
const at = (n, h, m) => onDay(n) + 'T' + String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0') + ':00'
// Test-only: pretend a habit was made a while ago. The app never does this.
const bornDaysAgo = (id, n) => sqlite.prepare("UPDATE habit SET created_at = datetime('now', ?) WHERE id = ?").run('-' + n + ' days', id)

S.init()
const v = S.currentVersion()
ok('schema reaches the newest migration', v >= 9, v)
const cols = sqlite.prepare('PRAGMA table_info(item)').all().map(c => c.name)
ok('item has extent', cols.includes('extent'), cols)
ok('item has isbn', cols.includes('isbn'), cols)

// --- dates ----------------------------------------------------------------
ok('loggedAtFor today is now', S.loggedAtFor(onDay(0)).substr(0, 10) === onDay(0), S.loggedAtFor(onDay(0)))
ok('loggedAtFor with nothing is now', S.loggedAtFor().substr(0, 10) === onDay(0))
ok('loggedAtFor yesterday is one minute to midnight', S.loggedAtFor(onDay(-1)) === onDay(-1) + 'T23:59:00', S.loggedAtFor(onDay(-1)))
ok('createdDay reads a local ISO string', S.createdDay('2026-03-04T10:00:00') === '2026-03-04')
const utcNow = sqlite.prepare("SELECT datetime('now') AS d").get().d
ok('createdDay reads SQLite UTC as the local day', S.createdDay(utcNow) === onDay(0), [utcNow, S.createdDay(utcNow)])
ok('createdDay of nothing is empty', S.createdDay(null) === '')

// --- logging yesterday ------------------------------------------------------
const flossId = S.addHabit({ name: 'Floss', valueType: 'boolean', frequency: 'daily' })
const floss = S.getHabit(flossId)
S.addEntry(floss, { loggedAt: at(-2, 21, 0) })
S.addEntry(floss, { loggedAt: at(-3, 21, 0) })
ok('a missed yesterday means no streak', S.streak(floss) === 0, S.streak(floss))
S.addEntry(floss, { loggedAt: S.loggedAtFor(onDay(-1)) })
ok('logging yesterday this morning rescues it', S.streak(floss) === 3, S.streak(floss))
ok('and today is still open', S.todayProgress(floss).logged === false)

const m = mkModel()
S.loadEntriesForDay(m, flossId, onDay(-1))
ok('yesterday shows one entry', m.count === 1, m.count)
ok('which is marked as written later', m[0].late === true, m[0])
S.addEntry(floss, {})
S.loadEntriesForDay(m, flossId, onDay(0))
ok("today's entry is not late", m[0].late === false, m[0])

// --- leftovers --------------------------------------------------------------
const organId = S.addHabit({ name: 'Organ', valueType: 'numeric', unit: 'min', dailyTarget: 30, frequency: 'daily' })
const rehabId = S.addHabit({ name: 'Rehab', valueType: 'boolean', frequency: 'daily' })
const gymId = S.addHabit({ name: 'Gym', valueType: 'boolean', frequency: 'weekly_n', frequencyN: 3 })
const oldId = S.addHabit({ name: 'Dropped', valueType: 'boolean', frequency: 'daily' })
const newId = S.addHabit({ name: 'Brand new', valueType: 'boolean', frequency: 'daily' })
for (const id of [flossId, organId, rehabId, gymId, oldId]) bornDaysAgo(id, 10)
S.archiveHabit(oldId)
S.addEntry(S.getHabit(organId), { numeric: 10, loggedAt: at(-1, 8, 0) })

let left = S.yesterdayLeftovers().map(x => x.habit.name)
ok('an unlogged daily habit is left over', left.includes('Rehab'), left)
ok('a counted one that fell short is left over', left.includes('Organ'), left)
ok('one that was done is not', !left.includes('Floss'), left)
ok('a weekly habit is not (it is still due today)', !left.includes('Gym'), left)
ok('an archived habit is not', !left.includes('Dropped'), left)
ok('a habit made today is not', !left.includes('Brand new'), left)

S.loadLeftovers(m)
const organRow = m.find(r => r.name === 'Organ')
ok('the leftover row carries yesterday\'s progress', organRow && Math.abs(organRow.fraction - 1 / 3) < 1e-9 && organRow.done === 10, organRow)

S.addEntry(S.getHabit(organId), { numeric: 20, loggedAt: S.loggedAtFor(onDay(-1)) })
left = S.yesterdayLeftovers().map(x => x.habit.name)
ok('finishing it for yesterday clears it', !left.includes('Organ'), left)

// --- sessions for yesterday -------------------------------------------------
const liftId = S.addHabit({ name: 'Lift', valueType: 'structured', detailProfile: 'strength', frequency: 'daily' })
const lift = S.getHabit(liftId)
S.saveSession(lift, null, [{ name: 'Squat', details: [{ reps: 5, weight: 80 }] }], '', onDay(-1))
const yS = S.sessionForDay(liftId, onDay(-1))
ok('a session can be saved to yesterday', yS !== null && yS.components.length === 1, yS)
ok('with its entry on yesterday', S.entriesOnDay(liftId, onDay(-1)).length === 1)
ok('and nothing on today', S.todaysSession(liftId) === null && S.entriesOnDay(liftId, onDay(0)).length === 0)
S.saveSession(lift, null, [{ name: 'Squat', details: [{ reps: 5, weight: 80 }, { reps: 5, weight: 85 }] }], '', onDay(-1))
ok('saving yesterday again rewrites the same session',
   sqlite.prepare('SELECT COUNT(*) c FROM session WHERE habit_id = ?').get(liftId).c === 1
   && S.sessionForDay(liftId, onDay(-1)).components[0].details.length === 2)
ok('still one entry for yesterday', S.entriesOnDay(liftId, onDay(-1)).length === 1)
S.saveSession(lift, null, [{ name: 'Bench', details: [{ reps: 8, weight: 60 }] }], '')
ok("today's session is separate", sqlite.prepare('SELECT COUNT(*) c FROM session WHERE habit_id = ?').get(liftId).c === 2)

// --- items: extent and isbn -------------------------------------------------
const bookKind = S.addKind('book', 'pages')
const readId = S.addHabit({ name: 'Reading', valueType: 'reference', frequency: 'daily', kindId: bookKind })
const reading = S.getHabit(readId)
const hadrian = S.addItem({ title: 'Hadrianus memoarer', creator: 'Marguerite Yourcenar', kindId: bookKind, extent: 330, isbn: '9789100123456' })
const stoner = S.addItem({ title: 'Stoner', creator: 'John Williams', kindId: bookKind, extent: '' })
const secret = S.addItem({ title: 'Ritual notes', kindId: bookKind, private: true })
ok('extent is stored', S.itemById(hadrian).extent === 330, S.itemById(hadrian))
ok('isbn is stored', S.itemById(hadrian).isbn === '9789100123456')
ok('an empty extent means unknown', S.itemById(stoner).extent === 0, S.itemById(stoner).extent)
ok('a nonsense extent means unknown', S.cleanExtent('abc') === null && S.cleanExtent(-5) === null && S.cleanExtent('12') === 12)
S.updateItem({ id: stoner, title: 'Stoner', creator: 'John Williams', kindId: bookKind, private: false, extent: 288, isbn: '' })
ok('updating sets the extent', S.itemById(stoner).extent === 288)
ok('and an empty isbn stays empty', S.itemById(stoner).isbn === '')

// Reading: Hadrian over three days (two entries on one of them), Stoner once,
// the private item once, and one Hadrian entry long before the window.
S.addReferenceEntry(reading, hadrian, 20, '', onDay(-1))
const e1 = S.addReferenceEntry(reading, hadrian, 12, '')
S.addReferenceEntry(reading, hadrian, 8, '')
S.addReferenceEntry(reading, stoner, 40, '')
S.addReferenceEntry(reading, secret, 5, '')
const longAgo = S.addEntry(reading, { numeric: 100, loggedAt: at(-200, 20, 0) })
sqlite.prepare('INSERT INTO log_entry_item (log_entry_id, item_id) VALUES (?, ?)').run(longAgo, hadrian)
const undone = S.addReferenceEntry(reading, stoner, 999, '')
S.voidEntry(readId, undone)

ok('itemTotal is everything, ever, minus undone', S.itemTotal(hadrian) === 140 && S.itemTotal(stoner) === 40, [S.itemTotal(hadrian), S.itemTotal(stoner)])

let ks = S.kindStats(bookKind, 30, false)
ok('kind stats: total inside the window', ks.total === 80, ks.total)
ok('kind stats: days with anything', ks.days === 2, ks.days)
ok('kind stats: two public items', ks.itemCount === 2, ks.items.map(i => i.title))
ok('kind stats: one private item left out, and counted', ks.hiddenPrivate === 1, ks.hiddenPrivate)
ok('kind stats: series is one value per day of the window', ks.series.length === 30 && ks.series[29].day === onDay(0))
const h = ks.items.find(i => i.id === hadrian)
ok('an item: total in the window, soFar across all time', h.total === 40 && h.soFar === 140, h)
ok('an item: days are days, not entries', h.days === 2, h.days)
ks = S.kindStats(bookKind, 30, true)
ok('including private brings it back', ks.total === 85 && ks.hiddenPrivate === 0, [ks.total, ks.hiddenPrivate])
S.setItemState(stoner, 'completed')
ok('finishing inside the window is counted', S.kindStats(bookKind, 30, false).finished === 1)

const is = S.itemStats(hadrian)
ok('item stats: sittings are days', is.days === 3 && is.sittings.map(s => s.value).join() === '100,20,20', is.sittings)
ok('item stats: total', is.total === 140, is.total)
ok('item stats: median of counted sittings', is.median === 20, is.median)
ok('item stats: best', is.best === 100)
ok('item stats: fraction of the extent', Math.abs(is.fraction - 140 / 330) < 1e-9, is.fraction)
ok('item stats: left and an estimate', is.left === 190 && is.estimate === 10, [is.left, is.estimate])
const unknown = S.itemStats(secret)
ok('without an extent there is no fraction or estimate', unknown.fraction === null && unknown.estimate === null && unknown.left === null)

// --- the calendar -------------------------------------------------------------
const series = [
  { day: '2026-02-27', value: 5 }, { day: '2026-02-28', value: 5 },
  { day: '2026-03-01', value: 10 }, { day: '2026-03-02', value: null },
  { day: '2026-03-03', value: 1 }, { day: '2026-03-04', value: 1 }, { day: '2026-03-05', value: 1 }, { day: '2026-03-06', value: 1 }
]
let f = S.calendarFacts(series, false)
ok('longest run crosses a month end', f.longestRun === 4, f)
ok('best month by sum', f.bestMonth === '2026-03' && f.bestMonthValue === 14, f)
f = S.calendarFacts(series, true)
ok('best month by days for ticks', f.bestMonth === '2026-03' && f.bestMonthValue === 5, f)
ok('an empty series has no facts', S.calendarFacts([], false).longestRun === 0 && S.calendarFacts([], false).bestMonth === '')

const wk = S.weeklyBuckets([{ day: '2026-09-24', value: 3 }, { day: '2026-09-27', value: 4 }, { day: '2026-09-28', value: null }, { day: '2026-09-29', value: 2 }])
ok('weeks start on Monday', wk[0].start === '2026-09-21' && wk[1].start === '2026-09-28', wk)
ok('weeks add up', wk[0].value === 7 && wk[1].value === 2, wk)
const wd = S.weekdayTotals([{ day: '2026-09-28', value: 3 }, { day: '2026-10-04', value: 2 }, { day: '2026-10-05', value: 1 }])
ok('weekday totals, Monday first', wd[0] === 4 && wd[6] === 2, wd)
ok('median of an even list', S.medianOf([4, 1, 3, 2]) === 2.5)

// --- export and import keep extent and isbn --------------------------------------
const dump = S.exportAll()
const hx = dump.items.find(i => i.title === 'Hadrianus memoarer')
ok('export carries extent and isbn', hx.extent === 330 && hx.isbn === '9789100123456', hx)
S.importAll(JSON.parse(JSON.stringify(dump)))
const back = S.items({ includePrivate: true }).find(i => i.title === 'Hadrianus memoarer')
ok('import brings them back', back.extent === 330 && back.isbn === '9789100123456', back)
const old = JSON.parse(JSON.stringify(dump))
old.items.forEach(i => { delete i.extent; delete i.isbn })
S.importAll(old)
const plain = S.items({ includePrivate: true }).find(i => i.title === 'Hadrianus memoarer')
ok('a file from before 1.2 still imports', plain !== undefined && plain.extent === 0 && plain.isbn === '', plain)

// --- ISBN ---------------------------------------------------------------------------
ok('a valid ISBN-13 stays as it is', L.normaliseIsbn('9780306406157') === '9780306406157')
ok('hyphens and spaces are ignored', L.normaliseIsbn('978-0-306-40615-7') === '9780306406157' && L.normaliseIsbn(' 978 0306 406157 ') === '9780306406157')
ok('an ISBN-10 becomes its ISBN-13', L.normaliseIsbn('0-306-40615-2') === '9780306406157', L.normaliseIsbn('0-306-40615-2'))
ok('an X check digit is understood', L.normaliseIsbn('080442957x') === '9780804429573', L.normaliseIsbn('080442957x'))
ok('a wrong check digit is refused', L.normaliseIsbn('9780306406158') === '' && L.normaliseIsbn('0306406153') === '')
ok('too short is refused', L.normaliseIsbn('12345') === '' && L.normaliseIsbn('') === '' && L.normaliseIsbn(null) === '')
ok('an ISBN-13 must start 978 or 979', L.normaliseIsbn('1234567890128') === '')

const olText = JSON.stringify({ 'ISBN:9780140449334': {
  title: 'Meditations', authors: [{ name: 'Marcus Aurelius', url: 'x' }], number_of_pages: 303,
  cover: { small: 'https://covers.openlibrary.org/b/id/1-S.jpg', medium: 'https://covers.openlibrary.org/b/id/1-M.jpg' } } })
const ol = L.parseOpenLibrary(olText, '9780140449334')
ok('Open Library: title, author, pages, cover', ol && ol.title === 'Meditations' && ol.creator === 'Marcus Aurelius' && ol.extent === 303 && ol.cover.indexOf('-M.jpg') > 0, ol)
ok('Open Library: an empty answer is not a book', L.parseOpenLibrary('{}', '9780140449334') === null)
ok('Open Library: rubbish is not a book', L.parseOpenLibrary('<html>', '9780140449334') === null)
const noPages = L.parseOpenLibrary(JSON.stringify({ 'ISBN:1': { title: 'T' } }), '1')
ok('Open Library: missing pages and cover are 0 and ""', noPages.extent === 0 && noPages.cover === '' && noPages.creator === '', noPages)

// Verbatim shape of a real Libris answer.
const lbText = '{"xsearch":{"from":1,"to":1,"records":1,"list":[{"identifier":"http://libris.kb.se/bib/3n2mq3341tz0crkf","title":"Doktor Glas / Hjalmar Söderberg","creator":"Söderberg, Hjalmar, 1869-1941","isbn":"9785001144373","type":"book","publisher":"Stockholm : Bonnier","date":"2024","language":"swe"}]}}'
const lb = L.parseLibris(lbText)
ok('Libris: title without the statement of responsibility', lb && lb.title === 'Doktor Glas', lb)
ok('Libris: the name turned round, dates dropped', lb.creator === 'Hjalmar Söderberg', lb)
ok('Libris: no pages, no cover', lb.extent === 0 && lb.cover === '')
ok('Libris: nothing found is null', L.parseLibris('{"xsearch":{"from":1,"to":0,"records":0,"list":[]}}') === null)
ok('Libris: a name with no comma is left alone', L.librisName('Homeros') === 'Homeros')

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails === 0 ? 0 : 1)
