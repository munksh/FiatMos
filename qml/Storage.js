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
    },
    {
        version: 9,
        // How long an item is, and which edition it is.
        //
        // extent is the item's whole length in its KIND's unit: 330 pages, a
        // 12-minute piece, 36 frames. It is the cataloguer's word for exactly
        // this, and it is not called `length` because every JS object that
        // comes back from a row would then have a `length` that is not one.
        // Optional. Without it an item logs and totals as before; with it,
        // progress and a finishing estimate can be worked out.
        //
        // isbn is stored as 13 digits, whatever was typed, so one book has one
        // key. It also names the cover file, which lives outside the database
        // and can always be fetched again from it.
        statements: [
            "ALTER TABLE item ADD COLUMN extent REAL",
            "ALTER TABLE item ADD COLUMN isbn TEXT"
        ]
    },
    {
        version: 10,
        // Things you finish, and things you practise.
        //
        // A kind now says which of the two it is. A book is finished; an
        // exercise, a piece or a stretch is practised and keeps coming back.
        // Kinds from before this have no nature, which reads as "finish" --
        // everything on the shelf until now was something you work through.
        //
        // A practised thing is measured per thing, not per habit: the plank
        // in a strength session is timed, the bench press beside it is weight
        // times reps. `measure` on the kind is only the default a new thing
        // starts with.
        //
        //   weight_reps     reps, and a weight that may be nothing yet
        //   time            minutes
        //   time_distance   minutes and a distance
        //
        // Exercises stop being a name typed into each session. component
        // gains item_id, so every session that did "Bench press" points at
        // the same thing, and its history can be followed over time. The name
        // on the component stays exactly as it was typed; nothing is renamed.
        //
        // All columns are new and nullable. The one procedural step, run()
        // below, only FILLS those new columns -- it gives each structured
        // habit a kind, and each exercise name already in use a thing of that
        // kind. No existing value is changed and nothing is removed. log_entry
        // is not touched at all.
        statements: [
            "ALTER TABLE item_kind ADD COLUMN nature TEXT",
            "ALTER TABLE item_kind ADD COLUMN measure TEXT",
            "ALTER TABLE item ADD COLUMN measure TEXT",
            "ALTER TABLE component ADD COLUMN item_id INTEGER REFERENCES item(id)",
            "ALTER TABLE detail ADD COLUMN distance_m REAL",
            "CREATE INDEX IF NOT EXISTS idx_component_item ON component(item_id)"
        ],
        run: function(tx) { linkPractise(tx) }
    },
    {
        version: 11,
        // What "done" is called for a kind on the shelf. A book is finished;
        // a piece of music, or a text learned by heart, is learned. One of two
        // words, set when the kind is made -- not free text, so the shelf can
        // always say it in the same breath as everything else.
        //
        // NULL reads as "finished", which is what every kind was until now.
        // The two kinds that were always about learning get the other word.
        statements: [
            "ALTER TABLE item_kind ADD COLUMN done_word TEXT",
            "UPDATE item_kind SET done_word = 'learned' WHERE done_word IS NULL AND name IN ('repertoire', 'texts')"
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
            // A step that SQL alone cannot say, in the same transaction, so a
            // migration still lands whole or not at all.
            if (m.run !== undefined) m.run(tx)
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

// The day n days from today. dayOffsetKey(-1) is yesterday.
function dayOffsetKey(n) {
    return dayKey(addDays(new Date(), n))
}

// The logged_at for something that belongs to `day`.
//
// Today gets the real time. An earlier day gets one minute to midnight: late
// in the day it belongs to, after anything that was logged as it happened.
// created_at still says when the row was really written, so a late entry is
// honest twice over and never pretends to have been on time.
function loggedAtFor(day) {
    if (day === undefined || day === null || day === "" || day === dayKey(new Date())) {
        return localIso(new Date())
    }
    return day + "T23:59:00"
}

// The local day a created_at falls on.
//
// SQLite's datetime('now') is UTC and written with a space. Rows that came in
// through import may carry a local ISO string with a T instead. Both happen,
// so both are read.
function createdDay(s) {
    if (s === null || s === undefined || s === "") return ""
    s = String(s)
    if (s.indexOf("T") >= 0) return s.substr(0, 10)
    var p = s.split(/[- :]/)
    var d = new Date(Date.UTC(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10),
                              parseInt(p[3] || "0", 10), parseInt(p[4] || "0", 10), parseInt(p[5] || "0", 10)))
    return dayKey(d)
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
    return progressOn(habit, dayKey(new Date()))
}

// The same question about any day. Yesterday's leftovers are asked this way.
function progressOn(habit, day) {
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

// What yesterday left undone.
//
// Daily habits only. A weekly quota or an interval habit that slipped
// yesterday is still due today, so it is already in the list below; a daily
// habit that slipped is gone from the list the moment the date changes, and
// that is the one worth a second chance. A habit made today had no yesterday
// to miss, and neither did an archived one.
function yesterdayLeftovers() {
    var day = dayOffsetKey(-1)
    var out = []
    var habits = allHabits(false)
    for (var i = 0; i < habits.length; i++) {
        var h = habits[i]
        if (h.frequency !== "daily") continue
        var born = createdDay(h.createdAt)
        if (born !== "" && born > day) continue
        var p = progressOn(h, day)
        if (p.complete) continue
        out.push({ habit: h, progress: p })
    }
    return out
}

function loadLeftovers(model) {
    model.clear()
    var list = yesterdayLeftovers()
    for (var i = 0; i < list.length; i++) {
        var h = list[i].habit, p = list[i].progress
        model.append({
            habitId: h.id,
            name: h.name,
            valueType: h.valueType,
            unit: unitForHabit(h),
            counted: p.counted,
            fraction: p.fraction,
            done: Math.round(p.done * 100) / 100,
            target: p.target,
            logged: p.logged
        })
    }
    return model.count
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
        note: row.note === null ? "" : row.note,
        createdAt: row.created_at
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
        var written = createdDay(rows[i].createdAt)
        model.append({
            entryId: rows[i].id,
            loggedAt: rows[i].loggedAt,
            timeLabel: rows[i].loggedAt.substr(11, 5),
            // Written on a later day than the one it belongs to. Its clock
            // time is the stand-in 23:59, so the page says "later" instead.
            late: written !== "" && written > rows[i].loggedAt.substr(0, 10),
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
    // Things you finish.
    { name: "book", unit: "pages", nature: "finish" },
    { name: "audiobook", unit: "minutes", nature: "finish" },
    { name: "article", unit: "pages", nature: "finish" },
    { name: "course", unit: "lessons", nature: "finish" },
    { name: "film", unit: "minutes", nature: "finish" },
    { name: "repertoire", unit: "minutes", nature: "finish", done: "learned" },
    { name: "texts", unit: "minutes", nature: "finish", done: "learned" },
    { name: "photo roll", unit: "frames", nature: "finish" },
    { name: "series", unit: "episodes", nature: "finish" },
    { name: "draft", unit: "words", nature: "finish" },
    // Things you work out with. No unit: each exercise carries a measure
    // instead, and the kind's is only where a new one starts. Music and
    // texts are not here on purpose -- you learn a piece the way you read a
    // book, so they live on the shelf.
    { name: "exercises", unit: "", nature: "practise", measure: "weight_reps" },
    { name: "stretches", unit: "", nature: "practise", measure: "time" },
    { name: "routes", unit: "", nature: "practise", measure: "time_distance" }
]

// How a practised thing is measured. The first is the default.
var MEASURES = ["weight_reps", "time", "time_distance"]

function cleanMeasure(m) {
    return MEASURES.indexOf(m) >= 0 ? m : MEASURES[0]
}

// A kind from before migration 10 has no nature. Everything on the shelf
// until then was something you work through, so that is what it reads as.
function cleanNature(n) {
    return n === "practise" ? "practise" : "finish"
}

// The old per-habit setting, read as the measure its exercises start with.
// 'reps' becomes weight times reps with no weight: a weight of nothing is
// still a weight, and the day you add one there is nothing to change.
function measureForProfile(profile) {
    return profile === "timed" ? "time" : "weight_reps"
}

// What "done" is called for things of a kind: "finished" or "learned".
function cleanDoneWord(w) {
    return w === "learned" ? "learned" : "finished"
}

// Anything not finished or put away is still on the go.
function isActiveState(state) {
    return state !== "completed" && state !== "archived"
}

// -- kinds -----------------------------------------------------------------

function rowToKind(row) {
    return {
        id: row.id,
        name: row.name,
        unit: (row.unit === null || row.unit === undefined) ? "" : row.unit,
        nature: cleanNature(row.nature),
        measure: cleanMeasure(row.measure),
        doneWord: cleanDoneWord(row.done_word)
    }
}

// filter: { nature } -- optional. Without it, every kind.
function kinds(filter) {
    var wanted = (filter && filter.nature) ? cleanNature(filter.nature) : ""
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT * FROM item_kind ORDER BY name COLLATE NOCASE")
        for (var i = 0; i < r.rows.length; i++) {
            var k = rowToKind(r.rows.item(i))
            if (wanted !== "" && k.nature !== wanted) continue
            out.push(k)
        }
    })
    return out
}

function kindById(kindId) {
    var k = null
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT * FROM item_kind WHERE id = ?", [kindId])
        if (r.rows.length > 0) k = rowToKind(r.rows.item(0))
    })
    return k
}

