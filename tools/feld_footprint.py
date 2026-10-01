"""Karten-Analyse: Ueberlappen Placeable-Grundflaechen (testAreas) oder Weidezaeune ein Feldpolygon?

Aufruf: py feld_footprint.py <Map-ZIP>
Nur lesen. Simuliert offline, was Build 137 zur Laufzeit rechnet.
"""
import math
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

MAPZIP = sys.argv[1]


def _ersterOrdner(*kandidaten):
    """Erster Pfad, den es wirklich gibt - sonst der erste als Hinweis."""
    for p in kandidaten:
        if p and os.path.isdir(p):
            return p
    return kandidaten[0]


# Pfade notfalls per Umgebungsvariable setzen:
#   set FS25_GAME_DIR=D:\Spiele\Farming Simulator 2025
#   set FS25_MODS_DIR=D:\FS25\mods
_home = os.path.expanduser("~")
GAME = os.environ.get("FS25_GAME_DIR") or _ersterOrdner(
    r"C:\Program Files (x86)\Farming Simulator 2025",
    r"C:\Program Files\Farming Simulator 2025")
MODS = os.environ.get("FS25_MODS_DIR") or _ersterOrdner(
    os.path.join(_home, "Documents", "My Games", "FarmingSimulator2025", "mods"),
    os.path.join(_home, "OneDrive", "Documents", "My Games", "FarmingSimulator2025", "mods"))
NODETAGS = ("TransformGroup", "Shape", "Light", "Camera", "Dynamic", "Spline", "AudioSource")

z = zipfile.ZipFile(MAPZIP)
low = {n.lower(): n for n in z.namelist()}
modzips = {}


def mapread(n):
    return z.read(low[n.lower().lstrip("/")])


def resolve(fn):
    """liefert (bytes, basis-loader) fuer eine Placeable-/i3d-Datei."""
    if fn.startswith("$mapdir$"):
        inner = fn[len("$mapdir$"):].lstrip("/")
        return mapread(inner), ("map", os.path.dirname(inner))
    if fn.startswith("$moddir$"):
        modname, inner = fn[len("$moddir$"):].split("/", 1)
        if modname not in modzips:
            modzips[modname] = zipfile.ZipFile(os.path.join(MODS, modname + ".zip"))
        mz = modzips[modname]
        ml = {n.lower(): n for n in mz.namelist()}
        return mz.read(ml[inner.lower()]), ("mod:" + modname, os.path.dirname(inner))
    if fn.startswith("$data/") or fn.startswith("data/"):
        rel = fn.split("data/", 1)[1]
        p = os.path.join(GAME, "data", rel.replace("/", os.sep))
        return open(p, "rb").read(), ("data", os.path.dirname("data/" + rel))
    return mapread(fn), ("map", os.path.dirname(fn))


def read_rel(base, rel):
    kind, d = base
    path = os.path.normpath(os.path.join(d, rel)).replace("\\", "/")
    if rel.startswith("$data/") or rel.startswith("data/"):
        return resolve(rel)[0]
    if kind == "map":
        return mapread(path)
    if kind.startswith("mod:"):
        mz = modzips[kind[4:]]
        ml = {n.lower(): n for n in mz.namelist()}
        return mz.read(ml[path.lower()])
    return open(os.path.join(GAME, path.replace("/", os.sep)), "rb").read()


def mulm(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rotmat(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    return mulm([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]],
                mulm([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]], [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]))


