# Fiat Mos

Vanetracker för Sailfish OS. *Mos* är latin för "sed, vana". Del av samma
appserie som **Fiat Lux** (ljusmätare) och **Fiat Vox** (tuner).

Bärande idé: komplexiteten per vana är användarens eget val, inte fast per
app. Man väljer mall när vanan skapas, och analyslagret bryr sig bara om att
det finns en `log_entry`-rad för perioden.

---

## Status

MVP-punkt 1–4 och 8 är byggda:

| # | Scope | Status |
|---|---|---|
| 1 | Skapa vana (Simple/Numeric/Scale), namn, frekvens | klar |
| 2 | Logga idag per vana enligt mallens fält | klar |
| 3 | Habit-lista med dagens status | klar |
| 4 | Streak-räkning (dagligt/veckovis/intervall) | klar |
| 5 | Reference-mall (böcker) | tabeller finns, ingen UI |
| 6 | Structured-mall (session/component/detail) | tabeller finns, ingen UI |
| 7 | Trend-/historikvy | klar (dagrutnät + stapelgraf + avvikelse mot mål) |
| 8 | Cover page med badge | klar |

Tabellerna för mall 4 och 5 ligger redan i migration 2 och 3. De kostar
ingenting tomma, och när UI:t kommer behöver schemat inte röras.

---

## Bygga

Öppna `FiatMos.pro` i Qt Creator, välj kit `SailfishOS-…-i486` för
emulatorn eller `aarch64` för telefonen, tryck play.

Efter ändringar i `.pro`: **Build → Clean All → Run qmake → Build.**

Build-engine: **VirtualBox, inte Docker.** Om host-only-nätet saknas:

```bash
sudo mkdir -p /etc/vbox
echo "* 10.220.220.0/24" | sudo tee /etc/vbox/networks.conf
sudo VBoxManage hostonlyif create
sudo VBoxManage hostonlyif ipconfig vboxnet0 --ip 10.220.220.1 --netmask 255.255.255.0
```

Ikonen genereras om med `python3 icons/make_icon.py` (kräver `pip install
cairosvg`). PNG:erna är redan incheckade, så det behövs bara om formen ändras.

---

## Arkitektur

```
qml/
├── FiatMos.qml          app entry, kör Storage.init() vid start
├── Storage.js           all SQL + all analys
├── FiatMosTheme.qml     singleton-tema (fast palett ↔ ambience)
├── qmldir               registrerar FiatMosTheme som singleton
├── components/
│   ├── Pill.qml         rundad toggle, ersätter TextSwitch
│   └── SectionLabel.qml liten grå etikett
├── cover/CoverPage.qml  badge: antal ologgade vanor idag
└── pages/
    ├── HabitListPage.qml
    ├── AddHabitPage.qml
    ├── LogPage.qml
    └── HistoryPage.qml
```

### Migrationer

`Storage.js` har en `MIGRATIONS`-array. Varje post har ett `version`-nummer
och en lista SQL-satser. `init()` läser `MAX(version)` ur `schema_version`
och kör bara det som saknas — idempotent, säker att anropa varje start.

**Lägg alltid till nya versioner sist. Redigera aldrig en version som redan
har shippats** — enheter som kört den kör den inte igen.

Bara additiva migrationer. `ALTER TABLE … ADD COLUMN`, alltid nullable eller
med DEFAULT. Aldrig `DROP COLUMN`, aldrig typbyte.

### Append-only

`log_entry` skrivs bara till. Det finns ingen UPDATE- eller DELETE-väg mot
tabellen i koden. Ångra är en ny rad.

### Analys

Streaks, completion rate, serier och avvikelse mot mål räknas ut on-the-fly
från rådata varje gång. Inget aggregat sparas. Analyslogiken kan därför bytas
ut helt utan datamigrering.

### Tema

`FiatMosTheme` är en resolver, inte en färglista — samma mönster som
`FiatLuxTheme`. Varje token har två grenar, växlade av `ambient` som ligger
i `Nemo.Configuration` på `/apps/fiatmos/ambient` och togglas från
pull-down-menyn.

Den fasta paletten är Fiat Lux varma mörka bas med egen accent:

