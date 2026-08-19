// A device that already ran v6 with real library data must come out of v7
// with every row, every tag and every log entry intact.
const fs = require('fs'), vm = require('vm'), path = require('path')
const { DatabaseSync } = require('node:sqlite')
const raw = fs.readFileSync(path.join(__dirname, '..', 'qml', 'Storage.js'), 'utf8')
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
vm.runInContext(src + ';globalThis.__S={init,MIGRATIONS,items,itemTags,kinds,itemLogCount,tagTotals,getHabit,unitForHabit}', sb)
const S = sb.__S

// Build a v6 database by hand and fill it the way the app would have.
sqlite.exec("CREATE TABLE schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))")
for (const m of S.MIGRATIONS) { if (m.version > 6) continue
  for (const st of m.statements) sqlite.exec(st)
  sqlite.exec('INSERT INTO schema_version (version) VALUES (' + m.version + ')') }

sqlite.exec("INSERT INTO habit (name, value_type, frequency, unit, reference_kind) VALUES ('Reading','reference','daily','pages','book')")
const habitId = sqlite.prepare('SELECT id FROM habit ORDER BY id DESC LIMIT 1').get().id
sqlite.exec("INSERT INTO book (title, author, status, creator, category, unit, state, private) VALUES ('Meditations','Aurelius','reading','Aurelius','book','pages','reading',0)")
sqlite.exec("INSERT INTO book (title, author, status, creator, category, unit, state, private) VALUES ('Toccata',NULL,'reading','Bach','repertoire','minutes','practicing',0)")
sqlite.exec("INSERT INTO book (title, author, status, creator, category, unit, state, private) VALUES ('Lodge text',NULL,'reading',NULL,'study text','pages','reading',1)")
const ids = sqlite.prepare('SELECT id, title FROM book ORDER BY id').all()
for (const b of ids) sqlite.exec(`INSERT INTO item_tag (book_id, tag) VALUES (${b.id}, 'carried')`)
for (const b of ids) {
  sqlite.exec(`INSERT INTO log_entry (habit_id, logged_at, value_type, value_numeric) VALUES (${habitId}, '2026-08-01T10:00:00', 'reference', 10)`)
  const le = sqlite.prepare('SELECT id FROM log_entry ORDER BY id DESC LIMIT 1').get().id
  sqlite.exec(`INSERT INTO log_entry_book (log_entry_id, book_id) VALUES (${le}, ${b.id})`)
}

const before = { books: 3, tags: 3, entries: 3 }
const v = S.init()

let fails = 0
const ok = (n, c, e) => { if (!c) { fails++; console.log('FAIL ' + n + (e !== undefined ? ' -> ' + JSON.stringify(e) : '')) } else console.log('ok   ' + n) }

// >= 7 rather than === 7: this file is about what migration 7 does to the
// data, and a later migration appended to the chain must not fail it.
ok('v6 database upgrades to at least v7', v >= 7, v)
const all = S.items({ includePrivate: true })
ok('every item survived', all.length === before.books, all.length)
ok('titles survived', all.map(i => i.title).sort().join(',') === 'Lodge text,Meditations,Toccata')
ok('creator carried over from author', all.find(i => i.title === 'Meditations').creator === 'Aurelius')
ok('private flag carried over', all.find(i => i.title === 'Lodge text').private === true)
ok('kinds were derived from the old categories',
   S.kinds().map(k => k.name).sort().join(',') === 'book,repertoire,study text', S.kinds())
ok('each kind kept the unit its items were using',
   S.kinds().find(k => k.name === 'repertoire').unit === 'minutes', S.kinds())
ok('items now inherit the unit from their kind',
   all.find(i => i.title === 'Toccata').unit === 'minutes')
ok('tags survived the key rename', all.every(i => S.itemTags(i.id).join(',') === 'carried'))
ok('log entries still point at their item', all.every(i => S.itemLogCount(i.id) === 1))
ok('totals still work', S.tagTotals('carried', 0, true).length === 2, S.tagTotals('carried', 0, true))
ok('the reference habit was pointed at the book kind',
   S.unitForHabit(S.getHabit(habitId)) === 'pages', S.getHabit(habitId).kindId)

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails ? 1 : 0)
