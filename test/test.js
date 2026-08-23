const { S, mkModel, sqlite } = require('./harness')
let fails = 0
function ok(name, cond, extra) {
  if (!cond) { fails++; console.log('FAIL ' + name + (extra !== undefined ? '  -> ' + JSON.stringify(extra) : '')) }
  else console.log('ok   ' + name)
}
const onDay = n => S.dayKey(S.addDays(new Date(), n))
const at = (n, h, m) => onDay(n) + 'T' + String(h).padStart(2,'0') + ':' + String(m).padStart(2,'0') + ':00'

S.init()

// --- habits -----------------------------------------------------------
const flossId = S.addHabit({ name: 'Floss',   valueType: 'boolean', frequency: 'daily' })
const runId   = S.addHabit({ name: 'Running', valueType: 'numeric', unit: 'min', targetValue: 30, frequency: 'weekly_n', frequencyN: 3 })
const sleepId = S.addHabit({ name: 'Sleep',   valueType: 'scale', scaleMax: 3, frequency: 'daily' })
const gymId   = S.addHabit({ name: 'Walk',    valueType: 'boolean', frequency: 'custom_interval', frequencyN: 3 })

ok('four habits created', S.activeHabitCount() === 4, S.activeHabitCount())
const floss = S.getHabit(flossId), run = S.getHabit(runId), sleep = S.getHabit(sleepId), gym = S.getHabit(gymId)
ok('numeric target survives round trip', run.targetValue === 30, run.targetValue)
ok('unit empty string when null', floss.unit === '', floss.unit)
ok('scaleMax read back', sleep.scaleMax === 3, sleep.scaleMax)

// --- free-form scale max ---------------------------------------------
const moodId = S.addHabit({ name: 'Mood', valueType: 'scale', scaleMax: 7, frequency: 'daily' })
ok('scale max is free-form, not a fixed list', S.getHabit(moodId).scaleMax === 7, S.getHabit(moodId).scaleMax)

// --- daily streak -----------------------------------------------------
for (const d of [0,-1,-2,-3,-4]) S.addEntry(floss, { loggedAt: at(d, 21, 0) })
ok('daily streak = 5', S.streak(floss) === 5, S.streak(floss))
S.addEntry(floss, { loggedAt: at(-7, 21, 0) })
ok('gap does not extend streak', S.streak(floss) === 5, S.streak(floss))

// --- unfinished today must not break the streak -----------------------
const stub = S.addHabit({ name: 'Stub', valueType: 'boolean', frequency: 'daily' })
const stubH = S.getHabit(stub)
for (const d of [-1,-2,-3]) S.addEntry(stubH, { loggedAt: at(d, 8, 0) })
ok('unlogged today keeps streak at 3', S.streak(stubH) === 3, S.streak(stubH))

// --- append-only undo -------------------------------------------------
const e = S.addEntry(sleep, { scale: 2, loggedAt: at(0, 23, 0) })
ok('entry present before undo', S.entriesOnDay(sleepId, onDay(0)).length === 1)
S.voidEntry(sleepId, e)
ok('entry gone from active view after undo', S.entriesOnDay(sleepId, onDay(0)).length === 0)
const rawCount = sqlite.prepare('SELECT COUNT(*) c FROM log_entry WHERE habit_id = ?').get(sleepId).c
ok('undo did not delete rows (2 remain)', rawCount === 2, rawCount)
ok('streak reflects the undo', S.streak(sleep) === 0, S.streak(sleep))

// --- weekly_n ---------------------------------------------------------
for (const d of [0,-1,-2]) S.addEntry(run, { numeric: 32, loggedAt: at(d, 7, 0) })
const wkThis = S.weekKey(new Date())
const sameWeek = [0,-1,-2].every(d => S.weekKey(S.addDays(new Date(), d)) === wkThis)
if (sameWeek) ok('weekly_n streak = 1 when quota met', S.streak(run) === 1, S.streak(run))
else console.log('skip weekly_n exact assertion (test days straddle a week boundary today)')

// --- custom_interval --------------------------------------------------
for (const d of [0,-3,-6,-9]) S.addEntry(gym, { loggedAt: at(d, 18, 0) })
ok('custom_interval streak = 4', S.streak(gym) === 4, S.streak(gym))