// Names are unique, so an existing name is reused rather than duplicated.
// The unit of an existing kind is never silently rewritten -- changing what
// a kind is measured in would reinterpret every number already logged.
//
// nature and measure are optional; a kind made without them is something you
// finish, as every kind was before.
function addKind(name, unit, nature, measure, doneWord) {
    var id = -1
    var clean = String(name).trim()
    if (clean === "") return -1
    var n = cleanNature(nature)
    db().transaction(function(tx) {
        var e = tx.executeSql("SELECT id FROM item_kind WHERE name = ?", [clean])
        if (e.rows.length > 0) {
            id = e.rows.item(0).id
        } else {
            var r = tx.executeSql("INSERT INTO item_kind (name, unit, nature, measure, done_word, uid) VALUES (?, ?, ?, ?, ?, ?)",
                                  [clean, (unit === undefined || unit === null) ? "" : String(unit).trim(),
                                   n, n === "practise" ? cleanMeasure(measure) : null,
                                   n === "finish" ? cleanDoneWord(doneWord) : null, newUid()])
            id = r.insertId
        }
    })
    return id
}

// The suggestions worth showing: the starter list, minus anything you have
// already made yourself. Matching is on name, case-insensitively, because
// "Book" and "book" are the same kind of thing to a human. With a nature,
// only the starters of that nature.
function starterKinds(nature) {
    var wanted = (nature === undefined || nature === null || nature === "") ? "" : cleanNature(nature)
    var mine = kinds()
    var taken = {}
    for (var i = 0; i < mine.length; i++) taken[mine[i].name.toLowerCase()] = true
    var out = []
    for (var j = 0; j < STARTER_KINDS.length; j++) {
        var s = STARTER_KINDS[j]
        if (taken[s.name.toLowerCase()]) continue
        if (wanted !== "" && s.nature !== wanted) continue
        out.push(s)
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

// An extent of 0 or less, or one that is not a number, means "not known".
function cleanExtent(v) {
    if (v === undefined || v === null || v === "") return null
    var n = Number(v)
    return (isNaN(n) || n <= 0) ? null : n
}

function cleanIsbn(v) {
    return (v === undefined || v === null || String(v).trim() === "") ? null : String(v).trim()
}

function addItem(o) {
    var id = -1
    db().transaction(function(tx) {
        var r = tx.executeSql("INSERT INTO item (title, creator, kind_id, state, private, started_at, extent, isbn, measure, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
                               cleanExtent(o.extent),
                               cleanIsbn(o.isbn),
                               // Only a practised thing has a measure of its
                               // own. Without one it follows its kind.
                               (o.measure === undefined || o.measure === null || o.measure === "") ? null : cleanMeasure(o.measure),
                               newUid()])
        id = r.insertId
    })
    if (o.tags !== undefined) setItemTags(id, o.tags)
    return id
}

// Every field is written, extent and isbn included, so the caller passes the
// whole item. The only caller is the item editor, which always has all of it.
function updateItem(o) {
    db().transaction(function(tx) {
        tx.executeSql("UPDATE item SET title = ?, creator = ?, kind_id = ?, private = ?, extent = ?, isbn = ? WHERE id = ?",
                      [o.title,
                       (o.creator === undefined || o.creator === "") ? null : o.creator,
                       (o.kindId === undefined || o.kindId < 0) ? null : o.kindId,
                       o.private ? 1 : 0,
                       cleanExtent(o.extent),
                       cleanIsbn(o.isbn),
                       o.id])
        // Left alone unless asked: the shelf's editor knows nothing of it.
        if (o.measure !== undefined && o.measure !== null && o.measure !== "") {
            tx.executeSql("UPDATE item SET measure = ? WHERE id = ?", [cleanMeasure(o.measure), o.id])
        }
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
        finishedAt: row.finished_at,
        extent: (row.extent === null || row.extent === undefined) ? 0 : row.extent,
        isbn: (row.isbn === null || row.isbn === undefined) ? "" : row.isbn,
        nature: cleanNature(row.kind_nature),
        doneWord: cleanDoneWord(row.kind_done),
        // A thing's own measure, else its kind's.
        measure: (row.measure !== null && row.measure !== undefined && row.measure !== "")
                 ? cleanMeasure(row.measure) : cleanMeasure(row.kind_measure)
    }
}

function itemById(itemId) {
    var it = null
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT i.*, k.name AS kind_name, k.unit AS unit, k.nature AS kind_nature, k.measure AS kind_measure, k.done_word AS kind_done FROM item i LEFT JOIN item_kind k ON k.id = i.kind_id WHERE i.id = ?", [itemId])
        if (r.rows.length > 0) it = rowToItem(r.rows.item(0))
    })
    return it
}

// Everything ever logged against one item, whatever the period.
function itemTotal(itemId) {
    var n = 0
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT SUM(COALESCE(le.value_numeric, 0)) AS n FROM log_entry_item lei JOIN log_entry le ON le.id = lei.log_entry_id WHERE lei.item_id = ? AND " + LIVE_ENTRY, [itemId])
        if (r.rows.length > 0 && r.rows.item(0).n !== null) n = r.rows.item(0).n
    })
    return n
}

