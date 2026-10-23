#!/usr/bin/env python3
"""Prueft FS25_SiloUnloadAmount gegen die automatisch pruefbaren Punkte aus
docs/MODHUB_REGELN.md. Aufruf: py modhub_check.py  (baut vorher die ZIP mit build.py)."""
import os
import re
import struct
import zipfile
import xml.etree.ElementTree as ET

os.chdir(os.path.dirname(os.path.abspath(__file__)))
ZIP = "FS25_SiloUnloadAmount.zip"
fehler = []

root = ET.parse("modDesc.xml").getroot()
if root.get("descVersion") != "113":
    fehler.append("descVersion ist nicht 113")
if root.findtext("version") != "1.0.0.0":
    fehler.append("Version ist nicht 1.0.0.0")

for sprache in ("en", "de", "fr"):
    titel = root.findtext("title/" + sprache)
    if not titel:
        fehler.append("Titel fehlt: " + sprache)
    else:
        for wort in titel.split():
            if not wort[0].isupper():
                fehler.append("Titelwort klein (%s): %s" % (sprache, wort))
    beschreibung = root.findtext("description/" + sprache)
    if not beschreibung:
        fehler.append("Beschreibung fehlt: " + sprache)
    elif re.search(r"Änderung|Changelog|Neu:|Fix:", beschreibung):
        fehler.append("Changelog-Wort in description/" + sprache)

for text in root.iter("text"):
    for sprache in ("en", "de", "fr"):
        if not text.findtext(sprache):
            fehler.append("l10n %s ohne %s" % (text.get("name"), sprache))

de_texte = " ".join(e.text or "" for e in root.iter("de"))
for ersatz in ("fuer", "ueber", "Gebaeude", "waehl", "Menue", "laed", "hoechst", "oeffn"):
    if ersatz in de_texte:
        fehler.append("Ersatzschreibung im deutschen Text: " + ersatz)

if os.path.isdir("l10n") or os.path.isdir("i18n"):
    fehler.append("separater l10n/i18n-Ordner")

for name in os.listdir("."):
    if name.endswith(".lua"):
        code = open(name, encoding="utf-8").read()
        for verboten in ("pcall", "xpcall", "loadstring", "collectgarbage"):
            if re.search(r"\b%s\b" % verboten, code):
                fehler.append("%s in %s" % (verboten, name))

icon = root.findtext("iconFilename")
if not icon or not os.path.exists(icon):
    fehler.append("Icon fehlt")
else:
    daten = open(icon, "rb").read()
    if len(daten) != 131200:
        fehler.append("Icon hat %d statt 131200 Byte" % len(daten))
    if daten[84:88] != b"DXT1":
        fehler.append("Icon nicht DXT1")
    if struct.unpack_from("<I", daten, 12)[0] != 512 or struct.unpack_from("<I", daten, 16)[0] != 512:
        fehler.append("Icon nicht 512x512")
    if struct.unpack_from("<I", daten, 8)[0] != 0xA1007 or struct.unpack_from("<I", daten, 28)[0] != 1 \
       or struct.unpack_from("<I", daten, 108)[0] != 0x1000:
        fehler.append("Icon-Header weicht vom geprueften Icon ab")

if not os.path.exists(ZIP):
    fehler.append("ZIP fehlt - erst build.py ausfuehren")
else:
    namen = zipfile.ZipFile(ZIP).namelist()
    if "modDesc.xml" not in namen:
        fehler.append("modDesc.xml nicht im ZIP-Root")
    for n in namen:
        if not n.endswith((".xml", ".lua", ".dds", ".ogg", ".wav")):
            fehler.append("unerlaubte Datei im ZIP: " + n)
    for quelle in [e.get("filename") for e in root.iter("sourceFile")] + [icon]:
        if quelle not in namen:
            fehler.append("in modDesc genannt, fehlt im ZIP: " + quelle)

if fehler:
    print("FEHLER:")
    for f in fehler:
        print("  - " + f)
    raise SystemExit(1)
print("OK: keine Befunde. Von Hand: TestRunner 0.9.22, Manufacturer 'None', Screenshots 1600x900.")
