#!/usr/bin/env python3
"""Baut FS25_NachbarFelder.zip.

NachbarFelder.lua ist der einzige Eintrag in extraSourceFiles; alle weiteren
Lua-Dateien laedt sie selbst per source(). Sie muessen trotzdem in die ZIP.

Die ZIP wird NUR hier im Codex-Ordner erzeugt und nicht in den Mods-Ordner
kopiert - das macht der Nutzer bzw. der Server-Upload selbst.
"""
import os
import zipfile

NAME = "FS25_NachbarFelder.zip"

DATEIEN = [
    "modDesc.xml",
    "icon_NachbarFelder.dds",
    # Einstiegspunkt (extraSourceFiles) - laedt den Rest per source()
    "NachbarFelder.lua",
    "NachbarFelderManager.lua",
    "NachbarFelderWorker.lua",
    "NachbarFelderSettingsPage.lua",
    "NachbarFelderUIHelper.lua",
    "NachbarFelderWaypointPage.lua",
    "NachbarFelderWaypointDialog.lua",
    # GUI
    "gui/NachbarFelderWaypointPage.xml",
    "gui/NachbarFelderWaypointDialog.xml",
    "gui/NachbarFelderGuiProfiles.xml",   # Build 135: Aktions-Buttons im Reiter Wegpunkte
    # Ingame-Hilfe (Build 153)
    "help/helpLine.xml",
    # Uebersetzungen stehen seit Build 169 inline in der modDesc (ModHub: ObsoleteFiles)
]

os.chdir(os.path.dirname(os.path.abspath(__file__)))

fehlend = [f for f in DATEIEN if not os.path.exists(f)]
if fehlend:
    raise SystemExit("FEHLEND: " + ", ".join(fehlend))

if os.path.exists(NAME):
    os.remove(NAME)

with zipfile.ZipFile(NAME, "w", zipfile.ZIP_DEFLATED) as z:
    for f in DATEIEN:
        # arcname explizit mit Vorwaertsschraegstrichen: os.sep wuerde unter
        # Windows Backslashes schreiben, die das Spiel im ZIP nicht als Ordner
        # erkennt.
        z.write(f, arcname=f.replace(os.sep, "/"))

print(f"{NAME} gebaut: {os.path.getsize(NAME):,} Bytes, {len(DATEIEN)} Dateien")
