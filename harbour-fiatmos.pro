# NOTICE:
#
# Application name defined in TARGET has a corresponding QML filename.
# If name defined in TARGET is changed, the following needs to be done
# to match new name:
#   - corresponding QML filename must be changed
#   - desktop icon filename must be changed
#   - desktop filename must be changed
#   - icon definition filename in desktop file must be changed
#   - translation filenames have to be changed
#
# The harbour- prefix is a STORE requirement, not a name. It is the package
# and binary name; what anyone actually sees is Name= in the .desktop file,
# which still says "Fiat Mos".

TARGET = harbour-fiatmos

CONFIG += sailfishapp

# Set by the rpm spec (%qmake5 "VERSION=%{version}"). The fallback is only for
# building straight out of Qt Creator, where rpm is not involved.
isEmpty(VERSION): VERSION = 0.0.0-dev
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/harbour-fiatmos.cpp \
    src/fileio.cpp

HEADERS += \
    src/fileio.h

# Everything listed here gets deployed to /usr/share/harbour-fiatmos/.
# Storage.js and qmldir MUST be listed or they silently do not ship.
DISTFILES += \
    qml/harbour-fiatmos.qml \
    qml/Storage.js \
    qml/FiatMosTheme.qml \
    qml/qmldir \
    qml/components/DialogHead.qml \
    qml/components/EmptyNote.qml \
    qml/components/MunkstolenMark.qml \
    qml/components/PageHead.qml \
    qml/components/Pill.qml \
    qml/components/ProgressRing.qml \
    qml/components/SectionLabel.qml \
    qml/components/ValueRow.qml \
    qml/cover/CoverPage.qml \
    qml/pages/HabitListPage.qml \
    qml/pages/AddHabitPage.qml \
    qml/pages/LogPage.qml \
    qml/pages/HistoryPage.qml \
    qml/pages/SessionPage.qml \
    qml/pages/LibraryPage.qml \
    qml/pages/AddBookPage.qml \
    qml/pages/KindPage.qml \
    qml/pages/BackupPage.qml \
    qml/pages/AboutPage.qml \
    qml/pages/TagTotalsPage.qml \
    rpm/harbour-fiatmos.spec

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# Translations are not wired up yet; add them here when they are.
# CONFIG += sailfishapp

# Set by the rpm spec (%qmake5 "VERSION=%{version}"). The fallback is only for
# building straight out of Qt Creator, where rpm is not involved.
isEmpty(VERSION): VERSION = 0.0.0-dev
DEFINES += APP_VERSION=\\\"$$VERSION\\\"_i18n
# TRANSLATIONS += translations/harbour-fiatmos-sv.ts
