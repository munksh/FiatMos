// Schema 10: things you finish and things you practise.
//
// The upgrade is the part that matters most. A phone that has been logging gym
// sessions as typed names must come out of migration 10 with every set it had,
// every name exactly as typed, and each exercise tied to one thing that its
// whole history hangs off.
const fs = require('fs'), vm = require('vm')
const { DatabaseSync } = require('node:sqlite')

const raw = fs.readFileSync(require('path').join(__dirname, '..', 'qml', 'Storage.js'), 'utf8')
const src = raw.split('\n').filter(l => !l.trim().startsWith('.pragma') && !l.trim().startsWith('.import')).join('\n')
const sqlite = new DatabaseSync(':memory:')
function makeTx() { return { executeSql(sql, params) {
  params = params || []
  const stmt = sqlite.prepare(sql)
  if (/^\s*(select|pragma)/i.test(sql)) { const rows = stmt.all(...params); return { rows: { length: rows.length, item: i => rows[i] } } }
  const info = stmt.run(...params); return { rows: { length: 0, item: () => undefined }, insertId: Number(info.lastInsertRowid) }
} } }
const fakeDb = { transaction: cb => cb(makeTx()), readTransaction: cb => cb(makeTx()) }
const sb = { LS: { LocalStorage: { openDatabaseSync: () => fakeDb } }, console: { log(){} }, Date, Math, parseInt, parseFloat, isNaN, JSON, Number, String }
vm.createContext(sb)
vm.runInContext(src + ';globalThis.__S={init,MIGRATIONS,currentVersion,addHabit,getHabit,lastSession,sessionForDay,saveSession,kinds,kindById,addKind,starterKinds,STARTER_KINDS,items,itemById,addItem,things,thingDays,thingStats,dayFacts,setSummary,lastTimeFor,thingSuggestions,loadThings,addThing,updateThing,hasShelf,hasPractice,programs,addRoutine,exportAll,importAll,dayKey,addDays,dayOffsetKey,entriesSince,MEASURES,cleanMeasure,addReferenceEntry,itemsForHabit,kindStats}', sb)
const S = sb.__S

let fails = 0
const ok = (n, c, e) => { if (!c) { fails++; console.log('FAIL ' + n + (e !== undefined ? ' -> ' + JSON.stringify(e) : '')) } else console.log('ok   ' + n) }
const q = (sql, ...p) => sqlite.prepare(sql).all(...p)
const one = (sql, ...p) => sqlite.prepare(sql).get(...p)
const day = n => S.dayKey(S.addDays(new Date(), n))

// ---------------------------------------------------------------------------
// A phone on schema 9, with sessions typed by hand.
// ---------------------------------------------------------------------------
sqlite.exec("CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))")
for (const m of S.MIGRATIONS) {
  if (m.version > 9) break
  for (const st of m.statements) sqlite.exec(st)
  sqlite.exec('INSERT INTO schema_version (version) VALUES (' + m.version + ')')
}
ok('starts on schema 9', S.currentVersion() === 9, S.currentVersion())

// A shelf that already has a kind called "exercises", with a book-like thing
// in it. Migration 10 must not turn that into a practise kind.
sqlite.exec("INSERT INTO item_kind (name, unit, uid) VALUES ('book', 'pages', 'k-book')")
sqlite.exec("INSERT INTO item_kind (name, unit, uid) VALUES ('exercises', 'pages', 'k-ex')")
sqlite.exec("INSERT INTO item (title, kind_id, state, uid) VALUES ('Exercise book for French', 2, 'active', 'i-fr')")

sqlite.exec("INSERT INTO habit (name, value_type, frequency, detail_profile, uid) VALUES ('Gym', 'structured', 'weekly_n', 'strength', 'h-gym')")
sqlite.exec("INSERT INTO habit (name, value_type, frequency, detail_profile, uid) VALUES ('Rehab', 'structured', 'daily', 'timed', 'h-rehab')")
sqlite.exec("INSERT INTO habit (name, value_type, frequency, kind_id, uid) VALUES ('Reading', 'reference', 'daily', 1, 'h-read')")