def apply(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def vec(s):
    return [float(v) for v in (s or "0 0 0").split()]


# ---------------------------------------------------------------- Karte
md = ET.fromstring(mapread("modDesc.xml"))
mapel = next(md.iter("map"))
mx = ET.fromstring(mapread(mapel.attrib["configFilename"]))
i3d = mx.find("filename").text
pl_file = mapel.attrib.get("defaultPlaceablesXMLFilename")
for e in mx.iter("placeables"):
    pl_file = e.attrib.get("filename") or pl_file

root = ET.fromstring(mapread(i3d))
ua = defaultdict(dict)
for u in root.iter("UserAttribute"):
    for a in u:
        ua[u.attrib.get("nodeId")][a.attrib.get("name")] = a.attrib.get("value")
felder = []


def walk(node, M, T):
    for ch in node:
        if ch.tag not in NODETAGS:
            continue
        CT = [a + b for a, b in zip(T, apply(M, vec(ch.attrib.get("translation"))))]
        CM = mulm(M, rotmat(*vec(ch.attrib.get("rotation"))))
        attrs = ua.get(ch.attrib.get("nodeId"), {})
        if "polygonIndex" in attrs:
            target, tM, tT = ch, CM, CT
            for i in [int(v) for v in attrs["polygonIndex"].split("|")]:
                target = [k for k in target if k.tag in NODETAGS][i]
                tT = [a + b for a, b in zip(tT, apply(tM, vec(target.attrib.get("translation"))))]
                tM = mulm(tM, rotmat(*vec(target.attrib.get("rotation"))))
            pts = []
            for p in target:
                if p.tag == "TransformGroup":
                    w = [a + b for a, b in zip(tT, apply(tM, vec(p.attrib.get("translation"))))]
                    pts.append((w[0], w[2]))
            if len(pts) >= 3:
                felder.append((ch.attrib.get("name"), pts))
        walk(ch, CM, CT)


walk(root.find("Scene"), [[1, 0, 0], [0, 1, 0], [0, 0, 1]], [0, 0, 0])

# ---------------------------------------------------------------- Placeables
i3dcache = {}


def i3d_node_local(i3dbytes_key, i3dxml, index):
    """Weltmatrix relativ zum Placeable-rootNode (Komponente) fuer Index 'c>a|b|c'."""
    scene = i3dxml.find("Scene")
    comps = [k for k in scene if k.tag in NODETAGS]
    if ">" in index:
        ci, path = index.split(">", 1)
    else:
        ci, path = "0", index
    node = comps[int(ci)]
    M = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    T = [0, 0, 0]
    if path != "":
        for i in [int(v) for v in path.split("|")]:
            node = [k for k in node if k.tag in NODETAGS][i]
            T = [a + b for a, b in zip(T, apply(M, vec(node.attrib.get("translation"))))]
            M = mulm(M, rotmat(*vec(node.attrib.get("rotation"))))
    return M, T, node


placeables = []
fehler = Counter()
for p in ET.fromstring(mapread(pl_file)).iter("placeable"):
    fn = p.attrib.get("filename", "")
    pos, rot = vec(p.attrib.get("position")), vec(p.attrib.get("rotation"))
    fence = []
    for seg in p.iter("segment"):
        s, e = vec(seg.attrib.get("start")), vec(seg.attrib.get("end"))
        fence.append(((s[0], s[2]), (e[0], e[2])))
    typ, rects = "?", []
    try:
        data, base = resolve(fn)
        x = ET.fromstring(data)
        typ = x.attrib.get("type", "?")
        maps = {m.attrib["id"]: m.attrib["node"] for m in x.iter("i3dMapping")}
        tas = [(t.attrib.get("startNode"), t.attrib.get("endNode")) for t in x.iter("testArea")
               if t.attrib.get("startNode") and t.attrib.get("endNode")]
        if tas:
            i3dname = x.find("base/filename").text
            key = (base, i3dname)
            if key not in i3dcache:
                i3dcache[key] = ET.fromstring(read_rel(base, i3dname))
            ix = i3dcache[key]
            PM = rotmat(*rot)
            for sn, en in tas:
                sidx, eidx = maps.get(sn, sn), maps.get(en, en)
                SM, ST, snode = i3d_node_local(key, ix, sidx)
                ev = vec(i3d_node_local(key, ix, eidx)[2].attrib.get("translation"))
                corners = []
                for lx, lz in ((0, 0), (ev[0], 0), (0, ev[2]), (ev[0], ev[2])):
                    loc = [a + b for a, b in zip(ST, apply(SM, [lx, 0, lz]))]
                    w = [a + b for a, b in zip(pos, apply(PM, loc))]
                    corners.append((w[0], w[2]))
                rects.append(corners)
    except Exception as ex:
        fehler[type(ex).__name__] += 1
    placeables.append({"fn": fn, "typ": typ, "x": pos[0], "z": pos[2], "rects": rects, "fence": fence})

print("Karte:", os.path.basename(MAPZIP), "| Felder:", len(felder), "| Placeables:", len(placeables),
      "| mit testArea:", sum(1 for p in placeables if p["rects"]), "| Lesefehler:", dict(fehler))


# ---------------------------------------------------------------- Geometrie
def inside(x, zc, pts):
    drin, j = False, len(pts) - 1
    for i in range(len(pts)):
        (xi, zi), (xj, zj) = pts[i], pts[j]
        if (zi > zc) != (zj > zc) and x < xi + (zc - zi) / (zj - zi) * (xj - xi):
            drin = not drin
        j = i
    return drin


def seg_x(a, b, c, d):
    def cr(o, p, q):
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    d1, d2, d3, d4 = cr(c, d, a), cr(c, d, b), cr(a, b, c), cr(a, b, d)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0)