// --- series / deviation ----------------------------------------------
const s = S.series(run, 30)
ok('series has one point per day', s.length === 30, s.length)
ok('series ends today', s[s.length-1].day === onDay(0), s[s.length-1].day)
ok('unlogged days are null not 0', s.some(p => p.value === null))
const dev = S.deviationFromTarget(run, 30)
ok('deviation from target 30 with 32s is +2', Math.abs(dev - 2) < 0.001, dev)
ok('deviation is null for boolean habits', S.deviationFromTarget(floss, 30) === null)

// =====================================================================
// Reference template -- kinds, items, one unit per habit
// =====================================================================

// The starter list lives in code and has no rows behind it. Nothing exists
// until somebody picks one -- that is what keeps the library clean.
ok('with no kinds yet, every starter is on offer',
   S.starterKinds().length === S.STARTER_KINDS.length, S.starterKinds().length)
ok('and none of them is in the database yet', S.kinds().length === 0, S.kinds())

const bookKind  = S.addKind('book', 'pages')
const audioKind = S.addKind('audiobook', 'minutes')
ok('a kind carries its unit', S.kindById(bookKind).unit === 'pages')

// Picking one turns it into a row, and it stops being offered as a starter.
ok('a picked starter drops off the starter list',
   S.starterKinds().every(k => k.name !== 'book'), S.starterKinds())
ok('the rest are still offered',
   S.starterKinds().length === S.STARTER_KINDS.length - 2, S.starterKinds().length)
S.addKind('Article', 'pages')
ok('matching is case-insensitive, because Book and book are one thing',
   S.starterKinds().every(k => k.name !== 'article'), S.starterKinds())

ok('a kind prints as name and unit', S.kindLabel(S.kindById(bookKind)) === 'book · pages')
ok('and as just the name when it has none',
   S.kindLabel({ name: 'oddity', unit: '' }) === 'oddity')

ok('the same kind name is reused, not duplicated', S.addKind('book', 'anything') === bookKind)
ok('and reusing it never rewrites the unit', S.kindById(bookKind).unit === 'pages')

const readId = S.addHabit({ name: 'Reading', valueType: 'reference', kindId: bookKind, frequency: 'daily' })
const read = S.getHabit(readId)
ok('a reference habit knows its kind', read.kindId === bookKind, read.kindId)
ok('and takes its unit from the kind, not from itself', S.unitForHabit(read) === 'pages')

const b1 = S.addItem({ title: 'Meditations', creator: 'Marcus Aurelius', kindId: bookKind })
const b2 = S.addItem({ title: 'The Long Ships', creator: 'Frans G. Bengtsson', kindId: bookKind })
const a1 = S.addItem({ title: 'Röde Orm, read aloud', kindId: audioKind })

ok('an item has no unit of its own -- it inherits', S.items({ kindId: bookKind })[0].unit === 'pages')
ok('a new item starts on the go, not finished', S.items({ kindId: bookKind })[0].state === 'active')
ok('two books on the go', S.items({ kindId: bookKind, active: true }).length === 2)

// the scoping rule
ok('a reading habit only offers books', S.itemsForHabit(read).length === 2, S.itemsForHabit(read).length)
ok('the audiobook is not among them', S.itemsForHabit(read).every(i => i.title.indexOf('read aloud') < 0))

S.addReferenceEntry(read, b1, 24, 'evening')
S.addReferenceEntry(read, b2, null, '')
const todays = S.entriesOnDay(readId, onDay(0))
ok('two reference entries today', todays.length === 2, todays.length)
ok('junction links entry to the right item', S.itemTitleForEntry(todays[0].id) === 'Meditations')
ok('optional amount stored', todays[0].valueNumeric === 24, todays[0].valueNumeric)
ok('amount may be omitted', todays[1].valueNumeric === null, todays[1].valueNumeric)
ok('an item with no amount still counts as logged', S.streak(read) === 1, S.streak(read))
ok('itemLogCount counts distinct days', S.itemLogCount(b1) === 1, S.itemLogCount(b1))

// one habit, one unit -- by construction
const habitSum = S.habitTotal(read, 30)
ok('a habit totals in exactly one unit', habitSum.unit === 'pages', habitSum)
ok('and the total is the sum of its entries', habitSum.total === 24, habitSum)

