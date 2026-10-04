.pragma library

// The five kinds of habit, as the New habit page and the empty habit list
// both show them. One list in one place, so the first screen and the form
// can never come to say different things.
//
// Ordered from the simplest to the richest. That order is the only grouping
// there is: a heading saying "complex" would only frighten.
//
//   key        Storage's value_type
//   title      what the row says
//   examples   always shown under it; what tells a newcomer which is theirs
//   gets       shown only once chosen: what this kind of habit brings along

function list() {
    return [
        { key: "boolean", title: qsTr("Do it"),
          examples: qsTr("Floss, meditate, a walk."),
          gets: [qsTr("One tap on the dot and the day is done.")] },
        { key: "numeric", title: qsTr("Count it"),
          examples: qsTr("Glasses of water, minutes run, words written."),
          gets: [qsTr("A number with its unit each time."),
                 qsTr("A ring that fills toward a daily goal, if you set one.")] },
        { key: "scale", title: qsTr("Rate it"),
          examples: qsTr("Sleep, mood, pain."),
          gets: [qsTr("A value on a scale you choose, and how it moves over the weeks.")] },
        { key: "reference", title: qsTr("Finish it"),
          examples: qsTr("Books, audiobooks, films, rolls of film."),
          gets: [qsTr("Each thing lives on your Shelf until it is finished."),
                 qsTr("Books can be looked up by ISBN, with a cover."),
                 qsTr("Counts what you finish: books this year, rolls this month.")] },
        { key: "structured", title: qsTr("Practise it"),
          examples: qsTr("Gym, rehab, an instrument, a text by heart."),
          gets: [qsTr("A session of several things, each with its sets, minutes or distance."),
                 qsTr("Last time is shown beside today, so you know what to aim for."),
                 qsTr("Each thing keeps its own history under Practice: heavier, longer, steadier."),
                 qsTr("Save a session as a program and start from it next time.")] }
    ]
}