def in_rect(px, pz, r):
    s, w, h = r[0], r[1], r[2]
    ux, uz = w[0] - s[0], w[1] - s[1]
    vx, vz = h[0] - s[0], h[1] - s[1]
    dx, dz = px - s[0], pz - s[1]
    uu, vv = ux * ux + uz * uz, vx * vx + vz * vz
    if uu == 0 or vv == 0:
        return False
    a, b = (dx * ux + dz * uz) / uu, (dx * vx + dz * vz) / vv
    return 0 <= a <= 1 and 0 <= b <= 1


def rect_hits_poly(r, pts):
    ordered = [r[0], r[1], r[3], r[2]]
    if any(inside(x, zc, pts) for x, zc in ordered):
        return True
    if any(in_rect(x, zc, r) for x, zc in pts):
        return True
    for i in range(4):
        a, b = ordered[i], ordered[(i + 1) % 4]
        for j in range(len(pts)):
            if seg_x(a, b, pts[j], pts[(j + 1) % len(pts)]):
                return True
    return False


def kat(p):
    b = p["fn"].lower()
    if "weathereffect" in b:
        return "Wetter-Effekt"
    return p["typ"]


SKIP = {"newFence", "fence", "trainSystem"}
treffer_rect = defaultdict(list)
treffer_root = defaultdict(list)
treffer_weide = defaultdict(list)
for fname, pts in felder:
    minx, maxx = min(q[0] for q in pts), max(q[0] for q in pts)
    minz, maxz = min(q[1] for q in pts), max(q[1] for q in pts)
    for p in placeables:
        if p["typ"] in SKIP or (abs(p["x"]) < 1 and abs(p["z"]) < 1):
            continue
        if minx - 5 <= p["x"] <= maxx + 5 and minz - 5 <= p["z"] <= maxz + 5 and inside(p["x"], p["z"], pts):
            treffer_root[fname].append(kat(p))
        for r in p["rects"]:
            rx = [c[0] for c in r]; rz = [c[1] for c in r]
            if max(rx) < minx or min(rx) > maxx or max(rz) < minz or min(rz) > maxz:
                continue
            if rect_hits_poly(r, pts):
                treffer_rect[fname].append((kat(p), os.path.basename(p["fn"])))
                break
        if p["fence"] and p["typ"] not in SKIP:
            wpts = [s for s, _ in p["fence"]]
            if len(wpts) >= 3:
                if any(inside(x, zc, wpts) for x, zc in pts) or any(inside(x, zc, pts) for x, zc in wpts):
                    treffer_weide[fname].append(os.path.basename(p["fn"]))

print("Felder mit rootNode innen:", len(treffer_root), dict(Counter(k for v in treffer_root.values() for k in v)))
print("Felder mit Grundflaeche (testArea) ueber dem Feld:", len(treffer_rect))
print("   nach Typ:", Counter(k for v in treffer_rect.values() for k, _ in v).most_common())
nicht_deko = {f: v for f, v in treffer_rect.items()
              if any(k not in ("Wetter-Effekt", "simplePlaceable", "decoObject", "?") for k, _ in v)}
print("   davon mit Funktions-Placeable:", len(nicht_deko))
for f in sorted(treffer_rect, key=lambda s: int(re.sub(r"\D", "", s) or 0)):
    print("     ", f, treffer_rect[f][:4])
print("Felder, die eine Weide (Zaun) ueberlappen:", len(treffer_weide))
for f in sorted(treffer_weide, key=lambda s: int(re.sub(r"\D", "", s) or 0)):
    print("     ", f, treffer_weide[f][:3])