S.setItemState(b1, 'completed')
ok('finished item leaves the on-the-go list', S.itemsForHabit(read).length === 1)
ok('finished item keeps its history', S.itemLogCount(b1) === 1)
ok('finishing an item does not touch the habit streak', S.streak(read) === 1)
ok('the habit survives its items -- that is the whole point',
   S.getHabit(readId) !== null && S.getHabit(readId).archivedAt === null)

const itemModel = mkModel()
S.loadItems(itemModel, { includePrivate: true })
ok('library model lists every item', itemModel.count === 3, itemModel.count)
ok('and carries the kind name', itemModel.find(r => r.title === 'Meditations').kindName === 'book')

// =====================================================================
// Structured template -- sessions
// =====================================================================

const liftId = S.addHabit({ name: 'Gym', valueType: 'structured', detailProfile: 'strength', frequency: 'weekly_n', frequencyN: 2 })
const lift = S.getHabit(liftId)
ok('detail profile stored', lift.detailProfile === 'strength', lift.detailProfile)

const comps = [
  { name: 'Deadlift', details: [ {reps: 5, weight: 100, duration: '', note: ''}, {reps: 5, weight: 105, duration: '', note: ''} ] },
  { name: 'Hip lift', details: [ {reps: 12, weight: '', duration: '', note: 'easy'} ] },
  { name: '',         details: [ {reps: '', weight: '', duration: '', note: ''} ] }   // dropped
]
const saved = S.saveSession(lift, null, comps, 'felt good')
ok('session written', saved.sessionId > 0, saved)
ok('session also writes a log_entry so streaks work', S.entriesOnDay(liftId, onDay(0)).length === 1)
ok('structured session shows up as a logged day', S.series(lift, 7).slice(-1)[0].value === 1, S.series(lift, 7).slice(-1)[0].value)
// Deliberate: this habit is 2×/week and only one DAY has a session, so the
// week's quota is unmet and the streak is still 0. Several sessions on the
// same day count as one day -- two gym visits on Monday are not "twice a week".
ok('quota of 2/week is not met by one day', S.streak(lift) === 0, S.streak(lift))
ok('and it is therefore still due today', S.isDueToday(lift) === true)

const sq = require('./harness').sqlite
ok('nameless component dropped', sq.prepare('SELECT COUNT(*) c FROM component WHERE session_id = ?').get(saved.sessionId).c === 2)
ok('empty detail rows dropped', sq.prepare('SELECT COUNT(*) c FROM detail').get().c === 3)
ok('session linked to its log_entry', sq.prepare('SELECT log_entry_id l FROM session WHERE id = ?').get(saved.sessionId).l === saved.entryId)

// routine + inherit
const rid = S.addRoutine(liftId, 'Lower body A')
ok('routine created', rid > 0, rid)
ok('same routine name is reused, not duplicated', S.addRoutine(liftId, 'Lower body A') === rid)
ok('routine listed for the habit', S.routines(liftId).length === 1, S.routines(liftId).length)

S.saveSession(lift, rid, comps, '')
const last = S.lastSession(liftId, rid)
ok('lastSession finds the routine session', last !== null && last.routineId === rid)
ok('prefill carries the exercises', last.components.length === 2, last.components.length)
ok('prefill carries the sets in order', last.components[0].details.length === 2)
ok('prefill carries weights', last.components[0].details[1].weight === 105, last.components[0].details[1].weight)

// Saving again on the SAME DAY rewrites the session rather than adding one.
//
// These three assertions used to say the opposite -- "new session is added",
// "old detail rows untouched", "detail rows only ever grow" -- and they were
// right about the old contract. The contract changed on purpose: saving twice
// during a workout produced three gym visits in the history, and the only way
// to avoid that was to remember not to save, which is not a thing to ask of
// somebody between sets.
//
// What must NOT change is the ledger. log_entry is still append-only, and a
// day still has exactly one entry however many times you save.
const beforeSessions = sq.prepare('SELECT COUNT(*) c FROM session').get().c
const beforeEntries = sq.prepare('SELECT COUNT(*) c FROM log_entry WHERE habit_id = ?').get(liftId).c
const heavier = [{ name: 'Deadlift', details: [ {reps: 5, weight: 110, duration: '', note: ''} ] }]
S.saveSession(lift, rid, heavier, '')
ok('saving again today rewrites the session rather than adding one',
   sq.prepare('SELECT COUNT(*) c FROM session').get().c === beforeSessions, beforeSessions)
