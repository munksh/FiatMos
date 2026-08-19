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

const id = S.addHabit('Gammal vana', 'boolean', '', null, null, 'daily', null)
S.addEntry(S.getHabit(id), {})
const before = sqlite.prepare('SELECT COUNT(*) c FROM log_entry').get().c

const v = S.init()
const after = sqlite.prepare('SELECT COUNT(*) c FROM log_entry').get().c
const tables = sqlite.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all().map(r => r.name)
const versions = sqlite.prepare('SELECT version FROM schema_version ORDER BY version').all().map(r => r.version)

let fails = 0
const ok = (n, c, e) => { if (!c) { fails++; console.log('FAIL ' + n + (e !== undefined ? ' -> ' + JSON.stringify(e) : '')) } else console.log('ok   ' + n) }
ok('upgraded v1 -> v3', v === 3, v)
ok('only new migrations recorded', JSON.stringify(versions) === '[1,2,3]', versions)
ok('no rows lost', before === after && after === 1, { before, after })
ok('reference tables now exist', tables.includes('book') && tables.includes('log_entry_book'), tables)
ok('structured tables now exist', ['routine','session','component','detail'].every(t => tables.includes(t)), tables)
ok('old habit still readable', S.getHabit(id).name === 'Gammal vana')
console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails ? 1 : 0)
