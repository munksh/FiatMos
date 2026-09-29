#ifndef COVERSTORE_H
#define COVERSTORE_H

#include <QObject>
#include <QString>

class QNetworkAccessManager;

// Book covers, kept on the phone.
//
// A cover is fetched once, when you press Look up (or Fetch cover on a book
// that has an ISBN but no picture yet), from a service you have switched on,
// and saved as <isbn>.jpg in the app's
// own data folder. It is never fetched on its own initiative: nothing here
// runs unless a page asks.
//
// The ISBN is the key because it is the one thing about a book that travels.
// Covers are not in the export; the ISBN is, so a new phone can fetch them
// again.
//
// This is C++ only because QML cannot write a binary file.
class CoverStore : public QObject
{
    Q_OBJECT

public:
    explicit CoverStore(QObject *parent = 0);

    // A file:// URL for the cover, or "" when there is none on the phone.
    Q_INVOKABLE QString path(const QString &isbn) const;

    // Downloads the cover from `url` (https only) and emits fetched() when
    // done. An empty or non-https address fails at once: this class has no
    // default source, because which services may be contacted is the user's
    // choice and is decided by the caller.
    Q_INVOKABLE void fetch(const QString &isbn, const QString &url);

signals:
    void fetched(const QString &isbn, bool ok);

private:
    static bool validIsbn(const QString &isbn);
    static QString directory();
    static QString fileFor(const QString &isbn);

    QNetworkAccessManager *m_net;
};

#endif // COVERSTORE_H
