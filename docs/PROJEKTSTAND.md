# FS25_NachbarFelder — Projektstand (Hand-off)

> Diese Datei fasst alles zusammen, damit in einem **neuen Chat** nahtlos weitergearbeitet werden
> kann. Bei neuem Chat sagen: *"Wir arbeiten an FS25_NachbarFelder weiter, lies den Projektstand
> in `Codex/NachbarFelder_PROJEKTSTAND.md`"*. Die Abschnitte darunter sind chronologisch gewachsen —
> **ältere Teile sind teils überholt; im Zweifel gilt der jüngste Abschnitt am Ende.**
>
> **ARBEITSGRUNDLAGE — Stand 2026-10-01 (hier zuerst lesen, alles darunter ist Historie)**
>
> **Stand**
> - **Build 141 (01.10.): Anfahrt über freien Feldrand + Abbruchgrund der Feldarbeit im Log** — Zielpunkt ist jetzt
>   die Randstelle mit der nächsten KI-Straße, deren Weg kein fremdes Feld / keine Weide kreuzt (`getFeldZugang`).
>   Offen: Lohnunternehmer-Auftrag auf eigenem Feld 47 endete nach 0 s — Grund steht ab 141 im Log. Abschnitt Build 141.
> - **Build 140 (01.10.): „Frucht steht“ auf abgeernteten Feldern behoben** — Messpunkte von `getFeldAktion` lagen
>   neben dem Feld (Grasstreifen gleiches Farmland). Jetzt nur Punkte im Feldumriss, ≥ 2 m vom Rand. Abschnitt Build 140.
> - **Build 139 (01.10.): Auftrag an den Lohnunternehmer** — Spieler steht an einem Feld und beauftragt die Helfer
>   mit genau diesem Feld, auch mit dem eigenen (Taste `NF_ORDER_FIELD`, Standard Strg+Alt+J, oder Reiter Wegpunkte →
>   „Lohnunternehmer“). Neue Datei `NachbarFelderAuftrag.lua`, Event `NachbarFelderAuftragEvent`. Details: Abschnitt Build 139 am Ende.
> - **Build 138 (24.09.): Helfer-Farm nicht mehr fest 2**, sondern Konfig `<farmId>` (0 = auto) bzw. automatisch die hoechste Farm ohne Spieler/Farmland/Gebaeude (Bergisch Land: Farm 6 Raufutterhandel). Grund: User wechselt mit seiner Farm auf Hof Klein = Farm 2. Log: `Helfer-Farm = N ...`.
> - **Build 137**, modDesc-Version `1.1.42.0` (wird nicht hochgezählt; maßgeblich ist `NachbarFelderManager.BUILD`,
>   im Log `loadMap auf SERVER (Build n)`). Alles muss **kartenunabhängig** sein.
> - ZIPs: `Codex\FS25_NachbarFelder_Build<N>.zip`, aktuell **Build137**. Build130/131-ZIPs sind fehlerhaft
>   (build.py + ZIP im ZIP) — nicht verwenden.
> - Deploy macht der User selbst (Server per FTP + eigener Mods-Ordner). **Nie** selbst in den Mods-Ordner legen.
> - Im Spiel noch ungetestet: Build 135 (Buttons), 136 (Spurwahl, Pool), 137 („bebaut" je Feldumriss), 138 und 139.
>
> **Arbeitsweise (verbindlich)**
> - Bauen nur mit `py build.py` im Quellordner (feste Liste, **15 Dateien** seit Build 139; neue Dateien in `DATEIEN` eintragen).
> - GitHub-Release: `.github/workflows/release.yml` baut mit `build.py` und legt Release `build<N>` mit
>   `FS25_NachbarFelder.zip` an — bei Push auf `main` (Merge), Tag `build<N>` oder „Run workflow“; schon vorhandenes
>   Release → nichts. Neues Release nur mit hochgezähltem `BUILD`. ZIP-Name nie ändern = Mod-Name.
>   Claude-Sitzungen dürfen nur ihren Branch pushen (keine Tags) → Release entsteht beim Merge.
> - Prüfen: `lsc.py` (Skill `ls25-modding/references/lua_syntax_check.py`, Kopie `%TEMP%\lsc.py`) + Vollparse mit
>   Python-`luaparser` oder `lupa` (`load()` ohne Ausführen; vorher `continue` → `break` ersetzen, GIANTS-Lua kennt
>   `continue`; BOM vorher entfernen); XML mit minidom.
> - API-Verifikation: Die LUADOC-Webseite kann gesperrt sein; dann das Repo `umbraprior/FS25-Community-LUADOC`
>   (Sparse-Checkout `docs/script/...`) lesen.
> - Textdateien nur per Edit-Tool oder Python-Bytes ändern (PowerShell Get-/Set-Content erzeugt Zeichensalat).
>   Nachträge hier per Python anhängen, diesen Kopf aktuell halten.
> - Logs: Server-Log schickt der User (eingefügt oder `Downloads\NeuServerLog.txt`). Client-Log:
>   `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt` + Unterordner `logs\`
>   („OneDrive" ist dort nur Ordnername, der Sync ist aus — nie als Ursache anführen).
> - Spielcode: `sdk\debugger\gameSource.zip` (Mission-Basisdateien fehlen, MathUtil-Rümpfe leer);
>   GUI-Profile samt Presets/Traits: `sdk\xmlDoku\guiProfiles.xml`; Karten-Objekte: `maps/config/placeables.xml` der Map-ZIP.
>
> **Server & Karten**
> - **Bergisch Land (seit 19.09., aktuell):** Server = VMware-Maschine (Ryzen 7 5700G, 4 vCores, 16 GB,
>   Profil `<Serverprofil>`, savegame1); jedes neu geladene Fahrzeugmodell kostet dort 1–2 s Stillstand.
>   Karte: **138 Felder und Wiesen** (0,2–4,2 ha; NF-Statistik: 31 Grünland), **8 Kuhweiden** (Placeables
>   Kuhweide1–8), **kaufbares Bauland** (Placeable `Deko_Bauland`), 968 Karten-Placeables (456 Wetter-Effekte/Laub,
>   217 Deko, 36 Zäune, 31 Silos, 28 Häuser, 22 Hallen, 13 Ställe …; keins steht in einem Feldumriss). KI-Straßen: 130 Splines (61 mit „R"-Zwilling,
>   7 Einbahn) + 29 aus Placeables; Shop x=-418 z=-25. Noch keine eigenen Wegpunkte/Spawnpunkte
>   (Datei `NachbarFelderWaypoints_FS25_BergischLand_BaseMap.xml`).
> - **Beuren (bis 18.09.):** Proxmox-Server (Ryzen 9 7900). 38 Wegpunkte; Spawnpunkte WP37 (868/−768) und
>   WP38 (729/−877) ungünstig — der Weg führt über den Landhandel-Hof x≈787 z≈−908 (Engstelle).
>   Datei `NachbarFelderWaypoints_FS25_Beuren_MultifruitModMap_Beuren.xml`.
>
> **Bedienung (User)**
> - ESC → Einstellungen → Reiter **Wegpunkte**: Buttons „Wegpunkt/Spawnpunkt hier setzen", Typ ändern, Löschen,
>   Teleportieren (nur Admin). Spawnpunkt: im Traktor auf der rechten Spur, Front in Fahrtrichtung, danach wegfahren.
> - Tasten beim User (Profil `inputBinding.xml`): Wegpunkt setzen **Strg+Alt+O**, Helfer starten Strg+Alt+N,
>   alles entfernen Strg+Alt+L, Shift+Alt+X/W (lösen Alt+X/Shift+X mit aus → umlegen). Neue Standards seit 134:
>   Strg+Alt+O/U/C/E/L, seit 139 zusätzlich Strg+Alt+J (Lohnunternehmer; Kollision mit Strg+J/Alt+J nicht geprüft).
>   Vor Tastentipps immer das Profil prüfen.
> - Lohnunternehmer (Build 139): an ein Feld stellen (im Feld oder ≤ 25 m vom Rand) → Strg+Alt+J oder Reiter
>   Wegpunkte → „Dieses Feld bearbeiten lassen“. Antwort als Meldung und in der Infozeile des Reiters.
>
> **Offene Punkte (nach Priorität)**
> 0. **Build 139 testen** (Auftrag an den Lohnunternehmer), Testplan im Abschnitt Build 139 am Ende.
> 1. Servertest Build 137 auf Bergisch Land (enthält 136): im Log `0 Felder bebaut (Hindernis mind. 1 m im Feld)`,
>    in der Feldarbeit-Statistik `0 bebaut` statt 83 und danach echte Feldaufträge; `[POOL] … aufgeweckt` muss
>    auftauchen, „sofort abgewiesen" und „Ladeplatz … taugt nicht" deutlich seltener.
> 2. ~~Feldarbeit auf Bergisch Land = 0 Felder~~ → **Build 137:** „bebaut" je Feldumriss statt je Farmland
>    (Hindernis mit Kollision ≥ 1 m im Feld: rootNode, Grundfläche, Zaunlinie). Offline gerechnet: Bergisch Land
>    0 von 138 Feldern (vorher 83), Beuren und Krebach 0. Was danach bremst, zeigt die Statistik (Frucht steht,
>    schon bearbeitet, Grünland). Prüfskript für neue Karten: `NachbarFelder\tools\feld_bebaut_tiefe.py`.
> 3. Spawnpunkte setzen: Bergisch Land 2–3 außerhalb des Orts; Beuren WP37/38 ersetzen.
> 4. Aus Test 134 angeboten: Engstellen-Erkennung statt Gespann-Sperre, Spawnpunkt-Bilanz bis zum ersten
>    Ziel (Pause nach 2 Fehlschlägen), Rettungs-Teleports begrenzen.
> 5. Falls 136 nicht reicht: Ziel sperren, das von ≥ 2 Standorten sofort abgewiesen wird.
> 6. TestRunner mit der aktuellen ZIP.
>
> **Verifizierte Engine-Fakten** (Details im Memory)
> - Clients interpolieren jede Server-Positionsänderung (Vehicle.lua:1768) → jeder Teleport ist ein sichtbarer Flug.
> - KI-Straßen sind Einbahn-Splines (Gegenverkehr = „R"-Zwilling), die KI fährt nur vorwärts →
>   nie gegen die Spline drehen, Spur mit `getRoadPointInRichtung` wählen.
> - Spielerfahrzeug nur über `player:getCurrentVehicle()`, Blickrichtung zu Fuß `getMapPositionAndLookYaw()`.
> - Buttons in Einstellungszeilen: echtes `Button` + eigenes Profil per `g_gui:loadProfiles`, nie MultiTextOption.
> - Feldumriss = `field.polygonPoints` (Knoten), Placeable-Grundfläche = `spec_placement.testAreas`
>   (start-/endNode), Kollision = `placeable.pickObjects` (leer = keine). Zaun-, Hecken- und Zug-rootNodes
>   liegen oft im Kartenursprung. Feldumrisse stehen lesbar in der `map.i3d` (UserAttribute `polygonIndex`).
>
> **Code-Kurzreferenz**
> - Manager: `addWaypointAtPlayer(cat)`, `waehleSpawnpunkt`, `setzeLadepositionStrasse`, `getRoadPointInRichtung`,
>   `buildRoadSamples`/`buildRoadWaypointList` (Straßenziele, Mindestabstand 200 m), `getPatrolWaypointList`,
>   `sleepPatrolEntry`/`wakePooledVehicle`, `merkeSpawnFehlschlag`, `getBebauteFelder`, `isPunktInWeide`,
>   `getPlaceableHindernis`/`getFeldPolygon` (Build 137, Konstanten `BEBAUT_*`),
>   `saveWaypoints`/`loadWaypoints` (Datei je Karte).
> - Worker: `onAIJobFinished` (Abweisungen, `pathFails`, `nfRoadSnap`, `nfMarkStartPlaceBad`).
> - Seite: `NachbarFelderWaypointPage.BUTTON_TEXT`, Profile in `gui/NachbarFelderGuiProfiles.xml`.
> - Feldnummer = immer `field:getId()` = Schlüssel für `getFieldById` (`getFeldNummer`, `getFeldNummern`); NIE den
>   Listenplatz aus `getFields()` als Nummer nehmen (Build 139, siehe dort).
> - Auftrag (Build 139): `NachbarFelderAuftrag.anfordern` (Client), `.ausfuehren` (Server), `.pruefe`, `.starte`,
>   `.getFeldAnPosition`, `.starteGespeichert`; Worker-Felder `istAuftrag`/`auftragFarmId`.
> - Events: `NachbarFelderAuftragEvent` (Build 139, beide Richtungen, `connection:getIsServer()`);
>   `NachbarFelderWaypointEditEvent` OP 1 ADD, 2 REMOVELAST, 3 DELETE, 4 SETCAT, 5 VEHCAT, 6 ADD_SPAWN;
>   Liste an Clients per `NachbarFelderWaypointSyncEvent`.
> - WP-Kategorien: 0 Normal, 1 Kurz, 2 Lang, 3 Durchfahrt (Straßenziele), 4 Spawnpunkt.
>
> **Log-Lesehilfe**
> - `sofort abgewiesen … AIMessageErrorNotReachable` (< 100 ms) = Start oder Ziel unerreichbar (Spur, Sackgasse);
>   `nicht erreichbar` nach > 1,5 s = Weg gesucht, keiner gefunden.
> - `Ladeplatz x/z taugt nicht` = für die Session gesperrt; `Spawnpunkt WPn: …` = Hinweis zum Admin-Spawnpunkt.
> - `30s ohne Bewegung … naechstes Fahrzeug X in n m` = blockiert; Stufe1/2 = neues Ziel, Stufe3 = Rettungs-Teleport.
> - `Feldhelfer … zweiter Stillstand … gesperrt` = Gespann für die Session gesperrt.
> - `n Felder bebaut (Hindernis mind. 1 m im Feld) … : Feld x (Name)` = diese Felder lässt die Feldarbeit aus
>   (erscheint beim ersten Mal und wenn sich die Zahl ändert); übersehene Hindernisse: `nachbarFelderSperre <Nr>`.
> - `[PERF]` nur mit Spielern; 200-ms-Frames im Leerlauf = Drosselung des Servers, kein Fehler.

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

