#include "fileio.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>

FileIO::FileIO(QObject *parent)
    : QObject(parent)
{
}

QString FileIO::resolve(const QString &target) const
{
    if (target.startsWith(QLatin1String("file:"))) {
        return QUrl(target).toLocalFile();
    }
    return target;
}

QString FileIO::documentsPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
}

bool FileIO::write(const QString &target, const QString &text)
{
    const QString path = resolve(target);
    if (path.isEmpty()) {
        m_lastError = QStringLiteral("No path given");
        return false;
    }

    // The directory may legitimately not exist yet on a fresh device.
    QDir().mkpath(QFileInfo(path).absolutePath());

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        m_lastError = file.errorString();
        return false;
    }

    QTextStream out(&file);
    out.setCodec("UTF-8");
    out << text;
    file.close();

    if (file.error() != QFile::NoError) {
        m_lastError = file.errorString();
        return false;
    }

    m_lastError.clear();
    return true;
}

QString FileIO::read(const QString &target)
{
    const QString path = resolve(target);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_lastError = file.errorString();
        return QString();
    }

    QTextStream in(&file);
    in.setCodec("UTF-8");
    const QString text = in.readAll();
    file.close();

    m_lastError.clear();
    return text;
}
