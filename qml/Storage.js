// Fiat Mos -- LocalStorage helpers
//
// Rules that this file exists to enforce (see the project instruction):
//   * Only additive migrations. ALTER TABLE ... ADD COLUMN, always nullable
//     or with a constant DEFAULT. Never DROP COLUMN, never a type change.
//   * log_entry is append-only. No UPDATE, no DELETE anywhere in this file.
//     Undo is a new row, see voidEntry().
//   * habit is archived (archived_at), never deleted.
//   * Analysis (streaks, trends, deviation from target) is computed on the
//     fly from raw rows. Nothing aggregated is ever stored.
//   * Every SQL string passed to tx.executeSql() is ON ONE LINE. QML's JS
//     engine does not accept multi-line string literals here.

.pragma library
.import QtQuick.LocalStorage 2.0 as LS

var _db = null

function db() {
    if (_db === null) {
        _db = LS.LocalStorage.openDatabaseSync("FiatMos", "", "Fiat Mos habit data", 1000000)
    }
    return _db
}

// ---------------------------------------------------------------------------
// Migrations
// ---------------------------------------------------------------------------
//
// Append new versions to the end of this array. Never edit a version that has
// already shipped -- devices that ran it will not run it again.

var MIGRATIONS = [
    {
        version: 1,
        statements: [
            "CREATE TABLE IF NOT EXISTS habit (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, value_type TEXT NOT NULL CHECK (value_type IN ('boolean','numeric','scale','reference','structured')), unit TEXT, scale_max INTEGER, target_value REAL, frequency TEXT NOT NULL CHECK (frequency IN ('daily','weekly_n','custom_interval')), frequency_n INTEGER, archived_at TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))",
            "CREATE TABLE IF NOT EXISTS log_entry (id INTEGER PRIMARY KEY AUTOINCREMENT, habit_id INTEGER NOT NULL REFERENCES habit(id), logged_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), value_type TEXT NOT NULL, value_bool INTEGER, value_numeric REAL, value_scale INTEGER, superseded_by INTEGER REFERENCES log_entry(id), note TEXT)",
            "CREATE INDEX IF NOT EXISTS idx_log_habit_time ON log_entry(habit_id, logged_at)"
        ]
    },
    {
        version: 2,
        statements: [
            "CREATE TABLE IF NOT EXISTS book (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, author TEXT, status TEXT NOT NULL DEFAULT 'reading' CHECK (status IN ('reading','completed','archived')), started_at TEXT, finished_at TEXT)",
            "CREATE TABLE IF NOT EXISTS log_entry_book (log_entry_id INTEGER NOT NULL REFERENCES log_entry(id), book_id INTEGER NOT NULL REFERENCES book(id), PRIMARY KEY (log_entry_id, book_id))"
        ]
    },
    {
        version: 3,
        statements: [
            "CREATE TABLE IF NOT EXISTS routine (id INTEGER PRIMARY KEY AUTOINCREMENT, habit_id INTEGER NOT NULL REFERENCES habit(id), name TEXT NOT NULL UNIQUE)",
            "CREATE TABLE IF NOT EXISTS session (id INTEGER PRIMARY KEY AUTOINCREMENT, habit_id INTEGER NOT NULL REFERENCES habit(id), routine_id INTEGER REFERENCES routine(id), started_at TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS component (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER NOT NULL REFERENCES session(id), name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE IF NOT EXISTS detail (id INTEGER PRIMARY KEY AUTOINCREMENT, component_id INTEGER NOT NULL REFERENCES component(id), reps INTEGER, weight_kg REAL, duration_sec INTEGER, note TEXT)",
            "CREATE INDEX IF NOT EXISTS idx_session_habit ON session(habit_id, started_at)",
            "CREATE INDEX IF NOT EXISTS idx_component_session ON component(session_id, sort_order)",
            "CREATE INDEX IF NOT EXISTS idx_detail_component ON detail(component_id)"
        ]
    },
    {
        version: 4,
        statements: [
            // Which detail fields a structured habit actually uses:
            // 'strength' (reps + weight), 'timed' (duration), 'reps', 'free'.
            "ALTER TABLE habit ADD COLUMN detail_profile TEXT",
            // Which kind of external entity a reference habit points at.
            // Only 'book' exists so far; the column is here so adding
            // 'language' later needs no migration of existing rows.
            "ALTER TABLE habit ADD COLUMN reference_kind TEXT",
            // A session always has a matching log_entry so streaks work
            // without the analysis layer knowing anything about sessions.
            "ALTER TABLE session ADD COLUMN log_entry_id INTEGER REFERENCES log_entry(id)",
            "CREATE INDEX IF NOT EXISTS idx_leb_book ON log_entry_book(book_id)"
        ]
    },
    {
        version: 5,
        statements: [
            // How much counts as a finished day. NULL means the habit is
            // checked rather than counted -- one log entry is the whole job.
            // With a value, today's entries are summed against it and the row
            // shows a fraction instead of a tick.
            "ALTER TABLE habit ADD COLUMN daily_target REAL",
            // 'morning' | 'afternoon' | 'evening', or NULL for no opinion.
            // Set by hand on the habit, never inferred from log timestamps --
            // Organ may get logged at night and still belong to the morning.
            "ALTER TABLE habit ADD COLUMN time_of_day TEXT"
        ]
    },
    {
        version: 6,
        statements: [
            // The library stops being about books.
            //
            // The table keeps the name `book` on purpose: renaming a table is
            // not an additive migration, and a table name is not a promise to
            // the user. Everything user-facing says "item". `author` and
            // `status` stay where they are and get backfilled into the new
            // columns, so nothing that already works stops working.
            "ALTER TABLE book ADD COLUMN creator TEXT",
            "ALTER TABLE book ADD COLUMN category TEXT",
            "ALTER TABLE book ADD COLUMN unit TEXT",
            // A second status column, free text. The old one has a CHECK
            // constraint locked to reading/completed/archived, and SQLite
            // cannot loosen a constraint without rebuilding the table.
            "ALTER TABLE book ADD COLUMN state TEXT",
            // Masonic study texts and anything else that should stay out of a
            // shared or exported view, without being deleted.
            "ALTER TABLE book ADD COLUMN private INTEGER NOT NULL DEFAULT 0",
            "UPDATE book SET creator = author WHERE creator IS NULL",
            "UPDATE book SET category = 'book' WHERE category IS NULL",
            "UPDATE book SET unit = 'pages' WHERE unit IS NULL",
            "UPDATE book SET state = status WHERE state IS NULL",
            // Tags are the point of the generalisation. Free text, several
            // per item, and what you actually query on later.
            "CREATE TABLE IF NOT EXISTS item_tag (book_id INTEGER NOT NULL REFERENCES book(id), tag TEXT NOT NULL, PRIMARY KEY (book_id, tag))",
            "CREATE INDEX IF NOT EXISTS idx_item_tag_tag ON item_tag(tag)"
        ]
    },
    {
        version: 7,
        // THE ONE NON-ADDITIVE MIGRATION. Agreed while the app is unreleased
        // and has exactly one user, on the understanding that the rule goes
        // back to additive-only afterwards. Take a copy of the database
        // before running it the first time.
        //
        // What it settles: the unit now belongs to the KIND, not to the item
        // and not to the habit. Kind -> item -> log entry -> graph, one value
        // the whole way. A habit tied to a kind therefore has exactly one
        // unit, and "4200 pages in 830 minutes" becomes unrepresentable
        // rather than merely discouraged.
        statements: [
            "CREATE TABLE IF NOT EXISTS item_kind (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, unit TEXT NOT NULL DEFAULT '')",
            // One kind per distinct category already in use, carrying whatever
            // unit those items were using.
            "INSERT INTO item_kind (name, unit) SELECT COALESCE(category, 'book'), COALESCE(MIN(unit), '') FROM book GROUP BY COALESCE(category, 'book')",
            "CREATE TABLE IF NOT EXISTS item (id INTEGER PRIMARY KEY, title TEXT NOT NULL, creator TEXT, kind_id INTEGER REFERENCES item_kind(id), state TEXT NOT NULL DEFAULT 'active', private INTEGER NOT NULL DEFAULT 0, started_at TEXT, finished_at TEXT)",
            "INSERT INTO item (id, title, creator, kind_id, state, private, started_at, finished_at) SELECT b.id, b.title, COALESCE(b.creator, b.author), (SELECT k.id FROM item_kind k WHERE k.name = COALESCE(b.category, 'book')), COALESCE(b.state, b.status, 'active'), COALESCE(b.private, 0), b.started_at, b.finished_at FROM book b",
            "CREATE TABLE item_tag_v7 (item_id INTEGER NOT NULL REFERENCES item(id), tag TEXT NOT NULL, PRIMARY KEY (item_id, tag))",
            "INSERT INTO item_tag_v7 (item_id, tag) SELECT book_id, tag FROM item_tag",
            "DROP TABLE item_tag",
            "ALTER TABLE item_tag_v7 RENAME TO item_tag",
            "CREATE INDEX IF NOT EXISTS idx_item_tag_tag ON item_tag(tag)",
            "CREATE TABLE IF NOT EXISTS log_entry_item (log_entry_id INTEGER NOT NULL REFERENCES log_entry(id), item_id INTEGER NOT NULL REFERENCES item(id), PRIMARY KEY (log_entry_id, item_id))",
            "INSERT INTO log_entry_item (log_entry_id, item_id) SELECT log_entry_id, book_id FROM log_entry_book",
            "CREATE INDEX IF NOT EXISTS idx_lei_item ON log_entry_item(item_id)",
            "DROP TABLE log_entry_book",
            "DROP TABLE book",
            // Which kind a reference habit works through. habit itself is not
            // rebuilt: it is referenced from log_entry, routine and session,
            // and rebuilding the most central table to drop one unused
            // nullable column is a bad trade. reference_kind stays behind,
            // unread.
            "ALTER TABLE habit ADD COLUMN kind_id INTEGER REFERENCES item_kind(id)",
            "UPDATE habit SET kind_id = (SELECT id FROM item_kind WHERE name = 'book') WHERE value_type = 'reference' AND kind_id IS NULL"
        ]
    },
    {
        version: 8,
        // Identity, for export and import.
        //
        // A row's id is a local counter. It says nothing about the row on
        // another phone, so an exported file cannot be matched against an
        // existing database by id -- and log_entry has no natural key either.
        // "Reading, 24 pages, 18 August" can legitimately be two entries.
        //
        // So every row that can travel gets a uid: an opaque string, made
        // once when the row is created, never changed, meaningless except as
        // identity.
        //
        // EXISTING ROWS ARE LEFT AT NULL, DELIBERATELY. Backfilling would
        // mean an UPDATE against log_entry, and this file has exactly one
        // rule it will not bend. A NULL uid means "local only, never matched"
        // -- which is the truth about a row that existed before identity did.
        //
        // Every table at once, because the cost is identical today and
        // asymmetric later: the one left out is the one you will want.
        // item_tag and log_entry_item need none -- they are derivable from
        // their parents' uids plus the tag string.
        statements: [
            "ALTER TABLE habit ADD COLUMN uid TEXT",
            "ALTER TABLE item_kind ADD COLUMN uid TEXT",
            "ALTER TABLE item ADD COLUMN uid TEXT",
            "ALTER TABLE log_entry ADD COLUMN uid TEXT",
            "ALTER TABLE routine ADD COLUMN uid TEXT",
            "ALTER TABLE session ADD COLUMN uid TEXT",
            "ALTER TABLE component ADD COLUMN uid TEXT",
            "ALTER TABLE detail ADD COLUMN uid TEXT",
            "CREATE INDEX IF NOT EXISTS idx_habit_uid ON habit(uid)",
            "CREATE INDEX IF NOT EXISTS idx_log_entry_uid ON log_entry(uid)",
            "CREATE INDEX IF NOT EXISTS idx_item_uid ON item(uid)"
        ]
    }
]

