// Test harness: runs qml/Storage.js under Node with a LocalStorage shim
// backed by node:sqlite, so the SQL and the analysis logic get exercised
// for real instead of by eye.
const fs = require('fs')
const vm = require('vm')
const { DatabaseSync } = require('node:sqlite')

const raw = fs.readFileSync(require('path').join(__dirname, '..', 'qml', 'Storage.js'), 'utf8')
const src = raw.split('\n')
  .filter(l => !l.trim().startsWith('.pragma') && !l.trim().startsWith('.import'))
  .join('\n')

const sqlite = new DatabaseSync(':memory:')

function makeTx() {
  return {
    executeSql(sql, params) {
      params = params || []
      const isSelect = /^\s*(select|pragma)/i.test(sql)
      const stmt = sqlite.prepare(sql)
      if (isSelect) {
        const rows = stmt.all(...params)
        return { rows: { length: rows.length, item: i => rows[i] }, insertId: undefined }
      }
      const info = stmt.run(...params)
      return { rows: { length: 0, item: () => undefined }, insertId: Number(info.lastInsertRowid) }
    }
  }
}

const fakeDb = {
  transaction(cb) { cb(makeTx()) },
  readTransaction(cb) { cb(makeTx()) }
}

const LS = { LocalStorage: { openDatabaseSync: () => fakeDb } }

const sandbox = { LS, console, Date, Math, parseInt, parseFloat, isNaN, JSON }
vm.createContext(sandbox)
vm.runInContext(src + '\n;globalThis.__S = { init, addHabit, getHabit, allHabits, archiveHabit, loadHabits, addEntry, voidEntry, entriesOnDay, entriesSince, loadEntriesForDay, streak, completionRate, series, deviationFromTarget, unloggedTodayCount, activeHabitCount, dayKey, weekKey, addDays, localIso, currentVersion, formatEntry, isDueToday, addReferenceEntry, itemTitleForEntry, routines, addRoutine, lastSession, saveSession, sessionSummary, loadSessionHistory, sessionForDay, todaysSession, updateHabit, todayProgress, dayCompletion, sectionRank, addItem, updateItem, items, itemsForHabit, loadItems, setItemState, itemTags, setItemTags, allTags, tagTotals, loadTagTotals, kindTotals, loadKindTotals, exportAll, importAll, describeImport, newUid, itemLogCount, isActiveState, normaliseTag, parseTags, kinds, kindById, addKind, kindUnit, kindLabel, starterKinds, STARTER_KINDS, unitForHabit, habitTotal }', sandbox)

module.exports = { S: sandbox.__S, sqlite, mkModel: () => {
  const m = []
  m.clear = () => { m.length = 0 }
  m.append = o => m.push(o)
  Object.defineProperty(m, 'count', { get() { return m.length } })
  return m
}}