function oldSession(habitId, when, comps) {
  const e = sqlite.prepare("INSERT INTO log_entry (habit_id, logged_at, value_type) VALUES (?, ?, 'structured')").run(habitId, when)
  const s = sqlite.prepare("INSERT INTO session (habit_id, started_at, log_entry_id) VALUES (?, ?, ?)").run(habitId, when, Number(e.lastInsertRowid))
  let order = 0
  for (const c of comps) {
    const cr = sqlite.prepare("INSERT INTO component (session_id, name, sort_order) VALUES (?, ?, ?)").run(Number(s.lastInsertRowid), c.name, order++)
    for (const d of c.sets) {
      sqlite.prepare("INSERT INTO detail (component_id, reps, weight_kg, duration_sec, note) VALUES (?, ?, ?, ?, ?)")
        .run(Number(cr.lastInsertRowid), d.r ?? null, d.w ?? null, d.t ?? null, d.n ?? null)
    }
  }
}
oldSession(1, day(-200) + 'T18:00:00', [
  { name: 'Bench press', sets: [{ r: 8, w: 50 }, { r: 8, w: 50 }] },
  { name: 'Plank', sets: [{ t: 60 }] }])
oldSession(1, day(-30) + 'T18:00:00', [
  { name: 'bench  Press ', sets: [{ r: 8, w: 60 }, { r: 6, w: 65 }] },
  { name: 'Squat', sets: [{ r: 5, w: 80 }] }])
oldSession(2, day(-10) + 'T08:00:00', [
  { name: 'Plank', sets: [{ t: 90 }] },
  { name: 'Bird dog', sets: [{ n: 'slow' }] }])

const detailsBefore = q('SELECT reps, weight_kg, duration_sec, note FROM detail ORDER BY id')
const namesBefore = q('SELECT name FROM component ORDER BY id').map(r => r.name)
const entriesBefore = one('SELECT COUNT(*) c FROM log_entry').c

// ---------------------------------------------------------------------------
// Migration 10
// ---------------------------------------------------------------------------
const v = S.init()
ok('reaches schema 10', v >= 10, v)
ok('item_kind has nature and measure', ['nature', 'measure'].every(c => q("SELECT name FROM pragma_table_info('item_kind')").map(r => r.name).includes(c)))
ok('item has measure', q("SELECT name FROM pragma_table_info('item')").some(r => r.name === 'measure'))
ok('component has item_id', q("SELECT name FROM pragma_table_info('component')").some(r => r.name === 'item_id'))
ok('detail has distance_m', q("SELECT name FROM pragma_table_info('detail')").some(r => r.name === 'distance_m'))

ok('no log entry added or removed', one('SELECT COUNT(*) c FROM log_entry').c === entriesBefore)
ok('every set is still there, unchanged',
   JSON.stringify(q('SELECT reps, weight_kg, duration_sec, note FROM detail ORDER BY id')) === JSON.stringify(detailsBefore))
ok('every name is still exactly as typed',
   JSON.stringify(q('SELECT name FROM component ORDER BY id').map(r => r.name)) === JSON.stringify(namesBefore))

const shelfEx = one("SELECT * FROM item_kind WHERE name = 'exercises'")
ok('the shelf kind called exercises is left alone', shelfEx.nature === null && shelfEx.unit === 'pages', shelfEx)
const gym = S.getHabit(1), rehab = S.getHabit(2)
ok('the gym habit got a kind', gym.kindId > 0, gym)
ok('rehab shares it', rehab.kindId === gym.kindId, [gym.kindId, rehab.kindId])
const pk = S.kindById(gym.kindId)
ok('which is a practise kind, not the shelf one', pk.nature === 'practise' && pk.id !== shelfEx.id, pk)
ok('named plainly', pk.name === 'practice', pk.name)
ok('every component is tied to a thing', one('SELECT COUNT(*) c FROM component WHERE item_id IS NULL').c === 0)
const th = S.things(gym.kindId, true)
ok('one thing per exercise, whatever the spacing and case', th.map(t => t.title).sort().join('|') === 'Bench press|Bird dog|Plank|Squat', th.map(t => t.title))
ok('the first spelling names the thing', th.some(t => t.title === 'Bench press'))
ok('gym things are weight times reps', S.itemById(th.find(t => t.title === 'Squat').id).measure === 'weight_reps')
ok('a thing first seen in a timed session is timed', S.itemById(th.find(t => t.title === 'Bird dog').id).measure === 'time')
ok('plank was first seen at the gym, so it starts as weight times reps', S.itemById(th.find(t => t.title === 'Plank').id).measure === 'weight_reps')
ok('the reading habit is untouched', S.getHabit(3).kindId === 1)