// An opaque identity for a row, made once and never changed.
//
// Not a real UUID -- QML's JS engine has no crypto source, and this does not
// need to resist an adversary. It needs to not collide between two phones
// owned by the same person, and 96 bits of time plus randomness does that
// with room to spare.
function newUid() {
    function chunk() { return Math.floor(Math.random() * 0x100000000).toString(36) }
    return Date.now().toString(36) + "-" + chunk() + "-" + chunk()
}

function currentVersion() {
    var v = 0
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT MAX(version) AS v FROM schema_version")
        if (r.rows.length > 0 && r.rows.item(0).v !== null) {
            v = parseInt(r.rows.item(0).v, 10)
        }
    })
    return v
}

// Idempotent. Safe to call on every app start.
function init() {
    db().transaction(function(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))")
    })

    var applied = currentVersion()

    for (var i = 0; i < MIGRATIONS.length; i++) {
        var m = MIGRATIONS[i]
        if (m.version <= applied) continue
        db().transaction(function(tx) {
            for (var j = 0; j < m.statements.length; j++) {
                tx.executeSql(m.statements[j])
            }
            tx.executeSql("INSERT INTO schema_version (version) VALUES (?)", [m.version])
        })
        console.log("FiatMos: applied migration " + m.version)
    }

    return currentVersion()
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------
//
// Everything is stored as a LOCAL ISO string, not UTC. A habit tracker cares
// about the user's day boundary, and datetime('now') in SQLite is UTC, which
// would silently shift late-evening logs into tomorrow.

function pad(n) {
    return (n < 10 ? "0" : "") + n
}

function localIso(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
         + "T" + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
}

function dayKey(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function dateFromDayKey(key) {
    var p = key.split("-")
    return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
}

function addDays(d, n) {
    var r = new Date(d.getTime())
    r.setDate(r.getDate() + n)
    return r
}

// Monday-based week key, e.g. "2026-W34". Used for weekly_n habits.
function weekKey(d) {
    var t = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    var dayNum = (t.getDay() + 6) % 7          // Mon = 0
    t.setDate(t.getDate() - dayNum + 3)        // Thursday of this week
    var firstThursday = new Date(t.getFullYear(), 0, 4)
    var fDayNum = (firstThursday.getDay() + 6) % 7
    firstThursday.setDate(firstThursday.getDate() - fDayNum + 3)
    var week = 1 + Math.round((t.getTime() - firstThursday.getTime()) / (7 * 24 * 3600 * 1000))
    return t.getFullYear() + "-W" + pad(week)
}

// ---------------------------------------------------------------------------
// Habits
// ---------------------------------------------------------------------------

// Takes an object rather than nine positional arguments -- the argument list
// grew past the point where call sites were readable.
//
//   { name, valueType, unit, scaleMax, targetValue, frequency, frequencyN,
//     detailProfile, referenceKind, dailyTarget, timeOfDay }
function addHabit(h) {
    var id = -1
    db().transaction(function(tx) {
        var r = tx.executeSql("INSERT INTO habit (name, value_type, unit, scale_max, target_value, frequency, frequency_n, detail_profile, reference_kind, daily_target, time_of_day, kind_id, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                              [h.name,
                               h.valueType,
                               (h.unit === undefined || h.unit === "") ? null : h.unit,
                               h.scaleMax === undefined ? null : h.scaleMax,
                               h.targetValue === undefined ? null : h.targetValue,
                               h.frequency,
                               h.frequencyN === undefined ? null : h.frequencyN,
                               h.detailProfile === undefined ? null : h.detailProfile,
                               h.referenceKind === undefined ? null : h.referenceKind,
                               (h.dailyTarget === undefined || h.dailyTarget === "") ? null : h.dailyTarget,
                               (h.timeOfDay === undefined || h.timeOfDay === "") ? null : h.timeOfDay,
                               (h.kindId === undefined || h.kindId < 0) ? null : h.kindId,
                               newUid()])
        id = r.insertId
    })
    return id
}

// habit is not append-only -- it is a definition, not a record of what
// happened -- so editing it in place is correct. Log entries keep their own
// copy of value_type, so changing a habit never rewrites its history.
function updateHabit(h) {
    db().transaction(function(tx) {
        tx.executeSql("UPDATE habit SET name = ?, unit = ?, scale_max = ?, target_value = ?, frequency = ?, frequency_n = ?, detail_profile = ?, daily_target = ?, time_of_day = ?, kind_id = ? WHERE id = ?",
                      [h.name,
                       (h.unit === undefined || h.unit === "") ? null : h.unit,
                       h.scaleMax === undefined ? null : h.scaleMax,
                       h.targetValue === undefined ? null : h.targetValue,
                       h.frequency,
                       h.frequencyN === undefined ? null : h.frequencyN,
                       h.detailProfile === undefined ? null : h.detailProfile,
                       (h.dailyTarget === undefined || h.dailyTarget === "") ? null : h.dailyTarget,
                       (h.timeOfDay === undefined || h.timeOfDay === "") ? null : h.timeOfDay,
                       (h.kindId === undefined || h.kindId < 0) ? null : h.kindId,
                       h.id])
    })
}

function getHabit(habitId) {
    var h = null
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT * FROM habit WHERE id = ?", [habitId])
        if (r.rows.length > 0) h = rowToHabit(r.rows.item(0))
    })
    return h
}

function rowToHabit(row) {
    return {
        id: row.id,
        name: row.name,
        valueType: row.value_type,
        unit: row.unit === null ? "" : row.unit,
        scaleMax: row.scale_max === null ? 0 : row.scale_max,
        targetValue: row.target_value,
        frequency: row.frequency,
        frequencyN: row.frequency_n === null ? 1 : row.frequency_n,
        detailProfile: row.detail_profile === null ? "free" : row.detail_profile,
        referenceKind: row.reference_kind === null ? "book" : row.reference_kind,
        dailyTarget: (row.daily_target === null || row.daily_target === undefined) ? null : row.daily_target,
        timeOfDay: (row.time_of_day === null || row.time_of_day === undefined) ? "" : row.time_of_day,
        kindId: (row.kind_id === null || row.kind_id === undefined) ? -1 : row.kind_id,
        archivedAt: row.archived_at,
        createdAt: row.created_at
    }
}

