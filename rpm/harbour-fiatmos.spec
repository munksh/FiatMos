Name:       harbour-fiatmos
Summary:    Habit tracker where each habit sets its own detail
Version:    1.2
Release:    1
License:    MIT
URL:        https://github.com/munksh/FiatMos
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  desktop-file-utils

# Note: QtQuick.LocalStorage and Nemo.Configuration both ship with the OS.
# Do NOT add Requires: lines for them -- nemo-qml-plugin-configuration does
# not exist as a package and the install will fail with "Paketet hittades ej".
#
# Do NOT use %%qtc_qmake5 / %%qtc_make / %%qmake5_install here. Those macros
# are Qt Creator's own and are not defined in this build target; an undefined
# macro passes through literally and the build dies with "fg: no job control".

# The five kinds of habit are separated by blank lines rather than written as
# consecutive lines. Some readers of this text preserve single line breaks and
# some collapse them; with blank lines the list survives both, and as one run
# of lines it would have become a wall of prose in half the places it appears.

%description
Most habit trackers decide in advance how much detail a habit deserves, and
then every habit has to live with that decision. Flossing gets the same form
as a gym session. Fiat Mos moves the choice to you, one habit at a time.

A habit can be:

A tick. Done or not done, one tap and the day is finished.

A number with a unit. Minutes run, glasses of water, kilos lifted.

A rating on a scale you invent. Sleep from 0 to 3, mood from 0 to 7.

Something you work through. Books, repertoire, rolls of film, study texts.
You keep a small library of them, and each kind of thing carries its own
unit - so pages and minutes can never be added together into one meaningless
number. Each kind gets its own shelf, calendar and statistics, and each item
shows how far in you are.

A whole session. Exercises, sets, reps and weights, for training and rehab.
One session per day, saved as you go.

Missed something before midnight? Yesterday stays open. The next morning
the list shows what was left, one tap from done.

The analysis does not care which you picked. Streaks, totals, averages,
medians and history are worked out from your entries every time they are
shown and never stored, so they cannot quietly drift out of step with what
actually happened.

Nothing is deleted behind your back either. Undo writes a new entry rather
than removing one, and habits are archived instead of erased.

WHAT IT DOES WITH YOUR DATA

Nothing at all. There is no account and no telemetry. Everything lives in
one file on your phone.

Fiat Mos asks for two permissions. Documents, so that Backup can write an
export you can carry to a new phone. That export is plain readable JSON:
your history stays yours and stays readable even if this app stops existing.

And Internet, for one button. When you add a book you can look it up by its
ISBN: the ISBN goes to the services you have switched on - Open Library,
Libris at the Swedish national library, the German and French national
libraries and, only if you allow it, Google Books - and the title, author,
length and cover come back. Each of them also sees your phone's IP address.
Nothing else is ever sent, nothing is sent until you press Look up, and a
service you have not switched on is never contacted.

THE NAME

fiat - Latin, let there be. From fiat lux in the Vulgate: let there be light,
and there was light.

mos - Latin, custom, the way a thing is usually done. Its plural, mores, is
where morals come from. A habit is a custom you keep with yourself.

Third in a small family of Sailfish instruments, alongside Fiat Lux, a light
meter for film photography, and Fiat Vox, a chromatic tuner.

Gutta cavat lapidem, non vi sed saepe cadendo. The drop hollows the stone,
not by force but by falling often.

Source, issues and licence (MIT): github.com/munksh/FiatMos

%if 0%{?_chum}
Title: Fiat Mos
Type: desktop-application
DeveloperName: Munkstolen
Categories:
 - Utility
 - Office
PackageIcon: https://munkstolen.se/SFOS/fiat-mos/harbour-fiatmos.png
Screenshots:
 - https://munkstolen.se/SFOS/fiat-mos/fiat-mos1.png
 - https://munkstolen.se/SFOS/fiat-mos/fiat-mos2.png
 - https://munkstolen.se/SFOS/fiat-mos/fiat-mos3.png
Custom:
  Repo: https://github.com/munksh/FiatMos
Links:
  Homepage: https://github.com/munksh/FiatMos
  Bugtracker: https://github.com/munksh/FiatMos/issues
%endif

%prep
%setup -q -n %{name}-%{version}

%build
# The version is passed IN rather than repeated. rpm owns it; qmake hands it to
# the code; the About page shows what was actually built. Written twice, the
# two copies drift, and an About page that lies about its version is worse
# than no About page.
%qmake5 "VERSION=%{version}"
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install INSTALL_ROOT=%{buildroot}
desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
  %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
