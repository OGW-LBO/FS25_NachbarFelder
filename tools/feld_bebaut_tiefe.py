"""NachbarFelder-Pruefung fuer eine neue Karte: wie tief ragen Placeables in die Feldumrisse?

Aufruf: py feld_bebaut_tiefe.py <Map-ZIP>
Nutzt feld_footprint.py (gleicher Ordner). Rechnet offline nach, was getBebauteFelder()
(Build 137) im Spiel prueft: rootNode, Grundflaechen-Raster (testAreas) und Zaunlinien;
Ausgabe = tiefster Punkt je Feld und Zahl der gesperrten Felder je Schwelle
(im Spiel BEBAUT_MIN_TIEFE = 1,0 m). Nur lesen.
"""
import math
import os
import runpy
import sys
from collections import defaultdict

karte = sys.argv[1]
sys.argv = ["feld_footprint.py", karte]
g = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "feld_footprint.py"))
inside, felder, placeables = g["inside"], g["felder"], g["placeables"]


def rand_abstand(x, zc, pts):
    best = 1e9
    for i in range(len(pts)):
        (ax, az), (bx, bz) = pts[i], pts[(i + 1) % len(pts)]
        dx, dz = bx - ax, bz - az
        l2 = dx * dx + dz * dz
        t = 0 if l2 == 0 else max(0, min(1, ((x - ax) * dx + (zc - az) * dz) / l2))
        best = min(best, math.hypot(x - ax - t * dx, zc - az - t * dz))
    return best


def punkte(p):
    out = []
    if not (abs(p["x"]) < 1 and abs(p["z"]) < 1):
        out.append((p["x"], p["z"], "root"))
    for r in p["rects"]:
        s, w, h = r[0], r[1], r[2]
        for i in range(5):
            for j in range(5):
                out.append((s[0] + (w[0] - s[0]) * i / 4 + (h[0] - s[0]) * j / 4,
                            s[1] + (w[1] - s[1]) * i / 4 + (h[1] - s[1]) * j / 4, "area"))
    for (a, b) in p["fence"]:
        n = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / 5.0)))
        for k in range(n + 1):
            out.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, "zaun"))
    return out


SKIP = {"newFence", "fence", "trainSystem"}
tiefe = defaultdict(lambda: (0.0, ""))
for fname, pts in felder:
    minx, maxx = min(q[0] for q in pts), max(q[0] for q in pts)
    minz, maxz = min(q[1] for q in pts), max(q[1] for q in pts)
    for p in placeables:
        pp = punkte(p)
        if p["typ"] in SKIP or "fence" in p["fn"].lower() or "hedge" in p["fn"].lower():
            pp = [q for q in pp if q[2] == "zaun"]
        for x, zc, art in pp:
            if minx <= x <= maxx and minz <= zc <= maxz and inside(x, zc, pts):
                d = rand_abstand(x, zc, pts)
                if d > tiefe[fname][0]:
                    tiefe[fname] = (d, "%s %s (%s)" % (p["typ"], os.path.basename(p["fn"]), art))

print("Felder mit Rasterpunkt im Feld:", len(tiefe))
for f, (d, wer) in sorted(tiefe.items(), key=lambda kv: -kv[1][0]):
    print("  %-9s max. %.1f m tief  %s" % (f, d, wer))
for schwelle in (0.5, 1, 2, 3, 5):
    print("Schwelle %.1f m -> %d Felder gesperrt" % (schwelle, sum(1 for d, _ in tiefe.values() if d >= schwelle)))