| Roll | Hex | |
|---|---|---|
| Deep bg | `#1E1A12` | delad med Fiat Lux |
| Surface | `#2A2318` | delad |
| Primärtext | `#F4EED8` | delad |
| Sekundärtext | `#9A8F78` | delad |
| Rim | `#D8CEAE` | delad |
| **Accent** | **`#8FA055`** | **mossgrön — Fiat Mos egen** |
| Varning | `#A0403A` | delad, aldrig ambient |

**Ingen hårdkodad hex i sid-QML.** Allt går via `FiatMosTheme`, annars går
ambient-läget sönder i ett hörn av appen utan att någon märker det.

### Ikon

Ett nött stentrappsteg: en platta som sitter lågt i Sailfish-formen med
överkanten urgröpt av att gås på, och en benvit kant längs slitageskålen.
*Mos* är det som formar en genom upprepning. Systerform till Fiat Lux
incidentkupol — samma mörka varma botten, samma ensamma objekt lågt i bild,
annan accent.

---

## Testning

Det finns en Node-baserad testrigg som kör `qml/Storage.js` mot en riktig
SQLite via `node:sqlite`, med en shim som härmar QML:s `LocalStorage`-API.
Den behöver ingen Qt-installation.

```bash
cd test
node test.js          # beteende: streaks, ångra, arkivering, serier
node test_migrate.js  # v1-enhet uppgraderas till v3 utan att tappa rader
python3 qmlcheck.py   # balanserade parenteser, dubbletter av id, DISTFILES
```

`qmlcheck.py` kontrollerar också att varje fil under `qml/` faktiskt står i
`DISTFILES`. Saknas `Storage.js` eller `qmldir` där deployas de inte, och
appen startar med ett tomt fel.

---

## Att verifiera först i emulatorn

Tre saker som inte går att kontrollera utan Qt, i den ordning de smäller:

1. **Singleton-importen.** `qml/qmldir` registrerar `FiatMosTheme` som
   singleton och sidorna når den via `import ".."`. Det är standard i Qt 5,
   men om det bråkar syns det direkt som "FiatMosTheme is not a type".
   Reservplan: ta bort `pragma Singleton` och instansiera `FiatMosTheme { }`
   i varje sida i stället — `ConfigurationValue` håller dem ändå i synk.
2. **`Nemo.Configuration`.** Modulen ligger i OS:et, ingen `Requires:`-rad
   behövs. Kontrollera med `ls /usr/lib64/qt5/qml/Nemo/Configuration/`.
3. **Application Output.** QML-bindningsfel skrivs där med radnummer. Kolla
   den först när något ser fel ut, före visuell felsökning.

---

## Öppna frågor

**`superseded_by`-riktningen.** Instruktionen är tvetydig: kolumnen sitter på
`log_entry` och heter "superseded_by", vilket läst bokstavligt betyder "den
här raden ersattes av rad N" — men att sätta det värdet kräver en UPDATE på
en gammal rad, vilket samma instruktion förbjuder. Implementationen läser den
därför som **"den här raden ersätter rad N"**, så en korrigering eller en
ångring är ett rent INSERT. En full ångring är en rad med `value_type`
`'void'` som pekar på den ersatta raden. Aktiva poster är de som varken är
`'void'` eller pekas ut av någon senare rad. Säg till om du vill ha det tvärtom
— då behövs en `superseded_at`-kolumn i stället, additivt.

**Notifikationer** är utanför v1 enligt beslut. Om de ska in senare räcker en
additiv `reminder_time TEXT` på `habit` plus `nemo-qml-plugin-notifications`.

**Wizard för Reference och Structured.** AddHabitPage är en sida med
villkorliga fält nu. När mall 4 och 5 kommer in får de ett eget steg i stället
för fler fält på samma sida.

**Cover-action.** Cover-sidan har ingen `CoverActionList` ännu. "Logga nästa
vana" vore den självklara, men ikonnamnen (`icon-cover-*`) behöver verifieras
på enheten innan de committas — Fiat Lux lärde oss att gissade ikonnamn
faller tyst.

---

## Git

```bash
cd ~/Projects/FiatMos
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/munksh/FiatMos.git
git push -u origin main    # PAT som lösenord
```