const bench = th.find(t => t.title === 'Bench press').id
ok('both bench sessions hang off one thing', S.thingDays(bench).length === 2, S.thingDays(bench))
const plank = th.find(t => t.title === 'Plank').id
ok('plank done at the gym and at rehab is one history', S.thingDays(plank).length === 2)

// Running it again changes nothing.
const snapshot = JSON.stringify(q('SELECT * FROM item ORDER BY id')) + JSON.stringify(q('SELECT * FROM component ORDER BY id'))
sqlite.exec('BEGIN'); S.MIGRATIONS[9].run(makeTx()); sqlite.exec('COMMIT')
ok('the link step is idempotent', JSON.stringify(q('SELECT * FROM item ORDER BY id')) + JSON.stringify(q('SELECT * FROM component ORDER BY id')) === snapshot)

// ---------------------------------------------------------------------------
// Kinds
// ---------------------------------------------------------------------------
ok('shelf kinds are the finish ones', S.kinds({ nature: 'finish' }).map(k => k.name).sort().join(',') === 'book,exercises', S.kinds({ nature: 'finish' }))
ok('practise kinds', S.kinds({ nature: 'practise' }).map(k => k.name).join(',') === 'practice')
ok('an old kind reads as finish', S.kindById(1).nature === 'finish')
ok('practise starters exclude finish ones', S.starterKinds('practise').every(k => k.nature === 'practise') && S.starterKinds('practise').length > 0)
ok('finish starters', S.starterKinds('finish').every(k => k.nature === 'finish') && S.starterKinds('finish').some(k => k.name === 'photo roll'))
ok('no starter shown twice once made', !S.starterKinds('finish').some(k => k.name === 'book'))
const pieces = S.addKind('pieces', '', 'practise', 'time')
ok('a practise kind keeps its measure', S.kindById(pieces).measure === 'time' && S.kindById(pieces).nature === 'practise')
ok('a kind made the old way is finish', S.kindById(S.addKind('draft', 'words')).nature === 'finish')
ok('the shelf does not list practised things', S.items({ nature: 'finish', includePrivate: true }).every(i => i.nature === 'finish'))

// ---------------------------------------------------------------------------
// Sessions tie exercises to things
// ---------------------------------------------------------------------------
S.saveSession(S.getHabit(1), null, [
  { name: ' bench press', details: [{ reps: 5, weight: 70 }, { reps: 5, weight: 70 }, { reps: 5, weight: 70 }] },
  { name: 'Farmer walk', measure: 'time_distance', details: [{ duration: 120, distance: 80 }] }
], '')
ok('a name in any case finds the existing thing', S.thingDays(bench).length === 3)
const fw = S.things(gym.kindId).find(t => t.title === 'Farmer walk')
ok('a new name becomes a new thing', fw !== undefined)
ok('with the measure chosen on the page', S.itemById(fw.id).measure === 'time_distance')
ok('distance is stored in metres', one('SELECT distance_m d FROM detail WHERE distance_m IS NOT NULL').d === 80)
const today = S.sessionForDay(1, day(0))
ok('a loaded session carries the thing', today.components[0].itemId === bench && today.components[0].measure === 'weight_reps', today.components[0])
ok('and its distance', today.components[1].details[0].distance === 80)

