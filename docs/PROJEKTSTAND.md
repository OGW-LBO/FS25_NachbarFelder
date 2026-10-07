# FS25_NachbarFelder — Projektstand (Hand-off)

> Diese Datei fasst alles zusammen, damit in einem **neuen Chat** nahtlos weitergearbeitet werden
> kann. Bei neuem Chat sagen: *"Wir arbeiten an FS25_NachbarFelder weiter, lies den Projektstand
> in `Codex/NachbarFelder_PROJEKTSTAND.md`"*. Die Abschnitte darunter sind chronologisch gewachsen —
> **ältere Teile sind teils überholt; im Zweifel gilt der jüngste Abschnitt am Ende.**
>
> **ARBEITSGRUNDLAGE — Stand 2026-10-07, Build 174 (hier zuerst lesen, alles darunter ist Historie)**
>
> **Was die Mod heute ist**
> - Anzeigename **„Lebendige Straßen“** (en Living Roads, fr Routes Vivantes), technisch weiter `FS25_NachbarFelder`
>   (ZIP-Name = Mod-Name, `modSettings/FS25_NachbarFelder/`, Spielstand `NachbarFelder.xml`, Aktionen `NF_*`, Log-Präfix
>   `NachbarFelder:`). modDesc-Version **1.0.0.0** (vom User für den ModHub zurückgesetzt, `descVersion` 113), `NachbarFelderManager.BUILD = 174`.
> - **Übersetzungen inline** im `l10n`-Block der `modDesc.xml` (de + en + fr), kein Ordner `l10n/` mehr (Build 169).
>   ModHub-Beanstandungen aus anderen Mods des Users: `docs/MODHUB_REGELN.md`.
> - **Nur noch KI-Verkehr**: Traktoren/Gespanne fahren zwischen eigenen Wegpunkten und Straßenzielen, parken, Pool,
>   Tagesrhythmus, Stammfahrzeuge, Spawnpunkte. Feldhelfer und Lohnunternehmer sind seit Build 150 **entfernt**
>   (alle Abschnitte zu Feldarbeit, Builds ≤ 149, sind nur noch Historie).
> - Builds **158–162** im Spiel bestätigt, Release **build162** (PR #6). **Build 163**: neues Mod-Icon (Spielmotiv, vom
>   User) + README-Banner `docs/bilder/banner.png` – kein Code geändert. **Build 164** (Mindesttempo 30 km/h) im Spiel
>   bestätigt, Release **build164** (PR #8). **Build 165** (Debug-Log-Schalter) im Spiel
>   bestätigt (Log 04.10. 13:25), noch kein PR. **Build 166** (Begegnungen, früheres Versetzen) läuft fehlerfrei (Log 04.10. 14:01–14:12), eine Begegnung kam noch nicht vor. **Build 167** (Stillstand am Ladeplatz, Sperrradius 40 m) läuft laut User bisher. **Build 168** (Fahrerfigur bleibt sitzen) im Spiel bestätigt, Release über PR #10. **Build 169** (Übersetzungen inline in der modDesc) im Spiel geprüft: Reiter und Texte da, lokales Log ohne Fehler der Mod (07.10.). **Build 170** (Bilder in der Ingame-Hilfe) im Spiel: Seitenbilder da, linke Liste noch leer. **Build 171** (Symbole der Hilfe-Seitenliste) im Spiel bestätigt („Bilder links sind jetzt vorhanden“, 07.10.). **Build 172** (Engine-Hooks der Helfer-Zeit raus, aus PR #12) im Spiel bestätigt: KI-Traktoren fahren auf dem Dedicated Server (07.10.), Release über PR #14. Ein Test davor mit noch Build 171 auf dem Server zeigte kurz keinen Losfahrer (Debug-Log aus, keine Fehler) – nicht reproduziert. **Build 173** (Ladeplatz-Sperre bei Stillstand: 25 m, Diagnose) läuft: alle vier geladenen Fahrzeuge fuhren vom Ladeplatz los (Log 07.10. 10:30–10:40). **Build 174** (Stufe-1-Schleife → Stufe 3, Diagnose nur bis 100 m) im Spiel bestätigt (Log 07.10. 10:51–11:24).
>
> **Stand der letzten Builds (Details: Abschnitte am Ende)**
> - 150 Feldhelfer/Lohnunternehmer raus · 151 Anzeigename · 152 beim Spielverkehr anmelden (`addTrafficSystemPlayer`,
>   Autos bremsen; Schalter `spielverkehrAnmelden`) · 153 Ingame-Hilfe `help/helpLine.xml`, ModHub-Beschreibung mit
>   Changelog, Version 1.2.0.0 · 154/155 Spawn: Höhe mit `TERRAIN_DELTA`, waagerecht über höchstem von 5 Messpunkten
>   (Neigung per `setRotation` scheiterte an der Shop-Drehung), Geräte ohne Physik laden · 156 Gerät drehrichtig an die
>   Kupplung (`jointOrigRotOffsetComponent`) und **weich** kuppeln (`noSmoothAttach=false`) · 157 kein Helfer-Symbol auf
>   der Karte (`IngameMap.drawHotspot` überschrieben, Helfer-Farm per Settings-Sync an Clients) · 158 ModHub-Fassung (User): kein `pcall` mehr,
>   Spielertexte aus l10n (`nfText`/`nfMeldung`), `l10n_fr.xml`, Speicher-Telemetrie raus · 159 Gerätebreite passend zum
>   Traktor (`specs.workingWidth`, max 1,2 m je t Traktor, 3–6 m) · 160 Fehler ohne `pcall` reißen den ganzen
>   Spiel-Frame mit (Join: Spieler fiel durch die Map) – Stellen abgesichert.
>
> **Arbeitsweise (verbindlich)**
> - **Kein `pcall`** im Code (ModHub-Fassung seit Build 158) – Existenz-Prüfungen statt `pcall`.
> - **Log-Ausgaben** laufen über `NachbarFelderLog.print` (in jeder Lua-Datei `local print = NachbarFelderLog.print`);
>   ohne Debug-Log nur Zeilen mit WARNUNG/Fehler/fehlgeschlagen/„loadMap auf“. Neue Warnungen entsprechend benennen.
> - Commits nur als `OGW-LBO <76265133+OGW-LBO@users.noreply.github.com>` (`git config user.name`/`user.email`
>   vor dem ersten Commit setzen). Keine `Co-Authored-By:`- oder Sitzungs-Zeilen in Commits, keine Hinweise auf
>   Werkzeuge in PR-Beschreibungen; automatisch angehängte Fußzeilen per Update wieder entfernen. Der Autor steht unter
>   Contributors allein. Arbeitszweig: `entwicklung` (keine Zweignamen mit Werkzeug-Präfix).
> - Neue Builds erst als ZIP zum Testen; PR/Release erst, wenn der User „läuft“ meldet. `BUILD` je Änderung hochzählen,
>   README-Buildzeile und einen Abschnitt hier am Ende ergänzen, den Kopf aktuell halten.
> - Bauen: `python3 build.py` (feste Liste, **15 Dateien**; neue Dateien in `DATEIEN`). Release-Workflow
>   `.github/workflows/release.yml`: bei Push auf `main` Release `build<N>` mit `FS25_NachbarFelder.zip`, falls neu.
>   Sitzungen pushen nur ihren Branch; nach einem Merge den Branch neu von `main` anlegen.
> - Prüfen: `lua_syntax_check.py` (Skill ls25-modding; `for … do`-Zeilen > 60 Zeichen vor `do` → Fehlalarm, Zeile kürzen),
>   Vollparse mit `lupa` (`continue` → `break`, BOM weg), XML mit minidom, YAML mit `yaml.safe_load`; Mock-Tests mit
>   lupa (Lua 5.5: `unpack = table.unpack` setzen). Referenzscan: keine Aufrufe auf entfernte Funktionen.
> - API nur verifiziert verwenden: LUADOC-Repo `umbraprior/FS25-Community-LUADOC` (Sparse-Checkout `docs/script`),
>   defensiv mit `pcall`/Existenzprüfung. Alles kartenunabhängig. Keine persönlichen Daten, Pfade als Platzhalter.
> - Textdateien UTF-8 (modDesc mit BOM + CRLF); nur per Edit-Tool oder Python ändern.
> - Logs schickt der User; Client-Log `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt`.
>
> **Server & Karten**
> - Bergisch Land (aktuell, VMware-Server), Shop x=-418 z=-25, Helfer-Farm automatisch (zuletzt Farm 14).
>   User hat Spawnpunkt WP1 gesetzt (nahe Werkstatt x≈-437 z≈-40).
> - Beuren (bis 18.09., Proxmox): Spawnpunkte WP37/38 ungünstig (Engstelle Landhandel-Hof).
>
> **Bedienung (User)**
> - ESC → Einstellungen, Abschnitt „Lebendige Straßen“: Mod an/aus, Verkehrsfahrzeuge 1–8, Anbaugeräte 0–3, Enge Karte.
> - ESC → Einstellungen → Reiter **Wegpunkte**: Punkte/Spawnpunkte setzen, Typ, Löschen, Teleport, Fahrzeugtypen (Admin).
> - ESC → Hilfe → „Lebendige Straßen“ (5 Seiten). Tasten: Strg+Alt+O/U/C (Wegpunkte), Strg+Alt+L (alles entfernen).
> - Konsole: `nachbarFelderTimer`, `nachbarFelderEntfernen`, `nachbarFelderTrafficStop`/`…Start`.
> - Server-Konfig `modSettings/FS25_NachbarFelder/NachbarFelderServerConfig.xml` (u. a. `spielverkehrAnmelden`,
>   `zielQuelle`, `poolSize`, `trailerChance`, `logLevel`).
>
> **Offene Punkte / Ideen**
> - Engstellen: Gespanne an engen Ortsdurchfahrten beobachten (Stufe1–3-Rettung, Abweisungen im Log).
> - Prüfen, ob Autos hinter einem länger parkenden Nachbar-Fahrzeug dauerhaft warten (Build 152).
> - Ungenutzte Altlasten: `missionHelper`/`MAX_ASSISTANT_WORKERS` laufen noch durch Settings-Sync und Spielstand
>   (bewusst, Stream-Kompatibilität); `tools/feld_*.py` nur noch Historie.
> - TestRunner mit der aktuellen ZIP (Changelog in modDesc vorhanden).
>
> **Verifizierte Engine-Fakten**
> - Clients interpolieren jede Server-Positionsänderung → jeder Teleport ist ein sichtbarer Flug.
> - KI-Straßen sind Einbahn-Splines („R"-Zwilling = Gegenrichtung); nie gegen die Spline drehen (`getRoadPointInRichtung`).
> - Spielverkehr bremst nur für angemeldete Objekte (`addTrafficSystemPlayer`; Spieler zu Fuß, Fahrzeug mit Fahrer).
> - `VehicleLoadingData`: y absolut, Shop-Offsets (`shopTranslationOffset`, `shopRotationOffset`) kommen beim Laden dazu.
> - `attachImplement(obj, in, joint, noEvent, idx, startLowered, noSmoothAttach, loadFromSavegame)`; `noSmoothAttach=true`
>   = Gelenkgrenzen sofort 0 → harter Ruck.
> - Ingame-Hilfe: `g_helpLineManager:loadFromXML(datei)` (Format `<helpLines>/<category>/<page>/<paragraph>`).
> - Buttons in Einstellungszeilen: echtes `Button` + eigenes Profil per `g_gui:loadProfiles`.
>
> **Code-Kurzreferenz**
> - Manager: `generateTraffic`, `update` (Status 0/1/1.5/2/60/100/9999), `onMinuteChanged` (Spawn-Takt), `driveToField`
>   (GOTO, nur Verkehr), `setzeLadepositionStrasse`/`waehleSpawnpunkt`/`getFahrbahnHoehe`, `setAttachment`/`kuppleGeraet`/
>   `setzeGeraetAnKupplung`, `sleepPatrolEntry`/`wakePooledVehicle`, `meldeGespannBeimSpielverkehrAn`/`…Ab`,
>   `installKartenHook`/`getIstNachbarHotspot`, `ladeHilfe`, `getEffectiveFarmId`, `saveWaypoints`/`loadWaypoints`.
> - Worker: `onAIJobFinished` (Abweisungen, `pathFails`, `nfRoadSnap`), `onDelete` (Spielverkehr abmelden).
> - Events: `NachbarFelderWaypointEditEvent` (OP 1–6), `NachbarFelderWaypointSyncEvent`, `NachbarFelderSettingsEditEvent`,
>   `NachbarFelderSettingsSyncEvent` (am Ende `helferFarmId`), `NachbarFelderDeleteEvent`.
> - WP-Kategorien: 0 Normal, 1 Kurz, 2 Lang, 3 Durchfahrt, 4 Spawnpunkt.
>
> **Log-Lesehilfe**
> - `[TRAFFIC] <traktor>.xml + <geraet>.xml | Ziel …` = Spawn; `wird am Spawnpunkt WPn geladen` / `direkt an der KI-Strasse`.
> - `sofort abgewiesen` (< 1,5 s) = Start/Ziel unerreichbar; `nicht erreichbar` danach = kein Weg gefunden.
> - `30s ohne Bewegung` → Stufe1/2 neues Ziel, Stufe3 Rettung/Pool; `umgekippt` → Platz gesperrt.
> - `Fahrzeuge werden beim Spielverkehr angemeldet`, `Ingame-Hilfe geladen`, `Helfer-Symbole … ausgeblendet` = Startzeilen.
> - `[PERF]` nur mit Spielern; 200-ms-Frames im Leerlauf = Server-Drosselung, kein Fehler.

## Was die Mod macht
KI-„Nachbarn" spawnen am Shop, fahren autonom zu **fremden** Feldern, bearbeiten sie und fahren
zurück — für mehr Leben auf der Map. MP/Dedicated-Server-fähig. Version 0.1.0.0. Map: **Krebach**
(kleinteilig, 121 Farmlands, Felder ~0,14–1,2 ha), mit **Precision Farming** aktiv.

## Dateien & Build
- **Arbeitskopie:** `<Quellordner>\NachbarFelder\` (5 Lua + modDesc.xml + 2 .dds).
  - `NachbarFelder.lua` — Einstieg, Netzwerk-Events, Spec-Registrierung
  - `NachbarFelderManager.lua` — Kern: Hooks, Spawn, Status-Maschine, Feldauswahl, Save/Load (~2000 Z.)
  - `NachbarFelderWorker.lua` — Vehicle-Spec: `onAIJobFinished` / `onAIFieldWorkerEnd`
  - `NachbarFelderSettingsPage.lua` + `NachbarFelderUIHelper.lua` — Settings im Allgemein-Menü
- **Build/Deliver:** ZIP per Python bauen (modDesc.xml im ZIP-**Root**), kopieren nach
  `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\FS25_NachbarFelder.zip`.
  Vor jeder Auslieferung Syntax prüfen: `python _check_lua.py NachbarFelder/*.lua` (im Codex-Root).
- ⚠️ **OneDrive-Setup:** Server (Server-PC) und Spiel-PC teilen denselben OneDrive-
  FS25-Ordner. Die ZIP muss erst zum Server **synchronisieren** (grünes Häkchen), DANN Server
  neu starten — sonst läuft der alte Build. Logs mischen beide Maschinen (Pfad <Serverprofil>
  = Server, Render Driver: NULL = Dedi); bei Fehlern log.txt sofort wegkopieren.

## STATUS der Feldarbeiten (vom User live bestätigt)
| Arbeit | Status |
|---|---|
| Pflügen | ✅ arbeitet ganzes Feld |
| Säen | ✅ arbeitet ganzes Feld (z.B. 12,5 min auf 0,73 ha) |
| Düngen — **Gülle/Flüssig** | ✅ arbeitet ganzes Feld |
| Grubbern | aktiv (flächig, sollte wie Pflügen laufen) |
| Ernten | aktiv — nur bei **voll reifen** Feldern; Mähdrescher-Korntank wird laufend geleert |
| **Düngen — mineralischer Festdünger-Streuer** | ⛔ wird aussortiert (PF = variable Rate → nur ~15 s) |
| **Spritzen (Herbizid)** | ⏸️ **deaktiviert** (PF = Spot-Spray → nur ~30 s, auch auf großen Feldern) |
| Hacken, Unkraut-Striegeln | ⛔ deaktiviert |

**Kern-Erkenntnis (Precision Farming):** *Flächige* Ausbringung (Pflug/Säe/Grubber/Gülle) lässt die
KI das ganze Feld in Bahnen abfahren. *PF-„intelligente"* Geräte (Herbizid-Spritze, mineralischer
Festdünger) bringen bedarfsgesteuert/variabel aus → die KI hat „kaum was zu tun" → 15–33 s
Kurzeinsatz. Deshalb sind diese zwei aussortiert/deaktiviert. (Die `weedSpotSpray`/`extendedSprayer`-
Abschaltung in `setAIOnField` greift nicht zuverlässig — PF ist eine Black Box ohne Doku.)

## Kritische Fakten / Stolperfallen (NICHT kaputtmachen)
- **`farmId` fest = 2** (`getEffectiveFarmId`). Nie Spectator-Farm 0 → Engine weist AI-Jobs sofort ab.
- **Feldbesitz-Trick:** vor Feldarbeit `field.farmland.farmId=2, isOwned=true` setzen, in
  `onAIFieldWorkerEnd` zurücksetzen (`tempFarmland`/`origFarmlandId`/`origIsOwned`). Sonst findet die
  KI das Feld nicht. `FSBaseMission.saveSavegame`-Hook setzt das beim Speichern kurz zurück →
  farmId=2 landet NIE in farmland.xml.
- **FarmlandManager-Hooks müssen für farmId 2 BEDINGUNGSLOS `true` liefern** (Gate nur
  `hasActiveWorkers()`), KEINE Positions-Einschränkung! Sonst scheitert die (asynchrone)
  Course-Generierung des FIELDWORK-Jobs (Engine prüft internes farmlandMapping, nicht unser
  gepatchtes `farmland.farmId`) → Helfer steht ewig. Betroffen:
  `getIsOwnedByFarmAtWorldPosition`, `getCanAccessLandAtWorldPosition`, `getIsOwnedByFarmAlongLine`.
- **`FieldCourse.findClosestField(...)` ist Pflicht** in `setAIOnField` (Seiteneffekt: registriert
  das Feld). Ohne den Aufruf endet FIELDWORK nach ~17 ms (`Laufzeit 0s`). NICHT durch manuelles
  `job.positionAngleParameter:setPosition()` ersetzen.
- **`finishFieldState`** setzt via `getDensityMapPolygon()` das GANZE Feld auf den Zielzustand
  (beim Job-Ende). Der sichtbare Feld-Effekt kommt daher — nicht zwingend von der KI-Fahrt.
- **Hooks für farmId 2:** `MissionManager.getIsMissionWorkAllowed` (+ `vehicle.allowedDrive` /
  `nf_isHelper`), die 3 FarmlandManager-Hooks, `FSBaseMission.addMoney` (kein Geldabzug).
  `markVehiclesAsHelper(vehicle)` setzt `allowedDrive`+`nf_isHelper` auf Traktor UND alle Anbaugeräte
  (Engine fragt Arbeits-Erlaubnis pro Gerät, nicht nur Traktor).
- **`getIsVehicleAlive(veh)`** (`veh~=nil and veh.isDeleted~=true and veh.rootNode~=nil`) vor JEDEM
  rootNode-Zugriff/delete — sonst tote Referenzen → Lua-Fehler-Spam → Server-Join blockiert.
- **Shutdown:** `FSBaseMission.delete` → `prepareForShutdown()` stoppt nur AI-Jobs + stellt Besitz
  wieder her; `isShuttingDown`-Flag lässt eigene delete-Aufrufe durchfallen (Engine löscht selbst,
  sonst „delete twice"-Callstacks).

## Status-Maschine (`NachbarFelderWorker.status`)
`0/0.5` kuppeln → `1` GOTO zum Feld → `2` Feldarbeit → `60` Rückfahrt → `100` löschen.
`9999` = zum Löschen markiert (5-min-Timeout). Job-Tasks im Log: `driveToTask` (Anfahrt) vs
`fieldWorkTask` (Arbeit).

## Spawn-Logik (`onMinuteChanged`)
- Intervall zwischen Helfern: **1–4 Spielminuten** (random). `MAX_ASSISTANT_WORKERS = 7`.
- Gates: kein Spieler online → `stopAllHelpers`; nach Login 3 Min Ladepause (`playerJoinGrace`);
  `g_sleepManager:getIsSleeping()` (Server schläft → kein Spawn); Spawn-Blocker wenn ein aktives
  Helfer-Fahrzeug < 50 m vom Shop-Spawn steht (Status 100/9999 ausgenommen).
- **Mini-Feld-Filter:** Felder < **0,3 ha** (`field.areaHa`) werden übersprungen (zu klein → Course
  leer → fieldWorkTask scheitert nach ~446 ms).
- Pfad-Fehlerklassen in `onAIJobFinished` (Status 1): GOTO-Abbruch **< 1500 ms** = Gespann ungeeignet
  → Implement auf `vehicleImplBlacklist`; **1500–5000 ms** = kein Pfad zum Feld → `fieldPathFails`,
  ab 2× Session-Sperre. Krebach-Felder 8 & 29 sind für die KI unerreichbar.
- **Rückfahrt-Hangeln** (Status 60): scheitert die Rückfahrt von der Feld-Endposition (FS25 findet
  keinen Weg aufs Straßennetz), wird mehrfach neu angefahren solange Fortschritt (>5 m näher,
  max 8 Versuche); erst bei Stillstand Teleport zum Shop (Notnagel). Tritt nur bei manchen Feldern auf.
- **Watchdog:** Helfer der bei Status 2 > 100 s ohne Bewegung (>2 m) steht → Cleanup + Feld-Cooldown.

## Krebach-Spezifika
- Sehr kleinteilig: 121 Farmlands, `pricePerHa=30000`, Felder 0,14–1,2 ha. Exakte ha nur via
  `field.areaHa` (Laufzeit) — steht in keiner lesbaren XML (GRLE-Densitymap).
- Shop-Spawnplätze (148,114) & (149,107) haben **rotY=0** (Mapper hat keine Richtung gesetzt) →
  Spawn dreht in `onSpawnedVehicle` Richtung Workshop (`x=98.65 z=119.08`, aus placeables.xml).
- Krebach-Früchte (SPELT/WINTERWHEAT/RYE/TRITICALE) fehlen in `vehicleHarvestVariant` → Fallback
  „GRAIN" (normaler Mähdrescher, ok).
- Admin-Tasten: Shift+Alt+L = alle Helfer löschen, Shift+Alt+N = sofort starten.

## Referenzen
- **Eltern-Mod** (bewährte AI-/Feldarbeit-Logik, daraus abgeleitet):
  `…\Downloads\01_Anpassung\FS25_FarmerWorkingAssistant_orig\` (`MissionInfo.lua:638` = setAIOnField).
- `Codex\_old_pfdump\` = letzter nachweislich funktionierender Build (zum Vergleichen).
- FS25-Engine-Scripts sind hier NICHT als Klartext lesbar (verschlüsselt) → Referenz-Mods +
  Community-LUADOC (`umbraprior.github.io/FS25-Community-LUADOC`) sind die Verifikationsquellen.

## BEKANNTES PROBLEM (zu fixen): Spawn am Shop — verkehrt herum / Anbaugerät verharkt
Symptom (User 13.06.): Fahrzeuge stehen manchmal verkehrt herum am Shop; Anbaugerät verharkt sich
beim Spawnen in einem Hindernis am Shop-Eck (vom User „Boot" genannt — NICHT das Kanu-Placeable bei
(188,−170); das echte Hindernis steckt in der Map-i3d, nicht in placeables.xml auslesbar).
**Ursache:** `onSpawnedVehicle` dreht den Traktor Richtung Workshop (x=98.65 z=119.08); danach setzt
`setAttachment` (Z. ~1092) das Anbaugerät **4 m „hinter" den Traktor** (`ax - dX*4`) = Richtung
Shop-Eck → ins Hindernis → verharkt. Beim Ankuppeln großer Anhänger wird der Traktor zusätzlich
schief gezogen → „verkehrt herum". **Lösungsideen (im frischen Chat, idealerweise mit Screenshot
vom Shop-Spawn, um Boot/Ausfahrt-Lage zu sehen):** (a) Anbaugerät-Vorab-Teleport (`ax-dX*4`) prüfen
— evtl. weglassen und `attachImplement(...,moveToJoint=true)` allein ziehen lassen (vermeidet
Hindernis), Risiko Physik-Zuck; (b) Traktor-Drehung erst NACH dem Ankuppeln auf das ganze Gespann
anwenden; (c) Spawn-/Steh-Richtung an der echten Ausfahrt ausrichten (Koordinaten vom User/Screenshot).
Hängt eng mit dem geplanten Park-Feature zusammen (gleiche Spawn-/Ausricht-Logik) → zusammen angehen.

## Offene Punkte / mögliche nächste Schritte
- **Settings-Seite wirkt nur lokal** — auf dem Dedi gelten immer die Defaults. Settings→Server-Sync
  (Event) wäre ein künftiges Feature.
- **Grubbern & Ernten** noch nicht ausgiebig live gesehen (sollten laufen; Ernte nur bei reifen Feldern).
- **Rückfahrt-Teleport** lässt sich nicht ganz vermeiden (FS25-Pfadanbindung mancher Felder).
- **Herbizid/Festdünger flächig erzwingen** wäre nur über tiefes PF-Reverse-Engineering möglich
  (aktuell bewusst deaktiviert/aussortiert).
- Bei sehr langen Chats trat ein **Usage-Policy-Fehlalarm** auf (API-Block) — dann neuen Chat
  starten, diese Datei + Memory `nachbarfelder-projekt.md` liefern den Kontext.

## Transport-/Park-Auftrag — „lebendige Map" ✅ GEBAUT (2026-06-13)

> ⚠️ **VERALTET:** Patrol ist inzwischen **wegpunkt-basiert** (nicht mehr Feld-Zielpunkte).
> Aktueller Stand im Abschnitt „WP-Patrol-System" unten (2026-07-05).

**Status:** Implementiert und ausgeliefert (`FS25_NachbarFelder.zip`).

**Was gebaut wurde:**
- `generatePatrol()` in `NachbarFelderManager.lua`: Traktor spawnt am Shop, fährt via GOTO zu
  einem zufälligen Feld-Zielpunkt, parkt 60–180 Sekunden, kehrt zum Shop zurück.
- **30 % Wahrscheinlichkeit** in `onMinuteChanged` statt Feldarbeit (fallback auf Feldarbeit wenn
  Patrol fehlschlägt).
- **Negative Pseudo-IDs** als `vehicleType`-Key (-1, -2, …) → kein Konflikt mit echten Feld-IDs.
- Worker-Flag `isPatrol=true`; Status-Maschine: `1` GOTO → `2` PARKEN (parkUntil-Timer) →
  `60` Rückfahrt (bestehende Hangel-Logik) → `100` despawn.
- Park-Timer-Loop in `update()` (außerhalb needTimer-Mechanismus).
- Guards in: `setAIOnField`, `finishFieldState`, `deleteMission`, `onMissionStarted`,
  `saveToXMLFile`, Bewegungs-Watchdog, `onAIFieldWorkerEnd`, `onAIJobFinished`-Blacklists.

**Bekannte Grenzen:**
- KI fährt nicht flüssig wie echter Verkehr (langsam, ruckelig an Kreuzungen) — unvermeidlich.
- GOTO-Pfadfindung wackelig: manche Ziele unerreichbar → bestehende <1500ms/<5000ms-Logik fängt ab.
- Nur Traktor (kein Anhänger) — Anhänger wäre möglich aber komplizierter (kuppeln, abkuppeln).
- Echtes FS25-Spline-Verkehrssystem ist NICHT bestückbar (separates Proxy-System).

---

# ERGÄNZUNG 2026-07-05 — WP-Patrol-System & aktuelle Baustelle

## WP-Patrol-System (löst Feld-Patrol von 06-13 ab)
- **49 Wegpunkte** vom User in-game aufgenommen (Fahrzeug + Aufnahme-Feature), Datei liegt auf dem
  Server. WPs sind am Straßenrand. Format je WP: `{x, z, ry}`.
- Patrol-Fahrzeuge fahren **WP zu WP** („Hops", z.B. 10–20 Stück), parken an WPs
  (`parkUntil`, 60–180 s), danach nächster Hop; bei `hopsLeft=0` → Status 60 Heimfahrt → 100 despawn.
- Negative Pseudo-Feld-IDs (-1, -2, …) = Patrol-Worker im `vehicleType`-Table. `trafficLimit` = max.
  gleichzeitige Patrols (aktuell 4). Auch Gespanne (Traktor + Anbaugerät) patrouillieren.
- **Client-Sync:** WPs werden Clients per Event geschickt (`[SYNC] 49 Wegpunkte an Client gesendet`);
  ESC-Menü hat einen **Wegpunkt-Tab** (`[WP-PAGE]`, pos=9); Map zeigt **WP-Hotspots mit Nummern**
  (`[MAP] 49 WP-Hotspots gesetzt`).
- **Fallback „Teleport-Patrol-Modus"** (`patrolNoNavmesh=true`): wenn GOTO 2× scheitert, wird das
  Fahrzeug pro Hop zum Ziel-WP **teleportiert** und parkt dort. Funktioniert, ist aber nur Notnagel —
  User will echtes Fahren.

## ✅ GELÖST (Build 50/51): Patrol-GOTO scheiterte SYNCHRON auf dem Dedi (elapsed=0)
**ROOT CAUSE: `AIMessageErrorOutOfMoney` — die NPC-Farm 2 („Lohner") war pleite (-111 €).**
`AIJob:updateCost` (AIJob.lua:178) stoppt JEDEN AI-Job (GOTO und FIELDWORK) im ersten
AISystem-Update-Tick, wenn die startende Farm die Helferkosten nicht decken kann. Gefunden via
Build-49-Hook auf `job.stop` (AIMessage-Klassenname + `printCallstack()`).
**Fix:** `ensureFarmMoney()` — vor jedem `startJob` wird Farm 2 bei Kontostand < 500 000 €
auf 1 000 000 € aufgefüllt (Aufruf in `driveToField` + `setAIOnField`). Live bestätigt:
„KI fährt jetzt wieder". Build 51 = Aufräum-Build: DIAG-Logs entfernt, Spawn-Teleport zum
Start-WP reaktiviert (verteilt Patrols, verhindert Shop-Stau).
**Debug-Regel für die Zukunft:** Bei AI-Job-Sofortabbrüchen `job.stop` wrappen — das
Vehicle-Event `onAIJobFinished` bekommt die AIMessage NICHT; `printCallstack()` (Engine-Global)
zeigt den Auslöser. Der eigene addMoney-Hook verhindert nicht alle Abbuchungspfade der Engine.

Der ursprüngliche Diagnose-Stand (historisch, alle Hypothesen abgearbeitet):
**Symptom:** Jeder `aiSystem:startJob(AIJobGoTo, farmId=2)` für Patrol-Fahrzeuge endet ~4 ms später
im selben Tick: `[DIAG] onAIJobFinished: … elapsed=0`. Kein Fahren, keine Pfadsuche-Phase.

**Gesichert:**
- `job:validate(2)` → **ok=true** (Build 47) — Ablehnung passiert NACH validate, in `job:start()`.
- Betrifft alle Fahrzeugtypen und alle Startpositionen (WP-Position wie natürlicher Shop-Spawn).
- Vanilla „Freie Fahrt" geht auf demselben Server von überall; FIELDWORK-Jobs funktionieren →
  Navmesh, AI-System, farmId-Hooks grundsätzlich ok. Früher lief Patrol-GOTO auf dem Server (Regression).
- `msg=?` im Vehicle-Event ist kein Indiz (Event bekommt vermutlich keine aiMessage übergeben).

**Ausgeschlossen (Builds 44–47, NICHT wiederholen):** `setOwnerFarmId(2)` vor startJob (44);
Spawn-Teleport übersprungen — GOTO von natürlicher Load-Position (45); `createAgent`-Block für
Patrol übersprungen, da Vanilla-GoTo das nicht macht (46/47); validate-Fehlschlag (47: ok=true).

**Nächste Schritte (Reihenfolge):**
1. **Build-48-Log auswerten:** `[DIAG3] paramVeh=…` — hält `job.vehicleParameter` das Fahrzeug?
   `false` → setVehicle/setValues-Problem. `true` → tiefer in start() schauen.
2. `AIJobGoTo.start` und/oder `aiSystem.stopJob` per Wrapper hooken → echten Ablehnungsgrund loggen.
3. Helper-Erschöpfung prüfen (`g_helperManager`, freie Helfer zählen).
4. Testen ob Feld-GOTO (fieldId>0) aktuell noch fährt → grenzt unser Setup vs. Server-Regression ab.
5. PropertyState MISSION vs. OWNED testen (Freie-Fahrt-Fahrzeuge sind OWNED).

**Nach dem Fix aufräumen:** `[DIAG]`/`[DIAG3]`-Blöcke raus (Worker ~44–64, Manager driveToField);
Spawn-Teleport zu WP in `onSpawnedVehicle` **wieder aktivieren** (aktuell deaktiviert, Log
„Spawn (kein Teleport)"); Teleport-Patrol-Fallback behalten.

**Ebenfalls gefixt (Builds 43–45):** Geister-Spawns ohne Spieler — `pendingRespawns` lief am
update()-Anfang VOR dem playersOnline-Gate → `stopAllHelpers()` leert jetzt `pendingRespawns={}`
und der Respawn-Loop hat einen `playersOnline > 0`-Guard.

**Build 63:** Fahrzeuge parken LÄNGS zur Straße: Spawn-/Teleport-Ausrichtung nutzt die
aufgezeichnete WP-Richtung (wp.ry, Fahrtrichtung beim Aufnehmen), nur 180°-Flip wenn das
Ziel "hinten" liegt — vorher wurde Richtung Ziel gedreht → Fahrzeuge standen quer.

**Build 64 — Spawn-Entzerrung gegen Server-Ruckler (User-Wunsch):**
Jeder Spawn (I3D+Physik+MP-Sync) = kurzer Ruckler; 3 hintereinander stapelten sich.
Neu (alle in ServerConfig): `spawnPerTick` (Default 1, war 3 hardcoded),
`spawnIntervalMinMinutes`/`MaxMinutes` (Default 2-5 SPIELminuten zwischen Spawns; vorher
random(0,timeScale)), `parkTimeFactor` (Default 1.0; z.B. 2.0 = doppelte Parkzeiten,
skaliert ALLE Patrol-Pausen via `scaleParkSecs()` + nfCatParkSecs). Kompensation für
weniger Spawns: längere Lebenszeit über `patrolHopsMin/Max` hochsetzen (z.B. 20-40).

## ⚠️ RUCKLER-DIAGNOSE 2026-07-27 (Builds 76/77)
Builds 65-75 entstanden in anderen Sitzungen (Pool 65, Einpark-Schnapp 66, Savegame-Settings 67,
Tagesrhythmus+Fruchtfolge 68, Gespann-Quote 69, WP-Richtung 70, Client-Prefs 71, Belegte-Plätze 73,
Ruckler-Diagnose 74, Admin-Checks 75). User: „ruckelt wie ein Speicherleck, immer mal wieder".
**Build 76:** LuaMem-Telemetrie (1x/min bei ±4MB), Spike-Schwelle 200→100ms, Input-Log-Spam
gestoppt (logOnce), Karten-Nummern-Hook allokationsfrei (hs._nfLabel vorberechnet).
**BEFUND (korrigiert durch User-Analyse, Build 78):** Die Dauer-200ms-Serien waren
**FEHLALARME**: Der Dedi drosselt OHNE verbundene Spieler auf 5 Ticks/s = exakt 200ms/Frame
(Engine kappt dt zusätzlich bei 200). Beweis: Zählerwert fiel exakt beim „OGW joined"-Moment
von 50 auf 27; CPU der Instanz nur ~14%. Die Autosave/OneDrive-These ist damit UNBEWIESEN
(Serien traten im Leerlauf auf); LuaMem stabil ~320-330 MB beidseitig, kein Leck; Client
komplett sauber. **MERKE: Konstant-200ms-Serien im Dedi-Log = Server leer, KEIN Lastproblem.**
**Build 77:** Spike-Log aggregiert (1 Zeile/10s statt 120 Einzelzeilen).
**Build 78:** PERF-Telemetrie nur noch bei playersOnline>0 (Server); Schwelle adaptiv
max(100ms, 2.5x gleitender dt-Schnitt) → Idle/Aktiv-Übergänge zählen nicht falsch; Schwelle
steht mit in der Log-Zeile. LuaMem-Zeile ebenfalls Spieler-gegatet.
**OFFEN:** Ob es MIT Spielern echte Ruckel-Fenster gibt (Autosave? OneDrive?) zeigt erst
eine Sitzung mit Build 78: [PERF]-Zeilen können jetzt nur noch aus Spieler-Phasen stammen.
**⛔ WORKFLOW-ÄNDERUNG 2026-08-04:** ZIPs NICHT mehr automatisch in den Mods-Ordner legen —
nur noch nach Codex bauen, User spielt selbst ein (siehe Memory fs25-mod-zip-workflow).

**Build 81 — ModHub-Vorbereitung (TestRunner-Fixes, 2026-08-04):**
TestRunner 0.9.19 FAIL behoben: descVersion 108→111; version 0.1.0.0→**1.0.0.0** (Schema
verlangt a≥1; 1.0.0.0 = Erstrelease → missingChangelog-Meldung entfällt); title.fr
"Champs voisins"→"Champs Voisins" (jedes Wort groß); redundanten <de>-Titel entfernt
(war identisch zu en → obsoleteLocalization); unbenutztes icon_FWA.dds aus dem Mod-Ordner
nach Codex\_backup_icon_FWA.dds verschoben (ObsoleteFiles).
MERKE: Ab dem nächsten Versions-Bump (1.0.0.1+) verlangt der TestRunner einen CHANGELOG
in description de+en. ZIP: Codex\FS25_NachbarFelder_Build81.zip (nicht deployed!).

**Build 80 — BetterContracts-Tab-Konflikt behoben (2026-08-03):**
BC berechnet bei JEDEM Öffnen des Einstellungs-Frames seinen Tab-Index als "#subCategoryPaging.texts"
(= LETZTER Eintrag, Code-Kommentar: "our mod button should always be the last one"). Unser
Wegpunkte-Tab hängt dahinter → BCs Tab-Klick (onClickBC → setState(modState)) öffnete UNSERE
Seite. Fix in NachbarFelderWaypointPage (nach der Tab-Einfügung): eigener onFrameOpen-Append
(läuft NACH BCs Hook) sucht den Paging-State, dessen texts-Wert == SUB_CATEGORY.BCONTRACTS,
und setzt `BetterContracts.settingsMgr.modState` darauf (BC-Zugriff: global `BetterContracts`
oder `_G["FS25_BetterContracts"].BetterContracts`). Eigener Tab-Klick ebenso gehärtet
(State per texts-Wert-Suche statt Seitennummer). Log: "[WP-PAGE] BetterContracts-Kompatibilität aktiv".
MERKE fürs Tab-Einfügen: Mods wie BC nehmen "letzter Tab = meiner" an — nach uns eingefügte
Tabs anderer Mods können dasselbe Problem in Gegenrichtung erzeugen.
lsc.py-Fehlalarm #3: MEHRZEILIGE for-Schleifen (do auf Folgezeile) → for-Kopf einzeilig halten.

**Build 79 — Performance-Trimm:** Die fünf Überwachungs-Blöcke in update() (9999-Timeout,
Mähdrescher-Tank-Leerung, Patrol-Park-Timer, Feldarbeits- + Patrol-Watchdog) laufen im
250ms-Takt (`slowTick`, `self._slowNextAt`) statt jeden Frame — sie prüfen nur Sekunden-
Grenzen. Tank-Leerung als benannte Funktion `nfEmptyCombineTank` (pcall(fn, veh)) statt
anonymer Closure pro Frame (GC-Müll). needAttachment-Scan + Status-Maschine bewusst
weiter pro Frame (Timing-Semantik). Restkosten der Mod sind event-getrieben und minimal;
größte Serverlast kommt von Map/PF/Physik, nicht von uns.

**Build-Stand:** Build 64 deployed (2026-07-05). ZIPs `Codex\FS25_NachbarFelder_Build<N>.zip`
(50=Geld-Fix, 51=Aufräumen, 52=Rollback Paket 1+2, 53=Paket 1-6, 54=WP-Sperren-Sichtbarkeit,
55=Server-Konfig in den Mod-Settings-Ordner, 56=Live-Test-Fixes, 57=Watchdog stoppt alten
Job via stopAIJobSafely, 58=WP-Editing MP-fähig, 59=ServerConfig bei loadMap + Build-Nr im
Log, 60=StoppedByUser-Klassifizierung + Spawn-Verteilung + Min-3-WPs, 61=Karten-Schalter,
62=Zapfwellen-Fix bei Gespannen).

**Build 59:** `NachbarFelderManager.BUILD` (bei jedem Build hochzählen!) erscheint in der
loadMap-Zeile: `NachbarFelder: loadMap auf SERVER (Build 59)` — IMMER zuerst prüfen ob der
Server den erwarteten Build fährt (OneDrive-Sync!). loadServerConfig läuft jetzt in loadMap
(Server-Branch, nach loadWaypoints) → Konfig-Vorlage entsteht direkt beim Serverstart, ohne
dass ein Spieler joinen muss (vorher hing sie an onMinuteChanged = erste Spielminute MIT
Spieler). Zusätzlich loggt loadServerConfig immer den Pfad: `Server-Konfig-Pfad: ...`.

**Build 61:** Karten-Schalter „WPs anzeigen" rief nur das Flag, nicht `setWpHotspotsVisible()`
→ Punkte blieben bei „Aus" sichtbar. Fix: Page-Callback nutzt die vorhandene Funktion.

**Build 62 — Zapfwellen-Fix (kilometerlange „Stange" am Patrol-Anbaugerät):**
Ursache: Traktor wurde beim Spawn zum Start-WP teleportiert, Gerät dann vom Shop
hinterher-teleportiert und im SELBEN Frame gekuppelt → Zapfwellen-Mesh behält einen alten
Welt-Ankerpunkt → gestreckte Stange Richtung Shop. Fix: Gespanne kuppeln jetzt AM SHOP
(kurze Distanz wie Feldarbeit = Zapfwelle korrekt), danach teleportiert der update-Fallback
das komplette Gespann (teleportVehicle nimmt Implements+PTO mit) zum in onSpawnedVehicle
gemerkten Start-WP (`nfW.spawnWpIdx`, firstStart bleibt bis dahin gesetzt). Solo-Fahrzeuge
teleportieren weiter sofort. setAttachment-Geradeziehen wird bei firstStart übersprungen
(Ausrichtung kommt mit dem WP-Teleport).

**Build 60 (nach Live-Log 16:12, Build 58/59 bestätigt funktionierend):** User baut WP-Netz
NEU auf (alte 49er-Datei weg, live-Editing via Events funktioniert ✓, ServerConfig angelegt ✓,
Blacklist greift ✓, Patrols hoppen ✓). Drei Korrekturen: (1) `AIMessageSuccessStoppedByUser`
in onAIJobFinished status==1 → sofortiges return OHNE Klassifizierung — eigene Watchdog-Stops
wurden sonst als „WP nicht erreichbar" gewertet → falsche WP-Strafen + doppelte Neuziel-Wahl;
(2) Batch-Spawn schließt den zuletzt gewählten Start-WP aus (3 Fahrzeuge spawnten am selben
WP5 und blockierten sich); (3) Traffic-Spawn erst ab 3 WPs (einmalige Log-Warnung) — schützt
die Netz-Aufbau-Phase. Merke: saveWaypoints() leert wpFails → jeder neu gesetzte WP hebt
alle Session-Sperren auf (gut beim Netzaufbau).

**Build 58 — WP-Editing auf dem Dedi („Wegpunkte werden nicht gespeichert"-Fix):**
ROOT CAUSE: ALLE WP-Änderungen (Shift+Alt+P setzen, entfernen, ESC-Seite Typ/Löschen/
Fahrzeugkategorien) liefen rein CLIENTSEITIG — der Server erfuhr nie davon, der nächste
Server→Client-Sync überschrieb die lokale Liste. Fix: neues Event
`NachbarFelderWaypointEditEvent` (OP_ADD/REMOVELAST/DELETE/SETCAT/VEHCAT) → Server führt
die Änderung in `applyWaypointEdit()` aus, speichert (saveWaypoints broadcastet Sync an
alle Clients). `saveWaypoints()` hat jetzt Client-Guard (reiner Client schreibt die Datei
NIE — wichtig auch wegen OneDrive-geteiltem Profil-Ordner). SP/Host unverändert direkt.
Präzedenz Fahrzeugkategorien: ESC-Seite wirkt ab sofort live auf dem Server (persistiert
in WP-Datei), aber nach Server-Neustart überschreibt die ServerConfig (falls vehicles-Keys
vorhanden) — Kategorien auf dem Dedi daher langfristig in der ServerConfig pflegen.
**User-Symptom-Deutung:** „ruckt zurück + verschwindet" = Watchdog Stufe1 (12s, 4m-Rück-Teleport)
→ Stufe3 (30s, delete). „Steht mit Rundumleuchte, blockiert aber nichts da" = vermutlich
unsichtbares nicht-gekuppeltes Implement IN der Traktor-Position (Build-53-55-Bug, gefixt in 56)
ODER normales WP-Parken (20-60s pro Hop, gewolltes Verhalten!).

**Build 56 (Live-Test-Fixes nach User-Screenshots):**
- ⚠️ REGRESSION aus Paket 3 behoben: das Geradeziehen nach dem Kuppeln drehte AUCH
  Patrol-Gespanne Richtung Workshop → an WPs mitten auf der Map drehte sich das Gespann
  in Felder/Hindernisse (Screenshot: Fendt im Maisfeld). Jetzt: Feldarbeit → Workshop,
  Patrol → Richtung Ziel-WP.
- Patrol-Hauptgerät (v==2) darf jetzt auch an die FRONT kuppeln (Kategorie MOWERS
  enthält Front-Mähwerke — hingen vorher falsch am Heck). Feldarbeit bleibt Heck-only.
- Patrol: nicht kuppelbare Geräte werden GELÖSCHT statt als Waisen stehen zu bleiben
  („das hintere fehlt") — Fahrzeug fährt solo weiter.
- Fahrzeugkategorien in der Server-Konfig (`vehicles.tractorsSmall/Medium/Large,
  wheelLoaders, teleLoaders`): Die Kategorie-Einstellung steckt sonst NUR in der
  Wegpunkt-Datei (catTractorL-Attribute) — die Server-Kopie des Users war älter,
  darum spawnten Großtraktoren trotz lokaler Einstellung. Server-Konfig überschreibt
  jetzt die WP-Datei-Werte. Alte Konfig-Datei löschen → Vorlage wird mit vehicles-Block
  neu geschrieben.
**WP-Sperren (Build 54):** Sperre ist NUR Session-RAM (Neustart = frei). Log zeigt beim Sperren
Koordinaten + Gesamtliste („Aktuell gesperrte Ziele: WP3, WP17"). WP-Nummer = Karten-Hotspot-Nummer.
`saveWaypoints()`/`loadWaypoints()` leeren `wpFails` (Indizes verschieben sich bei Listenänderung).
Workflow: gleicher WP über mehrere Sitzungen gesperrt → in-game via Karte/Shift+Alt+W finden,
löschen, näher an der Straßenmitte neu aufnehmen.
Syntax-Check: `references/lua_syntax_check.py` nach `%TEMP%\lsc.py`
kopieren, mit `py` ausführen (nur `py`-Launcher vorhanden, kein `python`; langer Skill-Pfad
scheitert). Deploy: PowerShell `Copy-Item` → OneDrive-mods → auf Server-Sync warten → Dedi neu starten.
⚠️ lsc.py-Eigenheit: bei `while <lange Bedingung> do` (>60 Zeichen zwischen while und do)
zählt der Checker das `do` als eigenen Block → Fehlalarm; lange Schleifen als `for _ = 1, N do` schreiben.

## Verbesserungs-Pakete 1-6 ✅ GEBAUT (2026-07-05, Builds 52+53)

**1. AIMessage-basierte Fehlerbehandlung (statt Zeit-Heuristik):**
`driveToField` wrappt `job.stop` und merkt den AIMessage-Klassennamen in `worker.lastStopMsg`
(`nfAIMessageName()` mit isa-Kandidatenliste, file-lokal in Manager.lua). `onAIJobFinished`
(status 1) klassifiziert primär über die Message: `SuccessFinishedJob` = angekommen (auch bei
Fahrt < 5 s — vorher Fehlklassifizierung!), `NoPathFound/NotReachable` = Ziel-Problem,
`OutOfMoney` = Konto auffüllen + selben Hop neu versuchen (max 3×, `moneyRetry`).
Zeit-Heuristik (<1500 ms/<5000 ms) greift nur noch ohne Message. Fehler-Logs enthalten jetzt
die Message. `NotReachable` nach >5 s wird jetzt korrekt als Fehler behandelt (vorher „Erfolg").

**2. WP-Blacklist (unerreichbare Wegpunkte lernen):**
`registerWaypointFail(idx)` / `isWaypointBlocked(idx)` / `pickPatrolWaypoint(waypoints, excludeIdx)`
im Manager. 2× nicht erreichbar → Session-Sperre als Ziel. ALLE Zielwahl-Stellen nutzen
pickPatrolWaypoint: Worker-Pathfail, Manager Next-Hop, Watchdog Stufe1/Stufe2, generatePatrol,
Spawn-Start-WP, Batch-Spawn overrideWp. Start-WP wird bestraft wenn GOTO von dort sofort
abgelehnt wird (Shop-Fallback-Zweig).

**3. Shop-Spawn „verkehrt herum":** Gespann wird in `setAttachment` NACH dem Kuppeln
zur Ausfahrt (Workshop 98.65/119.08) geradegezogen (teleportVehicle bewegt Implements mit).
Implement-auf-Traktor-Teleport + moveToJoint war schon vorher drin (verhindert Boot-Verharken).

**4. Server-Konfig:** `modSettings/FS25_NachbarFelder/NachbarFelderServerConfig.xml`
(seit Build 55 im selben Ordner wie NachbarFelderWaypoints.xml, via `g_currentModSettingsDirectory`;
im Server-Profil Server-PC!). Beim ersten Start schreibt der Server eine Vorlage mit Defaults;
danach editieren + Neustart. Schlüssel: `maxWorkers` (12), `trafficLimit` (4),
`trafficTrailerSize` (0-3, def. 2), `firstSpawnDelaySecs` (180), `patrolHopsMin`/`patrolHopsMax` (10/20).
Geladen einmalig in `onMinuteChanged` → `loadServerConfig()` (nur Server; pcall-gesichert).
Hinweis: Build 53/54 legte die Datei fälschlich als `modSettings/FS25_NachbarFelder.xml`
NEBEN den Ordner - falls vorhanden, löschen.

**5. Konto-Nachfüllung periodisch:** `ensureFarmMoney()` zusätzlich in `onMinuteChanged`
(wenn `hasActiveWorkers()`) — schützt lange laufende Jobs vor Mitten-drin-Stopp.

**6. Kein Mod-Fußabdruck in farms.xml:** `ensureFarmMoney` merkt den Original-Kontostand
(`farmOrigMoney`, z.B. -111). Der `saveSavegame`-Hook schreibt beim Speichern den Originalwert
in farms.xml und stellt danach das aufgefüllte Konto wieder her (analog Farmland-Trick).

---

# ERGÄNZUNG 2026-09-15 — Build 130: Log-Entschlackung (logLevel)

Hinweis: Diese Datei war seit Build 81 nicht mehr gepflegt (Builds 82-129 liefen in anderen
Sitzungen; deren Stand steckt in den Memory-Dateien). Build 130 baut auf Build 129 auf.

**logLevel in der ServerConfig** (`NachbarFelderServerConfig.xml`): 1 = normal (Standard),
2 = Debug. Helper `NachbarFelderManager:log(lvl, msg)`. Auf Debug-Stufe gelegt (waren die
drei Dauerschreiber, ~6-12 Zeilen/Minute bei 4 Patrols, rund um die Uhr):
- `GOTO Start -> x=...` (driveToField, jeder Hop)
- `[TRAFFIC] -> WPn [Kat] (noch X Hops...)` (Next-Hop)
- `[TRAFFIC] steht Xm vor Ziel still - gilt als angekommen` (Routine-Ankunft Build 98/105)
Fehler, Lebenszyklus (Spawn/Pool/Sperren/Watchdog-Stufen), [PERF] bleiben auf Stufe 1.
Für Fehlersuche: logLevel=2 setzen + Server-Neustart. Konfig-Logzeile zeigt `logLevel=`.
Nutzen: weniger String-GC und I/O (43-MB/s-Schreibdrossel der Server-VM), lesbares Log. (Hinweis 2026-09-15: OneDrive spielt KEINE Rolle - Spiel vom Sync ausgeschlossen, Server ohne OneDrive.)
Nebenbei 2 lsc.py-Fehlalarme in Build-82-129-Code behoben (lange/zweizeilige for-Köpfe).
ZIP: `Codex\FS25_NachbarFelder_Build130.zip` — **NICHT deployed** (Regel seit 2026-08-04).

# ERGÄNZUNG 2026-09-17 — Build 131: Fixes aus dem Server-Vergleichstest

Anlass: Vergleichstest alter vs. neuer Server (17.09., beide ohne Performance-Probleme beim Spielen).
Zwei Mod-Befunde daraus:

**1. Endlos-Zielsuche bei "nicht erreichbar" (series6C, neuer Server, 10:19-10:32):**
Der pathFail-Zweig (Worker, Patrol) hatte KEINEN Zähler — 17 Ziele nacheinander, jede Pfadsuche
20-30 s CPU, und jeder Fehlschlag bestrafte das ZIEL → gute WPs für ALLE Fahrzeuge gesperrt,
obwohl der Standort schuld war. Fix: `tt.pathFails` (in Folge; Reset bei Erfolg):
1. Fehlschlag → Ziel-WP bestrafen (registerWaypointFail) + neues Ziel
2. Fehlschlag → KEINE Ziel-Strafe mehr, Standort-Rettung `nfRoadSnap` (KI-Strasse, sonst Shop)
3. Fehlschlag → `nfMarkStartPlaceBad` + Pool (status 100). Max ~1,5 min statt 13 min.
Die Rettungs-Blöcke des Abweisungs-Zweigs (gotoRejects, Build 97-105) wurden dafür verhaltens-
gleich in file-lokale Funktionen `nfRoadSnap(tt, mgr, veh0)` / `nfMarkStartPlaceBad(tt, mgr, veh)`
ausgelagert und von beiden Zweigen genutzt. MERKE: sleepPatrolEntry lässt Fahrzeuge seit Build 93
STEHEN, wo sie sind — Pool allein repariert keinen schlechten Standort, deshalb erst Snap.

**2. PERF-Zeile widersprüchlich ("(>377ms) ... max 200ms"):**
Ursache a) ausgegebene Schwelle wurde beim DRUCKEN aus dem aktuellen dt-Schnitt neu berechnet,
gezählt wurde mit früheren, niedrigeren Schwellen. Fix: kleinste tatsächlich angewandte Schwelle
(`_spkLimitMin`) ausgeben. Ursache b) adaptive Schwelle konnte über 200 ms steigen, Engine kappt
dt bei 200 → Detektor nach Last BLIND. Fix: Schwelle auf 190 ms gedeckelt.
Ursache c) die "langsamen Frames direkt nach dem Verlassen" (18+2 / 14+5) waren sehr wahrscheinlich
Leerlauf-Frames: Dedi drosselt beim letzten Disconnect sofort, playersOnline wird aber nur
minütlich aktualisiert. Fix: PERF-Gate zählt Spieler im Sekundentakt (`nfCountConnectedPlayers`,
closure-frei via pcall(fn)); playersOnline selbst (steuert stopAllHelpers) unverändert.

ZIP: `Codex\FS25_NachbarFelder_Build131.zip` — NICHT deployed. Backup Worker vor dem Umbau:
Sitzungs-Scratchpad `NachbarFelderWorker_vor131.lua`.


# ERGÄNZUNG 2026-09-17 — Build 132: Admin-Spawnpunkte + Wegpunkt-Datei je Karte

Anlass: „Fahrzeuge kommen weiterhin aus der Luft geflogen und springen/drehen sich mehrmals".
Server läuft inzwischen auf **Beuren**; Lösung muss kartenunabhängig sein (User-Vorgabe).

**Befund (Log NeuServerLog 17.09. + Spielcode verifiziert):**
- Geladen wurde „direkt an der KI-Strasse … 40 m vom Shop-Platz" = mitten im Ort. Dort sofort
  abgewiesen („Ladeplatz taugt nicht (Verkehr sofort abgewiesen)"), dann Rettungs-Teleports
  („GOTO kommt nicht weg … weiter vorn gesetzt", „Schlafplatz war belegt … 26 m weiter gestellt").
- VERIFIZIERT Vehicle.lua:1768: Clients übernehmen JEDE Positionsänderung des Servers über
  ``networkInterpolators.position:setTargetPosition`` — es gibt kein Teleport-Flag. Jeder
  Server-Teleport ist für Mitspieler ein Flug durch die Luft.
- VERIFIZIERT VehicleLoadingData.lua:310 + Vehicle.lua:2332: ``setPosition(x,y,z)`` + Laden setzt
  den i3d-Root absolut → Laden selbst ist korrekt (y = Fahrbahn + 0,15 m).
- ``teleportVehicle`` selbst ist NICHT im gameSource.zip (Mission-Basisdateien fehlen dort).

**Lösung (Idee des Users): Wegpunkt-Typ „Spawnpunkt" (cat = 4)**
- ``NachbarFelderManager.WP_CAT_SPAWN = 4`` (3 = Durchfahrt ist belegt), ``getIstSpawnpunkt(wp)``
  für beide WP-Formen. ESC-WP-Seite: Typ-Zyklus Normal→Kurz→Lang→Spawnpunkt→Normal;
  Server ``OP_SETCAT`` erlaubt 0/1/2/4. Karten-Hotspot beschriftet „12 S".
- ``waehleSpawnpunkt(nurPruefen)``: zufällig reihum, Fläche 17×4 m frei (getIstSpawnFlaecheFrei),
  Reservierung 45 s (``spawnpunktReserviert``), Richtung = gespeicherte WP-Richtung; liegt eine
  KI-Strasse ≤ 8 m daneben UND weicht die Richtung < 45° ab → exakt längs geschnappt.
- ``setzeLadepositionStrasse``: Spawnpunkt hat Vorrang, alte Shop-Suche nur als Ausweich.
- ``generateTraffic``/``generateWorkMission``: Spawnpunkte vorhanden aber keiner frei → Takt
  auslassen (kein Laden im Ort); Shop-Blocker entfällt mit Spawnpunkten.
- Spawnpunkte sind nie Fahr-/Parkziel (pickPatrolWaypoint beide Schleifen, findFreeParkpunkt).
- ``merkeSpawnFehlschlag``: Spawnpunkte werden NICHT session-gesperrt, nur einmaliger Hinweis.
- WP-Richtung beim Setzen aus dem Fahrzeug jetzt per ``localDirectionToWorld`` (Euler-Y kippt am Hang).

**Wegpunkt-Datei je Karte:** ``NachbarFelderWaypoints_<mapId>.xml`` (mapId aus
``missionInfo.mapId`` — belegt über careerSavegame.xml ``<mapId>FS25_Beuren.MultifruitModMap_Beuren``;
Fallback letzter Ordner von ``g_currentMission.baseDirectory``, verifiziert FarmlandManager.lua:62;
ohne Kennung alte Datei). Einmalige Übernahme der alten gemeinsamen Datei für die erste Karte,
die der SERVER lädt; alte Datei bleibt liegen, bekommt ``#uebernommenFuer``.
ACHTUNG Server-Neustart: auf Beuren werden die bisherigen (Beuren-)Punkte übernommen.

**Bedienung:** Aus dem Fahrzeug an freier Stelle nahe befahrbarer Strasse, Blick in Abfahrtrichtung,
WP setzen → ESC → Wegpunkte → Typ bis „Spawnpunkt". Log: „wird am Spawnpunkt WPn geladen".

ZIP: ``Codex\FS25_NachbarFelder_Build132.zip`` — NICHT deployed.


**Nachtrag Build 132 (17.09.) — ZIP-Inhalt korrigiert:** Builds 130–132 waren per Ordner-Walk
gepackt und enthielten ``build.py`` und die alte Ausgabe ``FS25_NachbarFelder.zip`` (TestRunner:
„Unknown file type"). Richtig ist ausschließlich ``py build.py`` im Quellordner (feste Liste,
13 Dateien, Ausgabe ``Codex\NachbarFelder\FS25_NachbarFelder.zip``). ``Codex\FS25_NachbarFelder_Build132.zip``
wurde durch die saubere Fassung ersetzt; die Build-130/131-ZIPs in Codex sind weiter fehlerhaft
(überholt, nicht verwenden).


# ERGÄNZUNG 2026-09-17 — Build 133: Wegpunkt-Richtung beim Setzen korrigiert

Anlass: Frage „wie setze ich Spawnpunkte/Wegpunkte" — beim Nachprüfen der Anleitung
(„aus dem Fahrzeug in Abfahrtrichtung setzen") fiel auf, dass das Fahrzeug nie erkannt wurde.

**Befund (Spielcode verifiziert):**
- FS25 hat KEIN ``player.currentVehicle`` / ``player.controlledVehicle``: im gameSource 64 Aufrufe
  ``getCurrentVehicle()``, kein einziger Feldzugriff. Versuch 1 in ``onInputAddWaypoint`` lief nie.
- Folge: zu Fuß Richtung = Drehung des Spieler-rootNode = immer 0; aus dem Fahrzeug fiel es auf die
  Kamera zurück (Euler-Y, nur −90…+90°, Blick- statt Fahrtrichtung). Belegt in der Sicherung
  ``Sicherung DSH_Alt/modSettings/FS25_NachbarFelder/NachbarFelderWaypoints.xml``: 16× ry = 0,
  alle übrigen Werte zwischen −1,51 und +1,48 rad.
- Normale Wegpunkte: Richtung nur Rückfall, wenn keine KI-Strasse ≤ 20 m (Zielausrichtung) → alte
  Punkte können bleiben. Spawnpunkte brauchen die Richtung (Ausrichtung + 17×4-m-Freiflächenprüfung)
  → Spawnpunkte NUR mit Build 133 neu setzen, keine alten Punkte umtypisieren.

**Fix:** Muster wie AISystem.lua:862-875 — Fahrzeug über ``player:getCurrentVehicle()`` (Fallback alte
Felder) → rootNode + ``localDirectionToWorld(0,0,1)``; zu Fuß ``player:getMapPositionAndLookYaw()``
(Player.lua:1310, Blickrichtung); sonst Kamera ``localDirectionToWorld(cam,0,0,-1)``.
``ry = math.atan2(dx, dz)`` (passt zu sin/cos in waehleSpawnpunkt). Meldung zeigt „Richtung aus
Fahrzeug/Blickrichtung/Kamera"; Server-Log „Wegpunkt n gesetzt (Client-Event) … Richtung x Grad".

**Freifläche Spawnpunkt (getIstSpawnFlaecheFrei):** 17 m × 4 m, von 3 m vor dem Punkt bis 14 m
dahinter; Strasse/Gelände zählen nicht, Fahrzeuge/Zäune/Gebäude schon — das eigene Fahrzeug nach
dem Setzen wegfahren, sonst gilt der Punkt als belegt.

ZIP: ``Codex\FS25_NachbarFelder_Build133.zip`` (py build.py, 13 Dateien) — NICHT deployed.


# ERGÄNZUNG 2026-09-17 — Build 134: Punkte aus dem Menü setzen, Tasten, Beschreibung

Anlass: „Shift+Alt+P gibt es nicht, auch nicht im Steuerungsmenü". Die Taste ist beim User seit
längerem auf **Strg+Alt+O** umgelegt (Profil `inputBinding.xml`), die Mod-Texte nannten aber fest
Shift+Alt+P. Shift+Alt+P selbst löst Shift+P (Baumenü) bzw. Alt+P (Kleiderschrank) aus.

**Neu im Reiter Wegpunkte:** Abschnitt „Neuer Punkt an deiner Position" mit **„Wegpunkt hier setzen"**
und **„Spawnpunkt hier setzen"** (nur Admin). Beide rufen ``NachbarFelderManager:addWaypointAtPlayer(cat)``
— dieselbe Logik wie die Taste (Fahrzeug: Fahrtrichtung, zu Fuß: Blickrichtung, 10-m-Abstand).
Rückgabe ``true`` bzw. ``false, grund``; der Grund erscheint 8 s in der Infozeile der Seite, weil das
Menü Ingame-Meldungen verdeckt. Nach dem Setzen springt die Seite auf den neuen Punkt, sobald er in
der Liste ist (MP: nach dem Server-Sync, Frist 10 s).
MP: neues ``NachbarFelderWaypointEditEvent.OP_ADD_SPAWN = 6`` (x, z, ry) — Server legt den Punkt
direkt mit cat 4 an (kein OP_ADD + OP_SETCAT mit geratenem Index).

**Tasten:** keine fest verdrahteten Tastennamen mehr in Texten/Logs. Einträge im Steuerungsmenü heißen
jetzt „NachbarFelder: …". Neue **Standardtasten** (modDesc; eigene Belegungen im Profil bleiben):
Wegpunkt setzen Strg+Alt+O · Letzten entfernen Strg+Alt+U · Nacheinander anzeigen Strg+Alt+C ·
Helfer sofort starten Strg+Alt+E · Alle Nachbar-Fahrzeuge entfernen Strg+Alt+L.
Auswahl nach Profil-Analyse (Vanilla + alle Mods): bei L/O/U/C/E sind Strg+Taste und Alt+Taste frei;
N scheidet aus (Alt+N = ADD_NOTE, Vanilla), X (Alt+X Ballenzähler, Strg+X Klappen), W/A/S/D (Laufen).

**modDesc-Beschreibung:** war in allen drei Sprachen doppelt kodiert (Ã¤, â€“, â€™, Ã©, Â« …) —
repariert (Windows-1252-Rückweg, BOM bleibt), Tastenzeile auf Strg+Alt+L und Hinweis auf den Reiter
Wegpunkte geändert. Backup: Scratchpad ``modDesc_vor134_backup.xml``.

**Prüfung:** lsc.py alle Lua OK; zusätzlich ``luaparser`` Vollparse OK (``continue`` ist GIANTS-Lua,
94× im Spielcode — für den Parser durch ``break`` ersetzt); XML minidom OK.
ZIP: ``Codex\FS25_NachbarFelder_Build134.zip`` (py build.py, 13 Dateien) — NICHT deployed.


# ERGÄNZUNG 2026-09-17 — Servertest Build 134 (NeuServerLog 13:51–15:23, Beuren)

**Läuft:** Build 134 ohne Lua-Fehler; 38 Wegpunkte aus ``NachbarFelderWaypoints_FS25_Beuren_MultifruitModMap_Beuren.xml``
(mapId-Dateiname funktioniert); Spawnpunkte werden benutzt (6× „wird am Spawnpunkt WP37/WP38 geladen"),
kein Laden mehr am Shop im Ort, kein Versetzen direkt nach dem Laden. Feldhelfer von WP38 → Feld 68
gegrubbert (706 s). Die Texte „Spawn bleibt am Shop" / „kuppeln am Shop" sind nur veraltete Wortwahl
(``spawnAufStrasse`` verhindert das Versetzen).

**Punkte (aus dem Client-Log 12:52–13:02, Build 134 gibt „[WP] Position x/z, Richtung" aus):**
WP36 normal x=817 z=-860 (29°) · WP37 Spawnpunkt x=868 z=-768 (252°) · WP38 Spawnpunkt x=729 z=-877 (172°).
Ein erster Spawnpunkt x=840 z=-814 wurde um 12:58 wieder gelöscht. Zuordnung geprüft: „naechster WP38 (55m)"
bei x=729 z=-933 und „(82m)" bei x=688 z=-950 passen nur zu x=729 z=-877; WP36 war Fahrziel → kein Spawnpunkt.

**Problem — Engstelle am Landhandel x≈787 z≈-908** (Kartendatei ``maps/config/placeables.xml``: FarmPack-Unterstand
21 m, Dünger-/Saatgut-Silo 26 m, Kalkstation 31 m, Schredder 39 m, Landhandel 53 m):
- alle 3 Feldgespanne von WP37 (arion550 ×2, nSeries) standen genau dort („steht 60 s ohne Bewegung … x=787 z=-908",
  161 m vom Spawnpunkt → kein Spawnpunkt-Hinweis, der greift nur ≤ 10 m);
- „zweiter Stillstand" sperrte beide passenden Traktoren für die Session → ab 14:12 „keine Kombination passt",
  keine Feldarbeit mehr;
- Verkehr tony10900TTR (WP38) steckte 13 m daneben, irrte 15 min umher: 1× „25 m abseits … weiter vorn gesetzt",
  4× „10 m weiter auf die KI-Strasse gesetzt" (sichtbare Flüge), dann 3× sofort abgewiesen → Pool.
- WP38 schaut mit 172° (nach −Z) direkt auf Kartoffelfabrik/Landhandel (44–70 m voraus).

**Empfehlung an den User:** Spawnpunkte an durchgehender Hauptstraße außerhalb von Ort/Höfen neu setzen, WP37/WP38 danach löschen.
**Angeboten (Build 135):** Engstellen-Erkennung (Gespann nicht sperren, wenn schon ein anderes Fahrzeug ≤ 25 m davon
hing), Spawnpunkt-Bilanz bis zum ersten Ziel mit Pause nach 2 Fehlschlägen (solange ein anderer frei ist),
Rettungs-Teleports begrenzen (nach 2× „10 m weiter" ohne Fortschritt → Pool), „am Shop"-Texte korrigieren.


# ERGÄNZUNG 2026-09-17 — Build 135: echte Buttons im Reiter Wegpunkte

Anlass (Screenshot des Users): Die Aktionszeilen waren ``MultiTextOption`` mit einem einzigen Eintrag —
ausgelöst hat nur der kleine Pfeil ganz rechts, teils fehlte die Beschriftung.

**Umbau:** Prefab ``nfWpActionPrefab`` enthält jetzt einen ``Button`` (Profil ``nf_wpActionButton``) mit
``ThreePartBitmap`` (``nf_wpActionButtonBg`` = ``fs25_multiTextOptionBg``) und Tooltip-Text. Verifiziert:
- ``ButtonElement:mouseEvent`` löst bei Klick irgendwo in der Fläche aus (sendAction beim Loslassen).
- Eigene Profile: ``gui/NachbarFelderGuiProfiles.xml`` per ``g_gui:loadProfiles`` (Gui.lua:241) vor ``loadGui``;
  Muster FS25_EasyDevControls (``edc_button`` + ThreePartBitmap-Kinder). Presets/Traits aus
  ``sdk/xmlDoku/guiProfiles.xml`` (fs25_colorMainLight/-Highlight, colorDisabled, anchorMiddleRight).
- Fokus/Auswahl gehen an die Kinder weiter (``GuiElement.updateChildrenState`` = true) → Rahmen wird grün.
- Größe/Lage wie ``fs25_settingsMultiTextOption`` (280×36 px, anchorMiddleRight, −10 px).
Beschriftung: ``NachbarFelderWaypointPage.BUTTON_TEXT`` (l10n ``NF_wpBtn_*``: Zurück/Weiter/Teleportieren/Löschen/Setzen),
Typ-Button zeigt die aktuelle Kategorie. Zeilentitel mit echten Umlauten („Nächster Wegpunkt", „Typ ändern").
Inline-``<GuiProfiles>`` in der GUI-XML (Gui.lua:285) bewusst NICHT genutzt — keine Mod als Beleg gefunden.

**build.py:** Liste um ``gui/NachbarFelderGuiProfiles.xml`` erweitert → jetzt **14 Dateien**.
ZIP: ``Codex\FS25_NachbarFelder_Build135.zip`` — NICHT deployed. Die Vorschläge aus dem Servertest 134
(Engstellen, Spawnpunkt-Bilanz, Teleports begrenzen) sind noch offen.


# ERGÄNZUNG 2026-09-19 — Build 136: Einbahn-Splines, Pool ohne eigene Wegpunkte

Anlass: „auf der neuen Map Bergisch Land fahren sich die Helfer fest" (Server-Log 19.09. 16:42, Build 135,
Server = VMware-Maschine, Profil <Serverprofil>, 0 eigene Wegpunkte, 53 Straßenziele).

**Befund Log:** alle Ladeplätze am Shop (x=-465/3, -478/11, -376/38) sofort abgewiesen (AIMessageErrorNotReachable
35–70 ms) → Rettungs-Teleports; Ziel WP50 von WP10, WP35 und WP13 aus jeweils sofort abgewiesen; WP35 von WP10
erreichbar, von WP13 nicht. Pool-Schläfer (farmall+Volto, crystal) blieben auf der Straße am Shop, neue Fahrzeuge
wurden 7–9 m dahinter geladen und standen („30s ohne Bewegung … naechstes Fahrzeug … in 7 m"). Pool wurde nie
geweckt (Aktiv 3/4, 4/4 mit 2 Schläfern → frisch geladen).

**Ursache 1 — Einbahn-Splines:** Bergisch Land `maps/map.i3d`: Knoten `ai` (nodeId 24123, onCreate
AISystem.onCreateAIRoadSpline, keine maxWidth/maxTurningRadius → Defaults 6/20 m), 130 Splines, 61 von 68
Basis-Splines mit „R"-Zwilling → Richtung zählt. Die Mod drehte Ladeplatz (setzeLadepositionStrasse),
GOTO-Zielrichtung (Status 1.5), Legacy-Platzierung (onSpawnedVehicle), Spawnpunkt-Snap, nfRoadSnap und
Feldhelfer-Rettung um 180°, wenn die Spline nicht Richtung Ziel zeigte → gegen die Einbahn.
**Fix:** ``getRoadPointInRichtung(x, z, maxDist, minDist, wantDx, wantDz)`` — nächster Punkt mit ≤60° Abweichung
(Zwillingsspur), sonst nächster Punkt mit eigener Richtung, nie gedreht; an allen 6 Stellen. Ladeplatzsuche in
2 Durchgängen (erst Spuren Richtung Ziel, dann übrige), Spawnpunkt auf Einbahn in Gegenrichtung → mit der Spur
ausrichten + einmaliger Hinweis. Nur Parkpunkte ohne KI-Straße ≤20 m werden weiter nach Anfahrt gedreht.

**Ursache 2 — Pool:** ``wakePooledVehicle`` verlangte ≥3 EIGENE Wegpunkte → mit 0 eigenen nie geweckt. Jetzt
``#getPatrolWaypointList() >= 3`` (eigene + Straßenziele).

**Ursache 3 — Ladeplatz hinter Hindernis:** Ladeplatz braucht jetzt 6–26 m voraus frei
(``isSpotBlockedByAnyVehicle(rx + dir*16, rz + dir*16, 10)``).

**Texte:** „Spawn bleibt am Shop"/„kuppeln am Shop"/„Gespann startet am Shop" → „am Ladeplatz"; nfRoadSnap nennt
den Versatz („28 m weiter vorn auf die KI-Strasse gesetzt") statt fälschlich „stand 28 m abseits".

**Offen:** Feldarbeit auf Bergisch Land: 0 geeignete Felder, 83 von 138 als „bebaut" (``getBebauteFarmlands``
zählt jedes Placeable auf dem Farmland, auch Zäune/Hecken/Deko; 119 Farmlands). Vorschläge aus Test 134
(Engstellen-Erkennung, Spawnpunkt-Bilanz, Teleport-Begrenzung) weiter offen.
ZIP: ``Codex\FS25_NachbarFelder_Build136.zip`` (14 Dateien) — NICHT deployed.


# ERGÄNZUNG 2026-09-21 — Build 137: „bebaut" je Feldumriss statt je Farmland

Anlass: Übergabe aus der Sitzung „Bergisch Land Spielweise" — Feldarbeit findet auf Bergisch Land 0 Felder
(Server-Log Build 135: 83 von 138 Feldern „bebaut", 119 Farmlands mit Bebauung).

**Ursache:** ``getBebauteFarmlands`` markierte ein ganzes Farmland, sobald IRGENDEIN Placeable mit seinem rootNode
darauf stand. Bergisch Land hat 968 Karten-Placeables; im Spiel sind 710 davon ``simplePlaceable`` (456 Laub-/
Nässe-Effekte aus FS25_placeableWeatherEffects, 183 farmDecorationPack …), 36 ``newFence``. Ein Typ-Filter hätte
also nicht gereicht (Effekte und Deko-Häuser haben denselben Typ).

**Offline-Nachweis** (map.i3d-Feldumrisse gegen placeables.xml, Grundflächen aus den Placeable-XML/i3d):
- Bergisch Land: 138 Felder (0,15–4,19 ha, Summe 187,7 ha); **kein** rootNode liegt in einem Feld; Grundflächen
  berühren 2 Felder (Feld 98 Kuhstall PolishOldCowShed01 ~0 m, Feld 126 Schweinestall chlewnia 0,5 m tief);
  keine der 8 Kuhweiden und keine Zaun-/Heckenlinie ragt in ein Feld.
- Beuren (95 Felder) und Krebach (103 Felder): kein rootNode in einem Feld, keine Zaunlinie im Feld. Krebach
  Feld 49 enthält den Kartenursprung, dort sitzen die rootNodes von Zug, Zäunen und Hecken → solche rootNodes
  sind bedeutungslos.

**Fix (NachbarFelderManager.lua):**
- ``getBebauteFelder()`` ersetzt ``getBebauteFarmlands()``, liefert ``field → Name des Hindernisses``, Cache
  5 Minuten wie bisher. Ein Feld ist bebaut, wenn ein Hindernis-Punkt ≥ ``BEBAUT_MIN_TIEFE`` (1,0 m) innerhalb
  des Feldumrisses liegt (Punkt-in-Polygon + Randabstand). Suchraster 50 m (``BEBAUT_ZELLE``).
- ``getPlaceableHindernis(p)`` (gecacht, schwache Schlüssel): rootNode (nicht im Ursprung), Raster über jede
  Grundfläche ``spec_placement.testAreas`` (Punktabstand ≤ 8 m, ``BEBAUT_RASTER``), bei ``spec_newFence``/
  ``spec_fence``/``spec_husbandryFence`` die Zaunlinie (``getFence():getSegments()``). Ohne Kollision
  (``pickObjects`` leer) zählen nur Zaunpunkte; ``spec_trainSystem`` wird übersprungen.
- ``getFeldPolygon(field)``: ``field.polygonPoints`` → Weltkoordinaten, einmal je Feld.
- ``isFieldUseful`` und ``logFeldStatistik`` fragen ``bebaut[field]``. ``isPunktInWeide`` bleibt für Felder, die
  ganz in einer Weide liegen.
- Log (erstes Mal und bei Änderung der Zahl): ``NachbarFelder: n Felder bebaut (Hindernis mind. 1 m im Feld) -
  werden ausgelassen: Feld x (Name), … [p Placeables mit Hindernis-Punkten, q ohne Kollision/uebersprungen]``.

**Verifiziert im Spielcode:** Field.lua:36/82 (polygonPoints), PlaceablePlacement.lua:145-165 (testArea
start/endNode, endNode direktes Kind), Placeable.lua:246/742/1436 (pickObjects = RigidBody-Knoten),
PlaceableNewFence.lua:30/88/109 + PlaceableHusbandryFence.lua:34/156 (getFence, beide ``Fence.new``),
PlaceableFence.lua:151, PlaceableTrainSystem.lua:119, SpecializationUtil.lua:243 (typeName).

**Tests:** lsc.py + Vollparse sauber. Die neuen Lua-Funktionen liefen in lupa gegen die echten Bergisch-Land-
Daten (alle 968 Placeables, Worst Case „alle mit Kollision"): 1,0 m → 0 Felder, 0,4 m → Feld 126. Synthetische
Fälle: Halle mitten im Feld → bebaut, Stall 3 m im Feld → bebaut, Zaun quer durchs Feld → bebaut, Laub ohne
Kollision → frei, Stall streift 0,5 m → frei, Schienennetz ignoriert.

**Prüfskripte** (für die nächste Karte): ``NachbarFelder\tools\feld_footprint.py <Map-ZIP>`` (Umrisse,
Grundflächen, Weiden) und ``NachbarFelder\tools\feld_bebaut_tiefe.py <Map-ZIP>`` (Eindringtiefe je Feld,
Sperren je Schwelle). Die referenzierten Placeable-Mods müssen im Mods-Ordner liegen, sonst fehlen deren
Grundflächen (bei Beuren derzeit der Fall, rootNodes und Zäune sind trotzdem geprüft).

ZIP: ``Codex\FS25_NachbarFelder_Build137.zip`` (14 Dateien, 240.460 Bytes) — NICHT deployed.


## Build 138 (2026-09-24) - Helfer-Farm automatisch
- `getEffectiveFarmId()` waehlt beim ersten Aufruf (Server, lazy) und merkt sich die Wahl bis Neustart: Konfig `farmId` (>0, Farm existiert, keine Spieler) -> hoechste Farm ohne Spieler, ohne Farmland (`getOwnedFarmlandIdsByFarmId`), ohne Placeables (`placeableSystem.placeables` + `getOwnerFarmId`) -> hoechste Farm ohne Spieler -> sonst Spectator + Warnung (Helfer starten nicht).
- Spieler-Erkennung wie AgrarOekonomie: `farm.players`/`userIds`/`activeUsers`; ohne bekannte Liste wird die Farm NICHT genommen.
- Alle Hooks (addMoney, Farmland, MissionWork) nutzen weiter `self.farmId` - keine weitere feste 2 im Code.
- Bestehende Server-Konfig hat den Schluessel nicht -> automatisch. Test: im Server-Log die Zeile `Helfer-Farm = 6 'Raufutterhandel' (automatisch (leere Farm) ...)`.


# ERGÄNZUNG 2026-10-01 — Build 139: Auftrag an den Lohnunternehmer

Anlass: Wunsch des Users — der Spieler steht an einem Feld und beauftragt die NachbarFelder-Helfer, genau dieses
Feld zu bearbeiten, auch wenn es ihm selbst gehört. Eingabe-Aktion plus Zeile im Reiter Wegpunkte, MP-tauglich.

**Bedienung**
- Taste „NachbarFelder: Lohnunternehmer für dieses Feld beauftragen“ (`NF_ORDER_FIELD`, Standard **Strg+Alt+J**)
  oder ESC → Einstellungen → Wegpunkte → Abschnitt **Lohnunternehmer** → „Dieses Feld bearbeiten lassen“ (Button
  „Beauftragen“). Der Button ist für alle Spieler aktiv, die Rechte prüft der Server.
- Ergebnis: Ingame-Meldung und 8 s lang in der Infozeile des Reiters (das Menü verdeckt Meldungen).

**Regeln (Server)**
- Feld: Farmland unter der Position → `farmland.field`; sonst das nächste Feld nach Umriss (`getFeldPolygon`,
  Punkt im Umriss = 0 m, sonst Randabstand), höchstens `NachbarFelderAuftrag.MAX_ABSTAND` = 25 m.
- Besitz über `g_farmlandManager:getFarmlandOwner(farmland.id)` (liest `farmlandMapping`, bleibt vom temporären
  Helfer-Besitz `farmland.farmId` unberührt):
  - eigenes Feld (Besitzer = Farm des Absenders): Recht `hireAssistant` per
    `g_currentMission:getHasPlayerPermission("hireAssistant", connection, farmId)` — dieselbe Prüfung wie
    `AIJobFieldWork:getIsStartable`; prüft zugleich, dass der Absender zu der Farm gehört. Admin geht immer.
  - freies Feld: nur Admin (`getIsConnectionAdmin`, wie „Helfer sofort starten“).
  - Feld einer anderen Farm: immer abgelehnt, auch für Admins.
  - SP / eigener Host: lokaler Aufruf ohne Verbindung → gilt als berechtigt (Konvention `getIsConnectionAdmin(nil)`).
- Dann dieselben Sicherheitsprüfungen wie `isFieldUseful`, nur ohne „gehört einer Farm“ und ohne Cooldown:
  Mod aus, Helfer schon auf dem Feld, `nachbarFelderSperre`, angenommener Vertrag, bebaut, Weide, < 0,3 ha, Grünland.
- Arbeit über `getFeldAktion`: nur Pflügen (3) oder Grubbern (4) wie seit Build 125; Pflügen aus → Grubbern;
  Frucht steht / schon bearbeitet / unklar → abgelehnt mit eigenem Text.
- Start wie `generateWorkMission`: Helfer-Grenze `MAX_ASSISTANT_WORKERS`, Spawnpunkte belegt → „Händlerplatz belegt“,
  dann `createMission`. Der Worker bekommt `istAuftrag = true` und `auftragFarmId`.
- Feldbesitz während der Arbeit: unverändert der bestehende Trick (`farmland.farmId` = Helfer-Farm, Original in
  `origFarmlandId`/`origIsOwned`, Rücksetzen an allen bekannten Stellen, `saveSavegame`-Hook). Bei eigenen Feldern
  ist der Originalbesitzer die Spieler-Farm — wird genauso zurückgesetzt.

**Multiplayer**
- `NachbarFelderAuftragEvent` (neue Datei `NachbarFelderAuftrag.lua`), eine Klasse für beide Richtungen wie
  `AIJobStartRequestEvent`: Client → Server `x`, `z` (Float32), Farm-ID (`streamWriteUIntN`,
  `FarmManager.FARM_ID_SEND_NUM_BITS`); Server → Absender `ok`, Text-Key, Feld-Nr., Arbeits-Key
  (`connection:sendEvent`). Die Richtung entscheidet `connection:getIsServer()`.
- Der Server sucht das Feld selbst; der Client schickt nur Position und eigene Farm, die Farm wird über das Recht
  `hireAssistant` gegengeprüft.

**Savegame**
- `NachbarFelder.xml`: `worker(?)#auftrag` (bool) und `#auftragFarmId` (int), im Schema registriert. Beim Laden geht
  ein Auftrag über `NachbarFelderAuftrag.starteGespeichert` statt `startSavedMission` (das würde eigene Felder als
  „gehört einer Farm“ verwerfen). Besitz und Feldzustand werden neu geprüft (Feld verkauft → verworfen), Rechte nicht.
  Belegter Händlerplatz oder Helfer-Grenze → nächster Takt.

**Kartenunabhängig:** keine Koordinaten, keine Feldnummern; Feldsuche nur über Farmland-Karte und Feldumrisse.

**Feldnummer — es gibt nur eine (Stolperfalle, nicht nochmal suchen):**
- Feldnummer ist **immer `field:getId()`** (`NachbarFelderManager:getFeldNummer(field)`). Das ist die Nummer auf der
  Karte und in den Vertragsmeldungen, und genau sie erwartet `g_fieldManager:getFieldById`. Beleg im Spielcode:
  `FieldManager:saveToXMLFile` schreibt `field:getId()`, `loadFromXMLFile` liest mit `getFieldById`; dasselbe bei
  `AbstractFieldMission` (Spielstand und Netzwerk); `AbstractFieldMission:getFarmlandId()` liefert `field:getId()` —
  die Feldnummer ist die Farmland-Nummer (`FieldManager.farmlandIdFieldMapping[farmland.id]`).
- Der **Listenplatz in `getFields()` ist keine Feldnummer.** Farmland-Nummern können Lücken haben, die Feldliste
  nicht. Alle Schlüssel der Mod (`vehicleType`, `feldSperre`, `fieldCooldown`, `worker#fieldId` im Spielstand,
  `nachbarFelderSperre <Nr>`) sind die Feldnummer — dort war nichts umzurechnen.
- **Warum die Zufallswahl falsch war:** `generateWorkMission` zog `math.random(1, #getFields())` und gab das an
  `getFieldById`. Bei 100 Feldern mit Nummern bis 140 kamen die Felder 101–140 nie dran, und Nummern ohne Feld waren
  Fehlversuche. Jetzt: zufälliger Eintrag aus der echten Liste (`getFeldNummern()`), davon `getId()`.
- Ebenso falsch waren (behoben): `logFeldStatistik` (`fid` = Listenplatz → belegt/gesperrt am falschen Feld gezählt),
  die Liste „n Felder bebaut … : Feld x“ in `getBebauteFelder` und `NachbarFelderAuftrag.getFeldId` (suchte den
  Listenplatz → „Kein Feld in der Nähe“, obwohl man im Feld stand). `NachbarFelderWorker.lua` war sauber.
- Fallback nur für eine Spielversion ohne `getId`: `field.fieldId`/`field.id`, zuletzt der Listenplatz.
- Alte Spielstände: ein `worker`-Eintrag, dessen Nummer kein Feld trifft, wird mit Log-Zeile verworfen
  (`Gespeicherter Auftrag verworfen - Feld n gibt es auf dieser Karte nicht`), statt abzubrechen.
- `nachbarFelderSperre <Feldnummer wie auf der Karte> [aus]` prüft jetzt, ob es das Feld gibt.

**Verifiziert** (LUADOC-Repo `umbraprior/FS25-Community-LUADOC`, die Webseite war gesperrt):
`FarmlandManager:getFarmlandAtWorldPosition` / `getFarmlandOwner` / `NO_OWNER_FARM_ID`, `Farmland.field` und
`FieldManager:loadMapData` (`farmland:setField(field)`), `field:getId()` / `getFieldById` (siehe Feldnummer oben),
`AIJobStartRequestEvent` (Muster Event, `streamWriteUIntN`,
`FarmManager.FARM_ID_SEND_NUM_BITS`, `connection:sendEvent`), `AIJobFieldWork:getIsStartable`
(`getHasPlayerPermission("hireAssistant", connection, farmId)`), `g_currentMission:getFarmId()` und
`g_localPlayer.farmId` (Verwendung im Spielcode). `XMLFile:getValue` mit Default bewusst nicht genutzt (nicht belegt).

**Warum eigene Klassen-Tabelle:** `addSpecialization` lädt `NachbarFelderManager.lua` ein zweites Mal und legt die
globale Tabelle neu an. Methoden aus einer anderen Datei wären danach am globalen `NachbarFelderManager` weg. Deshalb
`NachbarFelderAuftrag.*(mgr, ...)`; die Polygon-Helfer sind als `NachbarFelderManager.nfPunktInPolygon` /
`.nfRandAbstand` in der Manager-Datei selbst eingetragen und über die Instanz erreichbar.

**Geändert:** `NachbarFelderAuftrag.lua` (neu), `NachbarFelder.lua` (source + Taste), `NachbarFelderManager.lua`
(BUILD 139, Helfer-Export, Speichern/Laden, gespeicherte Aufträge in `generateWorkMission`),
`NachbarFelderWaypointPage.lua` (Abschnitt + Button `nfAuftragHier`), `modDesc.xml` (Aktion, Taste, Beschreibung
de/en/fr), `l10n_de.xml`/`l10n_en.xml` (`input_NF_ORDER_FIELD`, `NF_auftrag*`), `build.py` (**15 Dateien**).

**Tests:** lsc.py + Vollparse (lupa) aller Lua-Dateien sauber, XML mit minidom. Logiktest mit nachgebauter Engine
(lupa): Feld im Umriss / 20 m daneben / 100 m weg, eigenes Feld mit und ohne Recht, doppelt beauftragt, freies Feld
mit und ohne Admin, fremde Farm (auch als Admin), Frucht steht, Helfer-Grenze, SP lokal, gespeicherter Auftrag
fortgesetzt bzw. nach Verkauf verworfen, Event Client → Server → Client mit Meldung. Probe-Build: 15 Dateien.

**Testplan im Spiel**
1. SP: auf eigenem abgeerntetem Feld Strg+Alt+J → „Auftrag angenommen – Feld n wird gepflügt/gegrubbert“, Helfer
   kommt vom Händler, bearbeitet das Feld; danach in der Karte wieder eigener Besitz. Log:
   `[AUFTRAG] Feld n fuer Farm 1 gestartet`.
2. Auf Feld mit Frucht → „Auf Feld n steht Frucht“. Auf der Straße fern jedes Felds → „Kein Feld in der Nähe“.
3. Speichern während der Arbeit, neu laden → `[AUFTRAG] Gespeicherter Auftrag auf Feld n fortgesetzt`, `farmland.xml`
   ohne Helfer-Farm.
4. Dedi: Nicht-Admin auf eigenem Feld (mit Recht „Helfer einstellen“) → angenommen; freies Feld → „nur als Admin“;
   Feld einer anderen Farm → abgelehnt.
5. Taste Strg+Alt+J auf Kollision prüfen (Steuerung → „NachbarFelder: Lohnunternehmer …“).

**Offen / Ideen:** Kosten für den Auftraggeber (Lohnunternehmer-Preis je ha) gibt es noch nicht — Helfer-Jobs laufen
weiter kostenlos über die Helfer-Farm. Keine Rückmeldung an den Auftraggeber, wenn die Arbeit fertig ist (nur Log).
Aufträge ohne Spieler online: es gilt wie bisher `stopAllHelpers`. Säen/Düngen/Ernten bleiben wie seit Build 125 aus.


# ERGÄNZUNG 2026-10-01 — Build 140: Messpunkte nur im Feldumriss

Anlass (User-Test Build 139): Lohnunternehmer-Auftrag auf Feld 54 immer abgelehnt mit „Auf Feld 54 steht Frucht“,
obwohl dort keine Frucht stand.

**Ursache:** `getFeldAktion` misst Feldmitte plus 16 Punkte auf zwei Ringen (Radius 0,2 bzw. 0,42 × √Fläche). Die
Ringpunkte wurden nur gegen „gleiches Farmland“ geprüft, nicht gegen den Feldumriss. Bei langen, schmalen oder
verwinkelten Feldern liegen sie neben dem Feld — auf Gras-/Wiesenstreifen desselben Farmlands. Gras zählt als wachsende
Frucht, und ein einziger Fruchtpunkt macht das Feld tabu. Betraf auch die normale Feldwahl und die Feldarbeit-Statistik
(„mit stehender Frucht“ zu hoch).

**Fix:** Ringpunkte zählen nur, wenn sie im Feldumriss (`getFeldPolygon`) und mindestens
`NachbarFelderManager.MESSPUNKT_RANDABSTAND` = 2 m vom Rand liegen; ohne Umriss wie bisher. Das Log nennt die Zahl
der verworfenen Punkte („n ausserhalb des Feldumrisses verworfen“) und die gefundene Frucht. `getFeldAktion` liefert als
4. Wert Frucht + Zustand (z. B. `GRASS waechst`); die Auftrags-Meldung zeigt das: „Auf Feld 54 steht Frucht (GRASS
waechst) …“, das Auftrags-Log hängt die Messwerte an (`… abgelehnt …: NF_auftrag_frucht | 9 Messpunkte: …`).

**Test:** echte Funktionen aus dem Manager (lupa), Feld 200 × 20 m abgeerntet mit Grasstreifen daneben: alt
`frucht (GRASS)`, neu `abgeerntet → pflügen`, 14 Punkte außerhalb verworfen. Auftrags-Logiktest und Vollparse sauber.

**Falls es weiter auftritt:** die Log-Zeile `[AUFTRAG] Feld n … abgelehnt …` enthält jetzt Fruchtname und Messpunkt —
die liefern.


# ERGÄNZUNG 2026-10-01 — Build 141: Anfahrt über freien Feldrand, Abbruchgrund der Feldarbeit

Anlass (User-Test Build 140, Bergisch Land, Einzelspieler, Helfer-Farm 14): Auftrag Feld 47 (eigenes Feld, 2,49 ha,
Triticale abgeerntet). Der Helfer fuhr über fremde Felder/Weide zum Feld, kam an — und die Feldarbeit endete nach 0 s
(`Feldarbeit beendet Feld 47 (Laufzeit: 0s)`, Grubber `aresXL` gesperrt), danach Rückfahrt/Entfernen. Für den User sah
das aus wie „am Feld vorbeigefahren“.

**1. Anfahrt (behoben):** `getFeldZielpunkt` nahm den Straßenpunkt nächst der **Feldmitte** und fuhr gerade zur Mitte;
dazwischen lagen fremde Felder und eine Weide („Feldrand zur Strasse (124 m von der Strasse)“). Laut LUADOC nutzt die
KI-Fahrt die Besitz-Hooks nicht (`getIsOwnedByFarmAlongLine` nur in PlaceablePlacement, `getCanAccessLand…` im
Leveler) — der Weg wird über das Straßennetz bis zum Punkt nahe am Ziel und dann gerade gefahren. Also entscheidet
der Zielpunkt. Neu `getFeldZugang(field)`: Feldumriss alle `ZUGANG_RAND_SCHRITT` = 8 m abtasten, je Stelle die nächste
KI-Straße (≤ `ZUGANG_MAX_STRASSE` = 250 m), nach Abstand sortiert; gewählt wird die erste Stelle (max.
`ZUGANG_KANDIDATEN` = 120), deren gerader Weg Straße → Rand weder ein fremdes Feld (FieldState anderes Farmland) noch
eine Weide (`isPunktInWeide`) kreuzt und an der ein Ziel `ZUGANG_TIEFE` = 10 m (sonst 6/3 m) im Feld mit ≥ 2 m
Randabstand liegt. Kein freier Weg → nächste Stelle trotzdem, Log „kein freier Weg“. Ohne Umriss alte Logik.
Log: `Anfahrt Feld n -> Feldrand nahe KI-Strasse (x m von der Strasse, Weg frei)`.
Test (lupa, echte Funktionen): Feld mit fremdem Feld zwischen Südstraße und Feld → alt quer durch das fremde Feld,
neu Zugang von der Oststraße (160 m, frei, Ziel 10 m im Feld); zusätzlich Weide im Osten → Fallback Süd, „kein freier Weg“.
Zuerst prüfte der Code nur 25 Kandidaten — alle lagen an der blockierten Seite; deshalb 120.

**2. Feldarbeit 0 s (offen, Diagnose eingebaut):** Kein Grund im Log. Ausgeschlossen per LUADOC: `AIJobFieldWork:validate`
prüft nur das Fahrzeug, `AIVehicleUtil.getIsAreaOwned` fragt `getIsOwnedByFarmAtWorldPosition` und
`getIsMissionWorkAllowed` — beide liefern über unsere Hooks true. Neu: `setAIOnField` hängt wie `driveToField` einen
`job.stop`-Wrapper an (`lastFieldStopMsg` = AIMessage-Klasse), `onAIFieldWorkerEnd` loggt `Grund: …`; die Zeile
`FIELDWORK Feld=n` nennt Gespann-Position, ob sie im Feldumriss liegt, und die Felderkennung (`findClosestField`).
Nächster Test: Auftrag auf eigenem Feld, Zeilen `FIELDWORK Feld=` und `Feldarbeit beendet … Grund:` liefern.

**3. Nebenbefunde:**
- „Pflügen und Grubbern abgeschaltet“ bei der ersten Anfrage, danach ging es: **kein Fehler** — beide Arbeiten waren in
  den Einstellungen wirklich aus, der User hat sie zwischen den Anfragen im ESC-Menü eingeschaltet (User 01.10.).
- Helfer startete an einer Weide: selbst gesetzter Shop-Trigger hatte den Lieferplatz (`storeSpawnPlaces[1]`) verschoben —
  gewollt seit Build 96. Abhilfe für den User: Spawnpunkt setzen (hat Vorrang).


# ERGÄNZUNG 2026-10-01 — Build 142: Ladeplatz-Sperren dauerhaft, Kipp-Erkennung

Anlass (User-Test Build 141, Screenshot): Lohnunternehmer-Helfer für Feld 47 lag am Ladeplatz im Shop-Hof auf dem Dach
(zwischen Zaun, Baum und Ausstellungsfahrzeugen). Log: `wird direkt an der KI-Strasse geladen (70 m vom Shop-Platz)`,
60 s später `steht 60 s ohne Bewegung … bei x=-473 z=12`, `Ladeplatz x=-478 z=11 taugt nicht (Stillstand)`.
Derselbe Platz war schon in der Sitzung davor gesperrt worden (`… taugt nicht (Anfahrt abgebrochen)`) — die Sperre galt
nur je Session, nach dem Neustart wurde er wieder genommen. Die Werkstatt-Drehung (`Spawn-Blickrichtung`) ist es nicht:
bei Ladung an der KI-Straße wird sie nur berechnet/geloggt, nicht angewendet (`aufStrasse`).

**Fix:**
- `merkeSpawnFehlschlag` schreibt gesperrte Ladeplätze (x, z, Grund) in
  `modSettings/FS25_NachbarFelder/NachbarFelderLadeplaetze_<KartenId>.xml` (Schema `lpXmlSchema`, Muster wie die
  Wegpunkt-Datei); `ladeLadeplatzSperre` liest sie einmal je Sitzung (Server). Admin-Spawnpunkte werden weiterhin nie
  gesperrt. Wieder freigeben: Datei löschen.
- Kipp-Erkennung im `update`: Hochachse des Traktors (`localDirectionToWorld(root, 0, 1, 0)`) < `KIPP_GRENZE` = 0,3
  länger als 3 s → Log `… ist umgekippt bei x z (Status s) - wird entfernt`, Ladeplatz sperren (nur wenn ≤ 10 m vom
  Ladeplatz), Job stoppen, Status 100. Gilt für Feldhelfer und Verkehr.

**Test:** echte Funktionen (lupa, XMLFile nachgebaut): Sperre geschrieben, nach „Neustart“ (neue Instanz) geladen,
Platz gesperrt, anderer Platz frei. Strukturcheck und Vollparse sauber.

**Hinweis:** Die Sperrliste wächst nur; Verkehrs-Abweisungen sperren ebenfalls. Werden zu viele Plätze gesperrt, lädt die
Mod wie bisher am Shop-Platz des Spiels (`Kein freier Strassenplatz …`). Zuverlässigster Weg: eigener Spawnpunkt.


# ERGÄNZUNG 2026-10-01 — Build 143: Ladeplatz-Suche in Stufen, Auftrag neu einplanen

Vorgabe des Users: Das Spawnen muss auf allen Karten funktionieren — notfalls auf einem Straßenstück, wo Platz ist.
Test Build 142 (Log 14:50): Helfer wieder am Hof-Ladeplatz x=-478 z=11 geladen, nach ~5 s umgekippt, von der
Kipp-Erkennung entfernt, Platz dauerhaft gesperrt — für den User „kurz da, dann wieder weg“, der Auftrag war verloren.

**Ursache, kartenunabhängig:** Auch Höfe (Shop, Betriebe) haben KI-Splines. Die Prüfung bis Build 142 (17 × 4 m frei,
hinten Straße, voraus kein Fahrzeug) passt an einer Hofecke gerade noch.

**Fix `setzeLadepositionStrasse` / neu `getIstLadeplatzGut(sp, rx, rz, ry, h, streng)`:**
`LADEPLATZ_STUFEN`: 1) streng 40–250 m um den Shop-Platz, 2) streng 250–800 m, 3) locker 40–250 m (alte Prüfung),
dann wie bisher Shop-Platz des Spiels. Je Stufe höchstens `LADEPLATZ_MAX_PRUEFUNGEN` = 150 Stellen, je Stufe erst
Spuren Richtung Ziel, dann die übrigen. Streng heißt zusätzlich:
- gerade Straße: Stützpunkte bei −20/−10/+10/+20 m entlang der Spur vorhanden und Richtung ≤ ~25° abweichend
  (`LADEPLATZ_GERADE_COS` = 0,9; Gegenspur zählt) — keine Hofecke, keine enge Kurve;
- eben: Fahrbahnhöhe (`getFahrbahnHoehe`, Raycast) vorn, Gespannende und seitlich ≤ `LADEPLATZ_MAX_HOEHE` = 1,2 m;
- Platz: Kasten 30 × 5 m frei, reicht 13 m vor den Punkt (Raum zum Losfahren).
Log: `… wird direkt an der KI-Strasse geladen (n m vom Shop-Platz, freier Platz, Stufe s, k Stellen geprueft)`.

**Auftrag neu einplanen:** `planeAuftragNeu(w, grund)` — kippt ein Lohnunternehmer-Helfer am Ladeplatz, kommt der
Auftrag zurück in die Warteschlange (`loadVehiclesFromXML`, über `starteGespeichert`), höchstens
`AUFTRAG_MAX_NEUVERSUCHE` = 2 je Feld und Sitzung. Steht der alte Helfer noch (Prüfung „belegt“), bleibt der Eintrag in
der Schlange statt verworfen zu werden.

**Tests:** `getIstLadeplatzGut` mit echtem Code (lupa): gerade+eben+frei → ja; Kurve/Hofecke, Hang 15 %, vorn zugestellt
→ streng nein, locker ja. Auftrags-Logiktest, Strukturcheck, Vollparse sauber. Im Spiel noch ungetestet.


# ERGÄNZUNG 2026-10-01 — Build 144: gekippte Gespanne dauerhaft sperren, Auftrag pflügt ersatzweise

Test Build 143 (Log 14:58): Ladeplatz diesmal nach der strengen Prüfung (Stufe 1, x=-376 z=38, gerade/eben/30 × 5 m
frei) — trotzdem `arion550.xml ist umgekippt` 4,5 s nach dem Laden (3 s Kipp-Wartezeit → gekippt ~1–2 s nach dem
Laden, also beim Ankuppeln/Ausrichten). Zuvor dasselbe Gespann am Hof-Platz. Gespannwahl:
`Eigenes Feldgespann fuer cultivateMission: arion550.xml (145 PS, 6.6 t) + aresXL.xml (Bedarf 150 PS) - Auswahl aus
1 Geraeten, 1 Kombinationen` — jeder Grubber-Auftrag nimmt genau dieses Gespann. Vermutung: schwerer Anbaugrubber an
leichtem Traktor ohne Frontgewicht (Gewichtsregel `getPasstFeldGeraetZuTraktor`: Gerät ≤ 50 % Traktor, entfällt bei
unbekanntem Gerätegewicht). Nicht verifiziert — das Gerätegewicht stand nicht im Log.

**Fix:**
- Kipp-Erkennung sperrt bei Feldhelfern zusätzlich das Gespann dauerhaft: `sperreFeldGespannDauerhaft` →
  `modSettings/FS25_NachbarFelder/NachbarFelderGespannSperren.xml` (kartenunabhängig, Schema `gsXmlSchema`,
  Traktor-/Geräte-XML + Grund); `getIstFeldGespannGesperrt` lädt die Datei einmal (`ladeGespannSperren`). Freigeben:
  Datei löschen.
- Log der Gespannwahl nennt jetzt auch das Gerätegewicht (`Bedarf n PS, x t`).
- `NachbarFelderAuftrag.starte`: schlägt `createMission` für Grubbern ohne Platzproblem fehl (kein taugliches Gespann)
  und ist Pflügen an → Pflügen; Meldung/Log nennen die tatsächliche Arbeit.

**Tests:** Auftrags-Logiktest sauber; Fallback (Grubbern scheitert → `plowMission` gestartet, Meldung „gepflügt“).
Strukturcheck und Vollparse sauber. Im Spiel noch ungetestet.

**Nächster Schritt, falls auch das Pflug-Gespann kippt:** Gewichtsregel verschärfen (Anbaugerät ≤ 35–40 % des
Traktorgewichts, unbekanntes Gerätegewicht ablehnen) — erst mit den Gewichten aus dem neuen Log entscheiden.


# ERGÄNZUNG 2026-10-01 — Build 145: Gewichtsregel 40 %, Kippen sperrt keinen Ladeplatz mehr

Test Build 144 (Log 15:04): `arion550.xml (145 PS, 6.6 t) + aresXL.xml (Bedarf 150 PS, 3.1 t)` — erstmals mit
Gerätegewicht. 3,1 t = 47 % des Traktors, erlaubt waren 50 %. Wieder gekippt (dritter verschiedener, guter Ladeplatz
nach Stufe 1), Gespann dauerhaft gesperrt, Auftrag neu eingeplant — Log endet vor dem neuen Anlauf.

**Fix:**
- `getPasstFeldGeraetZuTraktor`: Gerät höchstens `FELD_GEWICHT_ANTEIL` = 0,40 des Traktorgewichts (vorher fest 0,5).
  Gilt nur für Feldhelfer; die Regel für Verkehr-Anbaugeräte (`getPasstGeraetZuTraktor`, leichte Geräte) bleibt 0,5.
- Kipp-Erkennung sperrt den Ladeplatz nicht mehr (dasselbe Gespann kippte auf drei verschiedenen guten Plätzen);
  Plätze sperren weiterhin Stillstand und „sofort abgewiesen“. `ladeLadeplatzSperre` verwirft vorhandene Einträge mit
  Grund `umgekippt` (aus Builds 142–144) und schreibt die Datei neu — Log `n Ladeplatz-Sperren wegen 'umgekippt'
  aufgehoben`.

**Tests (lupa, echte Funktionen):** Arion 6,6 t + 3,1 t → passt nicht, + 2,5 t → passt. Datei mit 3 Kipp-Sperren und
1 Stillstand-Sperre: nach Neustart Kipp-Plätze frei, Stillstand-Platz gesperrt. Strukturcheck und Vollparse sauber.

**Folge auf Bergisch Land:** Für Grubbern gab es nur dieses eine Gespann — jetzt evtl. gar keins; der Lohnunternehmer
pflügt dann (Build 144). Ob es ein Pflug-Gespann ≤ 40 % gibt, zeigt das nächste Log (`Eigenes Feldgespann fuer
plowMission … t` bzw. `Kein eigenes Feldgespann …`).


# ERGÄNZUNG 2026-10-01 — Build 146: Ausweich-Zugänge bei „kein Pfad“

Test Build 145 (Log 15:13): 40-%-Regel greift — `Kein eigenes Feldgespann fuer cultivateMission … keine Kombination
passt`, Auftrag weicht aufs Pflügen aus: `seriesTJW.xml (123 PS, 4.6 t) + juwel6.xml (Bedarf 110 PS, 1.1 t)` (24 %),
**kein Kippen**. Die 3 alten Kipp-Sperren der Ladeplätze wurden aufgehoben. Neues Problem: `Anfahrt Feld 47 -> Feldrand
nahe KI-Strasse (19 m …, kein freier Weg …) x=-428 z=-423` → `GOTO kein Pfad (3044ms, AIMessageErrorNotReachable) …
Fahrzeug wird am Shop entfernt`. Feld 47 hat keinen freien Zugang; Build 141 nahm dann die straßennächste Stelle, deren
Weg offenbar über eine Weide (Zaun) führt. Mit der alten Zielwahl (Build 140) war der Helfer bis Feld 47 gekommen.

**Fix:**
- `getFeldZugang(field, ausschluss)` stuft jeden Zugang ein: 0 = Weg frei, 1 = kreuzt nur fremde Felder (befahrbar),
  2 = kreuzt eine Weide (`isPunktInWeide`). Gewählt wird die niedrigste Klasse, darin die nächste Straße. Ziele im
  Umkreis `ZUGANG_AUSSCHLUSS_M` = 80 m um schon gescheiterte Ziele werden übersprungen.
- `getFeldZielpunkt` liest den Ausschluss vom Worker (`zugangAusschluss`), merkt das gewählte Ziel (`zugangZiel`);
  ohne Kandidat greift wie bisher die alte Zielwahl (Straße nächst der Feldmitte). Log nennt die Wegklasse und
  `(Zugang-Versuch n)`.
- `NachbarFelderWorker:onAIJobFinished`, Zweig „GOTO kein Pfad“: Feldhelfer mit `zugangZiel` und weniger als
  `ZUGANG_MAX_VERSUCHE` = 3 Versuchen → Ziel in den Ausschluss, Status 1 + Timer (wie „neuer Anlauf“), die
  Update-Schleife plant mit dem nächsten Zugang neu. Log `GOTO kein Pfad … - anderer Zugang wird versucht (n/3)`.
  Erst danach wie bisher entfernen + Feld-Cooldown.

**Tests (lupa, echte Funktionen):** freier Zugang → Klasse 0; Ost über Weide, Süd über fremdes Feld → Süd (Klasse 1);
Folge mit Ausschluss: Süd → Süd andere Ecke → Ost (Klasse 2) → alte Zielwahl. Strukturcheck und Vollparse sauber.


# ERGÄNZUNG 2026-10-01 — Build 147: Felderkennung der KI ohne Besitzprüfung

Test Build 146 (Log 15:22): Pflug-Gespann `vestrum130.xml (110 PS, 5.5 t) + juwel6.xml (1.1 t)`, Anfahrt über
`Weg kreuzt fremdes Feld` — **Helfer kam auf Feld 47 an**: `FIELDWORK Feld=47 (plowMission) | Gespann x=-428 z=-421
im Feld: ja | Felderkennung x=-429 z=-421`, dann 1 ms später `Feldarbeit beendet Feld 47 (Laufzeit: 0s, Grund:
unbekannt)`. Gleiches Bild wie mit dem Grubber-Gespann in Build 140 — es liegt am Feld, nicht am Gespann.

**Analyse (LUADOC `AIDriveStrategyFieldCourse`):**
- `setAIVehicle`: ohne `AIDriveStrategyFieldCourse.fieldDetectionPosition` →
  `FieldCourse.findClosestField(nil, nil, nil, nil, vehicle:getAIJobFarmId(), vehicle, 2, settings)`; ist der dritte
  Rückgabewert `notOwned` true → `fieldNotOwned`, kein Kurs.
- `getDriveData` (nächstes Update, gleicher Frame) → `stopCurrentAIJob(AIMessageErrorFieldNotOwned)`.
- `FieldCourse.findClosestField` selbst steht nicht in der LUADOC — wie `notOwned` entsteht, ist nicht belegt. Vermutung:
  über `farmlandMapping` (bleibt beim Feldbesitz-Trick der Mod auf der Spielerfarm), auf herrenlosen Feldern greift die
  Missions-Erlaubnis. Passt dazu, dass nur das eigene Feld 47 scheitert.
- „Grund: unbekannt“: `onAIFieldWorkerEnd` kam offenbar vor dem `job.stop`-Wrapper.

**Fix:**
- `setAIOnField`: vor `aiSystem:startJob` `AIDriveStrategyFieldCourse.fieldDetectionPosition = {fieldDetectionX,
  fieldDetectionZ}` (nur wenn nicht schon gesetzt), danach sofort wieder `nil`; Start in `pcall`. Log-Zusatz
  `| Felderkennung ohne Besitzpruefung`.
- `job.stop`-Wrapper loggt sofort `FIELDWORK Feld n gestoppt: <AIMessage> (nach x ms)`.
- `NF_AI_MSG_CLASSES` um `AIMessageErrorFieldNotReady`, `AIMessageErrorVineyardNotSupported` ergänzt.

**Unverifiziert** — im Spiel testen. Erwartung: Pflügen auf Feld 47 läuft; falls nicht, nennt die neue Zeile
`FIELDWORK Feld 47 gestoppt: …` den Grund.


# ERGÄNZUNG 2026-10-01 — Build 148: Hindernis über der Fahrbahn, Kipp-Regel neu, Spawnpunkt-Hinweis

Test Build 147 (Log 15:32): leichtes Gespann `vario500.xml (131 PS, 6.4 t) + juwel6.xml (1.1 t)` (17 %) kippte auf
x=-365 z=28 — demselben Platz, auf dem um 15:04 Arion + Ares XL gekippt war. Übersicht aller Ladungen nahe dem Shop:
gekippt an -478/11 (2×), -376/38, -363/29 (2× mit zwei verschiedenen Gespannen); ohne Kippen am „76 m“-Platz
(Series TJW, Vestrum). **Die Gewichts-Theorie aus Build 144/145 war nicht die (alleinige) Ursache — es sind bestimmte
Plätze.** Erster Screenshot: Traktor lag unter einem großen Baum.

**Ursache (Vermutung, plausibel):** `getFahrbahnHoehe` tastet von Bezugshöhe + 3 m nach unten und nimmt den ersten Treffer
inkl. `STATIC_OBJECT`/`BUILDING` — eine Baumkrone oder ein Dach über der Straße liefert eine zu hohe Ladehöhe, das
Gespann wird oben abgesetzt und stürzt.

**Fix:**
- `getFahrbahnHoehe(x, z, splineH)` liefert zusätzlich `ueberkopf`: mit Spline-Höhe und Treffer mehr als
  `HOEHE_UEBERKOPF` = 1,0 m über max(Gelände, Spline) → Bezugshöhe zurück, `ueberkopf = true`. Ohne Spline-Höhe (Admin-
  Spawnpunkt, evtl. Brücke) unverändert.
- `getIstLadeplatzGut` (streng und locker): Platz abgelehnt, wenn bei +3/0/−5/−10/−15 m entlang der Spur etwas über der
  Fahrbahn ist.
- Kippen: Platz wieder sperren (Grund `umgekippt (Platz)`); Gespann dauerhaft erst, wenn es an zwei Plätzen > 30 m
  auseinander kippte (`gespannKippOrte`, Grund `umgekippt an 2 Plaetzen`). Beim Laden werden alte Gespann-Sperren mit Grund
  `umgekippt` (Builds 144–147, u. a. Vario 500 + Juwel 6) verworfen; alte Platz-Sperren `umgekippt` (Build 142–144) wurden
  schon in Build 145 verworfen.
- Wunsch des Users (Spieler wählt den Platz): Spawnpunkte gibt es seit Build 132 und sie haben Vorrang. Neu:
  `hinweisSpawnpunkt` — beim ersten gescheiterten automatischen Ladeplatz ohne Spawnpunkt einmal eine Ingame-Meldung
  (SP/Host, `NF_hinweisSpawnpunkt`) und eine Log-Zeile; im Reiter Wegpunkte, Abschnitt Lohnunternehmer, zusätzlich die
  Zeile „Spawnpunkt hier setzen“ (`nfAuftragSpawnHier`, nur Admin).

**Tests (lupa, echte Funktionen):** Höhe unter Baum → Bezugshöhe + `ueberkopf`; Platz unter Baum streng und locker
abgelehnt, ohne Baum angenommen; ohne Spline-Höhe Treffer wie bisher. Strukturcheck, Vollparse, XML sauber.


# ERGÄNZUNG 2026-10-01 — Build 149: toggleAIVehicle entfernt, falsche Ende-Meldungen ignorieren

Test Build 148 (Log 15:39): Spawnpunkt WP1 vom User gesetzt und genutzt (`wird am Spawnpunkt WP1 geladen`), Feldhelfer
kippte nicht; Ausweich-Zugang griff (`GOTO kein Pfad … anderer Zugang wird versucht (1/3)`, dann Zugang 2), Helfer kam
auf Feld 47 an. Feldarbeit wieder 0 s — **und die Zeile `FIELDWORK Feld 47 gestoppt: …` aus dem job.stop-Wrapper fehlt**:
unser Auftrag wurde gar nicht über `job:stop` beendet. (Nebenbei: Verkehrs-Lintrac kippte am Spawnpunkt WP1 — Hinweis
im Log, Spawnpunkte werden nie gesperrt.)

**Analyse (LUADOC):** `AISystem:startJob` → `startJobInternal` → `AIJob:start` setzt nur `currentTaskIndex = 0`; der
Teilschritt `AITaskFieldWork:start` → `vehicle:startFieldWorker()` läuft erst im nächsten `AIJob:update`. Jedes reguläre
Ende geht über `aiSystem:stopJob` → `job:stop`. Das „Feldarbeit beendet“ 1 ms nach `startJob` kann also nicht von unserem
Auftrag stammen. Direkt davor rief `setAIOnField` `vehicle:toggleAIVehicle()` — in FS25 `AIJobVehicle:toggleAIVehicle`,
die **Helfer-Taste des Spielers**: ohne aktiven Helfer `AIJobStartRequestEvent` für den „startbaren“ Auftrag des
Fahrzeugs über `g_client` (bzw. Helfer-Menü öffnen). Das startete einen zweiten Auftrag, der unsere Feldarbeit
verdrängte. Auf dem Dedi gibt es kein `g_client` (Fehler). Vermutlich ein FS22-Rest.

**Fix:**
- `toggleAIVehicle()` entfernt; gestartet wird nur über `aiSystem:startJob`.
- `onAIFieldWorkerEnd`: kommt die Meldung bei Status 2, während `tt.fieldWorkJob.isRunning` (AIJob:start/stop) true ist,
  wird nur geloggt (`Feldarbeit-Ende-Meldung … ignoriert - eigener Auftrag laeuft noch`).
- Felderkennung ohne Besitzprüfung (Build 147) hängt jetzt an `job.fieldWorkTask.start` (Instanz-Wrapper: setzen →
  Original → zurücksetzen). Build 147 setzte sie nur während `startJob` — dort wird sie noch nicht gelesen, wirkte also nie.
- `startJob` und Task-Start in `pcall` mit Log.

**Tests:** Mini-Gerüst nach LUADOC-Ablauf: Position beim Task-Start gesetzt, danach wieder frei. Strukturcheck, Vollparse.
**Unverifiziert im Spiel** — Erwartung: Feldarbeit auf Feld 47 läuft; sonst nennt `FIELDWORK Feld 47 gestoppt: …` den Grund.


# ERGÄNZUNG 2026-10-01 — Build 150: Alle Feldhelfer entfernt, nur noch Verkehr

**Anlass:** Build 149 (Feldarbeit 0 s) war noch ungetestet, da entschied der User: „Alle Feldhelfer raus“. Er fährt
seinen Trecker selbst ans Feld und startet dort den Helfer über eine andere eigene Mod. Übrig bleibt der Verkehr
(Patrouille zwischen Wegpunkten, Pool, Tagesrhythmus, Stammfahrzeuge, Ladeplatz-Suche, Spawnpunkte, Kipp-Erkennung).

**Entfernt**
- Datei `NachbarFelderAuftrag.lua` (Lohnunternehmer, Event `NachbarFelderAuftragEvent`), Eintrag in `build.py` (jetzt 14 Dateien).
- `NachbarFelder.lua`: `NachbarFelderStartEvent`, Registrierung von `NF_START_NOW` und `NF_ORDER_FIELD`, `source` der Auftragsdatei.
- `modDesc.xml`: Aktionen/Tasten `NF_START_NOW` (Strg+Alt+E) und `NF_ORDER_FIELD` (Strg+Alt+J); Beschreibung de/en/fr auf
  Verkehr umgeschrieben. modDesc-Version bleibt `1.1.42.0`.
- l10n de/en: `input_NF_START_NOW`, `input_NF_ORDER_FIELD`, alle `NF_auftrag*`. `NF_hinweisSpawnpunkt` bleibt (Ladeplatz-Hinweis).
- Reiter Wegpunkte: Abschnitt „Lohnunternehmer“ (`nfAuftragHier`, `nfAuftragSpawnHier`). „Spawnpunkt hier setzen“ gibt es
  weiter im Abschnitt „Neuer Punkt“.
- Einstellungen: Regler „Anzahl Arbeiter“ (`MAX_ASSISTANT_WORKERS`) und die Arbeitsarten (`missionHelper`). Die Werte
  laufen weiter durch Spielstand, Server-Konfig und Settings-Sync (Stream-Format unverändert, also keine
  Versionskonflikte zwischen Server und Client), wirken aber nicht mehr.
- Manager: Feldwahl (`isFieldUseful`, `getFeldAktion`, `getFruchtZustand`, Statistik, bebaut/Weide, Feldpolygon,
  Feldnummern), Feldarbeit (`setAIOnField`, `finishFieldState`, Saatwahl), Anfahrt (`getFeldZielpunkt`, `getFeldZugang`,
  Stillstand-Wächter Build 121), Gespannwahl (`getRandomVehicles`, `getEigenesFeldGespann`, Gespann-Sperren inkl.
  `NachbarFelderGespannSperren.xml`, starr/breit, Zugmaschine zu groß), `createMission`/`generateWorkMission`/
  `startSavedMission`, `planeAuftragNeu`, `onMissionStarted` (+ Abo `MissionStartedEvent`), Mähdrescher-Sonderfälle
  (Korntank, Schneidwerk-Wagen, Status 3/33/4), Feld-Cooldowns/-Sperren, Vorfrucht-Gedächtnis, Konsolenbefehle
  `nachbarFelderStart` und `nachbarFelderSperre`.
- Hooks: `MissionManager.getIsMissionWorkAllowed` und der `saveSavegame`-Schutz für den temporären Feldbesitz.
  **Behalten:** FarmlandManager-Hooks (`getCanAccessLandAtWorldPosition`/`AlongLine` sind Teil der GOTO-Wegsuche),
  `addMoney`, `getJobTypeIndex`, `FSBaseMission.delete`, `ItemSystem.save`.
- Worker: Feldhelfer-Zweige in `onAIJobFinished` (Rettung, Implement-Sperre, Zugangs-Wechsel, Feld-Cooldown),
  `onAIFieldWorkerEnd` (samt Event-Abo), Ernte-Spezialfall. Ein Eintrag ohne `isPatrol` wird jetzt sofort aufgeräumt
  (Status 100), falls je einer entsteht.
- `driveToField`: nur noch Verkehr (kein `createAgent`-Zweig mehr); ohne Zielpunkt kein Auftrag.
- Spielstand `NachbarFelder.xml`: es werden nur noch Einstellungen gespeichert; alte `worker`-Einträge und
  `fieldFruits` werden beim Laden ignoriert (Schema-Registrierung bleibt, damit alte Dateien sauber laden).

**Tests:** Referenzscan (keine Aufrufe ins Leere), Strukturcheck aller Lua-Dateien, Vollparse (lupa), XML (minidom).
Lauftest mit Platzhalter-Umgebung: Manager anlegen, `update()` räumt einen Verkehrseintrag im Status 100 ab,
`deleteMission` auf unbekannten Schlüssel ohne Fehler, entfernte Funktionen existieren nicht mehr.
**Unverifiziert im Spiel.** Prüfpunkte: Start ohne Lua-Fehler (`loadMap auf SERVER (Build 150)`), Verkehr spawnt
(`[TRAFFIC] …`), keine Zeilen „Feld … gewaehlt“/„generateWorkMission“ mehr, Einstellungsseite ohne „Anzahl Arbeiter“
und Arbeitsarten, Reiter Wegpunkte ohne Abschnitt Lohnunternehmer, Strg+Alt+L entfernt weiter alle Fahrzeuge.


# ERGÄNZUNG 2026-10-01 — Build 151: Angezeigter Name „Lebendige Straßen“

Nach Build 150 (nur noch Verkehr) passte „NachbarFelder“ nicht mehr. Entscheidung User: Name „Lebendige Straßen“,
umgesetzt als **reiner Anzeigename** (Empfehlung, kein Risiko):
- `modDesc.xml` `<title>`: de „Lebendige Straßen“, en „Living Roads“, fr „Routes vivantes“; Hinweis auf die Tasteneinträge
  in der Beschreibung angepasst.
- l10n de/en: Schlüssel `NachbarFelder`, `NF_setting_title` (Überschrift auf der Einstellungsseite, vorher „Aktivitaet auf
  fremden Feldern“) und die Tastennamen `input_NF_*` mit Präfix „Lebendige Straßen:“ bzw. „Living Roads:“.
- Wegpunkt-Dialog-Titel und Ingame-Meldungen (`addIngameNotification`) mit Präfix „Lebendige Straßen:“.

**Bewusst NICHT geändert:** ZIP-Name `FS25_NachbarFelder.zip` (= Mod-Name), `g_currentModName` in `NachbarFelder.lua`
(daran hängt die Registrierung der Spezialisierung `FS25_NachbarFelder.NachbarFelderWorker`), Ordner
`modSettings/FS25_NachbarFelder/`, Spielstand-Datei `NachbarFelder.xml`, Aktionsnamen `NF_*`, Dateinamen, Log-Präfix
`NachbarFelder:` (Logs bleiben vergleichbar). Eine echte Umbenennung bräuchte Übernahme der modSettings-Dateien,
Anpassung von `g_currentModName`, neue Tastenbelegung bei allen Spielern und wäre für das Spiel eine neue Mod.

**Tests:** XML (minidom), Strukturcheck, Vollparse. Im Spiel prüfen: Mod-Menü zeigt „Lebendige Straßen“, Steuerung zeigt
„Lebendige Straßen: …“, Einstellungsseite Überschrift „Lebendige Straßen“.


# ERGÄNZUNG 2026-10-01 — Build 152: Nachbar-Fahrzeuge beim Spielverkehr anmelden

**Frage User:** Fügt sich der KI-Verkehr in den normalen Spielverkehr ein, wenn der aktiv ist?

**Befund (LUADOC):** Die Autos des Spielverkehrs laufen in der Engine (`g_currentMission.trafficSystem`). Sie reagieren nur
auf angemeldete Objekte: `Player.lua` meldet den Spieler zu Fuß an (`addTrafficSystemPlayer(trafficSystemId,
graphicsRootNode)`), `Enterable.lua:1724` ein Fahrzeug beim Einsteigen (`components[1].node`), Zeile 1808 meldet beim
Aussteigen ab (`removeTrafficSystemPlayer`). Fahrzeuge ohne Fahrer – unsere Traktoren, auch normale Spieler-Helfer – kennt
der Spielverkehr nicht: Autos fahren auf sie auf. Umgekehrt bremst die KI vor Autos (`AICollisionTriggerHandler`,
Autos sind kinematisch → `hitStaticCounter`). Folge: Auffahrunfälle, verkeilte Autos, weggeschobene Gespanne.
Die alte Beschreibungszeile „PS: Es ist ratsam, den Verkehr auszuschalten“ (in Build 150 entfallen) war also berechtigt.

**Umsetzung:**
- Manager: `getSpielverkehrId`, `meldeBeimSpielverkehrAn` (je Fahrzeug einmal, merkt `vehicle.nf_spielverkehrNode`,
  `pcall`, Fehler einmal ins Log), `meldeGespannBeimSpielverkehrAn` (Traktor + `getChildVehicles`),
  `meldeBeimSpielverkehrAb`.
- Anmelden nach `aiSystem:startJob` in `driveToField` (jede Fahrt, idempotent; geweckte Pool-Fahrzeuge melden sich so
  wieder an). Während des Parkens bleibt die Anmeldung bestehen.
- Abmelden: `sleepPatrolEntry` (schlafend = wie ein abgestelltes Fahrzeug), Worker-`onDelete` (neues Event-Abo, deckt
  jedes Löschen ab), `prepareForShutdown` (aktive und Pool-Fahrzeuge, vor dem Abbau des Verkehrssystems).
- Server-Konfig `spielverkehrAnmelden` (Standard true, in Vorlage und Log-Zeile). Ohne Verkehrssystem
  (`trafficSystemId` 0/nil) oder ohne die Engine-Funktion passiert nichts.
- modDesc: PS-Zeile de/en/fr wieder aufgenommen (Autos bremsen; kracht es an Engstellen trotzdem → Verkehr ausschalten).

**Tests:** Mock (lupa): Anmeldung Traktor + Gerät, keine Doppelanmeldung, Abmeldung über `onDelete` und Shutdown inkl.
Pool, Schalter aus, ohne Verkehrssystem, Engine-Fehler → Log statt Absturz. Strukturcheck, Vollparse, XML.
**Unverifiziert im Spiel:** ob die Engine eine Obergrenze für angemeldete Objekte hat, und ob Autos hinter einem länger
parkenden Nachbar-Fahrzeug dauerhaft warten. Prüfen: Log-Zeile `Fahrzeuge werden beim Spielverkehr angemeldet`, Autos
bremsen hinter Traktoren, keine Ruckler; falls Autos sich stauen, `spielverkehrAnmelden` auf false.


# ERGÄNZUNG 2026-10-01 — Build 153: Ingame-Hilfe, ModHub-Beschreibung, GitHub

**Wunsch User:** Ingame-Hilfe, Beschreibung für ModHub und GitHub an „Lebendige Straßen“ / reinen Verkehr anpassen.

**Ingame-Hilfe (neu, gab es vorher nicht):**
- `help/helpLine.xml` im Format der Spielhilfe (`<helpLines>/<category>/<page>/<paragraph>/<title>|<text>`), Texte als
  `$l10n_NF_help_*` in `l10n_de/en.xml`. Seiten: Überblick, Wegpunkte und Spawnpunkte, Einstellungen, Tasten und Konsole,
  Spielverkehr und Probleme.
- Laden: `NachbarFelderManager:ladeHilfe()` aus `loadMap`, nur mit `g_client` (nicht auf dem reinen Dedi), einmal je
  Sitzung, `pcall`: `g_helpLineManager:loadFromXML(Utils.getFilename("help/helpLine.xml", modDirectory))`.
  `NachbarFelderManager.modDirectory` setzt `NachbarFelder.lua` nach dem `source`. Vorbild: Courseplay FS25
  (`CpHelpFrame`: `HelpLineManager:loadFromXML` + Kategorien je `customEnvironment` = Mod-Name). **Unverifiziert im
  Spiel**, ob die Kategorie im Standard-Hilfemenü erscheint (Log: `Ingame-Hilfe geladen` bzw. Fehlerzeile).
- `build.py`: `help/helpLine.xml` (15 Dateien).

**ModHub-Beschreibung (`modDesc.xml`):** de/en/fr neu (Features, Bedienung: wo Einstellungen, Wegpunkte, Hilfe; PS
Spielverkehr), Changelog 1.2.0.0 in de+en (TestRunner verlangt Changelog ab Version > 1.0.0.0, Build-81-Notiz).
**Version 1.1.42.0 → 1.2.0.0** (Namenswechsel + Feldarbeit entfernt; ModHub/MP brauchen eine neue Versionsnummer).
Titel fr „Routes Vivantes“ (TestRunner: jedes Wort groß).

**Texte:** `NF_active_*` („Nachbar-Verkehr aktiv“), `NF_engeMap_long` ohne Feldarbeit; entfernt: `NF_MAX_ASSISTANT_WORKERS_*`
und alle `NF_*Mission_*` (keine Regler mehr seit Build 150).

**GitHub:** README (Hilfe, Version, Dateiliste), Issue-Vorlagen (Mod-Name, Build-Platzhalter 153, Beispiel ohne Strg+Alt+E,
Frage nach Spielverkehr; nebenbei YAML-Fehler in `fehlerbericht.yml` Zeile 18 behoben – „: “ im ungequoteten Text, die Vorlage war dadurch ungültig), Release-Titel „Lebendige Straßen Build N“. Repo-Beschreibung/Name auf GitHub kann nur der User
in den Repo-Einstellungen ändern (Repo-Name bleibt sinnvoll `FS25_NachbarFelder` = Mod-Name).

**Tests:** XML aller Dateien, Strukturcheck, Vollparse, Mock `ladeHilfe` (Pfad, einmalig, Fehler → Log, ohne Client nichts).


# ERGÄNZUNG 2026-10-01 — Build 154: Fahrzeuge und Geräte spawnen ohne Hüpfen

**Test Build 153 (User):** Spielverkehr bremst und fährt nicht mehr auf (Build 152 bestätigt). Neu gemeldet: Fahrzeuge
und Anbaugeräte spawnen über dem Boden und hüpfen → Umkippen/Verkeilen möglich.

**Analyse (LUADOC):**
- `VehicleLoadingData:setPosition(x, y, z)` übernimmt y absolut; beim Laden kommt `storeItem.shopTranslationOffset` dazu
  (Höhe des Root-Knotens über dem Boden, vgl. `AIDrivable:drawDebugAIAgent`) – das ist richtig und bleibt.
- `getFahrbahnHoehe` maß mit `TERRAIN + ROAD + STATIC_OBJECT + BUILDING`. Das Spiel nimmt beim Paletten-Spawn
  (`VehicleSystem.lua`, `consoleCommandAddPallet`) zusätzlich `TERRAIN_DELTA`. Ohne sie trifft der Strahl bei Straßen aus
  Gelände-Deltas das tiefere Grundgelände → Fahrzeug steckt beim Laden in der Fahrbahn, die Physik drückt es heraus = Hüpfen.
- Geladen wurde immer waagerecht (`setRotation(0, ry, 0)`): am Hang steckt ein Ende in der Straße.
- Geräte wurden mit Physik geladen und erst im Ladecallback herausgenommen.

**Fix:**
- Maske + `CollisionFlag.TERRAIN_DELTA` (nur wenn vorhanden).
- Längsneigung: Höhe 2,5 m vor/hinter dem Ladepunkt, Richtung über `setDirection` an einem Hilfsknoten und `getRotation`
  (Euler-Reihenfolge der Engine, auch mit Modell-Drehung), höchstens ~11°; Höhe = max(Punkt, Mittel vorn/hinten) + 0,10 m.
  Neue Konstanten `SPAWN_HOEHE`, `SPAWN_NEIGUNG_ABST`, `SPAWN_MAX_NEIGUNG`. Gilt für Spawnpunkte und automatische Ladeplätze.
- Geräte (`index >= 2`) mit `data:setAddToPhysics(false)` laden; `setzeGeraetAnKupplung` bzw. die Rückfallwege nehmen
  sie wie bisher in die Physik.

**Tests:** Mock: 10 % Steigung → Richtung (0; 0,1; 0,995), Gerät 9 m dahinter tiefer, `setAddToPhysics(false)` nur fürs
Gerät. Strukturcheck, Vollparse. **Unverifiziert im Spiel** – besonders das Vorzeichen der Neigung (kommt aus der Engine).
Prüfen: Fahrzeuge setzen weich auf, kein Hüpfen; am Hang nicht verdreht.


# ERGÄNZUNG 2026-10-01 — Build 155: Spawn wieder waagerecht, Höhe über dem höchsten Messpunkt

**Test Build 154 (User, Log 17:09):** `vario500SCR.xml + Anbaugeraet` am Spawnpunkt WP1 geladen – „mit einer Seite auf dem
Boden, kippte dann auf alle 4 Räder“. Kuppeln und Losfahren danach normal (`Gespann startet am Ladeplatz …`).

**Ursache:** die Längsneigung aus Build 154 (`setDirection`/`getRotation` → `data:setRotation(rx, ry, rz)`). Beim Laden
verrechnet das Spiel zusätzlich die Shop-Drehung des Modells (`storeData.shopRotationOffset` „Rotation offset for shop
spawning“, `spawnRotationOffset`; StoreManager/VehicleLoadingData). Ein vorab berechneter Euler-Satz mit Neigung wird
dadurch zur seitlichen Schräglage. Nicht das Anbaugerät: das hängt erst nach dem Laden (ohne Physik) an der Kupplung.

**Fix:** Rotation wieder `(0, ry + Modelldrehung, 0)`. Höhe: Fahrbahn an Mitte, 2,5 m vorn/hinten, 1,2 m links/rechts
messen, höchsten Wert nehmen (höchstens +0,5 m über Mitte, sonst traf der Strahl ein Objekt) + 0,10 m. Am Hang fällt
das tiefere Ende ein paar Zentimeter, nichts steckt in der Fahrbahn. `TERRAIN_DELTA` und Geräte ohne Physik (Build 154)
bleiben. Konstanten `SPAWN_HOEHE`, `SPAWN_MESS_LAENGS`, `SPAWN_MESS_SEITE`, `SPAWN_MAX_ANHEBEN`.

**Tests:** Mock 10 % Steigung → Rotation 0, Traktor 0,35 m über Mittelpunkt (vorne 0,10 m), Gerät 9 m dahinter.
Strukturcheck, Vollparse.


# ERGÄNZUNG 2026-10-01 — Build 156: Kein Kippen mehr beim Ankuppeln

**Test Build 155 (User):** „Traktor landet sauber, aber wenn das Anbaugerät montiert wird, kippt er zur Seite.“ Log
17:19: `lintrac130.xml + Anbaugeraet` am Spawnpunkt WP1, `Gespann wird am Ladeplatz gekuppelt`, danach normal los.
Damit ist der Spawn (Build 155) in Ordnung, der Fehler sitzt im Kuppeln. Vermutlich auch die Ursache vieler früherer
„umgekippt“-Fälle (Builds 142–148), die damals Gewicht bzw. Ladeplatz zugeschrieben wurden.

**Analyse (LUADOC):**
- `AttacherJoints:createAttachmentJoint(implement, noSmoothAttach)`: mit `noSmoothAttach = true` sind die
  Gelenkgrenzen sofort 0 (`attachingTransLimit/RotLimit = {0,0,0}`), jede Abweichung zwischen Eingangspunkt des Geräts
  und Kupplung wird in einem Physik-Schritt erzwungen. Ohne (Spieler: `VehicleAttachEvent` → `attachImplement(…, true,
  nil, startLowered)`) wird über `smoothAttachTime` weich zusammengezogen.
- Unser `setzeGeraetAnKupplung` setzte nur die Gierrichtung (wie `additionalAttachmentLoaded`); geneigte oder
  verdrehte Eingangspunkte (`jointOrigRotOffsetComponent`, Attachable.lua:1958) passten nicht → harter Ruck.
  `SupportVehicle:enableSupportVehicle` setzt dagegen auch die Drehung: `localRotationToWorld(jointTransform, rotOffset)`.

**Fix:**
- `setzeGeraetAnKupplung`: Drehung = `localRotationToWorld(aj.jointTransform, ij.jointOrigRotOffsetComponent)`, sonst wie bisher
  Gierrichtung. Mindesthöhe 5 cm bleibt.
- Neu `kuppleGeraet(info)`: setzen + `attachImplement(…, true, nil, false, false, false)` = weich, nicht gesenkt, kein
  Spielstand-Modus. Beide Kuppelstellen (`setAttachment`, Status-0-Zweig in `update`) nutzen sie. `attachObjectToCar`
  (unbenutzt) entfernt.
- Spawn-Log nennt das Gerät (`lintrac130.xml + <Geraet>.xml` statt `+ Anbaugeraet`).

**Tests:** Mock: Position/Drehung aus Kupplung + Offsets, Physik an, `attachImplement` mit noSmoothAttach=false.
Strukturcheck, Vollparse, Referenzscan.

**Bestätigt im Spiel (User, 01.10.):** „Traktor und Anbaugerät sauber gespawnt, erst der Traktor, dann wurde das
Anbaugerät sanft angekuppelt.“ Damit bestätigt: Build 152 (Spielverkehr bremst), 155 (waagerechter Spawn) und 156
(weiches Kuppeln).


# ERGÄNZUNG 2026-10-01 — Build 157: Kein Helfer-Symbol der Nachbarn auf der Karte

**Wunsch User:** „das typische Helfergrafik weg, damit es mit echten Helfern keinen Konflikt gibt“ – nachgefragt: gemeint
ist das **Helfer-Symbol auf der Karte** (Minimap und ESC-Karte). Der KI-Verkehr soll sich wie normaler Verkehr einfügen.

**Umsetzung (LUADOC):**
- Minimap und große Karte zeichnen jeden Hotspot über `IngameMap:drawHotspot(hotspot, …)` (`IngameMapElement` →
  `ingameMap:drawHotspotsOnly()`). Hotspots kennen ihr Fahrzeug (`getVehicle()`, vgl. `IngameMapElement`; Fahrzeug-Hotspot
  aus `Vehicle:createMapHotspot` → `VehicleHotspot:setVehicle`). Ob das Helfer-Symbol während eines KI-Auftrags ein eigener
  Hotspot ist (`AIJobVehicle:getMapHotspot` ist überschrieben, Rumpf nicht dokumentiert), spielt so keine Rolle.
- `installKartenHook()` (aus `loadMap`, nur mit `g_client`, einmal): `IngameMap.drawHotspot` überschrieben – gehört der
  Hotspot zu einem Nachbar-Fahrzeug, wird nicht gezeichnet. `getIstNachbarHotspot`: Fahrzeug aus `getVehicle()` bzw.
  `.vehicle`, Zugfahrzeug über `getRootVehicle`, Besitzer-Farm == Helfer-Farm. Alles in `pcall`.
- Helfer-Farm für Clients: `getSettingsState().helferFarmId` (Server: `farmId`, sobald ermittelt; sonst 0), am Ende von
  `NachbarFelderSettingsSyncEvent` als UInt8 geschrieben/gelesen; `applySettingsState` merkt `helferFarmIdSync`. Nach der
  Farmwahl (`getEffectiveFarmId`) sofort `broadcastSettingsToClients()`. Server und Clients müssen dieselbe Mod-Version
  haben (Stream-Format geändert) – im MP ohnehin Pflicht.

**Tests:** Mock: vor dem Sync sichtbar, danach Nachbar-Traktor und sein Gerät ausgeblendet, eigenes Fahrzeug und
Hotspot ohne Fahrzeug gezeichnet; Server liefert `helferFarmId` 14; Stream-Rundlauf des Sync-Events. Strukturcheck,
Vollparse.

**Bestätigt im Spiel (User, 01.10.):** „Supi alles passt“ – Build 157 läuft, Stand freigegeben für PR/Release.

---

# ERGÄNZUNG 2026-10-01 — Build 158: ModHub-Fassung (vom User)

Der User hat eine eigene ZIP mit ModHub-Anpassungen geliefert, sie ist unverändert übernommen: alle `pcall` entfernt
(stattdessen `local function schritt() … end schritt()` und Existenz-Prüfungen), sichtbare Texte über `nfText`/`nfMeldung`
bzw. `nfDialogText` aus l10n (de/en/fr, neue `l10n/l10n_fr.xml`, auch GUI-XML mit `$l10n_…`), Speicher-Telemetrie
entfernt, modDesc `descVersion` 113, Version 1.0.0.0, Changelog aus der Beschreibung entfernt. `build.py` packt jetzt
auch `l10n_fr.xml`.

---

# ERGÄNZUNG 2026-10-01 — Build 159: Anbaugerät passend zur Traktorgröße

**Problem (User, Log + Screenshot):** „Anbaugeräte viel zu groß für die Trecker“. Log: `skh60.xml + claasVolto80.xml`
– Rigitrac SKH 60 (Kompakttraktor) mit 7,7-m-Zettwender; danach zweimal `AIMessageErrorNotReachable`. Geprüft wurden
bisher nur Leistungsbedarf ≤ Motorleistung und Gerätegewicht ≤ halbes Traktorgewicht – beides passte.

**Ursache:** Die Arbeitsbreite wurde nie geprüft. Der alte Kommentar „Arbeitsbreite steht nicht in den StoreItem-Specs“
stimmt nicht: `Vehicle.loadSpecValueWorkingWidth` legt `specs.workingWidth = { width, minWidth }` an
(`addSpecType("workingWidth", …)`, Vehicle.lua), Geräte mit Breiten-Konfiguration `specs.workingWidthConfig`
(`[configName][index] = { width, isSelectable }`). Gefüllt wird beides über das schon genutzte `nfLoadSpecs`.

**Fix:**
- `nfGetItemWorkingWidth(item)`: `workingWidth.width`, sonst größte Breite aus `workingWidthConfig`, sonst nil.
- `buildTrafficTrailerList`: Breite je Gerät (`breiteM`); Geräte ohne lesbare Breite nur noch bis 1 t
  (`NF_IMPL_OHNE_BREITE_MAX_KG`). Ohne `pcall` (ModHub-Fassung).
- `getPasstGeraetZuTraktor`: zusätzlich `breiteM ≤ getMaxGeraeteBreite(traktor)` = Traktorgewicht in t × 1,2 m, begrenzt
  auf 3–6 m (`NF_IMPL_BREITE_JE_TONNE/_MIN/_MAX`). SKH 60 (~2,5 t) → 3 m, 5-t-Traktor → 6 m.
- Spawn-Log: `… + gerät.xml (Breite m, Traktor t, max m)`.

**Tests:** Mock: Volto 80 (7,7 m) an 2,5 t und 5 t abgelehnt; Konfig-Gerät 4,2/5,4 m → 5,4 m, an 2,5 t abgelehnt, an
5 t erlaubt; Gerät ohne Breite (0,6 t) erlaubt; unbekanntes Traktorgewicht → 3 m. Strukturcheck, Vollparse.

---

# ERGÄNZUNG 2026-10-01 — Build 160: Join-Absturz nach Entfernen der pcall

**Problem (User, Log):** Beim Joinen landet der Spieler unter der Map. Log:
`Error: Running LUA method 'update'. NachbarFelderWaypointPage.lua:122: attempt to call missing method 'setImageColor'`.

**Ursache:** In der ModHub-Fassung (Build 158) sind alle `pcall` entfernt. Früher fing ein `pcall` je Layout-Kind den
Fehler ab (nicht jedes Kind im Wegpunkt-Layout ist eine Bitmap). Ohne Absicherung bricht der Fehler den kompletten
Update-Durchlauf des Spiels in diesem Frame ab (`Running LUA method 'update'`), genau beim Spieler-Spawn → Fall durch die
Map. Zweiter Fund: `nfSetDisabled` wurde in `refreshWpInfo` aufgerufen, war aber nirgends definiert (Absturz beim
ersten Öffnen des Wegpunkte-Tabs).

**Grundregel ab jetzt:** Ohne `pcall` ist jeder Laufzeitfehler ein Spiel-Fehler. Jede Spielfunktion vor dem Aufruf auf
Existenz prüfen, besonders in Hooks auf Spielfunktionen (Speichern, Menü-Update, Karten-Zeichnen, Mission-Delete).

**Fix:**
- WaypointPage: `nfSetDisabled` und `nfSetOptionState` definiert; `updateAlternating` nur bei vorhandenem
  `setImageColor`; `onTabOpen`, `onFrameOpen`-Hook, Slider und Fokus-Links prüfen Methoden vorher. Ja/Nein-Texte aus
  l10n (`NF_ui_ja`/`NF_ui_nein`, de/en/fr).
- Manager: `setzeGeraetAnKupplung` prüft Gelenk-Tabellen und Methoden; `saveToXMLFile` (läuft vor `ItemSystem.save`)
  prüft Pfad, `XMLFile.create`, Werte (keine nil an `setBool/setInt`), löscht die Datei-Instanz immer;
  `FSBaseMission.delete`-Hook ohne Manager sicher; Wegpunkt-Nummern auf der Karte nur bei `getLastScreenPosition`;
  `getIsMotorStarted` vor dem Aufruf geprüft.
- Komplettprüfung: alle 164 entfernten `pcall`-Stellen gegen Build 157 durchgesehen; Strukturcheck, Vollparse,
  Undefiniert-Scan (nf-Funktionen je Datei, Nutzung vor Definition), l10n-Abdeckung de/en/fr.

---

# ERGÄNZUNG 2026-10-01 — Build 161: Wegpunkt-Seite, letzte Lücken ohne pcall

Build 160 hat den Beitritts-Absturz an seiner Hauptursache behoben (`container:setImageColor` in der
Zeilenfärbung – nicht jedes Layout-Kind ist eine Bitmap). Eine Prüfung derselben Funktion in echtem Lua
(lupa, Skript `mh_join_pruef.py`: GUI noch nicht geladen / Menü halb aufgebaut / Wegpunkt ohne Koordinaten /
Normalbetrieb / Index zu groß) zeigte zwei verbliebene Stellen, die beim Beitritt genauso durchschlagen:

- `self.nfWpInfoText:setText(text)` ohne Methodenprüfung → „attempt to call a nil value (method 'setText')“,
  sobald das Menü erst halb aufgebaut ist.
- `math.floor(wp.x)` ohne Prüfung → „bad argument #1 to 'floor' (number expected, got nil)“, sobald ein
  Wegpunkt ohne Koordinaten in der Liste steht. Genau solche Punkte kommen über den Server-Sync.

Beides ist jetzt geprüft, ohne Schutzhülle. Dazu ein ModHub-Punkt, der in Build 160 zurückgekommen war:
die Kategorienamen am Typ-Schalter standen wieder fest auf Deutsch (`{ "Normal", "Kurz", "Lang",
"Spawnpunkt" }`) – englische und französische Spieler hätten deutsche Wörter gesehen. Jetzt über den
Helfer `nfCatKey` aus l10n, inklusive Kategorie 3 (Durchfahrt), die in der alten Liste fehlte. Die
Button-Beschriftungen laufen über `nfPageText` statt `g_i18n:getText` (prüft den Schlüssel mit `hasText`).

**Merke für den pcall-Umbau:** Ein Aufruf einer Funktion, die es nicht gibt, ist syntaktisch gültig – weder
`luaparser` noch der TestRunner finden ihn, erst die Laufzeit. Beim Umbau von Build 158 war so
`nfSetDisabled` aufgerufen, aber nie definiert worden. Deshalb gehört zur Prüfkette jetzt ein Referenzscan
(`mh_referenzscan.py`: einfache Aufrufe gegen alle Definitionen) **und** ein lupa-Durchlauf der Funktionen,
die ohne geöffnetes Menü laufen.

**Prüfungen:** TestRunner 0.9.22 PASS (alle 15 Module), Vollparse, Referenzscan ohne echte Treffer,
lupa-Join-Test 6 von 6 (dieselbe Prüfung meldet für Build 160 noch 2 Fehler), l10n de/en/fr je 105
Schlüssel deckungsgleich, alle 21 benutzten Schlüssel vorhanden und formatierbar.

---

# ERGÄNZUNG 2026-10-01 — Build 162: ClassUtil zur Laufzeit nicht vorhanden

**Problem (User, Log 19:15, Build 161):** Nach dem ersten Gespann-Start
`Error: Running LUA method 'update'. NachbarFelderManager.lua:4728: attempt to call a nil value`.

**Ursache:** `getVehicleAiDiag` rief `ClassUtil.getClassNameByObject(job)` auf. In der LUADOC benutzt (FieldManager),
zur Laufzeit im Mod aber nicht aufrufbar. Bis Build 157 vom Fehlerfänger verdeckt. **Lehre:** „steht in der LUADOC“
reicht ohne Absicherung nicht – jeden Aufruf einer Spiel-Hilfsfunktion auf Existenz prüfen.

**Fix:** Jobname über `ClassUtil` nur wenn vorhanden, sonst `job.name`, sonst „aktiv“. Gleich mit abgesichert:
`getFahrbahnHoehe` (Gelände-Node, `CollisionFlag`-Werte einzeln, `RaycastUtil.raycastClosest`; ohne Strahl
Geländehöhe) und `getIstSpawnFlaecheFrei` (`CollisionMask.ALL` und Flaggen geprüft, fehlt einer → Fläche gilt als
belegt; `getHasGroupFlagSet` im Callback geprüft).

**Tests:** Mock `getVehicleAiDiag` mit/ohne `ClassUtil`; Strukturcheck, Vollparse, kein `pcall` im Code.

**Bestätigt im Spiel (User, 01.10.):** „alles läuft“ – Builds 158–162 freigegeben für PR/Release.

---

# ERGÄNZUNG 2026-10-01 — Build 163: Mod-Icon und Banner

- `icon_NachbarFelder.dds` vom User ersetzt: Spielmotiv statt des alten Farmer-Assistant-Bildes (gleiche Größe, DDS).
- `docs/bilder/banner.png` (1280 × 640, selbst gezeichnet, ohne fremde Logos) oben in der README; passt auch als
  GitHub-Social-Preview (Settings → General → Social preview).
- Kein Lua-Code geändert; `BUILD` nur hochgezählt, damit der Release-Workflow ein neues Release `build163` mit dem neuen
  Icon baut (`build162` existiert schon und würde übersprungen).

---

# ERGÄNZUNG 2026-10-02 — Build 164: Mindesttempo für Verkehrsfahrzeuge

**Problem (User, Screenshot):** Ein kleiner blauer Raupen-Kompakttraktor fuhr viel zu langsam und blieb an einer
Kreuzung stehen, obwohl nichts im Weg war.

**Ursache:** Die Fahrzeugliste filterte nur nach Kategorie `TRACTORSS` und Gewicht (≤ 7 t). Mini- und Raupentraktoren
(10–20 km/h) passten durch.

**Fix:**
- `nfGetItemMaxSpeed(item)`: `specs.maxSpeed` in km/h (Store-Spec `maxSpeed`, `Motorized.loadSpecValueMaxSpeed`:
  storeData-Wert, Motor-Konfiguration oder aus den Gängen berechnet).
- `buildTrafficVehicleList`: Fahrzeuge unter `NF_MIN_VEH_SPEED_KMH` = 30 fallen raus, jedes mit Name und Tempo im Log
  (`[TRAFFIC]   zu langsam (12 km/h): …`); Zusammenfassung zählt sie mit. Unbekanntes Tempo gilt nicht als zu langsam.
- Stammfahrzeug, das nicht mehr in der Liste steht, wird durch ein zufälliges aus der Liste ersetzt.
- Die Liste wird beim Start gebaut – Fahrzeuge, die schon im Pool schlafen, bleiben bis zum Neustart.

**Tests:** Mock `nfGetItemMaxSpeed` (Zahl, Text, fehlend); Strukturcheck, Vollparse, kein `pcall`.

**Bestätigt im Spiel (User, 02.10.):** „ist erledigt, hat funktioniert“.

---

# ERGÄNZUNG 2026-10-04 — Build 165: Debug-Log-Schalter

**Wunsch (User, Log 04.10.):** Viel zu viele Log-Einträge (`[TRAFFIC][DIAG] nach Start …` alle paar Sekunden,
`[PERF]`, `[POOL]`, Stufe1/Stufe2 …) – ein Debug-Modus zum An- und Ausschalten.

**Umsetzung:**
- `NachbarFelderLog` (NachbarFelder.lua, vor allen anderen Dateien geladen): `NachbarFelderLog.print(msg)` schreibt bei
  `debug = true` alles, sonst nur Zeilen mit `WARNUNG`, `Warnung`, `Fehler`, `FEHLER`, `fehlgeschlagen`,
  `nicht verfuegbar`, `loadMap auf` (Startzeile mit Build) oder `Debug-Log` (Umschalt-Meldung).
- Jede Lua-Datei der Mod verdeckt `print` mit `local print = NachbarFelderLog.print` – keine der rund 170 Log-Stellen
  musste einzeln geändert werden. (`NachbarFelderUIHelper.lua` hat keine Log-Zeilen.)
- `NachbarFelderManager:setDebugLog(an)` setzt `debugLog`, `logLevel` (2/1, alte Dauerschreiber-Stufe) und
  `NachbarFelderLog.debug`; meldet den Wechsel („Debug-Log an/aus“).
- Schalter **„Debug-Log“** in ESC → Einstellungen → Lebendige Straßen (`NF_debugLog_short/_long`, de/en/fr), wie
  „Enge Karte“: Admin-Edit (`applySettingEdit "debugLog"`), Settings-Sync (UInt8 am Ende des Streams), Spielstand
  (`settings#debugLog`). Standard aus. `logLevel=2` in der Server-Konfig schaltet beim Start ein; ein im Spielstand
  gespeicherter Wert geht vor.
- Ingame-Hilfe (Einstellungen) und README erwähnen den Schalter.

**Tests:** Mock Log-Filter (DIAG weg, WARNUNG und loadMap bleiben, mit Debug alles); Strukturcheck, Vollparse, kein
`pcall`, keine `print`-Nutzung vor dem Filter; l10n-XML gültig.

---

# ERGÄNZUNG 2026-10-04 — Build 166: Begegnungen und früheres Versetzen

**Befund (Logs 04.10., Build 164/165):**
- Zwei Nachbar-Fahrzeuge warten aufeinander: series6M und arion550 standen 11:03 14 m auseinander gleichzeitig
  30 s fest, bekamen beide neue Ziele und standen 11:04 4 m auseinander wieder fest. Der Wächter behandelte das wie
  jeden Stillstand (Stufe 1 = neues Ziel vom Fleck) – das Patt blieb.
- Nach einem Stillstand wurde das neue Ziel fast immer zweimal sofort abgewiesen (~50 ms, `NotReachable`); erst
  nach dem Versetzen auf die KI-Straße (bisher beim 2. Fehlschlag) fuhr das Fahrzeug meist los.

**Fix:**
- `getStehenderNachbar(eintrag, x, z, radius)`: anderes Patrol-Fahrzeug (Status 1, Wächter misst) im Umkreis
  `BEGEGNUNG_RADIUS` = 100 m (ab `BEGEGNUNG_NAH` = 20 m nur, wenn er innerhalb 60° vor dem Fahrzeug steht –
  Screenshot 04.10.: Claas quer zum Wenden, Gegenverkehr weit über 30 m entfernt), das selbst schon `BEGEGNUNG_STEHT_MS` = 15 s steht.
- `loeseBegegnung(eintrag, veh, x, z)`: vor Stufe 1. Das Fahrzeug, dessen Wächter zuerst auslöst, weicht aus:
  Auftrag stoppen, neues Ziel (`pickPatrolWaypoint`), mit `getRoadPointInRichtung` (Richtung neues Ziel, mind. 25 m,
  Platz frei geprüft) auf die KI-Straße setzen, `roadSnapped = true`. Der Nachbar behält sein Ziel, seine Wächter-Uhr
  startet neu (`patrolWdSince = g_time`). Höchstens `BEGEGNUNG_MAX` = 3 mal je Fahrzeug, Zähler `begegnungen` wird
  bei echter Bewegung zurückgesetzt. Ohne freien Platz: normale Stufe 1. Log: `Begegnung mit … - weicht … aus`.
- Worker: Versetzen auf die KI-Straße (`nfRoadSnap`) schon beim **ersten** Sofort-Fehlschlag statt beim zweiten.

**Offen:** Ob ein Auto des Spielverkehrs vor dem Fahrzeug steht, lässt sich nicht prüfen – Verkehrsautos stehen
nicht in `vehicleSystem.vehicles`, eine verifizierte Abfrage gibt es nicht.

**Tests:** Mock `loeseBegegnung` (Partner steht 30 s → weicht aus, Partner-Uhr neu; Partner erst 5 s → nein;
Partner 50 m vorn → ja, 50 m hinten → nein, 150 m → nein); Strukturcheck, Vollparse, kein `pcall`.

# ERGÄNZUNG 2026-10-04 — Build 167: Stillstand am Ladeplatz zählt als Fehlschlag

**Befund (Log 04.10. 14:01–14:12, Build 166):** keine Fehler, das frühere Versetzen griff zweimal sofort. Aber vier
von fünf Fahrzeugen, die am automatischen Ladeplatz ~78 m vor dem Shop (x≈-363 z≈29) geladen wurden, kamen dort nie
weg (Motor an, Auftrag aktiv, 0 km/h, nach 30 s Wächter Stufe 1). Der Platz wurde nicht gesperrt, weil bisher nur ein
sofort abgewiesener Start (Worker) oder ein Umkippen als Fehlschlag galt. In der Nähe standen abgestellte Geräte des
Spielers (hr6040RCS ~60 m, jump320 ~56 m) – möglicherweise blockieren sie die Ausfahrt.

**Fix:** Im Patrol-Wächter ruft der 30-s-Stillstand (Stufe 0, nicht am Ziel) `merkeSpawnFehlschlag(w, x, z,
"steht nach dem Start still")`. Die Funktion wirkt wie bisher nur, wenn das Fahrzeug höchstens 10 m vom Ladeplatz
steht, und nur einmal je Fahrzeug: automatischer Platz → dauerhaft gesperrt (Ladeplatz-Datei) + einmaliger Hinweis
„Spawnpunkt setzen“; Admin-Spawnpunkt → nur Hinweis im Log. Der Wächter läuft danach normal weiter.

**Nachtrag (Screenshot 04.10.):** Der Händlerhof ist groß und leer – die abgestellten Geräte (56–63 m) sind nicht
die Ursache. Der Platz x=-363 z=29 wurde schon 14:05 gesperrt („Verkehr sofort abgewiesen“, `NotReachable`), danach
wurden aber wieder Fahrzeuge „78 m vom Shop-Platz“ geladen: knapp außerhalb des alten Sperrradius von 15 m auf
demselben Straßenstück, das die KI offenbar nicht ans Netz angebunden sieht. Sperrradius jetzt
`LADEPLATZ_SPERR_RADIUS` = 40 m.

**Tests:** Strukturcheck, Vollparse, kein `pcall`.

# ERGÄNZUNG 2026-10-04 — Build 168: Fahrerfigur bleibt im Fahrzeug

**Anlass (User):** „Warum bleiben die Fahrerfiguren nicht einfach im Fahrzeug, bis das Fahrzeug gelöscht wird? Das ist
doch Performance besser und es entstehen weniger Ruckler.“ Das Spiel entlädt die Figur bei jedem Auftragsende
(`restoreVehicleCharacter` → `deleteVehicleCharacter`, wenn niemand drinsitzt) und lädt beim nächsten Start eine neue
(`setRandomVehicleCharacter` → `setVehicleCharacter` → `VehicleCharacter:loadCharacter`). Nachbar-Fahrzeuge bekommen bei
jedem Ziel, Parkende und Wächter-Schritt einen neuen Auftrag.

**Fix:** `applyFahrerBleibt(vehicle)` überschreibt pro Fahrzeug `setVehicleCharacter`/`deleteVehicleCharacter`: Nach dem
ersten Laden werden Löschen und Neuladen übersprungen, solange kein Spieler drinsitzt (`getIsControlled`). Beim Löschen
des Fahrzeugs räumt `Enterable:onDelete` die Figur direkt ab (`spec.vehicleCharacter:delete()`). Sichtbarkeit bleibt
nur abstandsabhängig (`VehicleCharacter:updateVisibility`) – die Figur sitzt also auch beim Parken drin.
Server: in `onSpawnedVehicle`. Server und Clients: `pruefeFahrerfiguren()` alle 2 s im `update` (Kennzeichen
Besitzer-Farm = Helfer-Farm wie Build 157), weil die Clients ihre Figur selbst laden. Mit `fahrerfigurenAufServer=false`
bleibt es auf dem Server beim Weglassen (Build 95, `nf_keineFigur` hat Vorrang).

**Tests:** Mock (NF-Fahrzeug: 5 Aufträge → 1× geladen, Figur bleibt; fremdes Fahrzeug: 5× geladen, danach ohne Figur;
Spieler steigt ein → seine Figur wird geladen); Strukturcheck, Vollparse, kein `pcall`.

# ERGÄNZUNG 2026-10-05 — Build 169: Übersetzungen inline in der modDesc

**Anlass:** Der User hat die ModHub-Beanstandungen aus seinen anderen Mods geliefert (jetzt `docs/MODHUB_REGELN.md`)
samt Prüfskript `_modhub_check.py`. Das Skript fand bei dieser Mod **keine Fehler**: descVersion 113, Version 1.0.0.0,
Titel groß, EN/DE/FR, Icon 131200 Byte DXT1 ohne Mipmaps auf dunklem FS25-Grund (RGB 51–60), kein `pcall`/`xpcall`/
`loadstring`/`collectgarbage`, kein leerer `HEADER_SLICES`-Eintrag, keine `.png` in der ZIP. Die drei Treffer
„Ersatzschreibung“ in `l10n_de.xml` standen nur in Schlüsselnamen (`NF_gui_loeschen` …), nicht in Texten.

**Offen war nur:** separater Ordner `l10n/` – den flaggt der ObsoleteFiles-Check von GIANTS (bei FarmOverview trotz
literaler Schlüssel). **Fix:** alle 107 Schlüssel als `<l10n><text name="…"><en/><de/><fr/></text></l10n>` in die
`modDesc.xml` (ohne `filenamePrefix`), Ordner `l10n/` gelöscht, `build.py` (13 Dateien). `$l10n_`-Verweise in
`gui/` und `help/` sowie `g_i18n:getText` bleiben unverändert. Gegenprobe per Skript: alle Texte in allen drei Sprachen
identisch mit den alten Dateien.
Danach meldete das Skript „Änderung“ in den Texten (jetzt in der modDesc, Risiko `excessChangelog` bei 1.0.0.0):
`NF_help_einstellungen_text2` (de) umformuliert – „Was dort eingetragen wird, gilt nach einem Neustart.“ Endstand
`_modhub_check.py`: 0 Fehler, nur die zwei Info-Hinweise zu `$l10n_`-Verweisen in `gui/` (laut Regeln in Ordnung).

**Regel ab jetzt:** neue Texte nur noch im `l10n`-Block der `modDesc.xml` (de + en + fr); vor einer Einreichung
`docs/MODHUB_REGELN.md` Abschnitt 8 abarbeiten.

# ERGÄNZUNG 2026-10-07 — Build 170: Bilder in der Ingame-Hilfe

**Befund (User, Screenshot 07.10., Build 169):** Reiter und Hilfetexte da (inline-l10n funktioniert), lokales Log ohne
Fehler/Warnung der Mod – aber „InGame Hilfe fehlt die Grafik“: Die Bildfelder der Hilfeseiten (ESC → Hilfe) blieben
dunkel. `help/helpLine.xml` hatte seit Build 153 nie Bilder.

**Fix:** je Seite ein Bild im ersten Absatz, Format wie Courseplay FS25 (`config/HelpMenu.xml`):
`<image filename="help/hilfe_<seite>.dds" size="512 512" uvs="0px 0px 512px 256px" aspectRatio="0.5"/>`.
Fünf Motive ohne Text (sprachneutral): Überblick (Landschaft, Traktor mit Fahrer), Wegpunkte (Karte mit Pins und
Spawnpunkt), Einstellungen (Regler/Schalter), Tasten und Konsole, Spielverkehr (Kreuzung mit Warndreieck).
Erzeugt mit `tools/hilfebilder.py` (Pillow, DXT1); Header wie beim ModHub-geprüften Icon gesetzt (131200 Byte,
`dwFlags` 0xA1007, `dwMipMapCount` 1, `dwCaps` 0x1000). `build.py`: 18 Dateien, keine `.png` in der ZIP.

**Ergebnis (User 07.10.):** Seitenbilder da, die linke Seitenliste blieb leer – siehe Build 171.

# ERGÄNZUNG 2026-10-07 — Build 171: Symbole in der linken Hilfe-Seitenliste

**Befund (User, Screenshot 07.10., Build 170):** „es fehlen noch die Bilder auf der linken Seite“ – die Symbolfelder vor
„Überblick“, „Wegpunkte und Spawnpunkte“ usw. blieben schwarz. Die Liste nimmt nicht das Absatzbild, sondern
`page.iconSliceId` (Courseplay FS25 `CpHelpFrame:populateCellForItemInSection`, Kopie des Spiel-Frames:
`icon:setImageSlice(nil, page.iconSliceId)`, sonst unsichtbar). Wie das Spiel den Wert aus der XML liest, ist nicht
belegt – deshalb in Lua gesetzt.

**Fix:**
- Atlas `help/hilfe_icons.dds` (512×512 DXT1, Header wie Icon) mit fünf 128×128-Ausschnitten der Seitenbilder,
  Slices in `help/hilfe_icons.xml` (Format `texture/meta/slices` wie Courseplay `img/iconSprite.xml`).
- `setzeHilfeSymbole(dir)` direkt nach `g_helpLineManager:loadFromXML`: Atlas einmal per
  `g_overlayManager:addTextureConfigFile(…, "nfHilfe")` anmelden (verifiziert, LUADOC OverlayManager; Slice-ID
  `nfHilfe.<id>`, `getSliceInfoById` ohne customEnv). Dann über `getCustomEnvironmentNames()` (nur Namen, die das Spiel
  liefert – `getCategories` mit fremdem Namen ist nicht belegt) unsere Kategorie (`title` = `$l10n_NF_help_title` oder
  übersetzt) suchen und je Seite `iconSliceId` setzen, nur wo noch nichts steht. Ohne Treffer:
  „Hilfe-Symbole fehlgeschlagen (Kategorie nicht gefunden)“ im Log.
- `tools/hilfebilder.py` erzeugt jetzt auch Atlas und Slice-XML; `build.py` 20 Dateien.

**Tests:** Mock (Kategorie gefunden → 5 Symbole, fremde Kategorie unberührt, Atlas nur einmal angemeldet, kein Log;
Kategorie fehlt → Log-Zeile, keine Änderung); Strukturcheck, Vollparse, kein `pcall`.

# ERGÄNZUNG 2026-10-07 — Build 172: Engine-Hooks der Helfer-Zeit entfernt (aus PR #12)

**Anlass:** In einer parallelen Arbeitssitzung entstand Draft-PR #12 („Build 170“, Zweig inzwischen gelöscht):
Überbleibsel der Feldarbeit in Engine-Funktionen entfernen. Der PR war nicht mergebar: Die Build-Nummer 170 war schon
vergeben (Hilfe-Bilder, PR #13), und es gab einen Konflikt in diesem Dokument. Der User hat entschieden, den Inhalt hier als
Build 172 zu übernehmen – mit einer Abweichung (Geld-Hook bleibt).

**Wichtig:** Die Hooks waren **kein toter Code**. `hasActiveWorkers()` war wahr, sobald irgendein Nachbar-Fahrzeug
existiert (jeder `vehicleType`-Eintrag hat einen `NachbarFelderWorker`), also auch im reinen Verkehr.

**Änderungen:**
- `FarmlandManager`-Klassen-Hooks entfernt (`getIsOwnedByFarmAtWorldPosition`, `getCanAccessLandAtWorldPosition`,
  `getIsOwnedByFarmAlongLine` → für die Helfer-Farm überall „gehört“). Lua-Aufrufer laut LUADOC: `AIVehicleUtil.getIsAreaOwned`
  (Feldarbeit), Leveler, PlaceablePlacement, `WheelDestruction:update` (Räder zerstören Pflanzen nur auf eigenem Land – mit
  dem Hook also überall). Im GOTO-Weg kein Lua-Aufrufer; ob die Engine-Navigation sie intern nutzt, ist nicht sichtbar →
  **im Spiel prüfen, ob die Fahrzeuge weiter normal losfahren** (keine neuen „sofort abgewiesen“).
- `addMoney`-Hook **bleibt** (Abweichung von PR #12): ohne ihn liefen KI-Lohn und Sprit als Minus auf das Konto der
  Helfer-Farm. Bedingung jetzt `getHatFahrzeugeUnterwegs()` (umbenanntes `hasActiveWorkers`), Merker
  `moneyHookInstalled` entfällt (`installHooks` hat schon den Guard `hooksInstalled`).
- Totes `g_messageCenter:unsubscribe(MessageType.MISSION_GENERATED, self)` entfernt (nichts abonniert es mehr).

**Tests:** Strukturcheck, Vollparse, kein `pcall`, keine Verweise mehr auf `hasActiveWorkers`/`moneyHookInstalled`/
`MISSION_GENERATED`. PR #12 kann geschlossen werden.
**Ergebnis (User 07.10.):** mit Build 172 auf dem Server fahren die KI-Traktoren normal – die Landbesitz-Hooks werden zum
Losfahren nicht gebraucht.

# ERGÄNZUNG 2026-10-07 — Build 173: Stillstand am Ladeplatz – Umkreis 25 m und Diagnose

**Befund (Server-Log 07.10. 10:16–10:19, Build 172, Debug-Log an):** Vario 300 + Volto fuhr normal (WP49 nach ~2 min).
Vestrum 130, geladen 125 m vom Shop, stand nach dem Start 30 s still (Motor an, Auftrag aktiv, 0,1 km/h, nächstes
Fahrzeug 87 m) → Stufe 1, neues Ziel. **Der Ladeplatz wurde nicht gesperrt** (keine Zeile „taugt nicht“), obwohl
Build 167 genau das tun sollte. `merkeSpawnFehlschlag` wirkt nur bis 10 m vom Ladepunkt; vermutlich war das Fahrzeug ein
paar Meter angerollt. Die Entfernung stand nicht im Log – nicht belegt.

**Fix:**
- `merkeSpawnFehlschlag(w, x, z, grund, maxDist, diag)`: optionaler Umkreis (Standard weiter 10 m für „umgekippt“ und
  „Verkehr sofort abgewiesen“) und Diagnose. Der 30-s-Stillstand im Wächter übergibt
  `LADEPLATZ_STILLSTAND_RADIUS` = 25 m und `diag = true`.
- Diagnose (Debug-Log, einmal je Fahrzeug, `w.spawnPlatzDiagnose`): „Ladeplatz-Pruefung (…): steht N m vom Ladeplatz
  x= z= – Platz gilt als untauglich“ bzw. „… weiter als 25 m, nicht gesperrt“ bzw. „kein Ladeplatz an der Strasse
  bekannt (Shop-Platz oder Pool)“.

**Tests:** Mock (18 m → gesperrt + Diagnose; 40 m → nicht gesperrt + Diagnose; Shop-Platz → Diagnose; Diagnose nur
einmal; alter Aufruf ohne Radius bleibt bei 10 m); Strukturcheck, Vollparse, kein `pcall`.

# ERGÄNZUNG 2026-10-07 — Build 174: Stufe-1-Schleife erkennen

**Befund (Server-Log 07.10. 10:30–10:40, Build 173, Debug-Log an):** keine Fehler; Series 6M + Alpin Hit, Vario 500,
Vario 200 und Mach 4R fuhren alle vom Ladeplatz los und erreichten Durchfahrtsziele – kein Stillstand am Ladeplatz.
Zwei Auffälligkeiten:
- **Vario 200 (patrolId=-3) in einer Schleife:** ab 10:37 bei x≈-293 z≈-453 viermal „Stufe1 - 30s fest“ (10:37, 10:38,
  10:39, 10:40), dazwischen „sofort abgewiesen“ + 41 m auf die Straße gesetzt. Er rollte jedes Mal ein paar Meter
  (> 5 m → Wächter-Stufe zurück auf 0), Stufe 2/3 griffen nie. Nächste Fahrzeuge `relt.xml` 9–10 m, `superfex800.xml` 6 m
  (vermutlich abgestellte Geräte des Spielers – beim User nachgefragt).
- Ladeplatz-Diagnose meldete auch Stillstände weit weg („steht 444 m / 565 m vom Ladeplatz“) – nur Rauschen.

**Fix:**
- `merkeStufe1Schleife(w)`: merkt die Zeit jeder anstehenden Stufe 1 (`w.stufe1Zeiten`); die
  `STUFE1_SCHLEIFE_ANZAHL` = 3. binnen `STUFE1_SCHLEIFE_MS` = 5 min → Log „Stufe1 zum 3. Mal in 5 min – gilt als
  festgefahren, weiter mit Stufe 3“ und direkt Stufe 3 (einmal auf die KI-Straße setzen, sonst Pool). Liste wird danach
  geleert. Reihenfolge im Wächter: am Ziel → Begegnung → Schleife → Stufe 1 → 2 → 3.
- Stufe 3 als lokale Funktion `stufe3()` im Wächter (unverändert, von beiden Stellen aufgerufen).
- Ladeplatz-Diagnose nur bis `LADEPLATZ_DIAG_MAX` = 100 m vom Ladeplatz.

**Tests:** Mock `merkeStufe1Schleife` (0/60/120 s → dritte löst aus, Liste leer, 180 s → neu; 0/200/400/600 s → nie);
Strukturcheck, Vollparse, kein `pcall`.

**Ergebnis Build 174 (Server-Log 07.10. 10:51–11:24, Debug-Log an):** keine Fehler. Sechs Fahrzeuge geladen
(Series REX4, Series 6M + Volto 60, Proxima HS120 ×2, Vario 500 + Volto 60, Vario 300) – alle fuhren vom Ladeplatz los,
keine Ladeplatz-Diagnose nötig. 55 Durchfahrtsziele erreicht, 11× Stufe 1, 0× Stufe 2, 1× Stufe 3. Die neue
Schleifen-Erkennung griff einmal (11:08:22, Series 6M, patrolId=-2: „Stufe1 zum 3. Mal in 5 min“ → 11 m auf die
KI-Straße gesetzt, fuhr weiter). Die Begegnungs-Logik (Build 166) griff zum ersten Mal (11:03:56, „Begegnung mit
proximaHS120.xml – weicht 25 m auf die KI-Strasse aus“). Volto 60 wurde nach 3 Sofort-Abweisungen für die Session aus dem
Verkehr genommen (vorhandene Logik). Zwei Fahrzeuge gingen nach fertigen Hops in den Pool.
