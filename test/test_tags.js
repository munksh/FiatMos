// Narrowing the shelf by several tags, and the counts offered beside them.
//
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
vm.runInContext(src + ';globalThis.__S={addItem,setItemTags,items,tagChoices,allTags,init,MIGRATIONS,currentVersion,addHabit,getHabit,lastSession,sessionForDay,saveSession,kinds,addKind,things,thingIdByName,addThing,programs,addRoutine,routines,programItems,programById,programNameTaken,addProgram,renameProgram,setProgramItems,programHasItem,addProgramItem,removeProgramItem,moveProgramItem,programStart,saveAsProgram,exportAll,importAll,describeImport,dayKey,addDays,dayOffsetKey,itemById}', sb)
const S = sb.__S


let fails = 0
const ok = (n, c, e) => { if (!c) { fails++; console.log('FAIL ' + n + (e !== undefined ? ' -> ' + JSON.stringify(e) : '')) } else console.log('ok   ' + n) }
S.init()
const k = S.addKind('Records', 'min', 'finish', 'weight_reps')
const mk = (t, tags) => { const id = S.addItem({ title: t, kindId: k, state: 'planned' }); S.setItemTags(id, tags); return id }
mk('Kind of Blue', ['jazz', '1959'])
mk('Time Out', ['jazz', '1959'])
mk('A Love Supreme', ['jazz'])
mk('Dune', ['scifi'])
mk('Abbey Road', ['rock', '1969'])
const titles = l => l.map(x => x.title).sort().join(',')
const f = { includePrivate: true, kindId: k }
ok('no tag: everything', S.items(f).length === 5)
ok('one tag narrows', titles(S.items(Object.assign({ tags: ['jazz'] }, f))) === 'A Love Supreme,Kind of Blue,Time Out')
ok('two tags narrow further (and, not or)', titles(S.items(Object.assign({ tags: ['jazz', '1959'] }, f))) === 'Kind of Blue,Time Out')
ok('tags that share nothing leave nothing', S.items(Object.assign({ tags: ['jazz', 'scifi'] }, f)).length === 0)
const by = l => { const o = {}; l.forEach(x => o[x.tag] = x); return o }
let c = by(S.tagChoices(f, []))
ok('with nothing chosen each tag counts its items', c.jazz.count === 3 && c.scifi.count === 1 && c['1959'].count === 2 && !c.jazz.chosen, c)
c = by(S.tagChoices(f, ['jazz']))
ok('after jazz, 1959 would leave two, scifi none', c['1959'].count === 2 && c.scifi.count === 0 && c.rock.count === 0, c)
ok('a chosen tag is marked and counts the list as it is', c.jazz.chosen === true && c.jazz.count === 3, c.jazz)
c = by(S.tagChoices(f, ['jazz', '1959']))
ok('after jazz + 1959 the list is two and every chosen tag says so', c.jazz.count === 2 && c['1959'].count === 2, c)
console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES')
process.exit(fails ? 1 : 0)