// Changing the measure on the session page changes the thing.
S.saveSession(S.getHabit(1), null, [{ name: 'Plank', measure: 'time', details: [{ duration: 75 }] }], '', day(-1))
ok('measure chosen in a session sticks to the thing', S.itemById(plank).measure === 'time')
ok('and the gym sets it already had keep every field', one('SELECT COUNT(*) c FROM detail d JOIN component c ON c.id = d.component_id WHERE c.item_id = ? AND d.duration_sec = 60', plank).c === 1)

// A renamed thing is shown by its new name in old sessions.
ok('rename works', S.updateThing({ id: bench, title: 'Bench press (barbell)' }) === true)
const back = S.lastSession(1, null)
ok('history shows the new name', S.sessionForDay(1, day(-30)).components[0].name === 'Bench press (barbell)')
ok('the typed name is still stored as typed', one('SELECT name FROM component WHERE item_id = ? ORDER BY id LIMIT 1', bench).name === 'Bench press')
ok('a rename onto another thing is refused', S.updateThing({ id: bench, title: 'squat' }) === false)
ok('and changed nothing', S.itemById(bench).title === 'Bench press (barbell)')

// A structured habit made without a kind is given one on first save.
const yoga = S.addHabit({ name: 'Yoga', valueType: 'structured', frequency: 'daily' })
S.saveSession(S.getHabit(yoga), null, [{ name: 'Sun salutation', details: [{ duration: 300 }] }], '')
ok('a kindless habit gets the practice kind', S.getHabit(yoga).kindId === gym.kindId)

// ---------------------------------------------------------------------------
// What a thing's history says
// ---------------------------------------------------------------------------
ok('same sets read as sets × reps', S.setSummary([{ reps: 5, weight: 70 }, { reps: 5, weight: 70 }, { reps: 5, weight: 70 }], 'weight_reps') === '3 × 5 · 70 kg')
ok('different sets are listed', S.setSummary([{ reps: 8, weight: 60 }, { reps: 6, weight: 65 }], 'weight_reps') === '8 × 60, 6 × 65 kg')
ok('no weight yet reads as reps', S.setSummary([{ reps: 12 }, { reps: 12 }], 'weight_reps') === '2 × 12 reps')
ok('one set', S.setSummary([{ reps: 8, weight: 60 }], 'weight_reps') === '8 reps · 60 kg')
ok('time', S.setSummary([{ duration: 90 }], 'time') === '1.5 min')
ok('time over sets', S.setSummary([{ duration: 60 }, { duration: 60 }], 'time') === '2 sets · 2 min')
ok('distance and time', S.setSummary([{ duration: 1680, distance: 5200 }], 'time_distance') === '5.2 km in 28 min')
ok('only a note', S.setSummary([{ note: 'slow' }], 'weight_reps') === '1 set')

const f = S.dayFacts([{ reps: 5, weight: 100 }, { reps: 8, weight: 90 }], 'weight_reps')
ok('top weight', f.top === 100)
ok('volume', f.volume === 1220)
ok('estimated max: 5 × 100 is the stronger set', f.best === 116.7, f.best)
ok('the headline value is the top weight', f.value === 100)

const st = S.thingStats(bench)
ok('stats: three days', st.count === 3, st.count)
ok('stats: first and last', st.first === day(-200) && st.last === day(0), [st.first, st.last])
ok('stats: half a year back is the 200-day-old session', st.then !== null && st.then.day === day(-200) && st.halfYear === true, st.then)
ok('stats: best day is the heaviest', st.best.value === 70, st.best)
ok('stats: unit is kg', st.unit === 'kg')
const lt = S.lastTimeFor(gym.kindId, 'BENCH PRESS (barbell)', day(0))
ok('last time before today, found by name', lt !== null && lt.day === day(-30) && lt.summary === '8 × 60, 6 × 65 kg', lt)
ok('last time for an unknown name is nothing', S.lastTimeFor(gym.kindId, 'Clean and jerk', day(0)) === null)
ok('suggestions start with what is typed', S.thingSuggestions(gym.kindId, 'pl')[0].title === 'Plank')
ok('suggestions also match inside a name', S.thingSuggestions(gym.kindId, 'walk').some(t => t.title === 'Farmer walk'))