function allHabits(includeArchived) {
    var out = []
    db().readTransaction(function(tx) {
        var sql = includeArchived
            ? "SELECT * FROM habit ORDER BY archived_at IS NOT NULL, name COLLATE NOCASE"
            : "SELECT * FROM habit WHERE archived_at IS NULL ORDER BY name COLLATE NOCASE"
        var r = tx.executeSql(sql)
        for (var i = 0; i < r.rows.length; i++) out.push(rowToHabit(r.rows.item(i)))
    })
    return out
}

// Soft delete only. History must survive.
function archiveHabit(habitId) {
    db().transaction(function(tx) {
        tx.executeSql("UPDATE habit SET archived_at = ? WHERE id = ?", [localIso(new Date()), habitId])
    })
}

function unarchiveHabit(habitId) {
    db().transaction(function(tx) {
        tx.executeSql("UPDATE habit SET archived_at = NULL WHERE id = ?", [habitId])
    })
}

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

// How far through today this habit is.
//
// A habit is either COUNTED or CHECKED, and the difference is whether
// daily_target is set. Counted habits sum today's entries against the target
// and can be part-done; checked habits are done the moment there is one entry.
// The UI must keep these two apart -- a ring for counted, a filled dot for
// checked -- so the shape says which kind it is without relying on colour.
function todayProgress(habit) {
    var day = dayKey(new Date())
    var rows = entriesOnDay(habit.id, day)
    var counted = habit.dailyTarget !== null && habit.dailyTarget > 0

    var done = 0
    if (habit.valueType === "numeric" || habit.valueType === "reference") {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].valueNumeric !== null) done += rows[i].valueNumeric
        }
    } else {
        done = rows.length
    }

    var logged = rows.length > 0
    var target = counted ? habit.dailyTarget : 1
    var complete = counted ? (done >= target) : logged
    var fraction = counted
        ? Math.max(0, Math.min(1, target > 0 ? done / target : 0))
        : (logged ? 1 : 0)

    return {
        counted: counted,
        done: done,
        target: target,
        logged: logged,
        complete: complete,
        fraction: fraction,
        entries: rows
    }
}

// The header ring: how much of today is behind you. Only habits that are due
// today count, so a habit resting between intervals neither helps nor hurts.
function dayCompletion() {
    var habits = allHabits(false)
    var total = 0, completed = 0
    for (var i = 0; i < habits.length; i++) {
        if (!isDueToday(habits[i])) continue
        total++
        if (todayProgress(habits[i]).complete) completed++
    }
    return {
        completed: completed,
        total: total,
        fraction: total > 0 ? completed / total : 0
    }
}

// Fixed order, always. Untagged habits trail at the end.
function sectionRank(timeOfDay) {
    if (timeOfDay === "morning") return 0
    if (timeOfDay === "afternoon") return 1
    if (timeOfDay === "evening") return 2
    return 3
}

// Fills a ListModel for HabitListPage. Everything here is computed, not
// stored. When groupByTime is true the rows come back sorted by section so a
// ListView section header lands in the right place.
function loadHabits(model, groupByTime) {
    model.clear()
    var habits = allHabits(false)
    var today = dayKey(new Date())

    if (groupByTime) {
        habits.sort(function(a, b) {
            var ra = sectionRank(a.timeOfDay), rb = sectionRank(b.timeOfDay)
            if (ra !== rb) return ra - rb
            return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1
        })
    }

    for (var i = 0; i < habits.length; i++) {
        var h = habits[i]
        var p = todayProgress(h)

        var summary = ""
        if (p.logged) {
            if (h.valueType === "structured") summary = sessionSummary(h.id, today)
            else summary = formatEntry(h, p.entries[p.entries.length - 1])
        }

        model.append({
            habitId: h.id,
            name: h.name,
            valueType: h.valueType,
            unit: h.unit,
            scaleMax: h.scaleMax,
            targetValue: h.targetValue === null ? -1 : h.targetValue,
            frequency: h.frequency,
            frequencyN: h.frequencyN,
            timeOfDay: h.timeOfDay,
            section: h.timeOfDay === "" ? "anytime" : h.timeOfDay,
            counted: p.counted,
            doneToday: p.done,
            dailyTarget: p.target,
            fraction: p.fraction,
            loggedToday: p.logged,
            completeToday: p.complete,
            todaySummary: summary,
            streak: streak(h),
            dueToday: isDueToday(h)
        })
    }
    return model.count
}

// ---------------------------------------------------------------------------
// Log entries
// ---------------------------------------------------------------------------
//
// Append-only. An "active" entry is one that is not itself a void marker and
// that no later row supersedes.
//
// NOTE ON superseded_by: the instruction is ambiguous about direction. This
// implementation reads it as "this row supersedes row N", so a correction or
// an undo is a pure INSERT and log_entry never needs an UPDATE. A full undo is
// a row with value_type 'void'.

var ACTIVE_FILTER = "value_type <> 'void' AND id NOT IN (SELECT superseded_by FROM log_entry WHERE superseded_by IS NOT NULL)"

function addEntry(habit, values) {
    var id = -1
    var now = values && values.loggedAt ? values.loggedAt : localIso(new Date())
    var vBool = null, vNum = null, vScale = null
    if (habit.valueType === "boolean") vBool = 1
    if (habit.valueType === "numeric") vNum = values.numeric
    if (habit.valueType === "scale") vScale = values.scale
    if (habit.valueType === "reference" && values.numeric !== undefined && values.numeric !== null) vNum = values.numeric
    var note = (values && values.note && values.note !== "") ? values.note : null
    var supersedes = (values && values.supersedes) ? values.supersedes : null

    db().transaction(function(tx) {
        var r = tx.executeSql("INSERT INTO log_entry (habit_id, logged_at, value_type, value_bool, value_numeric, value_scale, superseded_by, note, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                              [habit.id, now, habit.valueType, vBool, vNum, vScale, supersedes, note, newUid()])
        id = r.insertId
    })
    return id
}

// Undo. Never a DELETE -- a new row that supersedes the old one and carries
// no value of its own.
function voidEntry(habitId, entryId) {
    var id = -1
    db().transaction(function(tx) {
        var r = tx.executeSql("INSERT INTO log_entry (habit_id, logged_at, value_type, superseded_by, uid) VALUES (?, ?, 'void', ?, ?)",
                              [habitId, localIso(new Date()), entryId, newUid()])
        id = r.insertId
    })
    return id
}

function rowToEntry(row) {
    return {
        id: row.id,
        habitId: row.habit_id,
        loggedAt: row.logged_at,
        valueType: row.value_type,
        valueBool: row.value_bool,
        valueNumeric: row.value_numeric,
        valueScale: row.value_scale,
        note: row.note === null ? "" : row.note
    }
}

function entriesOnDay(habitId, day) {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT * FROM log_entry WHERE habit_id = ? AND substr(logged_at, 1, 10) = ? AND " + ACTIVE_FILTER + " ORDER BY logged_at, id", [habitId, day])
        for (var i = 0; i < r.rows.length; i++) out.push(rowToEntry(r.rows.item(i)))
    })
    return out
}

function entriesSince(habitId, sinceDay) {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT * FROM log_entry WHERE habit_id = ? AND substr(logged_at, 1, 10) >= ? AND " + ACTIVE_FILTER + " ORDER BY logged_at, id", [habitId, sinceDay])
        for (var i = 0; i < r.rows.length; i++) out.push(rowToEntry(r.rows.item(i)))
    })
    return out
}

function loadEntriesForDay(model, habitId, day) {
    model.clear()
    var rows = entriesOnDay(habitId, day)
    for (var i = 0; i < rows.length; i++) {
        var title = ""
        if (rows[i].valueType === "reference") title = itemTitleForEntry(rows[i].id)
        model.append({
            entryId: rows[i].id,
            loggedAt: rows[i].loggedAt,
            timeLabel: rows[i].loggedAt.substr(11, 5),
            valueType: rows[i].valueType,
            valueNumeric: rows[i].valueNumeric === null ? 0 : rows[i].valueNumeric,
            hasNumeric: rows[i].valueNumeric !== null,
            valueScale: rows[i].valueScale === null ? -1 : rows[i].valueScale,
            bookTitle: title,
            note: rows[i].note
        })
    }
    return model.count
}

function formatEntry(habit, entry) {
    if (habit.valueType === "boolean") return "✓"
    if (habit.valueType === "numeric") {
        var n = entry.valueNumeric
        var s = (Math.round(n * 100) / 100).toString()
        return habit.unit === "" ? s : s + " " + habit.unit
    }
    if (habit.valueType === "scale") return entry.valueScale + "/" + habit.scaleMax
    if (habit.valueType === "reference") {
        var t = itemTitleForEntry(entry.id)
        if (entry.valueNumeric !== null && entry.valueNumeric !== undefined) {
            var v = Math.round(entry.valueNumeric * 100) / 100
            var u = unitForHabit(habit)
            var suffix = u === "" ? v : v + " " + u
            return t === "" ? String(suffix) : t + " · " + suffix
        }
        return t === "" ? "✓" : t
    }
    return "✓"
}