// filter: { kindId, active, tag, includePrivate, nature }  -- every field optional
function items(filter) {
    filter = filter || {}
    var out = []
    db().readTransaction(function(tx) {
        var sql = "SELECT i.*, k.name AS kind_name, k.unit AS unit, k.nature AS kind_nature, k.measure AS kind_measure, k.done_word AS kind_done FROM item i LEFT JOIN item_kind k ON k.id = i.kind_id"
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
            if (filter.nature !== undefined && filter.nature !== "" && it.nature !== cleanNature(filter.nature)) continue
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
            finishedAt: it.finishedAt === null ? "" : it.finishedAt,
            extent: it.extent,
            isbn: it.isbn,
            doneWord: it.doneWord,
            soFar: it.extent > 0 ? Math.round(itemTotal(it.id) * 100) / 100 : 0
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

// One log_entry plus the junction row that ties it to an item. `day` is
// optional and means today when left out.
function addReferenceEntry(habit, itemId, numeric, note, day) {
    var entryId = addEntry(habit, { numeric: (numeric === null || numeric === undefined) ? null : numeric,
                                    note: note, loggedAt: loggedAtFor(day) })
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
// The year at a glance, and the library's statistics
// ---------------------------------------------------------------------------
//
// Everything below is worked out from log_entry every time it is asked for,
// like the rest of the analysis. Nothing here writes.

function medianOf(values) {
    if (values.length === 0) return null
    var s = values.slice().sort(function(a, b) { return a - b })
    var mid = Math.floor(s.length / 2)
    return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
}

// Two facts about a series of days: the longest run of days in a row with
// anything logged, and the month with the most in it.
//
// `countDays` says what "most" means. For a number it is the sum; for a tick
// or a rating it is how many days were logged, because a month of sleep
// ratings does not add up to anything.
function calendarFacts(days, countDays) {
    var run = 0, best = 0, prev = null
    var months = {}, order = []
    for (var i = 0; i < days.length; i++) {
        var d = days[i]
        if (d.value === null || d.value === undefined) { run = 0; prev = null; continue }
        run = (prev !== null && dateFromDayKey(d.day).getTime() - dateFromDayKey(prev).getTime() === 86400000)
            ? run + 1 : 1
        prev = d.day
        if (run > best) best = run
        var m = d.day.substr(0, 7)
        if (months[m] === undefined) { months[m] = 0; order.push(m) }
        months[m] += countDays ? 1 : d.value
    }
    var bestMonth = "", bestValue = 0
    for (var j = 0; j < order.length; j++) {
        if (months[order[j]] > bestValue) { bestValue = months[order[j]]; bestMonth = order[j] }
    }
    return { longestRun: best, bestMonth: bestMonth, bestMonthValue: Math.round(bestValue * 100) / 100 }
}

// Days summed into Monday-to-Sunday weeks, oldest first. The first bucket
// starts on the Monday on or before the first day, so every bar is a real
// calendar week and not a seven-day window that happens to start on a Thursday.
function weeklyBuckets(days) {
    if (days.length === 0) return []
    var first = dateFromDayKey(days[0].day)
    var monday = addDays(first, -((first.getDay() + 6) % 7))
    var out = []
    for (var i = 0; i < days.length; i++) {
        var d = dateFromDayKey(days[i].day)
        var idx = Math.floor(Math.round((d.getTime() - monday.getTime()) / 86400000) / 7)
        while (out.length <= idx) out.push({ start: dayKey(addDays(monday, out.length * 7)), value: 0 })
        if (days[i].value !== null) out[idx].value += days[i].value
    }
    return out
}

// Sums per weekday, Monday first.
function weekdayTotals(days) {
    var out = [0, 0, 0, 0, 0, 0, 0]
    for (var i = 0; i < days.length; i++) {
        if (days[i].value === null) continue
        out[(dateFromDayKey(days[i].day).getDay() + 6) % 7] += days[i].value
    }
    return out
}

// One kind over a period: what was read, watched, played or shot, when, and
// in what.
//
// Two kinds of total per item, and they answer different questions. `total`
// is inside the period -- this is what the numbers and the charts are made
// of. `soFar` is everything ever logged against it, because a book begun in
// March and still going in September is 60 % read, not 60 % read since June.
// Progress always uses soFar.
//
// Private items are left out unless asked for, the same rule as Totals, and
// the page is told how many were left out so it can say so.
function kindStats(kindId, lookbackDays, includePrivate) {
    var firstDay = dayOffsetKey(-(lookbackDays - 1))
    var perDay = {}
    var byItem = {}, ids = []
    var hidden = {}, hiddenCount = 0

    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT substr(le.logged_at, 1, 10) AS day, COALESCE(le.value_numeric, 0) AS v, i.id AS item_id, i.private AS private FROM item i JOIN log_entry_item lei ON lei.item_id = i.id JOIN log_entry le ON le.id = lei.log_entry_id WHERE i.kind_id = ? AND substr(le.logged_at, 1, 10) >= ? AND " + LIVE_ENTRY + " ORDER BY le.logged_at, le.id", [kindId, firstDay])
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            if (row.private === 1 && includePrivate !== true) {
                if (!hidden[row.item_id]) { hidden[row.item_id] = true; hiddenCount++ }
                continue
            }
            perDay[row.day] = (perDay[row.day] || 0) + row.v
            var b = byItem[row.item_id]
            if (b === undefined) {
                b = byItem[row.item_id] = { total: 0, days: {}, dayCount: 0, first: row.day, last: row.day }
                ids.push(row.item_id)
            }
            b.total += row.v
            if (!b.days[row.day]) { b.days[row.day] = true; b.dayCount++ }
            b.last = row.day
        }
    })

    var series = []
    var total = 0, loggedDays = 0
    for (var k = 0; k < lookbackDays; k++) {
        var key = dayOffsetKey(-(lookbackDays - 1) + k)
        var v = perDay[key] === undefined ? null : perDay[key]
        if (v !== null) { total += v; loggedDays++ }
        series.push({ day: key, value: v })
    }

    var list = [], finished = 0
    for (var j = 0; j < ids.length; j++) {
        var it = itemById(ids[j])
        if (it === null) continue
        var s = byItem[ids[j]]
        var done = !isActiveState(it.state) && it.finishedAt !== null && it.finishedAt !== undefined
                   && it.finishedAt.substr(0, 10) >= firstDay
        if (done) finished++
        list.push({
            id: it.id, title: it.title, creator: it.creator, state: it.state,
            finishedAt: it.finishedAt === null ? "" : it.finishedAt,
            finishedHere: done,
            extent: it.extent, isbn: it.isbn, private: it.private,
            total: Math.round(s.total * 100) / 100, days: s.dayCount,
            first: s.first, last: s.last,
            soFar: Math.round(itemTotal(it.id) * 100) / 100
        })
    }

    return {
        kind: kindById(kindId),
        firstDay: firstDay,
        series: series,
        total: Math.round(total * 100) / 100,
        days: loggedDays,
        itemCount: list.length,
        finished: finished,
        hiddenPrivate: hiddenCount,
        items: list
    }
}

// One item, over its whole life: every sitting, and how far there is to go.
//
// A sitting is a DAY, not an entry. Two entries on one evening are one
// evening's reading, and a median of half-evenings would describe nobody.
function itemStats(itemId) {
    var it = itemById(itemId)
    if (it === null) return null

    var perDay = {}, order = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT substr(le.logged_at, 1, 10) AS day, COALESCE(le.value_numeric, 0) AS v FROM log_entry_item lei JOIN log_entry le ON le.id = lei.log_entry_id WHERE lei.item_id = ? AND " + LIVE_ENTRY + " ORDER BY le.logged_at, le.id", [itemId])
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            if (perDay[row.day] === undefined) { perDay[row.day] = 0; order.push(row.day) }
            perDay[row.day] += row.v
        }
    })

    var sittings = [], values = [], total = 0, best = 0
    for (var j = 0; j < order.length; j++) {
        var v = Math.round(perDay[order[j]] * 100) / 100
        sittings.push({ day: order[j], value: v })
        values.push(v)
        total += v
        if (v > best) best = v
    }
    total = Math.round(total * 100) / 100

    // Only amounts that were actually counted make a pace. A day marked read
    // with no number is still a sitting, but it says nothing about speed.
    var counted = []
    for (var c = 0; c < values.length; c++) if (values[c] > 0) counted.push(values[c])
    var median = medianOf(counted)
    if (median !== null) median = Math.round(median * 100) / 100

    var left = it.extent > 0 ? Math.max(0, Math.round((it.extent - total) * 100) / 100) : null
    var estimate = (left !== null && left > 0 && median !== null && median > 0) ? Math.ceil(left / median) : null

    return {
        item: it,
        unit: it.unit,
        sittings: sittings,
        total: total,
        days: sittings.length,
        median: median,
        best: best,
        first: order.length > 0 ? order[0] : "",
        last: order.length > 0 ? order[order.length - 1] : "",
        fraction: it.extent > 0 ? Math.min(1, total / it.extent) : null,
        left: left,
        estimate: estimate,
        tags: itemTags(itemId)
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

// Everything hanging off one session row. Shared by lastSession and
// sessionForDay so the two can never disagree about what a session is.
//
// Returns { id, startedAt, routineId, entryId,
//           components: [{ name, itemId, measure, details: [...] }] }
//
// `name` is the thing's title when the exercise is linked to one -- so a
// thing renamed on the Practice page is shown by its new name everywhere --
// and the name as typed otherwise. `measure` is the thing's, else its kind's.
function loadSessionRow(tx, row) {
    var s = { id: row.id, startedAt: row.started_at, routineId: row.routine_id,
              entryId: row.log_entry_id, components: [] }
    var c = tx.executeSql("SELECT c.*, i.title AS item_title, i.measure AS item_measure, k.measure AS kind_measure FROM component c LEFT JOIN item i ON i.id = c.item_id LEFT JOIN item_kind k ON k.id = i.kind_id WHERE c.session_id = ? ORDER BY c.sort_order, c.id", [s.id])
    for (var i = 0; i < c.rows.length; i++) {
        var cr = c.rows.item(i)
        var linked = cr.item_id !== null && cr.item_id !== undefined
        var comp = {
            name: (linked && cr.item_title !== null && cr.item_title !== undefined) ? cr.item_title : cr.name,
            itemId: linked ? cr.item_id : -1,
            measure: (cr.item_measure !== null && cr.item_measure !== undefined && cr.item_measure !== "")
                     ? cleanMeasure(cr.item_measure) : cleanMeasure(cr.kind_measure),
            details: []
        }
        var d = tx.executeSql("SELECT * FROM detail WHERE component_id = ? ORDER BY id", [cr.id])
        for (var j = 0; j < d.rows.length; j++) {
            comp.details.push(rowToDetail(d.rows.item(j)))
        }
        s.components.push(comp)
    }
    return s
}

function rowToDetail(row) {
    return {
        reps: row.reps,
        weight: row.weight_kg,
        duration: row.duration_sec,
        distance: (row.distance_m === undefined) ? null : row.distance_m,
        note: row.note === null ? "" : row.note
    }
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

// The most recent session for a habit, optionally restricted to one routine.
// Used both for the history view and for prefilling a new session --
// prefill lives in UI state only, nothing is copied into the database.
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
        s = loadSessionRow(tx, r.rows.item(0))
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
// Every exercise is tied to a THING of the habit's kind, found by name or
// made on the spot. That is what lets "Bench press" be followed over months:
// the history belongs to the thing, not to whatever was typed on the day. A
// habit that has no kind yet -- one made before kinds could be practised --
// is given one here, the same way the migration gives one to the rest.
//
// Components with no name are dropped; so are detail rows where every field is
// empty.
//
// `day` is optional and means today. Yesterday's forgotten session is saved
// the same way, one per day there too.
//
// comps: [{ name, itemId?, measure?,
//           details: [{ reps, weight, duration (s), distance (m), note }] }]
function saveSession(habit, routineId, comps, note, day) {
    var theDay = (day === undefined || day === null || day === "") ? dayKey(new Date()) : day
    var existing = sessionForDay(habit.id, theDay)

    // The entry is written once a day, by whichever save comes first.
    var entryId = (existing !== null && existing.entryId !== null && existing.entryId !== undefined)
        ? existing.entryId
        : addEntry(habit, { note: note, loggedAt: loggedAtFor(theDay) })
    var sessionId = existing === null ? -1 : existing.id

    function blank(v) { return v === "" || v === undefined || v === null }

    db().transaction(function(tx) {
        var rid = (routineId === null || routineId === undefined || routineId < 0) ? null : routineId
        var kindId = practiseKindForHabit(tx, habit)

        if (existing !== null) {
            // Children first, so nothing is left pointing at a gone parent.
            tx.executeSql("DELETE FROM detail WHERE component_id IN (SELECT id FROM component WHERE session_id = ?)", [sessionId])
            tx.executeSql("DELETE FROM component WHERE session_id = ?", [sessionId])
            tx.executeSql("UPDATE session SET routine_id = ? WHERE id = ?", [rid, sessionId])
        } else {
            var r = tx.executeSql("INSERT INTO session (habit_id, routine_id, started_at, log_entry_id, uid) VALUES (?, ?, ?, ?, ?)",
                                  [habit.id, rid, loggedAtFor(theDay), entryId, newUid()])
            sessionId = r.insertId
        }

        var known = thingIndex(tx, kindId)
        var order = 0
        for (var i = 0; i < comps.length; i++) {
            var name = tidyName(comps[i].name)
            if (name === "") continue
            var wanted = blank(comps[i].measure) ? "" : cleanMeasure(comps[i].measure)
            var itemId = thingIdFor(tx, kindId, known, name, wanted, loggedAtFor(theDay))
            // A measure chosen on the session page is the thing's from now on.
            // The thing is a definition, not a record, so this is an UPDATE
            // like any other edit of it; the sets already logged keep every
            // field they had.
            if (itemId >= 0 && wanted !== "") {
                tx.executeSql("UPDATE item SET measure = ? WHERE id = ? AND (measure IS NULL OR measure <> ?)", [wanted, itemId, wanted])
            }
            var cr = tx.executeSql("INSERT INTO component (session_id, name, sort_order, item_id, uid) VALUES (?, ?, ?, ?, ?)",
                                   [sessionId, name, order, itemId >= 0 ? itemId : null, newUid()])
            order++
            var compId = cr.insertId
            var details = comps[i].details || []
            for (var j = 0; j < details.length; j++) {
                var d = details[j]
                var reps = blank(d.reps) ? null : d.reps
                var weight = blank(d.weight) ? null : d.weight
                var dur = blank(d.duration) ? null : d.duration
                var dist = blank(d.distance) ? null : d.distance
                var dnote = blank(d.note) ? null : d.note
                if (reps === null && weight === null && dur === null && dist === null && dnote === null) continue
                tx.executeSql("INSERT INTO detail (component_id, reps, weight_kg, duration_sec, distance_m, note, uid) VALUES (?, ?, ?, ?, ?, ?, ?)",
                              [compId, reps, weight, dur, dist, dnote, newUid()])
            }
        }
    })

    return { sessionId: sessionId, entryId: entryId }
}

// ---------------------------------------------------------------------------
// Things you practise
// ---------------------------------------------------------------------------
//
// An exercise, a piece, a stretch, a route: an item of a kind whose nature is
// 'practise'. It is never finished. What it has instead is a history -- every
// session that included it -- and that history is what the Practice page and
// the thing's own page are made of. As everywhere else, nothing below writes
// a total or a best anywhere; it is all worked out when asked.

// "  Bench   press " and "Bench press" are one exercise. Case is kept as typed
// the first time; matching ignores it.
function tidyName(name) {
    return String(name === undefined || name === null ? "" : name).trim().replace(/\s+/g, " ")
}

function nameKey(name) {
    return tidyName(name).toLowerCase()
}

// The practise kind a structured habit's exercises belong to. A habit that
// has none -- every structured habit from before migration 10, and any made
// without one -- is given one: the kind called "exercises", made if needed.
// Inside the caller's transaction, so it can run during a migration.
function practiseKindForHabit(tx, habit) {
    var r = tx.executeSql("SELECT kind_id, detail_profile FROM habit WHERE id = ?", [habit.id])
    if (r.rows.length === 0) return -1
    var row = r.rows.item(0)
    if (row.kind_id !== null && row.kind_id !== undefined) return row.kind_id
    var kindId = defaultPractiseKind(tx, measureForProfile(row.detail_profile))
    // habit is a definition, not a record: giving it the kind it was always
    // implicitly using is an edit, and nothing it logged changes meaning.
    tx.executeSql("UPDATE habit SET kind_id = ? WHERE id = ?", [kindId, habit.id])
    habit.kindId = kindId
    return kindId
}

// "exercises" if it is free to be a practise kind; otherwise the first of a
// few plainer names that is. A kind of that name that is already on the
// shelf, with things in it, is left exactly as it is.
function defaultPractiseKind(tx, measure) {
    var names = ["exercises", "practice", "exercises (practice)"]
    for (var i = 0; i < names.length; i++) {
        var e = tx.executeSql("SELECT id, nature FROM item_kind WHERE name = ?", [names[i]])
        if (e.rows.length === 0) {
            var r = tx.executeSql("INSERT INTO item_kind (name, unit, nature, measure, uid) VALUES (?, '', 'practise', ?, ?)",
                                  [names[i], cleanMeasure(measure), newUid()])
            return r.insertId
        }
        var k = e.rows.item(0)
        if (k.nature === "practise") return k.id
        var used = tx.executeSql("SELECT COUNT(*) AS n FROM item WHERE kind_id = ?", [k.id]).rows.item(0).n
        if (used === 0) {
            tx.executeSql("UPDATE item_kind SET nature = 'practise', measure = ? WHERE id = ?", [cleanMeasure(measure), k.id])
            return k.id
        }
    }
    var last = tx.executeSql("INSERT INTO item_kind (name, unit, nature, measure, uid) VALUES (?, '', 'practise', ?, ?)",
                             ["exercises " + newUid().substr(0, 4), cleanMeasure(measure), newUid()])
    return last.insertId
}

// name key -> item id, for every thing of one kind.
function thingIndex(tx, kindId) {
    var map = {}
    if (kindId === null || kindId === undefined || kindId < 0) return map
    var r = tx.executeSql("SELECT id, title FROM item WHERE kind_id = ? ORDER BY id", [kindId])
    for (var i = 0; i < r.rows.length; i++) {
        var key = nameKey(r.rows.item(i).title)
        if (map[key] === undefined) map[key] = r.rows.item(i).id
    }
    return map
}

// The thing called `name` in this kind, made if there is none. `index` is a
// thingIndex() of the same kind and is kept up to date here.
function thingIdFor(tx, kindId, index, name, measure, startedAt) {
    var key = nameKey(name)
    if (key === "" || kindId === null || kindId === undefined || kindId < 0) return -1
    if (index[key] !== undefined) return index[key]
    var r = tx.executeSql("INSERT INTO item (title, kind_id, state, private, started_at, measure, uid) VALUES (?, ?, 'active', 0, ?, ?, ?)",
                          [tidyName(name), kindId, startedAt, (measure === undefined || measure === "") ? null : cleanMeasure(measure), newUid()])
    index[key] = r.insertId
    return r.insertId
}

// Gives every structured habit a practise kind, and every exercise that is
// still only a name a thing of that kind. Fills empty columns only; safe to
// run again, which is what import does after loading an older file.
function linkPractise(tx) {
    var hs = tx.executeSql("SELECT id, detail_profile FROM habit WHERE value_type = 'structured' ORDER BY id")
    var list = []
    for (var i = 0; i < hs.rows.length; i++) list.push({ id: hs.rows.item(i).id, profile: hs.rows.item(i).detail_profile })
    for (var h = 0; h < list.length; h++) {
        var kindId = practiseKindForHabit(tx, { id: list[h].id })
        if (kindId < 0) continue
        var measure = measureForProfile(list[h].profile)
        var index = thingIndex(tx, kindId)
        var cs = tx.executeSql("SELECT c.id AS id, c.name AS name, s.started_at AS started_at FROM component c JOIN session s ON s.id = c.session_id WHERE s.habit_id = ? AND c.item_id IS NULL ORDER BY s.started_at, c.id", [list[h].id])
        var comps = []
        for (var c = 0; c < cs.rows.length; c++) comps.push(cs.rows.item(c))
        for (var k = 0; k < comps.length; k++) {
            var itemId = thingIdFor(tx, kindId, index, comps[k].name, measure, comps[k].started_at)
            if (itemId >= 0) tx.executeSql("UPDATE component SET item_id = ? WHERE id = ?", [itemId, comps[k].id])
        }
    }
}

// The things of one practise kind, by name. `includeArchived` false leaves
// out what has been put away.
function things(kindId, includeArchived) {
    var list = items({ kindId: kindId, includePrivate: true })
    var out = []
    for (var i = 0; i < list.length; i++) {
        if (includeArchived !== true && list[i].state === "archived") continue
        out.push(list[i])
    }
    return out
}

// Every session one thing was part of, oldest first. One entry per DAY, like
// a sitting on the shelf. Two habits can share a day -- the plank done at
// rehab and at the gym on the same Tuesday is one Tuesday of planks.
//
// Within one habit, only the LAST session of a day counts. Before a save
// rewrote the day's session, every save made a new one, so some old days
// hold the same workout three or six times over. That last one is the one
// the session page itself has always shown; the others stay in the database,
// untouched, and are simply not counted twice.
//
// [{ day, details: [...] }]
function thingDays(itemId) {
    var byDay = {}, order = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT substr(s.started_at, 1, 10) AS day, d.reps AS reps, d.weight_kg AS weight_kg, d.duration_sec AS duration_sec, d.distance_m AS distance_m, d.note AS note FROM component c JOIN session s ON s.id = c.session_id LEFT JOIN detail d ON d.component_id = c.id WHERE c.item_id = ? AND s.id = (SELECT MAX(s2.id) FROM session s2 WHERE s2.habit_id = s.habit_id AND substr(s2.started_at, 1, 10) = substr(s.started_at, 1, 10)) ORDER BY s.started_at, s.id, c.sort_order, d.id", [itemId])
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            if (byDay[row.day] === undefined) { byDay[row.day] = []; order.push(row.day) }
            // A component with no sets still means it was done that day.
            var empty = row.reps === null && row.weight_kg === null && row.duration_sec === null
                        && row.distance_m === null && row.note === null
            if (!empty) byDay[row.day].push(rowToDetail(row))
        }
    })
    var out = []
    for (var j = 0; j < order.length; j++) out.push({ day: order[j], details: byDay[order[j]] })
    return out
}

