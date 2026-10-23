#!/usr/bin/env python3
"""Baut FS25_SiloAbgabemenge.zip im Ordner dieser Datei.

modDesc.xml muss in der ZIP ganz oben liegen, deshalb wird die feste
Dateiliste einzeln gepackt und nicht der Ordner.
"""
import os
import zipfile

NAME = "FS25_SiloAbgabemenge.zip"

DATEIEN = [
    "modDesc.xml",
    "icon_SiloAbgabemenge.dds",
    "SiloAbgabemenge.lua",
    "gui/SiloAbgabemengeDialog.xml",
]

os.chdir(os.path.dirname(os.path.abspath(__file__)))

fehlend = [f for f in DATEIEN if not os.path.exists(f)]
if fehlend:
    raise SystemExit("FEHLEND: " + ", ".join(fehlend))

if os.path.exists(NAME):
    os.remove(NAME)

with zipfile.ZipFile(NAME, "w", zipfile.ZIP_DEFLATED) as z:
    for f in DATEIEN:
        z.write(f, arcname=f.replace(os.sep, "/"))

print(f"{NAME} gebaut: {os.path.getsize(NAME):,} Bytes, {len(DATEIEN)} Dateien")
