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

# For CoverStore, which fetches a book's cover when you press Look up.
QT += network

# Set by the rpm spec (%qmake5 "VERSION=%{version}"). The fallback is only for
# building straight out of Qt Creator, where rpm is not involved.
isEmpty(VERSION): VERSION = 0.0.0-dev
DEFINES += APP_VERSION=\\\"$$VERSION\\\"

SOURCES += \
    src/harbour-fiatmos.cpp \
    src/coverstore.cpp \
    src/fileio.cpp

HEADERS += \
    src/coverstore.h \
    src/fileio.h

# Everything listed here gets deployed to /usr/share/harbour-fiatmos/.
# Storage.js and qmldir MUST be listed or they silently do not ship.
DISTFILES += \
    qml/harbour-fiatmos.qml \
    qml/Storage.js \
    qml/Lookup.js \
    qml/LookupSettings.qml \
    qml/FiatMosTheme.qml \
    qml/qmldir \
    qml/components/Almanac.qml \
    qml/components/BookCover.qml \
    qml/components/DialogHead.qml \
    qml/components/LookupRunner.qml \
    qml/components/EmptyNote.qml \
    qml/components/MunkstolenMark.qml \
    qml/components/PageHead.qml \
    qml/components/Pill.qml \
    qml/components/ProgressRing.qml \
    qml/components/SectionLabel.qml \
    qml/components/Shelf.qml \
    qml/components/ValueRow.qml \
    qml/cover/CoverPage.qml \
    qml/pages/images/family/harbour-fiatagenda.png \
    qml/pages/images/family/harbour-fiatmargo.png \
    qml/pages/images/family/harbour-fiatglossa.png \
    qml/pages/images/family/harbour-fiatvox.png \
    qml/pages/images/family/harbour-fiatpons.png \
    qml/pages/images/family/harbour-fiatlux.png \
    qml/pages/images/family/harbour-fiatcor.png \
    qml/pages/images/family/harbour-fiatpassus.png \
    qml/pages/images/family/harbour-fiatmos.png \
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
    qml/pages/KindStatsPage.qml \
    qml/pages/LookupServicesPage.qml \
    qml/pages/ItemPage.qml \
    rpm/harbour-fiatmos.spec

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

# Translations are not wired up yet; add them here when they are.
# CONFIG += sailfishapp
# TRANSLATIONS += translations/harbour-fiatmos-sv.ts