function round1(v) { return Math.round(v * 10) / 10 }
function round2(v) { return Math.round(v * 100) / 100 }

// What one day's sets of one thing come to. Everything a page might want to
// say about that day, worked out once.
//
// best is the estimated one-rep maximum of the strongest set (Epley: weight
// times one plus reps over thirty). It is a way to compare 5 × 100 with
// 8 × 90, not a claim about what you could lift.
function dayFacts(details, measure) {
    var f = { sets: details.length, reps: 0, top: 0, volume: 0, best: 0,
              minutes: 0, km: 0, value: 0, maxSet: 0 }
    for (var i = 0; i < details.length; i++) {
        var d = details[i]
        var reps = (d.reps === null || d.reps === undefined || d.reps === "") ? 0 : Number(d.reps)
        var w = (d.weight === null || d.weight === undefined || d.weight === "") ? 0 : Number(d.weight)
        f.reps += reps
        if (reps > f.maxSet) f.maxSet = reps
        if (w > f.top) f.top = w
        f.volume += reps * w
        if (w > 0 && reps > 0) {
            var e = reps === 1 ? w : w * (1 + reps / 30)
            if (e > f.best) f.best = e
        }
        if (d.duration !== null && d.duration !== undefined && d.duration !== "") f.minutes += Number(d.duration) / 60
        if (d.distance !== null && d.distance !== undefined && d.distance !== "") f.km += Number(d.distance) / 1000
    }
    f.top = round2(f.top)
    f.volume = round1(f.volume)
    f.best = round1(f.best)
    f.minutes = round1(f.minutes)
    f.km = round2(f.km)
    // The one number a line through the days is drawn with. Weight when
    // there is any, reps when there is not yet; minutes; distance when it
    // was measured, minutes when it was not.
    if (measure === "time") f.value = f.minutes
    else if (measure === "time_distance") f.value = f.km > 0 ? f.km : f.minutes
    else f.value = f.top > 0 ? f.top : f.reps
    return f
}

