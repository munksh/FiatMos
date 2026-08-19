#ifndef FILEIO_H
#define FILEIO_H

#include <QObject>
#include <QString>

// Reading and writing a text file, for export and import.
//
// This exists because QML cannot write files. XMLHttpRequest can read a
// file:// URL and that is where it stops -- there is no write side, and no
// amount of QML will produce one. So the smallest possible C++ class, doing
// exactly two things, and nothing that could not be read in a minute.
//
// It is deliberately not a general file API. It takes a path, it moves text,
// it reports what went wrong. It cannot list, delete, or walk a directory,
// so the worst a bug here can do is write the wrong file inside the sandbox.
class FileIO : public QObject
{
    Q_OBJECT

public:
    explicit FileIO(QObject *parent = 0);

    // Accepts either a plain path or a file:// URL, because the Sailfish
    // file picker hands back URLs and everything else hands back paths, and
    // making every caller remember which is a bug waiting to happen.
    Q_INVOKABLE bool write(const QString &target, const QString &text);
    Q_INVOKABLE QString read(const QString &target);

    // Where an export should go. Empty if the sandbox does not grant it,
    // which is the honest signal that the Documents permission is missing.
    Q_INVOKABLE QString documentsPath() const;

    Q_INVOKABLE QString lastError() const { return m_lastError; }

private:
    QString resolve(const QString &target) const;
    QString m_lastError;
};

#endif // FILEIO_H
