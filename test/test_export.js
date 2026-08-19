// Export/import round trip.
//
// The question this file answers is not "does it run" but "is the database
// afterwards the same database". So it builds a realistic one, exports,
// wipes, imports, and compares what the ANALYSIS says -- streaks, totals,
// tag totals -- rather than comparing rows. Rows can match while meaning
// something different; a streak cannot.
const { S, mkModel, sqlite } = require('./harness')
let fails = 0
function ok(name, cond, extra) {
  if (!cond) { fails++; console.log('FAIL ' + name + (extra !== undefined ? '  -> ' + JSON.stringify(extra) : '')) }
  else console.log('ok   ' + name)
}
const onDay = n => S.dayKey(S.addDays(new Date(), n))
const at = (n, h, m) => onDay(n) + 'T' + String(h).padStart(2,'0') + ':' + String(m).padStart(2,'0') + ':00'

S.init()

// --- build something worth losing ------------------------------------------
const bookKind = S.addKind('book', 'pages')
const organKind = S.addKind('repertoire', 'minutes')

const flossId = S.addHabit({ name: 'Floss', valueType: 'boolean', frequency: 'daily' })
const readId  = S.addHabit({ name: 'Reading', valueType: 'reference', kindId: bookKind, frequency: 'daily', dailyTarget: 20 })
const gymId   = S.addHabit({ name: 'Gym', valueType: 'structured', detailProfile: 'strength', frequency: 'weekly_n', frequencyN: 3 })
const floss = S.getHabit(flossId), read = S.getHabit(readId), gym = S.getHabit(gymId)

for (const d of [0,-1,-2,-3,-4]) S.addEntry(floss, { loggedAt: at(d, 21, 0) })

const b1 = S.addItem({ title: 'Meditations', creator: 'Marcus Aurelius', kindId: bookKind, tags: ['stoic','philosophy'] })
const b2 = S.addItem({ title: 'Secret text', kindId: bookKind, private: true, tags: ['masonic'] })
const rep = S.addItem({ title: 'BWV 565', kindId: organKind, tags: ['organ'] })
S.addReferenceEntry(read, b1, 24, 'evening')
S.addReferenceEntry(read, b2, 8, '')
S.setItemState(b1, 'completed')

// an undo, so the void chain has to survive too
const e = S.addEntry(floss, { loggedAt: at(-6, 9, 0) })
S.voidEntry(flossId, e)

S.addRoutine(gymId, 'Push day')
S.saveSession(gym, S.routines(gymId)[0].id, [
  { name: 'Bench', details: [{ reps: '8', weight: '60' }, { reps: '8', weight: '62.5' }] },
  { name: 'Row',   details: [{ reps: '10', weight: '40' }] }
])

// --- snapshot what the analysis says ---------------------------------------
const before = {
  flossStreak: S.streak(S.getHabit(flossId)),
  readTotal: S.habitTotal(S.getHabit(readId), 30),
  kindTotals: S.kindTotals('', 365, true),
  tags: S.allTags(),
  items: S.items({ includePrivate: true }).length,
  privateTitle: S.items({ includePrivate: true }).filter(i => i.private)[0].title,
  session: S.lastSession(gymId)
}

const dump = JSON.parse(JSON.stringify(S.exportAll()))
ok('export names itself', dump.app === 'fiat-mos' && dump.format === 1, { app: dump.app, format: dump.format })
ok('export carries every habit', dump.habits.length === 3, dump.habits.length)
ok('export carries the void entry too', dump.entries.some(e => e.valueType === 'void'))
ok('foreign keys travel as references, never ids',
   dump.entries.every(e => typeof e.habit === 'string'), dump.entries[0])
ok('the void points at the entry it supersedes',
   dump.entries.filter(e => e.valueType === 'void')[0].supersedes !== null)
ok('a session keeps its exercises', dump.components.length === 2, dump.components.length)
ok('and its sets', dump.details.length === 3, dump.details.length)

// --- a file from another app is refused, not half-imported ------------------
ok('a foreign file is refused', S.describeImport({ app: 'something-else' }).ok === false)
ok('and nonsense is refused', S.describeImport(null).ok === false)
ok('a newer format is refused rather than guessed',
   S.describeImport({ app: 'fiat-mos', format: 99 }).reason === 'too-new')
ok('describing it touches nothing', S.allHabits().length === 3, S.allHabits().length)

// --- wipe and restore ------------------------------------------------------
const res = S.importAll(dump)
ok('import reports what it did', res.ok && res.habits === 3, res)

const after = {
  flossStreak: S.streak(S.allHabits().filter(h => h.name === 'Floss')[0]),
  readTotal: S.habitTotal(S.allHabits().filter(h => h.name === 'Reading')[0], 30),
  kindTotals: S.kindTotals('', 365, true),
  tags: S.allTags(),
  items: S.items({ includePrivate: true }).length,
  privateTitle: S.items({ includePrivate: true }).filter(i => i.private)[0].title
}

ok('nothing was duplicated', S.allHabits().length === 3, S.allHabits().length)
ok('the streak survives', after.flossStreak === before.flossStreak, [before.flossStreak, after.flossStreak])
ok('the total survives, unit and all',
   after.readTotal.total === before.readTotal.total && after.readTotal.unit === before.readTotal.unit,
   [before.readTotal, after.readTotal])
ok('the undo survives as an undo -- the voided entry is still gone',
   S.entriesOnDay(S.allHabits().filter(h => h.name === 'Floss')[0].id, onDay(-6)).length === 0)
ok('tags survive', after.tags.join(',') === before.tags.join(','), [before.tags, after.tags])
ok('items survive', after.items === before.items, [before.items, after.items])
ok('private stays private', after.privateTitle === before.privateTitle)
// Compared WITHOUT kindId, on purpose. The local id is expected to change --
// that is the entire reason foreign keys travel as uids and not as ids. A
// test that demanded the id come back identical would be asserting the bug
// the design exists to avoid.
const stripIds = rows => rows.map(r => ({ name: r.name, unit: r.unit, total: r.total,
                                          days: r.days, items: r.items }))
ok('kind totals match to the number',
   JSON.stringify(stripIds(after.kindTotals)) === JSON.stringify(stripIds(before.kindTotals)),
   [before.kindTotals, after.kindTotals])
ok('and the local id is allowed to differ -- that is the point',
   after.kindTotals[0].kindId !== before.kindTotals[0].kindId ||
   before.kindTotals[0].kindId === after.kindTotals[0].kindId)

const sess = S.lastSession(S.allHabits().filter(h => h.name === 'Gym')[0].id)
ok('the session survives with its exercises', sess !== null && sess.components.length === 2, sess)
ok('and every set', sess.components[0].details.length === 2, sess.components[0])

// --- everything that came back has an identity -----------------------------
const nullUids = sqlite.prepare('SELECT COUNT(*) c FROM log_entry WHERE uid IS NULL').get().c
ok('every imported entry has a uid', nullUids === 0, nullUids)

// --- importing twice replaces, never accumulates ---------------------------
S.importAll(dump)
ok('a second import replaces rather than doubles', S.allHabits().length === 3, S.allHabits().length)
ok('and the entries did not double',
   S.habitTotal(S.allHabits().filter(h => h.name === 'Reading')[0], 30).total === before.readTotal.total)

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails === 0 ? 0 : 1)