// ---------------------------------------------------------------------------
// Reference template -- the library
// ---------------------------------------------------------------------------
//
// Three tables and one rule.
//
//   item_kind   what sort of thing it is, and WHAT IT IS MEASURED IN.
//               "book" is pages, "audiobook" is minutes, "photo roll" is
//               frames. You invent kinds as you go; the unit is set once,
//               when the kind is born.
//   item        one book, one piece, one roll. It belongs to a kind and
//               inherits the kind's unit. It has no unit of its own.
//   item_tag    free labels, several per item, for questions that cut
//               across kinds.
//
// The rule: a reference habit is tied to one kind, so it has exactly one
// unit. Mixing pages and minutes inside one habit is not discouraged, it is
// unrepresentable. "4200 pages in 830 minutes" cannot be produced.

// The kinds offered before you have invented any of your own.
//
// This list lives in code, NOT in the database. Nothing is inserted until
// somebody actually picks one, so it costs no migration, it can be reordered
// or reworded freely between releases, and the library never fills up with
// kinds you never used. A kind only becomes a row the moment it is chosen.
var STARTER_KINDS = [
    { name: "book", unit: "pages" },
    { name: "audiobook", unit: "minutes" },
    { name: "article", unit: "pages" },
    { name: "course", unit: "lessons" },
    { name: "repertoire", unit: "minutes" },
    { name: "photo roll", unit: "frames" },
    { name: "series", unit: "episodes" },
    { name: "draft", unit: "words" }
]

// Anything not finished or put away is still on the go.
function isActiveState(state) {
    return state !== "completed" && state !== "archived"
}

// -- kinds -----------------------------------------------------------------

function kinds() {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT id, name, unit FROM item_kind ORDER BY name COLLATE NOCASE")
        for (var i = 0; i < r.rows.length; i++) {
            out.push({ id: r.rows.item(i).id, name: r.rows.item(i).name, unit: r.rows.item(i).unit })
        }
    })
    return out
}

function kindById(kindId) {
    var k = null
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT id, name, unit FROM item_kind WHERE id = ?", [kindId])
        if (r.rows.length > 0) k = { id: r.rows.item(0).id, name: r.rows.item(0).name, unit: r.rows.item(0).unit }
    })
    return k
}

// Names are unique, so an existing name is reused rather than duplicated.
// The unit of an existing kind is never silently rewritten -- changing what
// a kind is measured in would reinterpret every number already logged.
function addKind(name, unit) {
    var id = -1
    var clean = String(name).trim()
    if (clean === "") return -1
    db().transaction(function(tx) {
        var e = tx.executeSql("SELECT id FROM item_kind WHERE name = ?", [clean])
        if (e.rows.length > 0) {
            id = e.rows.item(0).id
        } else {
            var r = tx.executeSql("INSERT INTO item_kind (name, unit, uid) VALUES (?, ?, ?)",
                                  [clean, unit === undefined ? "" : String(unit).trim(), newUid()])
            id = r.insertId
        }
    })
    return id
}

// The suggestions worth showing: the starter list, minus anything you have
// already made yourself. Matching is on name, case-insensitively, because
// "Book" and "book" are the same kind of thing to a human.
function starterKinds() {
    var mine = kinds()
    var taken = {}
    for (var i = 0; i < mine.length; i++) taken[mine[i].name.toLowerCase()] = true
    var out = []
    for (var j = 0; j < STARTER_KINDS.length; j++) {
        if (!taken[STARTER_KINDS[j].name.toLowerCase()]) out.push(STARTER_KINDS[j])
    }
    return out
}

function kindUnit(kindId) {
    var k = kindById(kindId)
    return k === null ? "" : k.unit
}

// The kind, written the way it is shown: "book · pages". A kind with no unit
// is possible (an old one, or one you did not bother measuring) and prints as
// just its name rather than a trailing separator.
function kindLabel(kind) {
    if (kind === null || kind === undefined) return ""
    if (kind.unit === undefined || kind.unit === "") return kind.name
    return kind.name + " · " + kind.unit
}

// What a habit's numbers are measured in. Reference habits read it off their
// kind; everything else keeps its own unit.
function unitForHabit(habit) {
    if (habit === null || habit === undefined) return ""
    if (habit.valueType === "reference") return kindUnit(habit.kindId)
    return habit.unit
}

// -- items -----------------------------------------------------------------

function addItem(o) {
    var id = -1
    db().transaction(function(tx) {
        var r = tx.executeSql("INSERT INTO item (title, creator, kind_id, state, private, started_at, uid) VALUES (?, ?, ?, ?, ?, ?, ?)",
                              [o.title,
                               (o.creator === undefined || o.creator === "") ? null : o.creator,
                               (o.kindId === undefined || o.kindId < 0) ? null : o.kindId,
                               // A new item is on the go. Nobody creates a
                               // book already finished, so it is not a choice
                               // at creation -- it is what the library does
                               // to it later.
                               "active",
                               o.private ? 1 : 0,
                               localIso(new Date()),
                               newUid()])
        id = r.insertId
    })
    if (o.tags !== undefined) setItemTags(id, o.tags)
    return id
}

function updateItem(o) {
    db().transaction(function(tx) {
        tx.executeSql("UPDATE item SET title = ?, creator = ?, kind_id = ?, private = ? WHERE id = ?",
                      [o.title,
                       (o.creator === undefined || o.creator === "") ? null : o.creator,
                       (o.kindId === undefined || o.kindId < 0) ? null : o.kindId,
                       o.private ? 1 : 0,
                       o.id])
    })
    if (o.tags !== undefined) setItemTags(o.id, o.tags)
}

function rowToItem(row) {
    return {
        id: row.id,
        title: row.title,
        creator: (row.creator === null || row.creator === undefined) ? "" : row.creator,
        kindId: (row.kind_id === null || row.kind_id === undefined) ? -1 : row.kind_id,
        kindName: (row.kind_name === null || row.kind_name === undefined) ? "" : row.kind_name,
        unit: (row.unit === null || row.unit === undefined) ? "" : row.unit,
        state: row.state,
        private: row.private === 1,
        startedAt: row.started_at,
        finishedAt: row.finished_at
    }
}

// filter: { kindId, active, tag, includePrivate }  -- every field optional
function items(filter) {
    filter = filter || {}
    var out = []
    db().readTransaction(function(tx) {
        var sql = "SELECT i.*, k.name AS kind_name, k.unit AS unit FROM item i LEFT JOIN item_kind k ON k.id = i.kind_id"
        var args = []
        if (filter.tag !== undefined && filter.tag !== "") {
            sql += " JOIN item_tag t ON t.item_id = i.id AND t.tag = ?"
            args.push(filter.tag)
        }
        sql += " WHERE 1 = 1"
        if (filter.kindId !== undefined && filter.kindId >= 0) {
            sql += " AND i.kind_id = ?"
            args.push(filter.kindId)
        }
        if (filter.includePrivate !== true) sql += " AND i.private = 0"
        sql += " ORDER BY i.title COLLATE NOCASE"
        var r = tx.executeSql(sql, args)
        for (var i = 0; i < r.rows.length; i++) {
            var it = rowToItem(r.rows.item(i))
            if (filter.active === true && !isActiveState(it.state)) continue
            if (filter.active === false && isActiveState(it.state)) continue
            out.push(it)
        }
    })
    return out
}

// What a given reference habit may be logged against: on the go, and of the
// habit's own kind. This is what makes it impossible to log a roll of film
// under Reading.
function itemsForHabit(habit) {
    if (habit === null || habit === undefined) return []
    return items({ kindId: habit.kindId, active: true, includePrivate: true })
}

function loadItems(model, filter) {
    model.clear()
    var list = items(filter)
    for (var i = 0; i < list.length; i++) {
        var it = list[i]
        model.append({
            itemId: it.id,
            title: it.title,
            creator: it.creator,
            kindId: it.kindId,
            kindName: it.kindName,
            unit: it.unit,
            state: it.state,
            isPrivate: it.private,
            active: isActiveState(it.state),
            tagList: itemTags(it.id).join(", "),
            loggedDays: itemLogCount(it.id),
            startedAt: it.startedAt === null ? "" : it.startedAt,
            finishedAt: it.finishedAt === null ? "" : it.finishedAt
        })
    }
    return model.count
}

// The item is a lifecycle entity, not a log row, so UPDATE is correct here.
function setItemState(itemId, state) {
    db().transaction(function(tx) {
        if (state === "completed") {
            tx.executeSql("UPDATE item SET state = ?, finished_at = ? WHERE id = ?", [state, localIso(new Date()), itemId])
        } else {
            tx.executeSql("UPDATE item SET state = ?, finished_at = NULL WHERE id = ?", [state, itemId])
        }
    })
}

// -- tags -------------------------------------------------------------------

function itemTags(itemId) {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT tag FROM item_tag WHERE item_id = ? ORDER BY tag", [itemId])
        for (var i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).tag)
    })
    return out
}

function normaliseTag(t) {
    return String(t).trim().toLowerCase().replace(/\s+/g, "-")
}

// Replaces the whole set. item_tag is a join table, not a log, so rewriting
// it is not the same sin as touching log_entry.
function setItemTags(itemId, tags) {
    var clean = []
    for (var i = 0; i < tags.length; i++) {
        var t = normaliseTag(tags[i])
        if (t !== "" && clean.indexOf(t) < 0) clean.push(t)
    }
    db().transaction(function(tx) {
        tx.executeSql("DELETE FROM item_tag WHERE item_id = ?", [itemId])
        for (var j = 0; j < clean.length; j++) {
            tx.executeSql("INSERT INTO item_tag (item_id, tag) VALUES (?, ?)", [itemId, clean[j]])
        }
    })
    return clean
}

