# Silo-Abgabemenge (FS25_SiloAbgabemenge)

Script-Mod für den Landwirtschafts-Simulator 25. Legt fest, wie viel ein Silo beim Befüllen eines
Fahrzeugs abgibt – in Schritten von 5.000 Litern. Sind keine vollen 5.000 l mehr möglich, wird die
Restmenge geladen.

Eigene Mod, unabhängig von „Lebendige Straßen“ im Hauptordner des Repos.

## Bedienung

1. Wie gewohnt mit dem Anhänger unter den Trichter fahren, **R** (Befüllen starten) drücken,
   Fruchtart wählen und **Start**.
2. Danach erscheint das Fenster **„Abgabemenge“**: 5.000 l, 10.000 l, … und als letzter Eintrag
   **„Alles (x l)“** mit der vollen möglichen Menge (Siloinhalt oder freier Platz im Fahrzeug, je nachdem,
   was kleiner ist).
3. Menge wählen und **Start**. Das Silo stoppt, sobald die Menge geladen ist. **Abbrechen** lädt nichts.

- Sind 5.000 l oder weniger möglich, gibt es nur die Restmenge – dann wird ohne zweites Fenster geladen.
- Die zuletzt gewählte Menge ist beim nächsten Mal vorausgewählt (nicht über das Speichern hinaus).
- Für die nächste Portion einfach wieder R drücken.

Gilt für alle Ladestationen des Basisspiels mit `LoadTrigger` (Silos, Ausgabe von Produktionen und Lagern).
KI-Helfer (Laden & Liefern) werden nicht begrenzt.

## Technik

`SiloAbgabemenge.lua` hängt sich an die Klasse `LoadTrigger` (Original-Code FS25):

- `onFillTypeSelection` (Client, Rückruf des Silo-Dialogs): merkt den Mengen-Dialog für den nächsten Frame vor.
  Nach „Start“ geht die Menge per `SiloAbgabemengeEvent` an den Server, danach läuft das Original weiter
  (Start-Event des Spiels, gleiche Verbindung, also kommt die Menge vorher an).
- `startLoading` / `stopLoading` (Server): übernehmen die Menge beim Start bzw. setzen sie beim Stopp zurück.
- `update` (Server): drosselt die Füllrate im jeweiligen Frame auf die Restmenge, zählt die geladenen Liter am
  Füllstand des Fahrzeugs und stoppt bei Erreichen der Menge.

Der Dialog (`gui/SiloAbgabemengeDialog.xml`) ist ein `MessageDialog` mit Basisspiel-Profilen und einer
`MultiTextOption`, aufgebaut nach dem Muster von FS25_UsedPlus.

Multiplayer und Dedicated Server werden unterstützt; die Begrenzung läuft auf dem Server.

## Bauen

```bash
py build.py
```

Erzeugt `FS25_SiloAbgabemenge.zip` in diesem Ordner (`modDesc.xml` liegt im ZIP ganz oben).

## Test

1. Singleplayer: Silo mit Getreide, Anhänger mit > 10.000 l. R → Fruchtart → Start → „10.000 l“ → Start →
   stoppt bei 10.000 l.
2. Letzter Eintrag „Alles (x l)“ → lädt wie im Basisspiel.
3. Silo mit weniger als 5.000 l → lädt die Restmenge ohne zweites Fenster.
4. Multiplayer/Dedi: dasselbe als Client.

Bei Fehlern bitte die komplette `log.txt` aus `Dokumente/My Games/FarmingSimulator2025/` schicken
(Log-Zeilen der Mod beginnen mit `[SiloAbgabemenge]`).
