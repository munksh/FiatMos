Name:       harbour-fiatmos
Summary:    Habit tracker where each habit sets its own detail
Version:    1.0.0
Release:    1
License:    MIT
URL:        https://github.com/munksh/FiatMos
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils

# Note: QtQuick.LocalStorage and Nemo.Configuration both ship with the OS.
# Do NOT add Requires: lines for them -- nemo-qml-plugin-configuration does
# not exist as a package and the install will fail with "Paketet hittades ej".
#
# Do NOT use %%qtc_qmake5 / %%qtc_make / %%qmake5_install here. Those macros
# are Qt Creator's own and are not defined in this build target; an undefined
# macro passes through literally and the build dies with "fg: no job control".

%description
Most habit trackers decide in advance how much detail a habit deserves, and
then every habit has to live with that decision. Fiat Mos moves the choice to
you, one habit at a time.

A habit can be a plain tick. It can be a number with a unit. It can be a
rating on a scale you invent. It can work through a library of things --
books, repertoire, rolls of film, whatever you actually work through -- where
each kind carries its own unit, so pages and minutes can never be added into
one meaningless total. Or it can be a full session of exercises and sets, for
training and rehab.

The analysis does not care which you picked. Streaks, totals, averages and
history are computed from the log every time they are shown, never stored, so
they cannot drift out of step with the entries behind them. Nothing is ever
deleted: undo writes a new row, and habits are archived rather than removed.

Fiat Mos asks for no permissions. It has no network access, no account and no
telemetry. Everything stays in one file on your phone.

Third in the Fiat family, after Fiat Lux (a light meter) and Fiat Vox (a
tuner).

%if 0%{?_chum}
Title: Fiat Mos
Type: desktop-application
DeveloperName: Munkstolen
Categories:
 - Utility
 - Office
Custom:
  Repo: https://github.com/munksh/FiatMos
Links:
  Homepage: https://github.com/munksh/FiatMos
  Bugtracker: https://github.com/munksh/FiatMos/issues
%endif

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5
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