// What the value of dayFacts() is counted in, said for a heading.
function valueUnit(measure, facts) {
    if (measure === "time") return "min"
    if (measure === "time_distance") return (facts && facts.km > 0) ? "km" : "min"
    return (facts && facts.top > 0) ? "kg" : "reps"
}

function fmt(v) {
    return String(round2(v))
}

// One day's sets, the way you would say them: "3 × 8 · 60 kg", "8 × 60,
// 6 × 65 kg", "12 min", "5.2 km in 28 min". Sets with only a note count but
// say nothing.
function setSummary(details, measure) {
    if (details === undefined || details === null || details.length === 0) return ""
    var m = cleanMeasure(measure)
    var parts = [], i
    if (m === "time") {
        var mins = 0
        for (i = 0; i < details.length; i++) if (details[i].duration) mins += Number(details[i].duration) / 60
        if (mins <= 0) return details.length === 1 ? "1 set" : details.length + " sets"
        return details.length > 1 ? details.length + " sets · " + fmt(round1(mins)) + " min" : fmt(round1(mins)) + " min"
    }
    if (m === "time_distance") {
        var tm = 0, km = 0
        for (i = 0; i < details.length; i++) {
            if (details[i].duration) tm += Number(details[i].duration) / 60
            if (details[i].distance) km += Number(details[i].distance) / 1000
        }
        if (km > 0 && tm > 0) return fmt(km) + " km in " + fmt(round1(tm)) + " min"
        if (km > 0) return fmt(km) + " km"
        if (tm > 0) return fmt(round1(tm)) + " min"
        return details.length === 1 ? "1 set" : details.length + " sets"
    }
    // weight times reps
    var sets = []
    for (i = 0; i < details.length; i++) {
        var r = details[i].reps, w = details[i].weight
        var hasR = r !== null && r !== undefined && r !== ""
        var hasW = w !== null && w !== undefined && w !== "" && Number(w) > 0
        if (!hasR && !hasW) continue
        sets.push({ r: hasR ? Number(r) : 0, w: hasW ? Number(w) : 0 })
    }
    if (sets.length === 0) return details.length === 1 ? "1 set" : details.length + " sets"
    // Sets that follow each other and are the same are said once, with how
    // many: "2 × 10 · 20 kg, 2 × 10 · 22.5 kg", not the same set four times.
    var groups = []
    for (i = 0; i < sets.length; i++) {
        var g = groups.length > 0 ? groups[groups.length - 1] : null
        if (g !== null && g.r === sets[i].r && g.w === sets[i].w) g.n++
        else groups.push({ n: 1, r: sets[i].r, w: sets[i].w })
    }
    var anyW = false
    for (i = 0; i < groups.length; i++) if (groups[i].w > 0) anyW = true
    if (!anyW) {
        // Bodyweight. "5, 4, 3, 2 reps" while every set differs; "2 × 5,
        // 2 × 3 reps" once sets repeat.
        var allOne = true
        for (i = 0; i < groups.length; i++) if (groups[i].n > 1) allOne = false
        for (i = 0; i < groups.length; i++) {
            if (allOne) parts.push(String(groups[i].r))
            else parts.push(groups[i].n > 1 ? groups[i].n + " × " + groups[i].r : String(groups[i].r))
        }
        if (groups.length === 1 && groups[0].n === 1) return groups[0].r + " reps"
        return parts.join(", ") + " reps"
    }
    if (groups.length === 1) {
        var only = groups[0]
        return (only.n > 1 ? only.n + " × " + only.r : only.r + " reps") + " · " + fmt(only.w) + " kg"
    }
    for (i = 0; i < groups.length; i++) {
        var gr = groups[i]
        parts.push((gr.n > 1 ? gr.n + " × " : "") + gr.r + (gr.w > 0 ? " · " + fmt(gr.w) : ""))
    }
    return parts.join(", ") + " kg"
}