ok('and writes no second log entry',
   sq.prepare('SELECT COUNT(*) c FROM log_entry WHERE habit_id = ?').get(liftId).c === beforeEntries, beforeEntries)
ok('the rewritten session holds the new values',
   S.lastSession(liftId, rid).components[0].details[0].weight === 110)
ok('and the replaced sets are gone rather than duplicated',
   sq.prepare('SELECT COUNT(*) c FROM detail WHERE weight_kg = 105').get().c === 0)

// timed profile stores seconds
const organId = S.addHabit({ name: 'Organ', valueType: 'structured', detailProfile: 'timed', frequency: 'daily' })
S.saveSession(S.getHabit(organId), null, [{ name: 'Toccata in D minor', details: [{reps: '', weight: '', duration: 1500, note: ''}] }], '')
ok('duration stored in seconds', S.lastSession(organId, null).components[0].details[0].duration === 1500)

const sessModel = mkModel()
S.loadSessionHistory(sessModel, liftId, 20)
ok('session history model populated', sessModel.count === 1, sessModel.count)
ok('history knows the routine name', sessModel.find(r => r.routineName === 'Lower body A') !== undefined)
ok('history counts exercises', sessModel[0].componentCount === 1, sessModel[0].componentCount)

// --- archive keeps history -------------------------------------------
S.archiveHabit(stub)
ok('archived habit leaves the active list', S.activeHabitCount() === 8, S.activeHabitCount())
ok('archived habit history survives', S.entriesSince(stub, onDay(-30)).length === 3, S.entriesSince(stub, onDay(-30)).length)

// --- habit list model -------------------------------------------------
const model = mkModel()
S.loadHabits(model)
const flossRow = model.find(r => r.name === 'Floss')
ok('model carries loggedToday', flossRow.loggedToday === true)
ok('model carries streak', flossRow.streak === 5, flossRow.streak)
const runRow = model.find(r => r.name === 'Running')
ok('numeric summary includes unit', runRow.todaySummary === '32 min', runRow.todaySummary)
const liftRow = model.find(r => r.valueType === 'structured' && r.name === 'Gym')
ok('structured summary names the routine', liftRow.todaySummary.indexOf('Lower body A') === 0, liftRow.todaySummary)
const readRow = model.find(r => r.name === 'Reading')
ok('reference summary names the book', readRow.todaySummary.indexOf('The Long Ships') >= 0, readRow.todaySummary)

// =====================================================================
// Daily goals, the header ring, and time-of-day grouping
// =====================================================================

// counted numeric habit: 20 of 30 minutes today
const jogId = S.addHabit({ name: 'Jog', valueType: 'numeric', unit: 'min', dailyTarget: 30, frequency: 'daily' })
const jog = S.getHabit(jogId)
ok('daily target stored', jog.dailyTarget === 30, jog.dailyTarget)
S.addEntry(jog, { numeric: 12, loggedAt: at(0, 7, 0) })
S.addEntry(jog, { numeric: 8,  loggedAt: at(0, 18, 0) })
let jp = S.todayProgress(jog)
ok('counted habit sums the day', jp.done === 20, jp.done)
ok('counted habit is a fraction', Math.abs(jp.fraction - 20/30) < 0.001, jp.fraction)
ok('counted habit not complete below target', jp.complete === false)
S.addEntry(jog, { numeric: 15, loggedAt: at(0, 21, 0) })
jp = S.todayProgress(jog)
ok('counted habit completes at target', jp.complete === true && jp.done === 35, jp)
ok('fraction never exceeds 1', jp.fraction === 1, jp.fraction)

