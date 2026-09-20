#include <QtQuick>
#include <sailfishapp.h>

#include "fileio.h"

int main(int argc, char *argv[])
{
    // The long form rather than SailfishApp::main(), for one reason: a type
    // has to be registered before the QML is loaded, and main() gives no
    // hook between the two. Everything else here is what main() would do.
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));

    qmlRegisterType<FileIO>("se.munkstolen.fiatmos", 1, 0, "FileIO");

    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // The About page reads this as appVersion. The .pro already compiles
    // APP_VERSION in from the rpm spec's version by way of qmake's DEFINES,
    // but nothing had ever handed it to QML -- so the page fell back to its
    // "unknown" placeholder every time, correctly, because appVersion really
    // was undefined.
    //
    // QStringLiteral(APP_VERSION) rather than plain QStringLiteral("...."):
    // APP_VERSION only exists once qmake's DEFINES substitutes it in, so this
    // project's QStringLiteral (redefined somewhere in these headers to route
    // through a custom operator""_i18n) never sees a literal it recognises --
    // it wants a string typed directly at the call site, not one that
    // arrives through another macro. fromUtf8() is a plain runtime call and
    // never touches that machinery.
    view->rootContext()->setContextProperty(QStringLiteral("appVersion"), QString::fromUtf8(APP_VERSION));

    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
