# Lebendige Straßen (FS25_NachbarFelder)

Angezeigter Name seit Build 151: **Lebendige Straßen** (en „Living Roads“, fr „Routes Vivantes“). Technisch heißt die
Mod weiter `FS25_NachbarFelder` – ZIP-Name, Ordner `modSettings/FS25_NachbarFelder/`, Spielstände und Tastenbelegungen
bleiben dadurch gültig.

Script-Mod für den Landwirtschafts-Simulator 25. KI-Nachbarn fahren mit Traktoren und Gespannen
eigenständig über die KI-Straßen der Karte, halten an Wegpunkten, parken eine Weile und fahren weiter –
damit die Straßen nicht leer wirken.

Seit Build 150 gibt es nur noch diesen Verkehr. Die Feldhelfer (zufällige Feldarbeit der Nachbarn und
der Auftrag an den Lohnunternehmer) sind entfernt.

Die Mod ist **kartenunabhängig** und läuft auf einem Dedicated Server im Multiplayer.

- Autor: OGW
- modDesc-Version: `1.2.0.0` (Changelog in der Beschreibung der `modDesc.xml`)
- Interner Stand: `NachbarFelderManager.BUILD = 153` (erscheint beim Start im Log als
  `NachbarFelder: loadMap auf SERVER (Build 153)`)

Maßgeblich für den Stand ist immer die Build-Nummer, nicht die modDesc-Version.

## Bauen

```bash
py build.py
```

Das Skript packt die feste Dateiliste aus `build.py` zu `FS25_NachbarFelder.zip` **im Quellordner**.
Die ZIP wird bewusst nicht in den Mods-Ordner kopiert; das Einspielen auf den Server und in den
eigenen Mods-Ordner passiert von Hand. Neue Dateien müssen in `build.py` in die Liste `DATEIEN`
eingetragen werden, sonst fehlen sie in der ZIP.

Der Ordner selbst darf nicht gezippt werden: `modDesc.xml` muss in der ZIP ganz oben liegen.

### Release auf GitHub

Der Workflow `.github/workflows/release.yml` baut die ZIP mit `build.py` und legt ein GitHub-Release
mit Tag `build<N>` an (N = `NachbarFelderManager.BUILD`). Er läuft

- bei jedem Push auf `main`, also auch beim Merge eines Pull Requests,
- wenn ein Tag `build<N>` gepusht wird (muss zur Build-Nummer passen),
- von Hand unter **Actions → Release → Run workflow**.

Gibt es das Release zur Build-Nummer schon, passiert nichts. Ein neues Release gibt es also nur mit
hochgezählter Build-Nummer.

Die ZIP heißt immer `FS25_NachbarFelder.zip` – das Spiel verwendet den Dateinamen als Mod-Namen.

## Aufbau

| Datei | Inhalt |
|---|---|
| `NachbarFelder.lua` | Einstiegspunkt aus `extraSourceFiles`, lädt die übrigen Lua-Dateien per `source()`, registriert die Tasten |
| `NachbarFelderManager.lua` | Kern: Spawn-Logik, Verkehr, Wegpunkte, Server-Konfiguration, Konsolenbefehle |
| `NachbarFelderWorker.lua` | Ende einer Fahrt auswerten (angekommen, nicht erreichbar, Rettung) |
| `NachbarFelderSettingsPage.lua` | Einstellungen im ESC-Menü |
| `NachbarFelderWaypointPage.lua` | Reiter „Wegpunkte" im ESC-Menü |
| `NachbarFelderWaypointDialog.lua`, `NachbarFelderUIHelper.lua` | Dialog und GUI-Hilfsfunktionen |
| `gui/` | GUI-Layouts und eigene GUI-Profile |
| `help/helpLine.xml` | Ingame-Hilfe (ESC → Hilfe → „Lebendige Straßen“), Texte in `l10n/` |
| `l10n/` | Übersetzungen Deutsch und Englisch |
| `tools/` | Prüfskripte aus der Zeit der Feldhelfer (siehe unten), nicht Teil der ZIP |
| `docs/PROJEKTSTAND.md` | Ausführlicher Projektstand und Historie. Oben steht der Block „ARBEITSGRUNDLAGE", alles darunter ist Historie je Build |

## Bedienung

Tasten laut `modDesc.xml` (im Spiel unter Einstellungen → Steuerung änderbar):

| Standard | Wirkung |
|---|---|
| `Strg+Alt+L` | Alle Nachbar-Fahrzeuge und den Fahrzeug-Pool entfernen (nur Admin) |
| `Strg+Alt+O` | Wegpunkt an der eigenen Position setzen |
| `Strg+Alt+U` | Zuletzt gesetzten Wegpunkt entfernen |
| `Strg+Alt+C` | Wegpunkte verwalten |

Eine Kurzanleitung steht im Spiel unter **ESC → Hilfe → „Lebendige Straßen“** (Überblick, Wegpunkte, Einstellungen,
Tasten, Spielverkehr). Die Einstellungen stehen unter ESC → Einstellungen im Abschnitt „Lebendige Straßen“.

