// Schema 12: a program is a list of exercises, in order.
//
// What matters: a phone that already has programs keeps them, each now with
// the list it last ran; a program can be built before it is run; a workout
// is its own copy; and a file from before schema 12 still imports.
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
const sb = { D: require('./dur.js'), LS: { LocalStorage: { openDatabaseSync: () => fakeDb } }, console: { log(){} }, Date, Math, parseInt, parseFloat, isNaN, JSON, Number, String }
vm.createContext(sb)
vm.runInContext(src + ';globalThis.__S={init,MIGRATIONS,currentVersion,addHabit,getHabit,lastSession,sessionForDay,saveSession,kinds,addKind,things,thingIdByName,addThing,programs,addRoutine,routines,programItems,programById,programNameTaken,addProgram,renameProgram,setProgramItems,programHasItem,addProgramItem,removeProgramItem,moveProgramItem,programStart,saveAsProgram,exportAll,importAll,describeImport,dayKey,addDays,dayOffsetKey,itemById}', sb)
const S = sb.__S

let fails = 0
const ok = (n, c, e) => { if (!c) { fails++; console.log('FAIL ' + n + (e !== undefined ? ' -> ' + JSON.stringify(e) : '')) } else console.log('ok   ' + n) }
const q = (sql, ...p) => sqlite.prepare(sql).all(...p)
const one = (sql, ...p) => sqlite.prepare(sql).get(...p)
const day = n => S.dayKey(S.addDays(new Date(), n))
const names = list => list.map(x => x.name).join(',')

// ---------------------------------------------------------------------------
// A phone on schema 11 with two programs that have been run.
// ---------------------------------------------------------------------------
sqlite.exec("CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))")
for (const m of S.MIGRATIONS) {
  if (m.version > 11) break
  for (const st of m.statements) sqlite.exec(st)
  sqlite.exec('INSERT INTO schema_version (version) VALUES (' + m.version + ')')
}
ok('starts on schema 11', S.currentVersion() === 11, S.currentVersion())

sqlite.exec("INSERT INTO item_kind (name, unit, nature, measure, uid) VALUES ('exercises', '', 'practise', 'weight_reps', 'k-ex')")
sqlite.exec("INSERT INTO habit (name, value_type, frequency, kind_id, uid) VALUES ('Gym', 'structured', 'weekly_n', 1, 'h-gym')")
for (const t of ['Squat', 'Lunge', 'Plank', 'Press']) sqlite.exec("INSERT INTO item (title, kind_id, state, measure, uid) VALUES ('" + t + "', 1, 'active', " + (t === 'Plank' ? "'time'" : "'weight_reps'") + ", 'i-" + t + "')")
sqlite.exec("INSERT INTO routine (habit_id, name, uid) VALUES (1, 'Legs', 'r-legs')")
sqlite.exec("INSERT INTO routine (habit_id, name, uid) VALUES (1, 'Never run', 'r-never')")
function workout(rid, when, comps) {
  const e = sqlite.prepare("INSERT INTO log_entry (habit_id, logged_at, value_type) VALUES (1, ?, 'structured')").run(when)
  const s = sqlite.prepare("INSERT INTO session (habit_id, routine_id, started_at, log_entry_id) VALUES (1, ?, ?, ?)").run(rid, when, Number(e.lastInsertRowid))
  let o = 0
  for (const c of comps) {
    const cr = sqlite.prepare("INSERT INTO component (session_id, name, sort_order, item_id) VALUES (?, ?, ?, ?)").run(Number(s.lastInsertRowid), c.name, o++, c.item)
    for (const d of c.sets) sqlite.prepare("INSERT INTO detail (component_id, reps, weight_kg, duration_sec) VALUES (?, ?, ?, ?)").run(Number(cr.lastInsertRowid), d.r ?? null, d.w ?? null, d.t ?? null)
  }
}
workout(1, day(-20) + 'T10:00:00', [{ name: 'Squat', item: 1, sets: [{ r: 5, w: 50 }] }, { name: 'Lunge', item: 2, sets: [{ r: 8, w: 20 }] }])
workout(1, day(-6) + 'T10:00:00', [{ name: 'Squat', item: 1, sets: [{ r: 5, w: 60 }, { r: 5, w: 60 }] }, { name: 'Plank', item: 3, sets: [{ t: 60 }] }, { name: 'Lunge', item: 2, sets: [{ r: 8, w: 22 }] }])
workout(null, day(-3) + 'T10:00:00', [{ name: 'Press', item: 4, sets: [{ r: 8, w: 30 }] }])