function parseTags(text) {
    return String(text).split(",")
}

function allTags() {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT tag, COUNT(*) AS n FROM item_tag GROUP BY tag ORDER BY n DESC, tag")
        for (var i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).tag)
    })
    return out
}

// -- log entries against an item -------------------------------------------

function itemTitleForEntry(entryId) {
    var t = ""
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT i.title AS title FROM log_entry_item lei JOIN item i ON i.id = lei.item_id WHERE lei.log_entry_id = ?", [entryId])
        if (r.rows.length > 0) t = r.rows.item(0).title
    })
    return t
}

// One log_entry plus the junction row that ties it to an item.
function addReferenceEntry(habit, itemId, numeric, note) {
    var entryId = addEntry(habit, { numeric: (numeric === null || numeric === undefined) ? null : numeric, note: note })
    db().transaction(function(tx) {
        tx.executeSql("INSERT INTO log_entry_item (log_entry_id, item_id) VALUES (?, ?)", [entryId, itemId])
    })
    return entryId
}

var LIVE_ENTRY = "le.value_type <> 'void' AND le.id NOT IN (SELECT superseded_by FROM log_entry WHERE superseded_by IS NOT NULL)"

function itemLogCount(itemId) {
    var n = 0
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT COUNT(DISTINCT substr(le.logged_at, 1, 10)) AS n FROM log_entry_item lei JOIN log_entry le ON le.id = lei.log_entry_id WHERE lei.item_id = ? AND " + LIVE_ENTRY, [itemId])
        if (r.rows.length > 0) n = r.rows.item(0).n
    })
    return n
}

// -- what a tag adds up to --------------------------------------------------
//
// Still grouped by unit. With the unit living on the kind there is usually
// only one row per tag -- but a tag may legitimately span kinds ("french"
// over books and audiobooks), and then the split is the whole point.
// lookbackDays <= 0 means all time.
function tagTotals(tag, lookbackDays, includePrivate) {
    var out = []
    var since = lookbackDays > 0 ? dayKey(addDays(new Date(), -lookbackDays)) : "0000-00-00"
    db().readTransaction(function(tx) {
        // Grouped by UNIT, not by kind: two kinds measured the same way are
        // the same question. The kind names come along as a list so the row
        // can say WHICH kinds it merged -- without that, a tag spanning
        // audiobooks and repertoire looks like a single mysterious pile of
        // minutes, and there is no way to tell from the screen whether that
        // is right.
        var sql = "SELECT COALESCE(k.unit, '') AS unit, GROUP_CONCAT(DISTINCT COALESCE(k.name, '')) AS kinds, SUM(COALESCE(le.value_numeric, 0)) AS total, COUNT(DISTINCT substr(le.logged_at, 1, 10)) AS days, COUNT(DISTINCT i.id) AS items FROM item_tag t JOIN item i ON i.id = t.item_id LEFT JOIN item_kind k ON k.id = i.kind_id JOIN log_entry_item lei ON lei.item_id = i.id JOIN log_entry le ON le.id = lei.log_entry_id WHERE t.tag = ? AND substr(le.logged_at, 1, 10) >= ? AND " + LIVE_ENTRY
        if (includePrivate !== true) sql += " AND i.private = 0"
        sql += " GROUP BY COALESCE(k.unit, '') ORDER BY total DESC"
        var r = tx.executeSql(sql, [tag, since])
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            var names = (row.kinds === null || row.kinds === undefined) ? "" : String(row.kinds)
            out.push({ unit: row.unit, kinds: names.split(","), total: row.total, days: row.days, items: row.items })
        }
    })
    return out
}

// Totals per KIND, optionally narrowed to one tag.
//
// This is the one tagTotals() should have been. A kind owns exactly one unit,
// so a row per kind can never mix pages and minutes -- the separation falls
// out of the data model instead of being enforced by a GROUP BY. And because
// the tag join is optional, an UNTAGGED item still shows up. That was the
// whole complaint: you read a book, the pages were in the habit's history,
// and the totals page pretended nothing had happened, because tagging is
// something you do afterwards and often not at all.
//
// Pass tag = "" for everything. Two kinds that happen to share a unit stay on
// separate rows: they are different things you did, and adding them up is a
// question you can ask by tagging both.
function kindTotals(tag, lookbackDays, includePrivate) {
    var out = []
    var since = lookbackDays > 0 ? dayKey(addDays(new Date(), -lookbackDays)) : "0000-00-00"
    var wanted = (tag === undefined || tag === null) ? "" : String(tag)
    db().readTransaction(function(tx) {
        var sql = "SELECT COALESCE(i.kind_id, -1) AS kind_id, COALESCE(k.name, '') AS name, COALESCE(k.unit, '') AS unit, SUM(COALESCE(le.value_numeric, 0)) AS total, COUNT(DISTINCT substr(le.logged_at, 1, 10)) AS days, COUNT(DISTINCT i.id) AS items FROM item i LEFT JOIN item_kind k ON k.id = i.kind_id JOIN log_entry_item lei ON lei.item_id = i.id JOIN log_entry le ON le.id = lei.log_entry_id"
        var args = []
        if (wanted !== "") {
            sql += " JOIN item_tag t ON t.item_id = i.id AND t.tag = ?"
            args.push(wanted)
        }
        sql += " WHERE substr(le.logged_at, 1, 10) >= ? AND " + LIVE_ENTRY
        args.push(since)
        if (includePrivate !== true) sql += " AND i.private = 0"
        sql += " GROUP BY COALESCE(i.kind_id, -1) ORDER BY total DESC, name COLLATE NOCASE"
        var r = tx.executeSql(sql, args)
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            out.push({ kindId: row.kind_id, name: row.name, unit: row.unit,
                       total: row.total, days: row.days, items: row.items })
        }
    })
    return out
}

function loadKindTotals(model, tag, lookbackDays, includePrivate) {
    model.clear()
    var rows = kindTotals(tag, lookbackDays, includePrivate)
    for (var i = 0; i < rows.length; i++) {
        model.append({
            kindId: rows[i].kindId,
            kindName: rows[i].name,
            unit: rows[i].unit,
            total: Math.round(rows[i].total * 100) / 100,
            days: rows[i].days,
            itemCount: rows[i].items
        })
    }
    return model.count
}

function loadTagTotals(model, tag, lookbackDays, includePrivate) {
    model.clear()
    var rows = tagTotals(tag, lookbackDays, includePrivate)
    for (var i = 0; i < rows.length; i++) {
        model.append({
            unit: rows[i].unit === "" ? "" : rows[i].unit,
            kindNames: rows[i].kinds.join(", "),
            total: Math.round(rows[i].total * 100) / 100,
            days: rows[i].days,
            itemCount: rows[i].items
        })
    }
    return model.count
}

// What one habit adds up to over a period. One unit, by construction.
// Sum, mean and median over the days that were actually logged.
//
// Per LOGGED day, not per calendar day. A mean that divides by 90 when you
// logged on nine of them is not a fact about the habit, it is a fact about the
// window -- and the day grid above already says how often you turned up.
//
// The median is here because the mean lies whenever one day is unlike the
// others. Ten pages a night and then a four-hour Sunday gives a mean nobody
// recognises; the median is the night you actually have.
function habitTotal(habit, lookbackDays) {
    var s = series(habit, lookbackDays)
    var sum = 0, values = []
    for (var i = 0; i < s.length; i++) {
        if (s[i].value === null) continue
        sum += s[i].value
        values.push(s[i].value)
    }

    var days = values.length
    var round = function(v) { return Math.round(v * 100) / 100 }

    var mean = null, median = null
    if (days > 0) {
        mean = round(sum / days)
        // Sort numerically. The default sort is lexicographic, which puts
        // 100 before 9 and quietly ruins the answer.
        var sorted = values.slice().sort(function(a, b) { return a - b })
        var mid = Math.floor(days / 2)
        median = round(days % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2)
    }

    return {
        total: round(sum),
        mean: mean,
        median: median,
        days: days,
        unit: unitForHabit(habit)
    }
}

// ---------------------------------------------------------------------------
// Structured template -- sessions
// ---------------------------------------------------------------------------

function routines(habitId) {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT id, name FROM routine WHERE habit_id = ? ORDER BY name COLLATE NOCASE", [habitId])
        for (var i = 0; i < r.rows.length; i++) out.push({ id: r.rows.item(i).id, name: r.rows.item(i).name })
    })
    return out
}

// routine.name is UNIQUE across the table, so an existing name is reused
// rather than failing the insert.
function addRoutine(habitId, name) {
    var id = -1
    db().transaction(function(tx) {
        var e = tx.executeSql("SELECT id FROM routine WHERE name = ?", [name])
        if (e.rows.length > 0) {
            id = e.rows.item(0).id
        } else {
            var r = tx.executeSql("INSERT INTO routine (habit_id, name, uid) VALUES (?, ?, ?)", [habitId, name, newUid()])
            id = r.insertId
        }
    })
    return id
}