// counted by number of entries, not by value
const waterId = S.addHabit({ name: 'Water', valueType: 'boolean', dailyTarget: 3, frequency: 'daily' })
const water = S.getHabit(waterId)
S.addEntry(water, { loggedAt: at(0, 9, 0) })
S.addEntry(water, { loggedAt: at(0, 13, 0) })
let wp = S.todayProgress(water)
ok('non-numeric counted habit counts entries', wp.done === 2 && wp.counted === true, wp)
ok('and is not done yet', wp.complete === false)

// no daily target -> checked, not counted
const checkedP = S.todayProgress(floss)
ok('habit without a daily target is checked, not counted', checkedP.counted === false)
ok('one entry finishes a checked habit', checkedP.complete === true)

// header ring
const day = S.dayCompletion()
ok('dayCompletion counts only habits due today', day.total <= S.activeHabitCount(), day)
ok('dayCompletion fraction is completed/total',
   Math.abs(day.fraction - day.completed / day.total) < 0.0001, day)
ok('a part-done counted habit does not count as complete',
   S.todayProgress(S.getHabit(waterId)).complete === false)

// time of day
ok('time_of_day defaults to empty', S.getHabit(jogId).timeOfDay === '', S.getHabit(jogId).timeOfDay)
S.updateHabit({ id: jogId, name: 'Jog', unit: 'min', frequency: 'daily', dailyTarget: 30, timeOfDay: 'morning' })
ok('updateHabit stores time of day', S.getHabit(jogId).timeOfDay === 'morning')
ok('updateHabit keeps the value type', S.getHabit(jogId).valueType === 'numeric')
ok('section order is morning, afternoon, evening, then untagged',
   S.sectionRank('morning') < S.sectionRank('afternoon') &&
   S.sectionRank('afternoon') < S.sectionRank('evening') &&
   S.sectionRank('evening') < S.sectionRank(''))

const grouped = mkModel()
S.loadHabits(grouped, true)
let lastRank = -1, ordered = true
for (const row of grouped) {
  const r = S.sectionRank(row.timeOfDay)
  if (r < lastRank) ordered = false
  lastRank = r
}
ok('grouped load returns rows already in section order', ordered)
ok('every row carries a section name', grouped.every(r => r.section !== undefined && r.section !== ''))
ok('untagged rows land in anytime', grouped.filter(r => r.timeOfDay === '').every(r => r.section === 'anytime'))

const ungrouped = mkModel()
S.loadHabits(ungrouped, false)
ok('ungrouped load returns the same rows', ungrouped.count === grouped.count, [ungrouped.count, grouped.count])
ok('rows carry the fraction for the ring', ungrouped.find(r => r.name === 'Jog').fraction === 1)
ok('rows say whether they are counted', ungrouped.find(r => r.name === 'Water').counted === true)
ok('checked rows are not counted', ungrouped.find(r => r.name === 'Floss').counted === false)

// =====================================================================
// Kinds, tags, privacy
// =====================================================================

const repKind   = S.addKind('repertoire', 'minutes')
const rollKind  = S.addKind('photo roll', 'frames')
const studyKind = S.addKind('study text', 'pages')

const organRep = S.addItem({ title: 'Toccata in D minor', creator: 'Bach', kindId: repKind,
                             tags: ['organ', 'psalmprojektet'] })
const roll = S.addItem({ title: 'Portra 400 #7', kindId: rollKind, tags: ['mamiya-m645'] })
const lodge = S.addItem({ title: 'Study text', kindId: studyKind, private: true, tags: ['masonic'] })
const french = S.addItem({ title: 'Grammaire progressive', creator: 'Grégoire', kindId: bookKind,
                           tags: ['French', 'language study'] })

ok('kinds are user-invented, not an enum', S.kinds().length >= 5, S.kinds().length)
ok('a roll is measured in frames', S.items({ kindId: rollKind })[0].unit === 'frames')
ok('tags are normalised', S.itemTags(french).join(',') === 'french,language-study', S.itemTags(french))
ok('several tags per item', S.itemTags(organRep).length === 2)
ok('allTags collects what is in use', S.allTags().indexOf('organ') >= 0)

ok('private items are hidden by default', S.items({}).every(i => i.title !== 'Study text'))
ok('and shown when asked for', S.items({ includePrivate: true }).some(i => i.title === 'Study text'))