// The thing of this kind that answers to `name`, or -1.
function thingIdByName(kindId, name) {
    var key = nameKey(name)
    if (key === "" || kindId === null || kindId === undefined || kindId < 0) return -1
    var id = -1
    db().readTransaction(function(tx) {
        var idx = thingIndex(tx, kindId)
        if (idx[key] !== undefined) id = idx[key]
    })
    return id
}

// The last time a thing was done before `beforeDay`, found by its name within
// a kind -- which is how the session page knows it while you are still typing.
// { itemId, day, details, measure, summary } or null.
function lastTimeFor(kindId, name, beforeDay) {
    var key = nameKey(name)
    if (key === "" || kindId === null || kindId === undefined || kindId < 0) return null
    var itemId = -1
    db().readTransaction(function(tx) {
        var idx = thingIndex(tx, kindId)
        if (idx[key] !== undefined) itemId = idx[key]
    })
    if (itemId < 0) return null
    var it = itemById(itemId)
    var days = thingDays(itemId)
    for (var i = days.length - 1; i >= 0; i--) {
        if (beforeDay !== undefined && beforeDay !== "" && days[i].day >= beforeDay) continue
        return { itemId: itemId, day: days[i].day, details: days[i].details,
                 measure: it.measure, summary: setSummary(days[i].details, it.measure) }
    }
    return { itemId: itemId, day: "", details: [], measure: it.measure, summary: "" }
}