const tm = []; tm.clear = () => { tm.length = 0 }; tm.append = o => tm.push(o); Object.defineProperty(tm, 'count', { get() { return tm.length } })
S.loadThings(tm, gym.kindId)
ok('the Practice list has every thing', tm.length === 6, tm.map(r => r.title))
ok('most recently done first', tm[0].lastDay === day(0), tm[0])
ok('rows say what was done last', tm.find(r => r.title === 'Squat').lastSummary === '5 reps · 80 kg', tm.find(r => r.title === 'Squat'))

const added = S.addThing({ title: 'Deadlift', kindId: gym.kindId, measure: 'weight_reps' })
ok('a thing can be added from the Practice page', added > 0 && S.itemById(added).nature === 'practise')
ok('adding an existing name reuses it', S.addThing({ title: 'deadlift', kindId: gym.kindId }) === added)

ok('the pull-down offers the shelf', S.hasShelf() === true)
ok('and practice', S.hasPractice() === true)
const rid = S.addRoutine(1, 'Push day')
S.saveSession(S.getHabit(1), rid, [{ name: 'Squat', details: [{ reps: 5, weight: 85 }] }], '', day(-2))
const pr = S.programs()
ok('programs are listed with their habit', pr.length === 1 && pr[0].name === 'Push day' && pr[0].habitName === 'Gym' && pr[0].sessions === 1, pr)

// ---------------------------------------------------------------------------
// Export and import keep it all
// ---------------------------------------------------------------------------
const file = JSON.parse(JSON.stringify(S.exportAll()))
ok('export carries the nature of kinds', file.kinds.some(k => k.nature === 'practise'))
ok('export carries which thing each exercise is', file.components.every(c => c.item !== null))
ok('export carries distance', file.details.some(d => d.distanceM === 80))
const benchRef = file.items.find(i => i.title === 'Bench press (barbell)').ref
S.importAll(file)
const benchAfter = S.items({ includePrivate: true }).find(i => i.title === 'Bench press (barbell)')
ok('after import the thing is back', benchAfter !== undefined && benchAfter.nature === 'practise')
ok('with its whole history', S.thingDays(benchAfter.id).length === 3, S.thingDays(benchAfter.id).length)
ok('and its measure', S.itemById(S.items({ includePrivate: true }).find(i => i.title === 'Farmer walk').id).measure === 'time_distance')

// An old file: no nature, no item on components.
const old = JSON.parse(JSON.stringify(file))
for (const k of old.kinds) { delete k.nature; delete k.measure }
for (const i of old.items) delete i.measure
for (const c of old.components) delete c.item
for (const d of old.details) delete d.distanceM
// Things you practise did not exist as items in an old file.
const practisedRefs = new Set(file.items.filter(i => file.kinds.find(k => k.ref === i.kind && k.nature === 'practise')).map(i => i.ref))
old.items = old.items.filter(i => !practisedRefs.has(i.ref))
const practiseKindRefs = new Set(file.kinds.filter(k => k.nature === 'practise').map(k => k.ref))
old.kinds = old.kinds.filter(k => !practiseKindRefs.has(k.ref))
for (const h of old.habits) if (practiseKindRefs.has(h.kind)) h.kind = null
S.importAll(old)
ok('an old file comes in with every exercise tied to a thing', one('SELECT COUNT(*) c FROM component WHERE item_id IS NULL').c === 0)
const g2 = S.getHabit(sqlite.prepare("SELECT id FROM habit WHERE name = 'Gym'").get().id)
ok('and the gym habit has a practise kind again', S.kindById(g2.kindId).nature === 'practise')
const b2 = S.things(g2.kindId).find(t => t.title.toLowerCase().indexOf('bench press') === 0)
ok('bench press is one thing again with its history', b2 !== undefined && S.thingDays(b2.id).length === 3, b2)

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails ? 1 : 0)
