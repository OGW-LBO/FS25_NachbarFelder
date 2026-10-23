# Silo-Abgabemenge (FS25_SiloUnloadAmount)

Script-Mod für den Landwirtschafts-Simulator 25. Legt fest, wie viel ein Silo beim Befüllen eines
Fahrzeugs abgibt – auf den Liter genau. Mehr als im Silo liegt oder ins Fahrzeug passt, geht nicht;
dann wird die Restmenge geladen.

Eigene Mod, unabhängig von „Lebendige Straßen“ im Hauptordner des Repos. Angezeigter Name:
de „Silo-Abgabemenge“, en „Silo Unload Amount“, fr „Quantité De Sortie Du Silo“.

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

`SiloUnloadAmount.lua` hängt sich an die Klasse `LoadTrigger` (Original-Code FS25):

- `onFillTypeSelection` (Client, Rückruf des Silo-Dialogs): merkt das Eingabefeld für den nächsten Frame vor
  (damit sich der Silo-Dialog vorher schließt) und öffnet dann den `TextInputDialog` des Spiels (Muster aus
  FS25_UsedPlus). Nach der Eingabe geht die Menge per `SiloUnloadAmountEvent` an den Server, danach läuft das
  Original weiter (Start-Event des Spiels, gleiche Verbindung, also kommt die Menge vorher an).
- `startLoading` / `stopLoading` (Server): übernehmen die Menge beim Start bzw. setzen sie beim Stopp zurück.
- `update` (Server): drosselt die Füllrate im jeweiligen Frame auf die Restmenge, zählt die geladenen Liter am
  Füllstand des Fahrzeugs und stoppt bei Erreichen der Menge.

Multiplayer und Dedicated Server werden unterstützt; die Begrenzung läuft auf dem Server.

## ModHub

Stand nach `docs/MODHUB_REGELN.md` (im Hauptordner):

- `descVersion` 113, Version 1.0.0.0, Titel und Beschreibung in EN/DE/FR, Titelwörter groß.
- Texte inline in der `modDesc.xml` (kein `l10n/`-Ordner), echte Umlaute, keine Changelog-Wörter.
- Kein `pcall`/`xpcall`/`loadstring`/`collectgarbage`.
- Icon `icon_SiloUnloadAmount.dds`: 512×512 DXT1 ohne Mipmaps (131200 Byte), Rand aus dem geprüften Icon von
  „Lebendige Straßen“ (FS25-Template), eigenes Motiv ohne Text.
- ZIP englisch: `FS25_SiloUnloadAmount.zip`, nur `.xml`, `.lua`, `.dds`.

`py modhub_check.py` prüft diese Punkte automatisch. Von Hand bleiben: TestRunner 0.9.22,
Manufacturer im Formular auf `None`, Screenshots (mind. 3 × 1600×900, erstes ohne HUD/Text, Text englisch).

## Bauen

```bash
py build.py
```

Erzeugt `FS25_SiloUnloadAmount.zip` in diesem Ordner (`modDesc.xml` liegt im ZIP ganz oben).

## Test

1. Singleplayer: R → Fruchtart → Start → `750` eingeben → stoppt bei 750 l.
2. Feld leer lassen → lädt wie im Basisspiel.
3. Abbrechen → lädt nichts.
4. Multiplayer/Dedi: dasselbe als Client.

Bei Fehlern bitte die komplette `log.txt` aus `Dokumente/My Games/FarmingSimulator2025/` schicken
(Log-Zeilen der Mod beginnen mit `[SiloUnloadAmount]`).
