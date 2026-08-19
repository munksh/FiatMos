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
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
