# ModHub-Zertifizierung FS25 — was GIANTS beanstandet hat

Stand 05.10.2026. Grundlage sind zwei Certification Reports zu **Farm Economy**
(21.09. und 05.10.2026) und die Erfahrungen aus den Einreichungen von
FarmOverview, CurveView und SaatgutHUD. Alles hier Genannte wurde entweder von
GIANTS ausdrücklich beanstandet oder im Spiel nachgemessen.

Autor aller Mods: **OGW**.

---

## 1. modDesc

| Punkt | Regel |
|---|---|
| `descVersion` | **113**. 111 fällt durch. **114 ebenfalls** — der TestRunner 0.9.22 lehnt es als „outside allowed range" ab, obwohl sein eigenes Changelog 114 ankündigt (am 30.09.2026 verifiziert). |
| Version | Erstveröffentlichung ist **1.0.0.0 ohne Changelog**. Das gilt auch nach einer zurückgezogenen Einreichung, solange die Mod nie öffentlich war. |
| Titel | **Jedes** durch Leerzeichen getrennte Wort muss groß beginnen, pro Sprache. „Aperçu de l'exploitation" fiel durch, „Point De Livraison" geht durch. |
| Sprachen | EN, DE und **FR** müssen in der modDesc stehen (`<title>` und `<description>`). Das Formular liest sie aus der Mod, nicht aus dem Eingabefeld. |
| Deutsche Texte | **Echte Umlaute**, keine Ersatzschreibung wie „fuer", „ueber", „Gebaeude". Vorsicht bei der Umstellung: „Steuer", „aktuell", „teuer", „Quereinsteiger" dürfen nicht angefasst werden — feste Wortliste statt Regel. |
| Changelog-Wörter | Bei Version x.0.0.0 keine Wörter wie „Änderung", „Changelog", „Neu:", „Fix:" in den Beschreibungen. Der TestRunner meldet sonst `excessChangelog` — und zwar mit falscher Sprachzuordnung (gemeldet wurde `description.fr`, schuld war der deutsche Text). |

## 2. Lua

**Verboten, vom Modul `PublicLuaCheck` geprüft:**

- `pcall`, `xpcall` — „swallows errors and hides them from the log". Jede
  einzelne Stelle wird im Bericht aufgeführt. Bei Farm Economy waren es 141,
  bei FarmOverview 184.
- `loadstring` — seit Spiel-Patch 1.24 ohnehin gesperrt.
- `collectgarbage` — auch `collectgarbage("count")`, das nur liest.

**Die Falle beim Entfernen von pcall:** Ein `return` INNERHALB einer
`pcall(function() … end)`-Hülle verlässt nur die anonyme Funktion. Nimmt man
die Hülle weg, verlässt dasselbe `return` plötzlich die umgebende Funktion —
aus „überspring diesen Fall" wird „brich alles ab", und Funktionen geben `nil`
statt ihres Ergebnisses zurück. Semantisch exakte Umwandlung:

```lua
local function schritt()
    -- Inhalt unverändert
end
schritt()
```

Blöcke ohne `return`: Hülle weg, Inhalt ausrücken. Ersatz für pcall sind
explizite nil- und Methodenprüfungen.

## 3. ModIcon

- **Hintergrund muss das FS25-Template sein:**
  https://modhub.giants-software.com/documents/FS25_ModHub_BG512.png
  512×512, **dunkelgrauer** Verlauf mit feinem Muster (RGB 47–59).
- Das **FS19-Template ist falsch** und wurde ausdrücklich beanstandet. Es ist
  ein heller Grauverlauf — ein dunkles Motiv darauf geht auf dem FS25-Grund
  unter.
- Folge: Auf dem dunklen Grund **helle** Farben verwenden. Bei Farm Economy
  musste das Grün von (46, 96, 44) auf (126, 206, 94) und der Schatten von
  Alpha 0,35 auf 0,55.
- Format: **512×512 DDS, BC1/DXT1, ohne Mipmaps** = 128 Byte Header +
  131072 Byte Daten = genau **131200 Byte**. Header: `dwFlags` 0xA1007,
  `dwMipMapCount` 1, `dwCaps` 0x1000.
- Dateiname: `icon_<ModName>.dds`, nicht `icon.dds`.
- Kein Text, keine Logos, keine Wasserzeichen im Icon.

## 4. Übersetzungen

- **Keine separaten `i18n/`- oder `l10n/`-Dateien.** Der ObsoleteFiles-Check
  flaggt sie als „unused", selbst wenn alle Schlüssel literal im Code stehen.
  Bei FarmOverview blieb der Check trotz 68 literaler `getText`-Aufrufe rot.