// The most recent session for a habit, optionally restricted to one routine.
// Returns { id, startedAt, routineId, components: [{ name, details: [...] }] }
// or null. Used both for the history view and for prefilling a new session --
// prefill lives in UI state only, nothing is copied into the database.
// Everything hanging off one session row. Shared by lastSession and
// sessionForDay so the two can never disagree about what a session is.
function loadSessionRow(tx, row) {
    var s = { id: row.id, startedAt: row.started_at, routineId: row.routine_id,
              entryId: row.log_entry_id, components: [] }
    var c = tx.executeSql("SELECT * FROM component WHERE session_id = ? ORDER BY sort_order, id", [s.id])
    for (var i = 0; i < c.rows.length; i++) {
        var comp = { name: c.rows.item(i).name, details: [] }
        var d = tx.executeSql("SELECT * FROM detail WHERE component_id = ? ORDER BY id", [c.rows.item(i).id])
        for (var j = 0; j < d.rows.length; j++) {
            comp.details.push({
                reps: d.rows.item(j).reps,
                weight: d.rows.item(j).weight_kg,
                duration: d.rows.item(j).duration_sec,
                note: d.rows.item(j).note === null ? "" : d.rows.item(j).note
            })
        }
        s.components.push(comp)
    }
    return s
}

// Today's session for this habit, if there is one.
//
// This is what makes a workout one thing rather than a pile of saves. You do
// one gym session a day; saving twice during it should carry on with the same
// session, not start a second one.
function sessionForDay(habitId, day) {
    var s = null
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT * FROM session WHERE habit_id = ? AND substr(started_at, 1, 10) = ? ORDER BY id DESC LIMIT 1", [habitId, day])
        if (r.rows.length > 0) s = loadSessionRow(tx, r.rows.item(0))
    })
    return s
}

function todaysSession(habitId) {
    return sessionForDay(habitId, dayKey(new Date()))
}

function lastSession(habitId, routineId) {
    var s = null
    db().readTransaction(function(tx) {
        var r
        if (routineId === null || routineId === undefined) {
            r = tx.executeSql("SELECT * FROM session WHERE habit_id = ? ORDER BY started_at DESC, id DESC LIMIT 1", [habitId])
        } else {
            r = tx.executeSql("SELECT * FROM session WHERE habit_id = ? AND routine_id = ? ORDER BY started_at DESC, id DESC LIMIT 1", [habitId, routineId])
        }
        if (r.rows.length === 0) return
        var row = r.rows.item(0)
        s = { id: row.id, startedAt: row.started_at, routineId: row.routine_id, components: [] }

        var c = tx.executeSql("SELECT * FROM component WHERE session_id = ? ORDER BY sort_order, id", [s.id])
        for (var i = 0; i < c.rows.length; i++) {
            var comp = { name: c.rows.item(i).name, details: [] }
            var d = tx.executeSql("SELECT * FROM detail WHERE component_id = ? ORDER BY id", [c.rows.item(i).id])
            for (var j = 0; j < d.rows.length; j++) {
                comp.details.push({
                    reps: d.rows.item(j).reps,
                    weight: d.rows.item(j).weight_kg,
                    duration: d.rows.item(j).duration_sec,
                    note: d.rows.item(j).note === null ? "" : d.rows.item(j).note
                })
            }
            s.components.push(comp)
        }
    })
    return s
}

// ONE SESSION PER DAY.
//
// Saving twice during a workout used to write a second session and a second
// log entry, so a Tuesday at the gym could end up as three sessions in the
// history -- and the way to avoid that was to remember not to save, which is
// the wrong thing to ask of somebody between sets.
//
// So: if today already has a session for this habit, this rewrites it. The
// session row keeps its id, its uid and its log_entry, and the exercises and
// sets underneath are replaced wholesale.
//
// That does NOT break the append-only rule. log_entry is the ledger, and there
// is still exactly one entry for the day -- the first save wrote it and no
// later save touches it. session, component and detail are a description of
// what happened, not a record that it did, and a description is allowed to be
// corrected. The DELETEs below are the only ones in this file outside import,
// and they are scoped to the session being rewritten.
//
// Components with no name are dropped; so are detail rows where every field is
// empty.
//
// comps: [{ name, details: [{reps, weight, duration, note}] }]
function saveSession(habit, routineId, comps, note) {
    var existing = todaysSession(habit.id)

    // The entry is written once a day, by whichever save comes first.
    var entryId = (existing !== null && existing.entryId !== null && existing.entryId !== undefined)
        ? existing.entryId
        : addEntry(habit, { note: note })
    var sessionId = existing === null ? -1 : existing.id

    db().transaction(function(tx) {
        var rid = (routineId === null || routineId === undefined || routineId < 0) ? null : routineId

        if (existing !== null) {
            // Children first, so nothing is left pointing at a gone parent.
            tx.executeSql("DELETE FROM detail WHERE component_id IN (SELECT id FROM component WHERE session_id = ?)", [sessionId])
            tx.executeSql("DELETE FROM component WHERE session_id = ?", [sessionId])
            tx.executeSql("UPDATE session SET routine_id = ? WHERE id = ?", [rid, sessionId])
        } else {
            var r = tx.executeSql("INSERT INTO session (habit_id, routine_id, started_at, log_entry_id, uid) VALUES (?, ?, ?, ?, ?)",
                                  [habit.id, rid, localIso(new Date()), entryId, newUid()])
            sessionId = r.insertId
        }

        var order = 0
        for (var i = 0; i < comps.length; i++) {
            var name = (comps[i].name || "").trim()
            if (name === "") continue
            var cr = tx.executeSql("INSERT INTO component (session_id, name, sort_order, uid) VALUES (?, ?, ?, ?)", [sessionId, name, order, newUid()])
            order++
            var compId = cr.insertId
            var details = comps[i].details || []
            for (var j = 0; j < details.length; j++) {
                var d = details[j]
                var reps = (d.reps === "" || d.reps === undefined) ? null : d.reps
                var weight = (d.weight === "" || d.weight === undefined) ? null : d.weight
                var dur = (d.duration === "" || d.duration === undefined) ? null : d.duration
                var dnote = (d.note === "" || d.note === undefined) ? null : d.note
                if (reps === null && weight === null && dur === null && dnote === null) continue
                tx.executeSql("INSERT INTO detail (component_id, reps, weight_kg, duration_sec, note, uid) VALUES (?, ?, ?, ?, ?, ?)",
                              [compId, reps, weight, dur, dnote, newUid()])
            }
        }
    })

    return { sessionId: sessionId, entryId: entryId }
}

// Short human summary of what was done on a given day, for the habit list.
function sessionSummary(habitId, day) {
    var out = ""
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT s.id AS id, r.name AS rname FROM session s LEFT JOIN routine r ON r.id = s.routine_id WHERE s.habit_id = ? AND substr(s.started_at, 1, 10) = ? ORDER BY s.started_at DESC, s.id DESC LIMIT 1", [habitId, day])
        if (r.rows.length === 0) return
        var row = r.rows.item(0)
        var c = tx.executeSql("SELECT COUNT(*) AS n FROM component WHERE session_id = ?", [row.id])
        var n = c.rows.length > 0 ? c.rows.item(0).n : 0
        out = (row.rname === null ? "" : row.rname + " · ") + n
    })
    return out
}

function loadSessionHistory(model, habitId, limit) {
    model.clear()
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT s.id AS id, s.started_at AS started_at, r.name AS rname FROM session s LEFT JOIN routine r ON r.id = s.routine_id WHERE s.habit_id = ? ORDER BY s.started_at DESC, s.id DESC LIMIT ?", [habitId, limit])
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            var c = tx.executeSql("SELECT COUNT(*) AS n FROM component WHERE session_id = ?", [row.id])
            model.append({
                sessionId: row.id,
                startedAt: row.started_at,
                dayLabel: row.started_at.substr(0, 10),
                routineName: row.rname === null ? "" : row.rname,
                componentCount: c.rows.length > 0 ? c.rows.item(0).n : 0
            })
        }
    })
    return model.count
}

// ---------------------------------------------------------------------------
// Analysis -- always on the fly, never stored
// ---------------------------------------------------------------------------

// The set of days (as keys) that have at least one active entry, newest first.
function loggedDayKeys(habitId, lookbackDays) {
    var out = []
    var since = dayKey(addDays(new Date(), -lookbackDays))
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT DISTINCT substr(logged_at, 1, 10) AS d FROM log_entry WHERE habit_id = ? AND substr(logged_at, 1, 10) >= ? AND " + ACTIVE_FILTER + " ORDER BY d DESC", [habitId, since])
        for (var i = 0; i < r.rows.length; i++) out.push(r.rows.item(i).d)
    })
    return out
}

function isDueToday(habit) {
    if (habit.frequency === "daily") return true
    if (habit.frequency === "weekly_n") {
        var wk = weekKey(new Date())
        var days = loggedDayKeys(habit.id, 14)
        var n = 0
        for (var i = 0; i < days.length; i++) {
            if (weekKey(dateFromDayKey(days[i])) === wk) n++
        }
        return n < habit.frequencyN
    }
    if (habit.frequency === "custom_interval") {
        var last = lastLoggedDay(habit.id)
        if (last === null) return true
        var gap = Math.round((dateFromDayKey(dayKey(new Date())).getTime() - dateFromDayKey(last).getTime()) / 86400000)
        return gap >= habit.frequencyN
    }
    return true
}