// The things one habit has used, most recently used first. What the session
// page offers before anything is typed: your own exercises, not everything
// of the kind.
function habitThings(habitId, limit) {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT i.id AS id, MAX(s.started_at) AS last FROM component c JOIN session s ON s.id = c.session_id JOIN item i ON i.id = c.item_id WHERE s.habit_id = ? AND i.state <> 'archived' GROUP BY i.id ORDER BY last DESC", [habitId])
        for (var k = 0; k < r.rows.length; k++) out.push(r.rows.item(k).id)
    })
    var list = []
    for (var j = 0; j < out.length; j++) {
        var it = itemById(out[j])
        if (it !== null) list.push(it)
        if (limit !== undefined && limit > 0 && list.length >= limit) break
    }
    return list
}

// The things of a kind that start with or contain what is being typed, for
// picking an exercise by name. Starts-with first. With nothing typed and a
// habit given, that habit's own things instead of the whole kind.
function thingSuggestions(kindId, text, limit, habitId) {
    if (nameKey(text) === "" && habitId !== undefined && habitId !== null && habitId >= 0)
        return habitThings(habitId, limit)
    var t = nameKey(text)
    var list = things(kindId, false)
    var first = [], rest = []
    for (var i = 0; i < list.length; i++) {
        var k = nameKey(list[i].title)
        if (t === "") { first.push(list[i]); continue }
        if (k === t) continue
        if (k.indexOf(t) === 0) first.push(list[i])
        else if (k.indexOf(t) > 0) rest.push(list[i])
    }
    var out = first.concat(rest)
    return (limit !== undefined && limit > 0) ? out.slice(0, limit) : out
}

// One thing over its whole life. Worked out every time it is asked for.
//
// `then` is the comparison the page leads with: the last day at least half a
// year back, so "heavier than six months ago" is a fact and not a feeling.
// When there is no day that old yet, the first day there is.
function thingStats(itemId) {
    var it = itemById(itemId)
    if (it === null) return null
    var m = it.measure
    var days = thingDays(itemId)
    var list = []
    var bestDay = null
    for (var i = 0; i < days.length; i++) {
        var f = dayFacts(days[i].details, m)
        var row = { day: days[i].day, sets: f.sets, reps: f.reps, top: f.top, volume: f.volume,
                    best: f.best, minutes: f.minutes, km: f.km, value: f.value, maxSet: f.maxSet,
                    summary: setSummary(days[i].details, m) }
        list.push(row)
        if (bestDay === null || row.value > bestDay.value) bestDay = row
    }
    var latest = list.length > 0 ? list[list.length - 1] : null
    var cutoff = dayOffsetKey(-182)
    var then = null
    for (var j = list.length - 1; j >= 0; j--) {
        if (list[j].day <= cutoff) { then = list[j]; break }
    }
    if (then === null && list.length > 1) then = list[0]
    if (then !== null && latest !== null && then.day === latest.day) then = null
    var maxSet = 0, maxDay = 0, sets = 0
    for (var q = 0; q < list.length; q++) {
        if (list[q].maxSet > maxSet) maxSet = list[q].maxSet
        if (list[q].reps > maxDay) maxDay = list[q].reps
        sets += list[q].sets
    }
    var weighted = false
    for (var w = 0; w < list.length; w++) if (list[w].top > 0) weighted = true
    return {
        item: it,
        measure: m,
        // Weight times reps with no weight anywhere yet: what counts is reps.
        bodyweight: m === "weight_reps" && !weighted,
        maxSet: maxSet,
        maxDayReps: maxDay,
        sets: sets,
        unit: valueUnit(m, latest),
        days: list,
        count: list.length,
        first: list.length > 0 ? list[0].day : "",
        last: latest === null ? "" : latest.day,
        latest: latest,
        best: bestDay,
        then: then,
        halfYear: then !== null && then.day <= cutoff,
        tags: itemTags(itemId)
    }
}

// For the Practice page: every thing of a kind with the last time it was done.
function loadThings(model, kindId) {
    model.clear()
    var list = things(kindId, false)
    var rows = []
    for (var i = 0; i < list.length; i++) {
        var days = thingDays(list[i].id)
        var lastDay = days.length > 0 ? days[days.length - 1] : null
        rows.push({
            itemId: list[i].id,
            title: list[i].title,
            measure: list[i].measure,
            isPrivate: list[i].private,
            count: days.length,
            lastDay: lastDay === null ? "" : lastDay.day,
            lastSummary: lastDay === null ? "" : setSummary(lastDay.details, list[i].measure),
            tagList: itemTags(list[i].id).join(", ")
        })
    }
    // Most recently done first; never done last, by name.
    rows.sort(function(a, b) {
        if (a.lastDay !== b.lastDay) return a.lastDay < b.lastDay ? 1 : -1
        return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : 1
    })
    for (var j = 0; j < rows.length; j++) model.append(rows[j])
    return model.count
}

// A new thing to practise, from the Practice page rather than from a session.
// An existing name in the same kind is reused.
function addThing(o) {
    var id = -1
    db().transaction(function(tx) {
        var idx = thingIndex(tx, o.kindId)
        id = thingIdFor(tx, o.kindId, idx, o.title, o.measure === undefined ? "" : o.measure, localIso(new Date()))
    })
    if (id >= 0 && o.measure !== undefined && o.measure !== "") updateThing({ id: id, measure: o.measure })
    return id
}

// Renames a thing or changes how it is measured. A name that another thing of
// the same kind already has is refused, because two things answering to one
// name would split a history in two -- false is returned and nothing changes.
function updateThing(o) {
    var it = itemById(o.id)
    if (it === null) return false
    var ok = true
    db().transaction(function(tx) {
        if (o.title !== undefined) {
            var t = tidyName(o.title)
            if (t === "") { ok = false; return }
            var idx = thingIndex(tx, it.kindId)
            var other = idx[nameKey(t)]
            if (other !== undefined && other !== o.id) { ok = false; return }
            tx.executeSql("UPDATE item SET title = ? WHERE id = ?", [t, o.id])
        }
        if (o.measure !== undefined && o.measure !== "") {
            tx.executeSql("UPDATE item SET measure = ? WHERE id = ?", [cleanMeasure(o.measure), o.id])
        }
    })
    return ok
}

// Whether the pull-down offers the Shelf and Practice. The Shelf is there
// when a habit finishes things or anything is on it already -- an update must
// never hide books somebody already has. Practice, when a habit practises or
// there is anything to practise.
function hasShelf() {
    var yes = false
    db().readTransaction(function(tx) {
        var h = tx.executeSql("SELECT COUNT(*) AS n FROM habit WHERE value_type = 'reference' AND archived_at IS NULL").rows.item(0).n
        var i = tx.executeSql("SELECT COUNT(*) AS n FROM item i LEFT JOIN item_kind k ON k.id = i.kind_id WHERE COALESCE(k.nature, 'finish') <> 'practise'").rows.item(0).n
        yes = h > 0 || i > 0
    })
    return yes
}