// an organ habit, scoped to repertoire, measured in minutes
const organRefId = S.addHabit({ name: 'Organ reading', valueType: 'reference', kindId: repKind, frequency: 'daily' })
const organ = S.getHabit(organRefId)
ok('a second reference habit has its own unit', S.unitForHabit(organ) === 'minutes')
ok('and only sees its own kind', S.itemsForHabit(organ).length === 1)

S.addReferenceEntry(organ, organRep, 25, '')
S.addReferenceEntry(organ, organRep, 15, '')
S.addReferenceEntry(read, french, 12, '')
S.addReferenceEntry(read, b2, 8, '')

const organTotal = S.habitTotal(organ, 30)
ok('organ totals in minutes', organTotal.unit === 'minutes' && organTotal.total === 40, organTotal)
const readTotal = S.habitTotal(read, 30)
ok('reading totals in pages, never mixed with minutes',
   readTotal.unit === 'pages' && readTotal.total === 44, readTotal)

// --- mean and median, per LOGGED day ---------------------------------
// Deliberately lopsided: 10, 10, 100 over three days. Mean 40, median 10.
// If the two ever agree on data like this, one of them is wrong.
const skewKind = S.addKind('scribble', 'words')
const skewId = S.addHabit({ name: 'Writing', valueType: 'reference', kindId: skewKind, frequency: 'daily' })
const skew = S.getHabit(skewId)
const skewItem = S.addItem({ title: 'Notebook', kindId: skewKind })
S.addReferenceEntry(skew, skewItem, 10, '')
S.addEntry(skew, { numeric: 10, loggedAt: at(-1, 9, 0) })
S.addEntry(skew, { numeric: 100, loggedAt: at(-2, 9, 0) })
const skewStats = S.habitTotal(skew, 30)
ok('total is the sum', skewStats.total === 120, skewStats)
ok('mean divides by logged days, not by the window', skewStats.mean === 40, skewStats)
ok('median is the day you actually have', skewStats.median === 10, skewStats)
ok('and the window did not sneak into the day count', skewStats.days === 3, skewStats)

// Even count takes the midpoint of the middle two, and the sort is numeric --
// a lexicographic sort would put 100 before 9 and quietly ruin the answer.
const evenId = S.addHabit({ name: 'Even', valueType: 'numeric', unit: 'x', frequency: 'daily' })
const even = S.getHabit(evenId)
;[9, 100, 1, 5].forEach((v, i) => S.addEntry(even, { numeric: v, loggedAt: at(-i, 9, 0) }))
const evenStats = S.habitTotal(even, 30)
ok('median of an even count is the midpoint of the middle two',
   evenStats.median === 7, evenStats)

const emptyId = S.addHabit({ name: 'Untouched', valueType: 'numeric', unit: 'x', frequency: 'daily' })
const emptyStats = S.habitTotal(S.getHabit(emptyId), 30)
ok('with nothing logged, mean and median are null rather than zero',
   emptyStats.mean === null && emptyStats.median === null && emptyStats.days === 0, emptyStats)

const organTag = S.tagTotals('organ', 30, false)
ok('tag totals group by unit', organTag.length === 1 && organTag[0].unit === 'minutes', organTag)
ok('tag totals sum the quantity', organTag[0].total === 40, organTag[0].total)

const masonic = S.tagTotals('masonic', 30, false)
ok('a private item stays out of totals', masonic.length === 0, masonic)

// a tag may legitimately span kinds -- that is when the split earns its keep
S.setItemTags(organRep, ['organ', 'mixed'])
S.setItemTags(french, ['french', 'language-study', 'mixed'])
const mixed = S.tagTotals('mixed', 30, false)
ok('a tag across two kinds comes back as two rows', mixed.length === 2, mixed)
const byUnit = {}
mixed.forEach(r => byUnit[r.unit] = r.total)
ok('minutes stay minutes', byUnit['minutes'] === 40, byUnit)
ok('pages stay pages', byUnit['pages'] === 12, byUnit)

// undo reaches everywhere
const organEntries = S.entriesOnDay(organRefId, onDay(0))
S.voidEntry(organRefId, organEntries[0].id)
ok('voided entries leave the habit total', S.habitTotal(organ, 30).total === 15)
ok('and leave the tag totals', S.tagTotals('organ', 30, false)[0].total === 15)