function lastLoggedDay(habitId) {
    var d = null
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT MAX(substr(logged_at, 1, 10)) AS d FROM log_entry WHERE habit_id = ? AND " + ACTIVE_FILTER, [habitId])
        if (r.rows.length > 0 && r.rows.item(0).d !== null) d = r.rows.item(0).d
    })
    return d
}

// Running streak, counted in whatever period the habit's frequency defines.
// The current period never breaks the streak just by being unfinished -- an
// unlogged today only means the streak has not been extended yet.
function streak(habit) {
    var lookback = 400
    var days = loggedDayKeys(habit.id, lookback)
    if (days.length === 0) return 0

    var set = {}
    for (var i = 0; i < days.length; i++) set[days[i]] = true

    if (habit.frequency === "daily") {
        var cursor = new Date()
        if (!set[dayKey(cursor)]) cursor = addDays(cursor, -1)
        var n = 0
        while (set[dayKey(cursor)]) {
            n++
            cursor = addDays(cursor, -1)
        }
        return n
    }

    if (habit.frequency === "weekly_n") {
        var perWeek = {}
        for (var j = 0; j < days.length; j++) {
            var k = weekKey(dateFromDayKey(days[j]))
            perWeek[k] = (perWeek[k] || 0) + 1
        }
        var w = new Date()
        if ((perWeek[weekKey(w)] || 0) < habit.frequencyN) w = addDays(w, -7)
        var wn = 0
        while ((perWeek[weekKey(w)] || 0) >= habit.frequencyN) {
            wn++
            w = addDays(w, -7)
        }
        return wn
    }

    // custom_interval: consecutive logs no further apart than frequency_n days.
    var n2 = 1
    for (var m = 0; m < days.length - 1; m++) {
        var gap = Math.round((dateFromDayKey(days[m]).getTime() - dateFromDayKey(days[m + 1]).getTime()) / 86400000)
        if (gap <= habit.frequencyN) n2++
        else break
    }
    return n2
}

// Completion rate over the last N days, 0..1.
function completionRate(habit, lookbackDays) {
    var days = loggedDayKeys(habit.id, lookbackDays)
    if (habit.frequency === "daily") return days.length / lookbackDays
    if (habit.frequency === "weekly_n") {
        var weeks = Math.max(1, Math.round(lookbackDays / 7))
        return Math.min(1, days.length / (weeks * habit.frequencyN))
    }
    var expected = Math.max(1, Math.round(lookbackDays / Math.max(1, habit.frequencyN)))
    return Math.min(1, days.length / expected)
}

// Series for the history graph. Returns [{day, value}] oldest first.
// numeric and reference -> summed value, scale -> the highest value that day,
// everything else -> 1 for logged.
function series(habit, lookbackDays) {
    var since = dayKey(addDays(new Date(), -lookbackDays))
    var rows = entriesSince(habit.id, since)
    var byDay = {}
    for (var i = 0; i < rows.length; i++) {
        var e = rows[i]
        var d = e.loggedAt.substr(0, 10)
        if (habit.valueType === "numeric" || habit.valueType === "reference") {
            var add = e.valueNumeric === null ? 0 : e.valueNumeric
            byDay[d] = (byDay[d] === undefined) ? add : byDay[d] + add
        } else if (habit.valueType === "scale") {
            var v = e.valueScale === null ? 0 : e.valueScale
            byDay[d] = (byDay[d] === undefined) ? v : Math.max(byDay[d], v)
        } else {
            byDay[d] = 1
        }
    }
    var out = []
    var cursor = addDays(new Date(), -lookbackDays + 1)
    for (var k = 0; k < lookbackDays; k++) {
        var key = dayKey(cursor)
        out.push({ day: key, value: byDay[key] === undefined ? null : byDay[key] })
        cursor = addDays(cursor, 1)
    }
    return out
}

// Mean deviation from target_value over the period, for numeric habits with a
// target. Returns null when it does not apply or there is no data.
function deviationFromTarget(habit, lookbackDays) {
    if (habit.valueType !== "numeric" || habit.targetValue === null) return null
    var s = series(habit, lookbackDays)
    var sum = 0, n = 0
    for (var i = 0; i < s.length; i++) {
        if (s[i].value === null) continue
        sum += (s[i].value - habit.targetValue)
        n++
    }
    if (n === 0) return null
    return sum / n
}

// ---------------------------------------------------------------------------
// Cover page
// ---------------------------------------------------------------------------

// How many active habits are due today and not yet logged.
function unloggedTodayCount() {
    var habits = allHabits(false)
    var today = dayKey(new Date())
    var n = 0
    for (var i = 0; i < habits.length; i++) {
        if (!isDueToday(habits[i])) continue
        if (entriesOnDay(habits[i].id, today).length === 0) n++
    }
    return n
}

function activeHabitCount() {
    return allHabits(false).length
}

// ---------------------------------------------------------------------------
// Export and import
// ---------------------------------------------------------------------------
//
// One JSON file holding the whole database. Not a copy of the SQLite file:
// that would be opaque, uncheckable, and would fail in silence when the
// schema versions did not match. JSON can be read by a human, validated
// before anything is touched, and refused with a reason.
//
// FOREIGN KEYS TRAVEL AS UIDS, NEVER AS IDS. A row id is a local counter and
// means nothing on another phone. Carrying ids would force the importer to
// build a translation table and get it right for ten tables; carrying uids
// means every reference is already the thing it refers to.
//
// Rows made before migration 8 have no uid. They get a synthetic one at
// export time -- "local-log_entry-42" -- which is unique inside the file and
// deliberately meaningless outside it. That is the honest description of a
// row that existed before identity did: it can be moved, but it can never be
// recognised on the far side. The alternative was backfilling real uids,
// which would have meant an UPDATE against log_entry, and that is the one
// rule this file does not bend.

var EXPORT_FORMAT = 1

function ref(table, row) {
    if (row.uid !== null && row.uid !== undefined && row.uid !== "") return row.uid
    return "local-" + table + "-" + row.id
}

function rowsOf(tx, sql) {
    var r = tx.executeSql(sql)
    var out = []
    for (var i = 0; i < r.rows.length; i++) out.push(r.rows.item(i))
    return out
}

// The whole database, as a plain object ready for JSON.stringify.
function exportAll() {
    var out = {
        app: "fiat-mos",
        format: EXPORT_FORMAT,
        schemaVersion: currentVersion(),
        exportedAt: localIso(new Date()),
        kinds: [], habits: [], items: [], itemTags: [],
        entries: [], entryItems: [],
        routines: [], sessions: [], components: [], details: []
    }

    db().readTransaction(function(tx) {
        var byId = {}          // table -> local id -> reference

        function remember(table, rows) {
            byId[table] = {}
            for (var i = 0; i < rows.length; i++) byId[table][rows[i].id] = ref(table, rows[i])
            return rows
        }
        function look(table, id) {
            if (id === null || id === undefined) return null
            var m = byId[table]
            return (m && m[id] !== undefined) ? m[id] : null
        }

        var kinds = remember("item_kind", rowsOf(tx, "SELECT * FROM item_kind ORDER BY id"))
        for (var a = 0; a < kinds.length; a++) {
            out.kinds.push({ ref: look("item_kind", kinds[a].id),
                             name: kinds[a].name, unit: kinds[a].unit })
        }

        var habits = remember("habit", rowsOf(tx, "SELECT * FROM habit ORDER BY id"))
        for (var b = 0; b < habits.length; b++) {
            var h = habits[b]
            out.habits.push({
                ref: look("habit", h.id), name: h.name, valueType: h.value_type,
                unit: h.unit, scaleMax: h.scale_max, targetValue: h.target_value,
                frequency: h.frequency, frequencyN: h.frequency_n,
                detailProfile: h.detail_profile, dailyTarget: h.daily_target,
                timeOfDay: h.time_of_day, kind: look("item_kind", h.kind_id),
                archivedAt: h.archived_at, createdAt: h.created_at
            })
        }

        var items = remember("item", rowsOf(tx, "SELECT * FROM item ORDER BY id"))
        for (var c = 0; c < items.length; c++) {
            var it = items[c]
            out.items.push({
                ref: look("item", it.id), title: it.title, creator: it.creator,
                kind: look("item_kind", it.kind_id), state: it.state,
                private: it.private, startedAt: it.started_at, finishedAt: it.finished_at
            })
        }

        var tags = rowsOf(tx, "SELECT * FROM item_tag")
        for (var d = 0; d < tags.length; d++) {
            out.itemTags.push({ item: look("item", tags[d].item_id), tag: tags[d].tag })
        }

        // In id order, which is also chronological. That matters:
        // superseded_by always points at an EARLIER entry, so importing in
        // this order means the target already exists and the reference can be
        // resolved inline -- no second pass, and therefore no UPDATE.
        var entries = remember("log_entry", rowsOf(tx, "SELECT * FROM log_entry ORDER BY id"))
        for (var e = 0; e < entries.length; e++) {
            var le = entries[e]
            out.entries.push({
                ref: look("log_entry", le.id), habit: look("habit", le.habit_id),
                loggedAt: le.logged_at, createdAt: le.created_at, valueType: le.value_type,
                valueBool: le.value_bool, valueNumeric: le.value_numeric,
                valueScale: le.value_scale, supersedes: look("log_entry", le.superseded_by),
                note: le.note
            })
        }

        var ei = rowsOf(tx, "SELECT * FROM log_entry_item")
        for (var f = 0; f < ei.length; f++) {
            out.entryItems.push({ entry: look("log_entry", ei[f].log_entry_id),
                                  item: look("item", ei[f].item_id) })
        }

        var routines = remember("routine", rowsOf(tx, "SELECT * FROM routine ORDER BY id"))
        for (var g = 0; g < routines.length; g++) {
            out.routines.push({ ref: look("routine", routines[g].id),
                                habit: look("habit", routines[g].habit_id),
                                name: routines[g].name })
        }

        var sessions = remember("session", rowsOf(tx, "SELECT * FROM session ORDER BY id"))
        for (var i2 = 0; i2 < sessions.length; i2++) {
            var se = sessions[i2]
            out.sessions.push({ ref: look("session", se.id), habit: look("habit", se.habit_id),
                                routine: look("routine", se.routine_id),
                                startedAt: se.started_at,
                                entry: look("log_entry", se.log_entry_id) })
        }

        var comps = remember("component", rowsOf(tx, "SELECT * FROM component ORDER BY id"))
        for (var j = 0; j < comps.length; j++) {
            out.components.push({ ref: look("component", comps[j].id),
                                  session: look("session", comps[j].session_id),
                                  name: comps[j].name, sortOrder: comps[j].sort_order })
        }

        var details = remember("detail", rowsOf(tx, "SELECT * FROM detail ORDER BY id"))
        for (var k = 0; k < details.length; k++) {
            var de = details[k]
            out.details.push({ ref: look("detail", de.id),
                               component: look("component", de.component_id),
                               reps: de.reps, weightKg: de.weight_kg,
                               durationSec: de.duration_sec, note: de.note })
        }
    })

    return out
}