function hasPractice() {
    var yes = false
    db().readTransaction(function(tx) {
        var h = tx.executeSql("SELECT COUNT(*) AS n FROM habit WHERE value_type = 'structured' AND archived_at IS NULL").rows.item(0).n
        var i = tx.executeSql("SELECT COUNT(*) AS n FROM item i JOIN item_kind k ON k.id = i.kind_id WHERE k.nature = 'practise'").rows.item(0).n
        yes = h > 0 || i > 0
    })
    return yes
}

// Programs -- saved sessions to start from -- with how often and when last
// each was used, for the Practice page. A program is still a `routine` row;
// only the word changed.
function programs() {
    var out = []
    db().readTransaction(function(tx) {
        var r = tx.executeSql("SELECT r.id AS id, r.name AS name, r.habit_id AS habit_id, h.name AS habit_name, COUNT(s.id) AS n, MAX(substr(s.started_at, 1, 10)) AS last FROM routine r JOIN habit h ON h.id = r.habit_id LEFT JOIN session s ON s.routine_id = r.id WHERE h.archived_at IS NULL GROUP BY r.id ORDER BY last DESC, r.name COLLATE NOCASE")
        for (var i = 0; i < r.rows.length; i++) {
            var row = r.rows.item(i)
            out.push({ id: row.id, name: row.name, habitId: row.habit_id, habitName: row.habit_name,
                       sessions: row.n, last: row.last === null ? "" : row.last })
        }
    })
    return out
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

// What a habit's history page says in its first sentence. The numbers are
// worked out here; the words belong to the page.
//
//   streak, lastDays (logged days of the last 30), median (a usual logged
//   day, numbers only), goalDays (days of the last 30 that reached the daily
//   goal, when there is one), thisMonth / lastMonth (mean rating per logged
//   day, ratings only), unit.
function habitFacts(habit) {
    var s30 = series(habit, 30)
    var logged = 0, goal = 0
    var counted = habit.dailyTarget !== null && habit.dailyTarget > 0
    for (var i = 0; i < s30.length; i++) {
        if (s30[i].value === null) continue
        logged++
        if (counted && s30[i].value >= habit.dailyTarget) goal++
    }
    var out = { streak: streak(habit), lastDays: logged, goalDays: counted ? goal : -1,
                median: null, thisMonth: null, lastMonth: null, unit: unitForHabit(habit) }
    if (habit.valueType === "numeric" || habit.valueType === "reference") {
        out.median = habitTotal(habit, 30).median
    }
    if (habit.valueType === "scale") {
        var now = new Date()
        var thisStart = dayKey(new Date(now.getFullYear(), now.getMonth(), 1))
        var lastStart = dayKey(new Date(now.getFullYear(), now.getMonth() - 1, 1))
        var rows = entriesSince(habit.id, lastStart)
        var perDay = {}
        for (var j = 0; j < rows.length; j++) {
            var d = rows[j].loggedAt.substr(0, 10)
            var v = rows[j].valueScale === null ? 0 : rows[j].valueScale
            perDay[d] = perDay[d] === undefined ? v : Math.max(perDay[d], v)
        }
        var a = [0, 0], b = [0, 0]
        for (var k in perDay) {
            if (k >= thisStart) { a[0] += perDay[k]; a[1]++ } else { b[0] += perDay[k]; b[1]++ }
        }
        if (a[1] > 0) out.thisMonth = round1(a[0] / a[1])
        if (b[1] > 0) out.lastMonth = round1(b[0] / b[1])
    }
    return out
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
                             name: kinds[a].name, unit: kinds[a].unit,
                             nature: kinds[a].nature === undefined ? null : kinds[a].nature,
                             measure: kinds[a].measure === undefined ? null : kinds[a].measure,
                             doneWord: kinds[a].done_word === undefined ? null : kinds[a].done_word })
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
                private: it.private, startedAt: it.started_at, finishedAt: it.finished_at,
                extent: it.extent === undefined ? null : it.extent,
                isbn: it.isbn === undefined ? null : it.isbn,
                measure: it.measure === undefined ? null : it.measure
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
                                  item: look("item", comps[j].item_id),
                                  name: comps[j].name, sortOrder: comps[j].sort_order })
        }

        var details = remember("detail", rowsOf(tx, "SELECT * FROM detail ORDER BY id"))
        for (var k = 0; k < details.length; k++) {
            var de = details[k]
            out.details.push({ ref: look("detail", de.id),
                               component: look("component", de.component_id),
                               reps: de.reps, weightKg: de.weight_kg,
                               durationSec: de.duration_sec,
                               distanceM: de.distance_m === undefined ? null : de.distance_m,
                               note: de.note })
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
            // nature and measure arrived in schema 10; an older file has
            // neither, and its kinds come in as things you finish.
            var kn = (k.nature === undefined || k.nature === null) ? null : cleanNature(k.nature)
            var kr = tx.executeSql("INSERT INTO item_kind (name, unit, nature, measure, done_word, uid) VALUES (?, ?, ?, ?, ?, ?)",
                                   [k.name, (k.unit === null || k.unit === undefined) ? "" : k.unit, kn,
                                    (k.measure === undefined || k.measure === null) ? null : cleanMeasure(k.measure),
                                    (k.doneWord === undefined || k.doneWord === null) ? null : cleanDoneWord(k.doneWord),
                                    keep(k.ref)])
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
            // extent and isbn arrived in schema 9. A file from before then
            // simply has neither, and the item comes in without them.
            var ir = tx.executeSql("INSERT INTO item (title, creator, kind_id, state, private, started_at, finished_at, extent, isbn, measure, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                   [it.title, it.creator, id("item_kind", it.kind),
                                    it.state || "active", it.private ? 1 : 0,
                                    it.startedAt, it.finishedAt,
                                    cleanExtent(it.extent), cleanIsbn(it.isbn),
                                    (it.measure === undefined || it.measure === null) ? null : cleanMeasure(it.measure),
                                    keep(it.ref)])
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
            var cr = tx.executeSql("INSERT INTO component (session_id, name, sort_order, item_id, uid) VALUES (?, ?, ?, ?, ?)",
                                   [sid, co.name, co.sortOrder || 0, id("item", co.item), keep(co.ref)])
            map.component[co.ref] = cr.insertId
        }

        var details = data.details || []
        for (i = 0; i < details.length; i++) {
            var de = details[i]
            var cid = id("component", de.component)
            if (cid === null) continue
            tx.executeSql("INSERT INTO detail (component_id, reps, weight_kg, duration_sec, distance_m, note, uid) VALUES (?, ?, ?, ?, ?, ?, ?)",
                          [cid, de.reps, de.weightKg, de.durationSec,
                           (de.distanceM === undefined) ? null : de.distanceM, de.note, keep(de.ref)])
        }

        // A file from before schema 10 has exercises that are only names.
        // The same step the migration ran ties them to things now -- it only
        // fills what is empty, so on a newer file it does nothing.
        linkPractise(tx)
        // And a file from before schema 11 has no done word; the kinds that
        // were always about learning get theirs, as the migration gave them.
        tx.executeSql("UPDATE item_kind SET done_word = 'learned' WHERE done_word IS NULL AND name IN ('repertoire', 'texts')")
    })

    counts.ok = true
    return counts
}