S.setItemState(roll, 'completed')
ok('finishing an item takes it out of the on-the-go list',
   S.items({ active: true, includePrivate: true }).every(i => i.title !== 'Portra 400 #7'))
ok('and it keeps its tags', S.itemTags(roll).join(',') === 'mamiya-m645')


// --- tag totals name the kinds they merged --------------------------------
//
// Two kinds measured the same way collapse into one row on purpose. The row
// has to say which two, or the number cannot be checked against reality.
const mixedRows = S.tagTotals('mixed', 30, false)
ok('a merged row lists its kinds', mixedRows.every(r => r.kinds.length > 0), mixedRows)
const minutesRow = mixedRows.filter(r => r.unit === 'minutes')[0]
ok('and names the right one', minutesRow.kinds.indexOf('repertoire') >= 0, minutesRow.kinds)


// --- totals per kind, tag optional ----------------------------------------
//
// The bug this replaces: an untagged item was invisible here, even though its
// pages were sitting in the habit's own history the whole time.
const untagged = S.addItem({ title: 'Something nobody labelled', kindId: bookKind })
S.addReferenceEntry(read, untagged, 17, '')
ok('an untagged item still counts in the totals',
   S.kindTotals('', 30, false).some(r => r.name === 'book'), S.kindTotals('', 30, false))

const bookRow = S.kindTotals('', 30, false).filter(r => r.name === 'book')[0]
ok('and the pages are actually in the number', bookRow.total >= 17, bookRow)
ok('a kind row carries exactly one unit', bookRow.unit === 'pages', bookRow)

const frenchOnly = S.kindTotals('french', 30, false)
ok('the tag still narrows it', frenchOnly.every(r => r.unit === 'pages'), frenchOnly)
ok('and narrowing drops the untagged item',
   frenchOnly[0].total < bookRow.total, [frenchOnly[0], bookRow])

const kindModel = mkModel()
S.loadKindTotals(kindModel, '', 30, false)
ok('the model gets one row per kind', kindModel.count === S.kindTotals('', 30, false).length)


// --- one session per day ---------------------------------------------------
//
// Saving twice during a workout used to write a second session and a second
// log entry. The day was still one day to the streak, but the history showed
// three gym visits and the way to avoid it was to remember not to save.
const gymId2 = S.addHabit({ name: 'Gym', valueType: 'structured', detailProfile: 'strength', frequency: 'daily' })
const gym2 = S.getHabit(gymId2)

S.saveSession(gym2, null, [{ name: 'Bench', details: [{ reps: 8, weight: 60 }] }], '')
const afterFirst = S.entriesOnDay(gymId2, onDay(0)).length
ok('the first save writes one entry', afterFirst === 1, afterFirst)

S.saveSession(gym2, null, [{ name: 'Bench', details: [{ reps: 8, weight: 60 }, { reps: 8, weight: 62.5 }] }], '')
ok('the second save does not write a second entry',
   S.entriesOnDay(gymId2, onDay(0)).length === 1, S.entriesOnDay(gymId2, onDay(0)).length)

const sessRows = sqlite.prepare('SELECT COUNT(*) c FROM session WHERE habit_id = ?').get(gymId2).c
ok('and does not write a second session', sessRows === 1, sessRows)

const today = S.todaysSession(gymId2)
ok("today's session is found", today !== null)
ok('and holds the SECOND version, not the first',
   today.components[0].details.length === 2, today.components[0].details)
ok('the session keeps its log entry', today.entryId !== null && today.entryId !== undefined)

// a rewrite must not orphan rows
const orphanComps = sqlite.prepare('SELECT COUNT(*) c FROM component WHERE session_id NOT IN (SELECT id FROM session)').get().c
const orphanDetails = sqlite.prepare('SELECT COUNT(*) c FROM detail WHERE component_id NOT IN (SELECT id FROM component)').get().c
ok('no orphaned exercises', orphanComps === 0, orphanComps)
ok('no orphaned sets', orphanDetails === 0, orphanDetails)

// the streak still sees exactly one day
ok('the day counts once', S.streak(S.getHabit(gymId2)) === 1, S.streak(S.getHabit(gymId2)))

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails === 0 ? 0 : 1)