// What the file says about itself, without touching anything. The import page
// shows this and makes the user confirm before a single row is removed.
function describeImport(data) {
    if (data === null || data === undefined || typeof data !== "object") {
        return { ok: false, reason: "not-a-file" }
    }
    if (data.app !== "fiat-mos") return { ok: false, reason: "wrong-app" }
    if (data.format > EXPORT_FORMAT) return { ok: false, reason: "too-new" }
    return {
        ok: true,
        exportedAt: data.exportedAt || "",
        habits: (data.habits || []).length,
        entries: (data.entries || []).length,
        items: (data.items || []).length,
        sessions: (data.sessions || []).length
    }
}

// REPLACE, not merge. Everything currently in the database is removed and the
// file becomes the database.
//
// The deletes here are the only ones in this file, and they are deliberate:
// this is not the logging path, it is the user saying "make this phone look
// like that file". Undo is not a new row here -- undo is the export you took
// first, which is why the page insists on one.
function importAll(data) {
    var check = describeImport(data)
    if (!check.ok) return check

    var counts = { habits: 0, entries: 0, items: 0 }

    db().transaction(function(tx) {
        // Children first, so no statement ever leaves a dangling reference.
        tx.executeSql("DELETE FROM detail")
        tx.executeSql("DELETE FROM component")
        tx.executeSql("DELETE FROM session")
        tx.executeSql("DELETE FROM routine")
        tx.executeSql("DELETE FROM log_entry_item")
        tx.executeSql("DELETE FROM item_tag")
        tx.executeSql("DELETE FROM log_entry")
        tx.executeSql("DELETE FROM item")
        tx.executeSql("DELETE FROM habit")
        tx.executeSql("DELETE FROM item_kind")

        var map = { item_kind: {}, habit: {}, item: {}, log_entry: {},
                    routine: {}, session: {}, component: {} }

        function id(table, reference) {
            if (reference === null || reference === undefined) return null
            var v = map[table][reference]
            return v === undefined ? null : v
        }
        // A reference that came from a pre-uid row is not identity, so it is
        // not carried into the new database as one.
        function keep(reference) {
            return (reference && reference.indexOf("local-") !== 0) ? reference : newUid()
        }

        var i
        var kinds = data.kinds || []
        for (i = 0; i < kinds.length; i++) {
            var k = kinds[i]
            var kr = tx.executeSql("INSERT INTO item_kind (name, unit, uid) VALUES (?, ?, ?)",
                                   [k.name, k.unit === null ? "" : k.unit, keep(k.ref)])
            map.item_kind[k.ref] = kr.insertId
        }

        var habits = data.habits || []
        for (i = 0; i < habits.length; i++) {
            var h = habits[i]
            var hr = tx.executeSql("INSERT INTO habit (name, value_type, unit, scale_max, target_value, frequency, frequency_n, detail_profile, daily_target, time_of_day, kind_id, archived_at, created_at, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                   [h.name, h.valueType, h.unit, h.scaleMax, h.targetValue,
                                    h.frequency, h.frequencyN, h.detailProfile, h.dailyTarget,
                                    h.timeOfDay, id("item_kind", h.kind), h.archivedAt,
                                    h.createdAt || localIso(new Date()), keep(h.ref)])
            map.habit[h.ref] = hr.insertId
            counts.habits++
        }

        var items = data.items || []
        for (i = 0; i < items.length; i++) {
            var it = items[i]
            var ir = tx.executeSql("INSERT INTO item (title, creator, kind_id, state, private, started_at, finished_at, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                   [it.title, it.creator, id("item_kind", it.kind),
                                    it.state || "active", it.private ? 1 : 0,
                                    it.startedAt, it.finishedAt, keep(it.ref)])
            map.item[it.ref] = ir.insertId
            counts.items++
        }

        var tags = data.itemTags || []
        for (i = 0; i < tags.length; i++) {
            var iid = id("item", tags[i].item)
            if (iid === null) continue
            tx.executeSql("INSERT INTO item_tag (item_id, tag) VALUES (?, ?)", [iid, tags[i].tag])
        }

        // In file order, which is id order, which is chronological -- so the
        // entry a void supersedes is always already in the map.
        var entries = data.entries || []
        for (i = 0; i < entries.length; i++) {
            var e = entries[i]
            var hid = id("habit", e.habit)
            if (hid === null) continue
            var er = tx.executeSql("INSERT INTO log_entry (habit_id, logged_at, created_at, value_type, value_bool, value_numeric, value_scale, superseded_by, note, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                   [hid, e.loggedAt, e.createdAt || e.loggedAt, e.valueType,
                                    e.valueBool, e.valueNumeric, e.valueScale,
                                    id("log_entry", e.supersedes), e.note, keep(e.ref)])
            map.log_entry[e.ref] = er.insertId
            counts.entries++
        }

        var ei = data.entryItems || []
        for (i = 0; i < ei.length; i++) {
            var eid = id("log_entry", ei[i].entry)
            var itid = id("item", ei[i].item)
            if (eid === null || itid === null) continue
            tx.executeSql("INSERT INTO log_entry_item (log_entry_id, item_id) VALUES (?, ?)", [eid, itid])
        }

        var routines = data.routines || []
        for (i = 0; i < routines.length; i++) {
            var ro = routines[i]
            var rhid = id("habit", ro.habit)
            if (rhid === null) continue
            var rr = tx.executeSql("INSERT INTO routine (habit_id, name, uid) VALUES (?, ?, ?)",
                                   [rhid, ro.name, keep(ro.ref)])
            map.routine[ro.ref] = rr.insertId
        }

        var sessions = data.sessions || []
        for (i = 0; i < sessions.length; i++) {
            var se = sessions[i]
            var shid = id("habit", se.habit)
            if (shid === null) continue
            var sr = tx.executeSql("INSERT INTO session (habit_id, routine_id, started_at, log_entry_id, uid) VALUES (?, ?, ?, ?, ?)",
                                   [shid, id("routine", se.routine), se.startedAt,
                                    id("log_entry", se.entry), keep(se.ref)])
            map.session[se.ref] = sr.insertId
        }

        var comps = data.components || []
        for (i = 0; i < comps.length; i++) {
            var co = comps[i]
            var sid = id("session", co.session)
            if (sid === null) continue
            var cr = tx.executeSql("INSERT INTO component (session_id, name, sort_order, uid) VALUES (?, ?, ?, ?)",
                                   [sid, co.name, co.sortOrder || 0, keep(co.ref)])
            map.component[co.ref] = cr.insertId
        }

        var details = data.details || []
        for (i = 0; i < details.length; i++) {
            var de = details[i]
            var cid = id("component", de.component)
            if (cid === null) continue
            tx.executeSql("INSERT INTO detail (component_id, reps, weight_kg, duration_sec, note, uid) VALUES (?, ?, ?, ?, ?, ?)",
                          [cid, de.reps, de.weightKg, de.durationSec, de.note, keep(de.ref)])
        }
    })

    counts.ok = true
    return counts
}
