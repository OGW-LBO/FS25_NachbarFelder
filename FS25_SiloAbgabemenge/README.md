# Silo-Abgabemenge (FS25_SiloAbgabemenge)

Script-Mod für den Landwirtschafts-Simulator 25. Legt fest, wie viel ein Silo beim Befüllen eines
Fahrzeugs abgibt – aus einer Liste oder als eigene Menge in Litern. Mehr als im Silo liegt oder ins
Fahrzeug passt, geht nicht; dann wird die Restmenge geladen.

Eigene Mod, unabhängig von „Lebendige Straßen“ im Hauptordner des Repos.

## Bedienung

1. Wie gewohnt mit dem Anhänger unter den Trichter fahren, **R** (Befüllen starten) drücken,
   Fruchtart wählen und **Start**.
2. Danach erscheint das Fenster **„Abgabemenge“** mit den Einträgen:
   - **„Eigene Menge …“** – nach Start öffnet sich ein Eingabefeld für eine beliebige Literzahl
     (z. B. 750). Punkte und „l“ werden ignoriert, „1.500 l“ ist also 1.500 l.
   - **2.000 / 4.000 / 6.000 / 8.000 / 10.000 l**, danach in 5.000-l-Schritten.
   - **„Alles (x l)“** – die volle mögliche Menge (Siloinhalt oder freier Platz im Fahrzeug, je nachdem,
     was kleiner ist).
3. Menge wählen und **Start**. Das Silo stoppt, sobald die Menge geladen ist. **Abbrechen** lädt nichts.

- Der zuletzt gewählte Eintrag ist beim nächsten Mal vorausgewählt, im Eingabefeld steht die zuletzt
  eingegebene Menge (nicht über das Speichern hinaus).
- Für die nächste Portion einfach wieder R drücken.

Gilt für alle Ladestationen des Basisspiels mit `LoadTrigger` (Silos, Ausgabe von Produktionen und Lagern).
KI-Helfer (Laden & Liefern) werden nicht begrenzt.

## Technik

`SiloAbgabemenge.lua` hängt sich an die Klasse `LoadTrigger` (Original-Code FS25):

- `onFillTypeSelection` (Client, Rückruf des Silo-Dialogs): merkt den Mengen-Dialog für den nächsten Frame vor.
  „Eigene Menge …“ öffnet danach (wieder im nächsten Frame) den `TextInputDialog` des Spiels.
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
2. „Eigene Menge …“ → Start → 750 eingeben → stoppt bei 750 l.
3. Letzter Eintrag „Alles (x l)“ → lädt wie im Basisspiel.
4. Multiplayer/Dedi: dasselbe als Client.

Bei Fehlern bitte die komplette `log.txt` aus `Dokumente/My Games/FarmingSimulator2025/` schicken
(Log-Zeilen der Mod beginnen mit `[SiloAbgabemenge]`).