Wegpunkte lassen sich auch ohne Tasten pflegen: ESC → Einstellungen → Reiter **Wegpunkte**.
Dort gibt es Schaltflächen zum Setzen, Ändern des Typs, Löschen und Teleportieren.

Am zuverlässigsten starten die Fahrzeuge von einem eigenen **Spawnpunkt** (Reiter **Wegpunkte** →
„Spawnpunkt hier setzen“). Ohne Spawnpunkt sucht die Mod selbst einen Platz an einer KI-Straße; scheitert das,
kommt einmal ein Hinweis.

Wegpunkt-Typen: 0 Normal, 1 Kurz, 2 Lang, 3 Durchfahrt, 4 Spawnpunkt. Ein Spawnpunkt wird am besten
im Fahrzeug auf der rechten Spur gesetzt, Front in Fahrtrichtung.

### Konsolenbefehle

| Befehl | Wirkung |
|---|---|
| `nachbarFelderTimer` | Zeit bis zum nächsten Verkehrs-Spawn anzeigen |
| `nachbarFelderEntfernen` | Alle Nachbar-Fahrzeuge entfernen |
| `nachbarFelderTrafficStop` / `…Start` | Patrouille-Verkehr anhalten und fortsetzen |

### Spielverkehr

Die Autos des Spielverkehrs bremsen nur für Objekte, die bei ihnen angemeldet sind – im Spiel sind das Spieler zu Fuß
und Fahrzeuge mit Spieler am Steuer. Seit Build 152 meldet die Mod ihre Traktoren und Geräte beim Losfahren genauso an
und beim Einschlafen im Pool, beim Löschen und beim Spielende wieder ab. Abschalten lässt sich das in der
`NachbarFelderServerConfig.xml` mit `spielverkehrAnmelden` = `false`.

## Einstellungen und Daten

Alle Dateien liegen im Profil unter `modSettings/FS25_NachbarFelder/`:

- `NachbarFelderServerConfig.xml` — Server-Einstellungen (Verkehrsdichte, Fahrzeug-
  kategorien, `logLevel` 1 oder 2 für ausführliche Diagnose).
- `NachbarFelderWaypoints_<KartenId>.xml` — Wegpunkte je Karte. Seit Build 132 pro Karte getrennt,
  damit nach einem Kartenwechsel keine alten Punkte übrig bleiben.
- `NachbarFelderLadeplaetze_<KartenId>.xml` — Ladeplätze an der KI-Straße, an denen Fahrzeuge nicht wegkamen oder
  umgekippt sind. Sie werden auf dieser Karte nicht mehr benutzt. Zum Freigeben die Datei löschen.
- `NachbarFelderGespannSperren.xml` — stammt von den Feldhelfern (bis Build 149) und wird nicht mehr gelesen;
  die Datei kann gelöscht werden.

## Prüfskripte in `tools/`

`tools/feld_footprint.py` und `tools/feld_bebaut_tiefe.py` stammen aus der Zeit der Feldhelfer: Sie rechnen
offline nach, ob Gebäude oder Zäune in Feldumrisse ragen. Seit Build 150 braucht die Mod das nicht mehr; die
Skripte bleiben nur zum Nachschlagen im Repository.

## Fehler melden

Fehler und Vorschläge bitte über den Reiter **Issues** melden. Dort gibt es zwei Vorlagen, die
gleich die richtigen Angaben abfragen: Fehlerbericht und Vorschlag.

Hilfreich sind immer:

- die **Build-Nummer** aus dem Log (`NachbarFelder: loadMap auf SERVER (Build …)`),
- die **Karte** und ob Einzelspieler, eigener Host oder Dedicated Server,
- die Log-Zeilen rund um das Problem, also alles, was mit `NachbarFelder:` beginnt.

Das Log liegt unter `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt`, beim Dedicated
Server im Profil des Servers. **Bitte vor dem Einfügen persönliche Daten entfernen** — Logs enthalten
Benutzernamen, Pfade und im Multiplayer auch Spielernamen.

Für längere Diagnosen lässt sich die Mod gesprächiger stellen: in der
`NachbarFelderServerConfig.xml` den Wert `logLevel` auf `2` setzen.

## Lizenz und Nutzung

Alle Rechte liegen beim Autor. Die Mod darf gespielt und der Code gelesen werden; eine
Weiterverbreitung, auch in veränderter Form oder als Teil einer Sammlung, bitte vorher absprechen.

## Hinweise für die Weiterarbeit

- Lua-Syntax vor jeder Auslieferung prüfen (Strukturcheck plus vollständiger Parse).
- Textdateien sind UTF-8. Nicht mit PowerShell `Get-Content`/`Set-Content` bearbeiten, das erzeugt
  doppelt kodierte Umlaute.
- Die KI fährt nicht nach den Straßen-Splines, sondern über den Navigations-Agenten der Engine
  (`AIDrivable`). `AIMessageErrorNotReachable` kommt von dort.
- KI-Straßen sind Einbahnen: Gegenverkehr läuft über die Zwillings-Spline mit „R" im Namen. Fahrzeug
  oder Ziel nie um 180 Grad gegen die Spline drehen.