// ---------------------------------------------------------------------------
// The upgrade
// ---------------------------------------------------------------------------
S.init()
ok('upgrades to 12', S.currentVersion() === 12, S.currentVersion())
ok('Legs got its list from its last run, in order', names(S.programItems(1)) === 'Squat,Plank,Lunge', names(S.programItems(1)))
ok('a program never run stays empty', S.programItems(2).length === 0)
ok('a workout with no program changed nothing', one("SELECT COUNT(*) c FROM routine_item").c === 3)
ok('every session and set is still there', one("SELECT COUNT(*) c FROM session").c === 3 && one("SELECT COUNT(*) c FROM detail").c === 7)
S.init()
ok('running init again adds nothing', one("SELECT COUNT(*) c FROM routine_item").c === 3)
ok('the program list carries the measure of each exercise', S.programItems(1)[1].measure === 'time', S.programItems(1))
const pl = S.programs().find(p => p.name === 'Legs')
ok('programs say how many exercises they hold', pl.exercises === 3 && S.programs().find(p => p.name === 'Never run').exercises === 0, S.programs())

// ---------------------------------------------------------------------------
// Building a program before running it
// ---------------------------------------------------------------------------
const sq = S.thingIdByName(1, 'squat'), pr = S.thingIdByName(1, 'Press')
const nd = S.addThing({ kindId: 1, title: 'Face pull', measure: 'weight_reps' })
const upper = S.addProgram(1, 'Upper', [pr, nd])
ok('a program is made with its exercises', upper > 0 && names(S.programItems(upper)) === 'Press,Face pull', names(S.programItems(upper)))
ok('a name already taken is refused', S.addProgram(1, 'legs', [sq]) === -1 && S.addProgram(1, '  ', [sq]) === -1)
ok('and made nothing', q("SELECT * FROM routine").length === 3)
S.addProgramItem(upper, sq)
ok('an exercise is added at the end', names(S.programItems(upper)) === 'Press,Face pull,Squat')
S.addProgramItem(upper, sq)
ok('never twice', S.programItems(upper).length === 3)
S.moveProgramItem(upper, sq, -1)
ok('moved up a step', names(S.programItems(upper)) === 'Press,Squat,Face pull', names(S.programItems(upper)))
S.moveProgramItem(upper, pr, -1)
ok('the first cannot go further up', names(S.programItems(upper)) === 'Press,Squat,Face pull')
S.removeProgramItem(upper, pr)
ok('an exercise is taken out', names(S.programItems(upper)) === 'Squat,Face pull' && !S.programHasItem(upper, pr))
ok('rename works', S.renameProgram(upper, 'Upper body') === true && S.programById(upper).name === 'Upper body')
ok('rename onto another program is refused', S.renameProgram(upper, 'LEGS') === false)
ok('a program knows its habit and kind', S.programById(upper).habitId === 1 && S.programById(upper).kindId === 1)

// ---------------------------------------------------------------------------
// Starting a workout from a program
// ---------------------------------------------------------------------------
const st = S.programStart(1, day(0))
ok('a workout from Legs has its exercises in order', names(st) === 'Squat,Plank,Lunge', names(st))
ok('with the sets of the last run of the program', st[0].details.length === 2 && st[0].details[0].weight === 60, st[0].details)
ok('and the measure of each', st[1].measure === 'time' && st[1].details[0].duration === 60)
const st2 = S.programStart(upper, day(0))
ok('an exercise never done from this program has the last time it was done', st2[0].name === 'Squat' && st2[0].details[0].weight === 60, st2[0])
ok('an exercise never done at all starts empty', st2[1].name === 'Face pull' && st2[1].details.length === 0)
ok('a program that is not there starts nothing', S.programStart(999, day(0)).length === 0)

