# FS25_NachbarFelder

Script-Mod für den Landwirtschafts-Simulator 25. KI-Nachbarn spawnen am Shop, fahren eigenständig
über die Karte und bearbeiten fremde Felder. Dazu kommt Patrouille-Verkehr zwischen Wegpunkten,
damit die Straßen nicht leer wirken.

Die Mod ist **kartenunabhängig** und läuft auf einem Dedicated Server im Multiplayer.

- Autor: OGW
- modDesc-Version: `1.1.42.0`
- Interner Stand: `NachbarFelderManager.BUILD = 139` (erscheint beim Start im Log als
  `NachbarFelder: loadMap auf SERVER (Build 139)`)

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

## Aufbau

| Datei | Inhalt |
|---|---|
| `NachbarFelder.lua` | Einstiegspunkt aus `extraSourceFiles`, lädt die übrigen Lua-Dateien per `source()`, registriert die Tasten |
| `NachbarFelderManager.lua` | Kern: Spawn-Logik, Feldauswahl, Verkehr, Wegpunkte, Server-Konfiguration, Konsolenbefehle |
| `NachbarFelderAuftrag.lua` | Auftrag an den Lohnunternehmer: Feld an der Spielerposition, Prüfung, Start, Netzwerk-Event |
| `NachbarFelderWorker.lua` | Status-Maschine eines einzelnen Helfers (Fahrt, Feldarbeit, Rettung) |
| `NachbarFelderSettingsPage.lua` | Einstellungen im ESC-Menü |
| `NachbarFelderWaypointPage.lua` | Reiter „Wegpunkte" im ESC-Menü |
| `NachbarFelderWaypointDialog.lua`, `NachbarFelderUIHelper.lua` | Dialog und GUI-Hilfsfunktionen |
| `gui/` | GUI-Layouts und eigene GUI-Profile |
| `l10n/` | Übersetzungen Deutsch und Englisch |
| `tools/` | Prüfskripte für neue Karten (siehe unten), nicht Teil der ZIP |
| `docs/PROJEKTSTAND.md` | Ausführlicher Projektstand und Historie. Oben steht der Block „ARBEITSGRUNDLAGE", alles darunter ist Historie je Build |

## Bedienung

Tasten laut `modDesc.xml` (im Spiel unter Einstellungen → Steuerung änderbar):

| Standard | Wirkung |
|---|---|
| `Strg+Alt+E` | Helfer sofort starten, ohne auf den Timer zu warten (nur Admin) |
| `Strg+Alt+L` | Alle Helfer und den Fahrzeug-Pool entfernen (nur Admin) |
| `Strg+Alt+O` | Wegpunkt an der eigenen Position setzen |
| `Strg+Alt+U` | Zuletzt gesetzten Wegpunkt entfernen |
| `Strg+Alt+C` | Wegpunkte verwalten |
| `Strg+Alt+J` | Lohnunternehmer: das Feld an der eigenen Position bearbeiten lassen |

Wegpunkte lassen sich auch ohne Tasten pflegen: ESC → Einstellungen → Reiter **Wegpunkte**.
Dort gibt es Schaltflächen zum Setzen, Ändern des Typs, Löschen und Teleportieren.

### Auftrag an den Lohnunternehmer

An ein Feld stellen (im Feld oder höchstens 25 m vom Rand) und `Strg+Alt+J` drücken oder im Reiter
**Wegpunkte** unter **Lohnunternehmer** auf „Beauftragen“ klicken. Die Nachbar-Helfer pflügen oder grubbern
dann genau dieses Feld – auch ein eigenes.

- Eigenes Feld: Recht „Helfer einstellen“ der eigenen Farm nötig.
- Freies Feld: nur Admin.
- Feld einer anderen Farm, Feld mit stehender Frucht, Grünland, bebaute Felder und Weiden: abgelehnt.

Die Antwort des Servers erscheint als Meldung und in der Infozeile des Reiters.

### Feldnummern

Es gibt nur eine Feldnummer: die, die das Spiel auf der Karte und in den Vertragsmeldungen zeigt
(`field:getId()`). Sie gilt überall – in Meldungen, im Log, beim Konsolenbefehl `nachbarFelderSperre`
und im Spielstand. Der Platz eines Felds in der internen Feldliste ist keine Feldnummer.

Wegpunkt-Typen: 0 Normal, 1 Kurz, 2 Lang, 3 Durchfahrt, 4 Spawnpunkt. Ein Spawnpunkt wird am besten
im Fahrzeug auf der rechten Spur gesetzt, Front in Fahrtrichtung.

### Konsolenbefehle

| Befehl | Wirkung |
|---|---|
| `nachbarFelderStart` | Helfer sofort starten |
| `nachbarFelderTimer` | Timer bis zum nächsten Start anzeigen/setzen |
| `nachbarFelderEntfernen` | Alle Helfer entfernen |
| `nachbarFelderTrafficStop` / `…Start` | Patrouille-Verkehr anhalten und fortsetzen |
| `nachbarFelderSperre <Nr> [aus]` | Ein Feld dauerhaft aussperren oder wieder freigeben (Nummer wie auf der Karte) |

## Einstellungen und Daten

Beides liegt im Profil unter `modSettings/FS25_NachbarFelder/`:

- `NachbarFelderServerConfig.xml` — Server-Einstellungen (Anzahl Helfer, Verkehrsdichte, Fahrzeug-
  kategorien, `logLevel` 1 oder 2 für ausführliche Diagnose).
- `NachbarFelderWaypoints_<KartenId>.xml` — Wegpunkte je Karte. Seit Build 132 pro Karte getrennt,
  damit nach einem Kartenwechsel keine alten Punkte übrig bleiben.

## Prüfskripte für neue Karten

`tools/feld_footprint.py` und `tools/feld_bebaut_tiefe.py` rechnen offline aus einer Karten-ZIP nach,
ob Gebäude, Weidezäune oder Deko in die Feldumrisse ragen — also das, was die Mod zur Laufzeit in
`getBebauteFelder()` prüft.

```bash
py tools/feld_bebaut_tiefe.py "Pfad/zur/FS25_Karte.zip"
```

Die Pfade zum Spiel- und zum Mods-Ordner stehen oben in `feld_footprint.py` und müssen auf dem
jeweiligen Rechner passen. Die referenzierten Placeable-Mods müssen im Mods-Ordner liegen, sonst
fehlen deren Grundflächen in der Rechnung.

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