- **Lösung: alles inline in die modDesc**, ohne `filenamePrefix`:
  ```xml
  <l10n>
      <text name="KEY"><en>…</en><de>…</de><fr>…</fr></text>
  </l10n>
  ```
  Runtime-`g_i18n:getText("KEY")` und `$l10n_KEY` in GUI-Dateien funktionieren
  damit unverändert.
- **ObsoleteFiles ist ein Folgefehler:** Sobald die modDesc einen anderen
  Fehler hat, bricht die Referenzerkennung ab und flaggt alle i18n-Dateien.
  Erst alle übrigen Checks grün machen, dann ObsoleteFiles bewerten.

## 5. `$l10n`-Verweise in eigenen GUI-Dateien

Verifizierte Mechanik (`dataS/scripts/gui/elements/TextElement.lua`):

- Zeile 265 löst Verweise mit `g_i18n:getText(text:sub(7), self.customEnvironment)` auf.
- `customEnvironment` setzt `TextElement:loadFromXML` (Zeile 159-165) aus dem
  **Dateipfad der GUI-XML** über `Utils.getModNameAndBaseDirectory`.

**Das heißt: `$l10n_`-Verweise sind in Ordnung**, solange die GUI-Datei im
Mod-Ordner liegt. FarmOverview fährt 101 davon ohne eine einzige Warnung.

Die DevWarning `Missing '<key>' in l10n_de.xml` tritt nur im Einzelfall auf —
bei Farm Economy für genau einen Schlüssel, nämlich den, der zusätzlich in
`InGameMenuSettingsFrame.HEADER_TITLES` eingetragen wird; diese Liste liest das
Basismenü ohne Mod-Umgebung. Dort hilft, den Text zur Laufzeit per `setText`
zu setzen statt im XML.

**Was NICHT hilft:** Mod-Texte per `getfenv(0).g_i18n:setText` global
nachtragen. Im Spiel gemessen: `getfenv(0).g_i18n` **ist** das `g_i18n` der
Mod, der Umweg trägt nichts nach.

**Folgefehler beim Umstellen:** Ohne `text` im XML ist das Element beim Laden
leer und damit zu schmal. Nach dem Einhängen `updateSize()` auf dem Element,
die Größe der Hintergrundgrafik und `invalidateLayout()` auf dem Elternelement
nachziehen — sonst reicht etwa die grüne Markierung eines Reiters nur über die
ersten Zeichen.

## 6. Eigene Einstellungs-Tabs

- `HEADER_SLICES` darf **keinen leeren Eintrag** bekommen. Ein leerer String
  ergibt beim Öffnen „Identifier '' does not contain prefix or slice ID"
  (OverlayManager.lua:159). Stattdessen den Slice eines vorhandenen
  Basisspiel-Tabs übernehmen.

## 7. ZIP und Formular

- ZIP-Name **englisch**, ohne Versionsnummer, Form `FS25_Name.zip`. Deutsche
  Dateinamen sind ein Fail-Beispiel der Guidelines.
- **Kein `.png` in der ZIP**, nur `.xml`, `.lua`, `.dds` (und Sound-Dateien).
- **Manufacturer im Formular auf `None`** stellen. Das Feld ist nur für reale
  Hersteller; ein Modder-Tag wie „OGW" wird beanstandet.
- Screenshots: mindestens 3, je 1600×900, **erstes Bild ohne HUD und ohne
  Text**, Text in Screenshots **englisch**.
- Keine Logos, Wasserzeichen, Links oder Credits in Icon, Screenshots oder
  Beschreibung. Modder-Name nicht im Beschreibungstext.

## 8. Vor jeder Einreichung

1. `py _modhub_check.py <ModName>` (liegt in `Codex`) — prüft alle Punkte
   oben, soweit automatisch prüfbar.
2. TestRunner **0.9.22** laufen lassen, alle 15 Module müssen PASS zeigen.
3. Spieltest im Einzelspieler, danach Log auf DevWarnings durchsehen.

Nicht automatisch prüfbar bleiben: Manufacturer im Formular und die
Screenshots.

---

## Statusverlauf im ModHub-Panel

Die Kette ist Pending → Testing → **Testing Completed** → Freigabe oder
Bericht. „Testing Completed" ist **keine** Freigabe, sondern der zuletzt
abgeschlossene Durchlauf; der Satz dahinter („We are currently testing your mod
again") beschreibt, was gerade läuft. Der Certification Report bleibt so lange
stehen, bis ein neuer ihn ersetzt — alte Punkte dort bedeuten nicht, dass sie
noch offen sind. Verlässlich ist nur das Datum bei „Last Update".
