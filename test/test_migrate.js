// A device that only ever ran schema v1 must reach v3 without losing rows.
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
const sb = { LS: { LocalStorage: { openDatabaseSync: () => fakeDb } }, console: { log(){} }, Date, Math, parseInt, parseFloat, isNaN, JSON }
vm.createContext(sb)
vm.runInContext(src + ';globalThis.__S={init,MIGRATIONS,currentVersion,addHabit,addEntry,getHabit,entriesSince,dayKey,addDays}', sb)
const S = sb.__S

// Hand-apply only v1, exactly as an old build would have left the device.
sqlite.exec("CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))")
for (const st of S.MIGRATIONS[0].statements) sqlite.exec(st)
sqlite.exec('INSERT INTO schema_version (version) VALUES (1)')

// Insert with raw SQL, not addHabit() -- addHabit writes columns that only
// exist from migration 4 onwards, and this test is simulating a v1 device.
sqlite.exec("INSERT INTO habit (name, value_type, frequency) VALUES ('Old habit', 'boolean', 'daily')")
const id = sqlite.prepare('SELECT id FROM habit ORDER BY id DESC LIMIT 1').get().id
sqlite.exec("INSERT INTO log_entry (habit_id, logged_at, value_type, value_bool) VALUES (" + id + ", '2026-01-01T08:00:00', 'boolean', 1)")
const before = sqlite.prepare('SELECT COUNT(*) c FROM log_entry').get().c

const v = S.init()
const after = sqlite.prepare('SELECT COUNT(*) c FROM log_entry').get().c
const tables = sqlite.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all().map(r => r.name)
const versions = sqlite.prepare('SELECT version FROM schema_version ORDER BY version').all().map(r => r.version)

let fails = 0
const ok = (n, c, e) => { if (!c) { fails++; console.log('FAIL ' + n + (e !== undefined ? ' -> ' + JSON.stringify(e) : '')) } else console.log('ok   ' + n) }
// Derived, not hardcoded. This assertion used to name version 7, so adding
// migration 8 broke it -- which is noise, not a finding. What is worth
// asserting is that the chain is COMPLETE and CONTIGUOUS: every version from
// 1 to the latest, each recorded exactly once, none skipped.
const LATEST = versions[versions.length - 1]
const contiguous = versions.join(',') === Array.from({length: LATEST}, (_, i) => i + 1).join(',')
ok('upgraded v1 -> latest', v === LATEST, { v, LATEST })
ok('every migration recorded exactly once, none skipped', contiguous, versions)
ok('and there is more than one of them', LATEST >= 8, LATEST)
ok('no rows lost', before === after && after === 1, { before, after })
ok('detail_profile column added to habit', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('habit') WHERE name = 'detail_profile'").get().c === 1)
ok('session.log_entry_id column added', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('session') WHERE name = 'log_entry_id'").get().c === 1)
ok('the library survived as item, not book', tables.includes('item') && !tables.includes('book'), tables)
ok('structured tables now exist', ['routine','session','component','detail'].every(t => tables.includes(t)), tables)
ok('daily_target column added', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('habit') WHERE name = 'daily_target'").get().c === 1)
ok('time_of_day column added', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('habit') WHERE name = 'time_of_day'").get().c === 1)
ok('a habit from v1 has no daily target, so it stays a tick', S.getHabit(id).dailyTarget === null)
ok('book table is gone', sqlite.prepare("SELECT COUNT(*) c FROM sqlite_master WHERE type='table' AND name='book'").get().c === 0)
ok('item and item_kind exist', ['item','item_kind','log_entry_item'].every(t => sqlite.prepare("SELECT COUNT(*) c FROM sqlite_master WHERE type='table' AND name=?").get(t).c === 1))
ok('item_tag now keys on item_id', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('item_tag') WHERE name='item_id'").get().c === 1)
ok('habit gained kind_id', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('habit') WHERE name='kind_id'").get().c === 1)
ok('legacy library columns are gone with the table', sqlite.prepare("SELECT COUNT(*) c FROM pragma_table_info('item') WHERE name IN ('author','status','category','unit')").get().c === 0)
ok('old habit still readable', S.getHabit(id).name === 'Old habit')
console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails ? 1 : 0)