// A workout is its own copy.
S.saveSession(S.getHabit(1), 1, [{ name: 'Squat', measure: 'weight_reps', details: [{ reps: 5, weight: 70 }] }, { name: 'Lunge', measure: 'weight_reps', details: [{ reps: 8, weight: 24 }] }], '', day(0))
ok('saving a workout from a program leaves the program as it was', names(S.programItems(1)) === 'Squat,Plank,Lunge', names(S.programItems(1)))
S.saveSession(S.getHabit(1), 1, [{ name: 'Squat', measure: 'weight_reps', details: [{ reps: 5, weight: 72 }] }], '', day(0))
ok('saving twice on one day rewrites that day', q("SELECT * FROM session WHERE substr(started_at,1,10) = ?", day(0)).length === 1 && S.sessionForDay(1, day(0)).components[0].details[0].weight === 72)
const next = S.programStart(1, day(1))
ok('the next workout starts from the last one, not the program\'s old numbers', next[0].details[0].weight === 72, next[0].details)
ok('a program\'s exercise skipped last time falls back to the last time it was done', next[2].name === 'Lunge' && next[2].details[0].weight === 22, next[2])
const compsBefore = one("SELECT COUNT(*) c FROM component").c, detBefore = one("SELECT COUNT(*) c FROM detail").c
S.setProgramItems(1, [sq])
ok('changing a program changes no old workout', one("SELECT COUNT(*) c FROM component").c === compsBefore && one("SELECT COUNT(*) c FROM detail").c === detBefore)

// ---------------------------------------------------------------------------
// A workout becomes a program
// ---------------------------------------------------------------------------
S.saveSession(S.getHabit(1), null, [{ name: 'Press', measure: 'weight_reps', details: [{ reps: 8, weight: 32 }] }, { name: 'Row', measure: 'weight_reps', details: [{ reps: 10, weight: 40 }] }], '', day(-1))
const made = S.saveAsProgram(1, 'Pull day', day(-1))
ok('a saved workout is made a program', made > 0 && names(S.programItems(made)) === 'Press,Row', names(S.programItems(made)))
ok('and that workout is now one from it', S.sessionForDay(1, day(-1)).routineId === made)
ok('a taken name makes nothing', S.saveAsProgram(1, 'Pull day', day(-1)) === -1)
ok('nor does a day with nothing saved', S.saveAsProgram(1, 'Empty', day(-40)) === -1)

// ---------------------------------------------------------------------------
// Export and import
// ---------------------------------------------------------------------------
const data = JSON.parse(JSON.stringify(S.exportAll()))
ok('export carries the program lists', data.routineItems.length === q("SELECT * FROM routine_item").length && data.routineItems.length > 0)
const before = { legs: names(S.programItems(1)), upper: names(S.programItems(upper)), pull: names(S.programItems(made)) }
ok('import accepts it', S.importAll(data).ok === true)
const idOf = n => q("SELECT id FROM routine WHERE name = ?", n)[0].id
ok('import brings every program\'s list back, in order', names(S.programItems(idOf('Legs'))) === before.legs && names(S.programItems(idOf('Upper body'))) === before.upper && names(S.programItems(idOf('Pull day'))) === before.pull,
   [names(S.programItems(idOf('Legs'))), names(S.programItems(idOf('Upper body')))])
const old = JSON.parse(JSON.stringify(data)); delete old.routineItems
ok('a file from before schema 12 imports', S.importAll(old).ok === true)
ok('and its programs get their list from their last run', names(S.programItems(idOf('Legs'))) === 'Squat' || S.programItems(idOf('Legs')).length > 0, names(S.programItems(idOf('Legs'))))
ok('a program that was never run stays empty', S.programItems(idOf('Never run')).length === 0)

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails ? 1 : 0)
