# Silo-Abgabemenge (FS25_SiloAbgabemenge)

Script-Mod für den Landwirtschafts-Simulator 25. Legt fest, wie viel ein Silo beim Befüllen eines
Fahrzeugs abgibt – in Schritten von 5.000 Litern. Hat das Silo weniger oder passt weniger ins Fahrzeug,
wird die Restmenge geladen. Bei „Alles“ verhält sich das Silo wie im Basisspiel.

Eigene Mod, unabhängig von „Lebendige Straßen“ im Hauptordner des Repos.

## Bedienung

| Standard | Wirkung |
|---|---|
| `Strg+Alt+M` | Abgabemenge +5.000 l (bis 200.000 l) |
| `Strg+Alt+N` | Abgabemenge −5.000 l (unterste Stufe „Alles“) |

- Die Tasten sind änderbar unter Einstellungen → Steuerung („Silo-Abgabemenge: …“).
- An der Ladestation steht die gewählte Menge im Text: „Befüllen starten (10.000 l)“. Solange man dort steht,
  erscheinen auch die beiden Tasten im F1-Hilfefenster.
- Nach Erreichen der Menge stoppt das Silo. Mit erneutem „Befüllen starten“ kommt die nächste Portion.
- Die Menge gilt pro Spieler und wird nicht gespeichert (nach dem Laden steht sie auf „Alles“).

Gilt für alle Ladestationen des Basisspiels mit `LoadTrigger` (Silos, Ausgabe von Produktionen und Lagern).
KI-Helfer (Laden & Liefern) werden nicht begrenzt.

## Technik

`SiloAbgabemenge.lua` hängt sich an die Klasse `LoadTrigger` (Original-Code FS25):

- `onFillTypeSelection` (Client): schickt vor dem Start die gewählte Menge per `SiloAbgabemengeEvent` an den
  Server. Gleiche Verbindung wie das Start-Event des Spiels, damit kommt die Menge vorher an.
- `startLoading` / `stopLoading` (Server): übernimmt die Menge beim Start und setzt sie beim Stopp zurück.
- `update` (Server): drosselt die Füllrate im jeweiligen Frame auf die Restmenge, zählt die geladenen Liter am
  Füllstand des Fahrzeugs und stoppt bei Erreichen der Menge.
- `LoadTriggerActivatable.getIsActivatable`: ergänzt den Aktionstext um die Menge.

Multiplayer und Dedicated Server werden unterstützt; die Begrenzung läuft auf dem Server.

## Bauen

```bash
py build.py
```

Erzeugt `FS25_SiloAbgabemenge.zip` in diesem Ordner (`modDesc.xml` liegt im ZIP ganz oben).

## Test

1. Singleplayer: Silo mit Getreide, Anhänger mit > 10.000 l. `Strg+Alt+M` zweimal → „10.000 l“, befüllen →
   stoppt bei 10.000 l.
2. Silo mit weniger als der gewählten Menge → lädt die Restmenge.
3. `Strg+Alt+N` bis „Alles“ → normales Verhalten.
4. Multiplayer/Dedi: dasselbe als Client.

Bei Fehlern bitte die komplette `log.txt` aus `Dokumente/My Games/FarmingSimulator2025/` schicken
(Log-Zeilen der Mod beginnen mit `[SiloAbgabemenge]`).
