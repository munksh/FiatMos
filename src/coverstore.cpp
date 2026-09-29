#include "coverstore.h"

#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegExp>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>

CoverStore::CoverStore(QObject *parent)
    : QObject(parent)
    , m_net(0)
{
}

// Thirteen digits and nothing else. The ISBN becomes a file name, so this is
// also what keeps a stray value from naming a file somewhere it should not.
bool CoverStore::validIsbn(const QString &isbn)
{
    return QRegExp(QStringLiteral("^[0-9]{13}$")).exactMatch(isbn);
}

QString CoverStore::directory()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/covers");
}

QString CoverStore::fileFor(const QString &isbn)
{
    return directory() + QLatin1Char('/') + isbn + QStringLiteral(".jpg");
}

QString CoverStore::path(const QString &isbn) const
{
    if (!validIsbn(isbn))
        return QString();
    QFileInfo info(fileFor(isbn));
    if (!info.exists() || info.size() == 0)
        return QString();
    return QUrl::fromLocalFile(info.absoluteFilePath()).toString();
}

void CoverStore::fetch(const QString &isbn, const QString &url)
{
    if (!validIsbn(isbn)) {
        emit fetched(isbn, false);
        return;
    }

    // No address, no request. Which services may be contacted is decided by
    // the user (LookupSettings), so nothing here picks one on its own.
    QUrl source(url);
    if (url.isEmpty() || source.scheme() != QLatin1String("https")) {
        emit fetched(isbn, false);
        return;
    }

    QNetworkRequest request(source);
    // Open Library hands covers out through a redirect to the Internet
    // Archive, and Qt does not follow redirects unless told to.
    request.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("harbour-fiatmos (Sailfish OS)"));

    // Made on first use. Most CoverStores only ever answer path() for a row
    // in a list, and have no business holding a network stack.
    if (!m_net)
        m_net = new QNetworkAccessManager(this);

    QNetworkReply *reply = m_net->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, isbn]() {
        reply->deleteLater();

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError || status != 200) {
            emit fetched(isbn, false);
            return;
        }

        // Only keep it if it really is a picture. A missing cover can come
        // back as a tiny placeholder or an error page with a 200 on it.
        const QByteArray data = reply->readAll();
        QImage image;
        if (data.size() < 200 || !image.loadFromData(data) || image.width() < 10) {
            emit fetched(isbn, false);
            return;
        }

        QDir().mkpath(directory());
        QSaveFile file(fileFor(isbn));
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
            emit fetched(isbn, false);
            return;
        }
        emit fetched(isbn, true);
    });
}
