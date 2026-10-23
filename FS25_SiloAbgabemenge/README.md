# Silo-Abgabemenge (FS25_SiloAbgabemenge)

Script-Mod für den Landwirtschafts-Simulator 25. Legt fest, wie viel ein Silo beim Befüllen eines
Fahrzeugs abgibt – auf den Liter genau. Mehr als im Silo liegt oder ins Fahrzeug passt, geht nicht;
dann wird die Restmenge geladen.

Eigene Mod, unabhängig von „Lebendige Straßen“ im Hauptordner des Repos.

## Bedienung

1. Wie gewohnt mit dem Anhänger unter den Trichter fahren, **R** (Befüllen starten) drücken,
   Fruchtart wählen und **Start**.
2. Danach öffnet sich das Eingabefeld des Spiels: Menge in Litern eingeben (z. B. `750`) und bestätigen.
   Punkte und „l“ werden ignoriert, „1.500 l“ ist also 1.500 l.
   - **Feld leer** oder eine Zahl über der möglichen Menge → alles bzw. die Restmenge laden.
   - **Abbrechen** → nichts laden.
   - Ungültige Eingabe (nur Buchstaben) → Hinweis, nichts laden.
3. Das Silo stoppt, sobald die Menge geladen ist.

- Die zuletzt eingegebene Menge steht beim nächsten Mal schon im Feld (nicht über das Speichern hinaus).
- Für die nächste Portion einfach wieder R drücken.

Gilt für alle Ladestationen des Basisspiels mit `LoadTrigger` (Silos, Ausgabe von Produktionen und Lagern).
KI-Helfer (Laden & Liefern) werden nicht begrenzt.

## Technik

`SiloAbgabemenge.lua` hängt sich an die Klasse `LoadTrigger` (Original-Code FS25):

- `onFillTypeSelection` (Client, Rückruf des Silo-Dialogs): merkt das Eingabefeld für den nächsten Frame vor
  (damit sich der Silo-Dialog vorher schließt) und öffnet dann den `TextInputDialog` des Spiels (Muster aus
  FS25_UsedPlus). Nach der Eingabe geht die Menge per `SiloAbgabemengeEvent` an den Server, danach läuft das
  Original weiter (Start-Event des Spiels, gleiche Verbindung, also kommt die Menge vorher an).
- `startLoading` / `stopLoading` (Server): übernehmen die Menge beim Start bzw. setzen sie beim Stopp zurück.
- `update` (Server): drosselt die Füllrate im jeweiligen Frame auf die Restmenge, zählt die geladenen Liter am
  Füllstand des Fahrzeugs und stoppt bei Erreichen der Menge.

Multiplayer und Dedicated Server werden unterstützt; die Begrenzung läuft auf dem Server.

## Bauen

```bash
py build.py
```

Erzeugt `FS25_SiloAbgabemenge.zip` in diesem Ordner (`modDesc.xml` liegt im ZIP ganz oben).

## Test

1. Singleplayer: R → Fruchtart → Start → `750` eingeben → stoppt bei 750 l.
2. Feld leer lassen → lädt wie im Basisspiel.
3. Abbrechen → lädt nichts.
4. Multiplayer/Dedi: dasselbe als Client.

Bei Fehlern bitte die komplette `log.txt` aus `Dokumente/My Games/FarmingSimulator2025/` schicken
(Log-Zeilen der Mod beginnen mit `[SiloAbgabemenge]`).
