"""Hilfe-Bilder fuer Lebendige Strassen: 512x256 Motiv in 512x512-DDS (DXT1).
Ohne Text (sprachneutral). Aufruf: python3 hilfebilder.py <zielordner>"""
import math, os, struct, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # Supersampling
W, H = 512 * S, 256 * S
ZIEL = sys.argv[1]
os.makedirs(ZIEL, exist_ok=True)

GRUEN = (126, 206, 94)
ASPHALT = (78, 80, 86)
LINIE = (232, 230, 220)


def leinwand(farbe=(44, 52, 48)):
    img = Image.new("RGB", (W, H), farbe)
    return img, ImageDraw.Draw(img)


def speichern(img, name):
    klein = img.resize((512, 256), Image.LANCZOS)
    tex = Image.new("RGB", (512, 512), (40, 46, 44))
    tex.paste(klein, (0, 0))
    pfad = os.path.join(ZIEL, name + ".dds")
    tex.save(pfad, pixel_format="DXT1")
    # Header wie beim ModHub-geprueften Icon: dwFlags 0xA1007, dwMipMapCount 1, dwCaps 0x1000
    with open(pfad, "r+b") as f:
        kopf = bytearray(f.read(128))
        struct.pack_into("<I", kopf, 8, 0xA1007)
        struct.pack_into("<I", kopf, 28, 1)
        struct.pack_into("<I", kopf, 108, 0x1000)
        f.seek(0)
        f.write(kopf)


def traktor(d, cx, base, s, col, geraet=True):
    if geraet:
        d.rectangle([cx-150*s, base-70*s, cx-96*s, base-58*s], fill=(70, 70, 70))
        d.polygon([(cx-150*s, base-62*s), (cx-120*s, base-140*s), (cx-110*s, base-140*s), (cx-128*s, base-62*s)], fill=(214, 72, 56))
        d.polygon([(cx-128*s, base-62*s), (cx-100*s, base-128*s), (cx-90*s, base-128*s), (cx-108*s, base-62*s)], fill=(230, 90, 70))
        for k in range(3):
            d.ellipse([cx-160*s+k*16*s, base-34*s, cx-136*s+k*16*s, base-10*s], fill=(30, 30, 30))
        d.line([(cx-96*s, base-64*s), (cx-70*s, base-56*s)], fill=(70, 70, 70), width=int(6*s))
    d.rounded_rectangle([cx-78*s, base-92*s, cx+70*s, base-40*s], radius=int(10*s), fill=col)
    d.rounded_rectangle([cx-10*s, base-104*s, cx+92*s, base-48*s], radius=int(12*s), fill=col)
    d.rectangle([cx+84*s, base-96*s, cx+96*s, base-56*s], fill=(50, 50, 50))
    d.rounded_rectangle([cx-74*s, base-196*s, cx+4*s, base-88*s], radius=int(10*s), fill=(45, 50, 55))
    d.rounded_rectangle([cx-66*s, base-186*s, cx-4*s, base-100*s], radius=int(6*s), fill=(160, 200, 220))
    # Fahrer (bleibt seit Build 168 sitzen)
    d.ellipse([cx-46*s, base-170*s, cx-24*s, base-148*s], fill=(230, 190, 150))
    d.rounded_rectangle([cx-52*s, base-148*s, cx-18*s, base-104*s], radius=int(8*s), fill=(60, 90, 150))
    d.line([(cx-36*s, base-186*s), (cx-36*s, base-100*s)], fill=(45, 50, 55), width=int(4*s))
    d.rectangle([cx-80*s, base-204*s, cx+10*s, base-192*s], fill=col)
    d.rectangle([cx+30*s, base-150*s, cx+38*s, base-104*s], fill=(40, 40, 40))

    def rad(x, r):
        d.ellipse([x-r, base-2*r, x+r, base], fill=(26, 26, 26))
        d.ellipse([x-r*0.55, base-r-r*0.55, x+r*0.55, base-r+r*0.55], fill=(205, 205, 200))
        d.ellipse([x-r*0.2, base-r-r*0.2, x+r*0.2, base-r+r*0.2], fill=(90, 90, 90))
    rad(cx-46*s, 58*s)
    rad(cx+62*s, 40*s)


def ueberblick():
    img, d = leinwand()
    for y in range(H):
        t = min(y / (H*0.6), 1)
        d.line([(0, y), (W, y)], fill=(int(120+130*t), int(170+40*t), int(225-70*t)))
    sx, sy, sr = int(W*0.82), int(H*0.30), int(26*S)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([sx-sr*2.4, sy-sr*2.4, sx+sr*2.4, sy+sr*2.4], fill=(255, 230, 160, 100))
    glow = glow.filter(ImageFilter.GaussianBlur(18*S))
    img.paste(glow, (0, 0), glow)
    d = ImageDraw.Draw(img)
    d.ellipse([sx-sr, sy-sr, sx+sr, sy+sr], fill=(255, 238, 185))

    def huegel(base, amp, freq, phase, col):
        pts = [(0, H)] + [(x, base+amp*math.sin(x/W*math.pi*freq+phase)) for x in range(0, W+1, 8)] + [(W, H)]
        d.polygon(pts, fill=col)
    huegel(H*0.56, 10*S, 2.2, 0.6, (132, 166, 104))
    huegel(H*0.62, 12*S, 1.6, 2.0, (108, 152, 80))
    huegel(H*0.70, 8*S, 1.2, 1.0, (94, 138, 66))
    road = [(0, H), (int(W*0.70), H), (int(W*0.90), int(H*0.62)), (int(W*0.84), int(H*0.62))]
    d.polygon(road, fill=ASPHALT)
    for i in range(12):
        def p(t):
            x0, y0, x1, y1 = W*0.35, H, W*0.87, H*0.62
            tt = 1-(1-t)**1.8
            return (x0+(x1-x0)*tt, y0+(y1-y0)*tt)
        d.line([p(i/12), p((i+0.5)/12)], fill=LINIE, width=max(1, int((1-i/12)*4*S)))
    traktor(d, int(W*0.30), int(H*0.95), 0.62*S, (52, 140, 70))
    traktor(d, int(W*0.80), int(H*0.70), 0.2*S, (210, 160, 44), geraet=False)
    speichern(img, "hilfe_ueberblick")


def pin(d, x, y, r, col):
    d.polygon([(x-r*0.8, y-r*1.2), (x+r*0.8, y-r*1.2), (x, y+r*0.6)], fill=col)
    d.ellipse([x-r, y-r*2.4, x+r, y-r*0.4], fill=col)
    d.ellipse([x-r*0.42, y-r*1.82, x+r*0.42, y-r*0.98], fill=(250, 250, 245))


def karte_grund():
    img, d = leinwand((92, 130, 70))
    felder = [((0.02, 0.05, 0.30, 0.42), (160, 150, 90)), ((0.62, 0.05, 0.98, 0.40), (120, 160, 80)),
              ((0.05, 0.62, 0.38, 0.95), (176, 160, 100)), ((0.66, 0.60, 0.97, 0.96), (110, 150, 74))]
    for (a, b, c, e), col in felder:
        d.rectangle([W*a, H*b, W*c, H*e], fill=col)
        for k in range(1, 12):
            x = W*a + (W*(c-a))*k/12
            d.line([(x, H*b), (x, H*e)], fill=tuple(max(0, v-18) for v in col), width=S)
    return img, d


def strasse(d, pts, breite):
    d.line(pts, fill=ASPHALT, width=breite, joint="curve")
    for p in pts:
        d.ellipse([p[0]-breite/2, p[1]-breite/2, p[0]+breite/2, p[1]+breite/2], fill=ASPHALT)


def wegpunkte():
    img, d = karte_grund()
    b = 22*S
    haupt = [(0, H*0.52), (W*0.45, H*0.52), (W*0.62, H*0.48), (W, H*0.50)]
    neben = [(W*0.45, H*0.52), (W*0.50, H*0.75), (W*0.52, H)]
    strasse(d, haupt, b)
    strasse(d, neben, b)
    # gestrichelte Fahrt
    route = [(W*0.10, H*0.52), (W*0.45, H*0.52), (W*0.50, H*0.75), (W*0.515, H*0.92)]
    for i in range(len(route)-1):
        (x0, y0), (x1, y1) = route[i], route[i+1]
        n = int(math.hypot(x1-x0, y1-y0) / (14*S))
        for k in range(0, n, 2):
            d.line([(x0+(x1-x0)*k/n, y0+(y1-y0)*k/n), (x0+(x1-x0)*(k+1)/n, y0+(y1-y0)*(k+1)/n)], fill=(250, 240, 120), width=3*S)
    # Spawnpunkt (blau, Ring)
    sx, sy = W*0.10, H*0.52
    d.ellipse([sx-16*S, sy-16*S, sx+16*S, sy+16*S], outline=(90, 170, 255), width=4*S)
    d.ellipse([sx-7*S, sy-7*S, sx+7*S, sy+7*S], fill=(90, 170, 255))
    for x, y in [(W*0.45, H*0.52), (W*0.80, H*0.49), (W*0.515, H*0.92)]:
        pin(d, x, y, 14*S, GRUEN)
    speichern(img, "hilfe_wegpunkte")


def einstellungen():
    img, d = leinwand((34, 40, 38))
    d.rounded_rectangle([W*0.06, H*0.08, W*0.94, H*0.92], radius=14*S, fill=(52, 60, 56))
    zeilen = 5
    for i in range(zeilen):
        y = H*0.17 + i*H*0.155
        d.rounded_rectangle([W*0.10, y, W*0.36, y+H*0.07], radius=4*S, fill=(110, 120, 114))
        if i % 2 == 0:
            d.rounded_rectangle([W*0.46, y+H*0.025, W*0.88, y+H*0.045], radius=4*S, fill=(84, 92, 88))
            pos = [0.62, 0.74, 0.55][i // 2]
            d.rounded_rectangle([W*0.46, y+H*0.025, W*pos, y+H*0.045], radius=4*S, fill=GRUEN)
            d.ellipse([W*pos-11*S, y+H*0.035-11*S, W*pos+11*S, y+H*0.035+11*S], fill=(240, 245, 236))
        else:
            an = i == 1
            x0 = W*0.76
            d.rounded_rectangle([x0, y, x0+W*0.12, y+H*0.07], radius=int(H*0.035), fill=GRUEN if an else (90, 98, 94))
            kx = x0 + (W*0.12 - H*0.035) if an else x0 + H*0.035
            d.ellipse([kx-H*0.03, y+H*0.005, kx+H*0.03, y+H*0.065], fill=(240, 245, 236))
    speichern(img, "hilfe_einstellungen")


def tasten():
    img, d = leinwand((34, 40, 38))
    # Tastenreihe
    breite, abst = 58*S, 10*S
    x0 = W*0.06
    for i in range(7):
        x = x0 + i*(breite+abst)
        hell = i in (0, 1, 4)
        d.rounded_rectangle([x, H*0.10+6*S, x+breite, H*0.10+breite+6*S], radius=8*S, fill=(20, 24, 22))
        d.rounded_rectangle([x, H*0.10, x+breite, H*0.10+breite], radius=8*S, fill=GRUEN if hell else (96, 104, 100))
        d.rounded_rectangle([x+8*S, H*0.10+6*S, x+breite-8*S, H*0.10+breite-14*S], radius=6*S,
                            fill=(150, 225, 120) if hell else (120, 128, 124))
    # Konsole
    d.rounded_rectangle([W*0.06, H*0.50, W*0.94, H*0.92], radius=10*S, fill=(14, 16, 15))
    d.rectangle([W*0.06, H*0.50, W*0.94, H*0.56], fill=(70, 78, 74))
    for k, (laenge, col) in enumerate([(0.55, (200, 210, 200)), (0.38, (126, 206, 94)), (0.47, (200, 210, 200))]):
        y = H*0.61 + k*H*0.085
        d.polygon([(W*0.09, y), (W*0.105, y+H*0.025), (W*0.09, y+H*0.05)], fill=GRUEN)
        d.rounded_rectangle([W*0.12, y+H*0.012, W*(0.12+laenge), y+H*0.04], radius=3*S, fill=col)
    speichern(img, "hilfe_tasten")


def verkehr():
    img, d = karte_grund()
    b = 26*S
    strasse(d, [(0, H*0.5), (W, H*0.5)], b)
    strasse(d, [(W*0.5, 0), (W*0.5, H)], b)
    for x in range(0, W, 24*S):
        if abs(x - W*0.5) > b:
            d.line([(x, H*0.5), (x+12*S, H*0.5)], fill=LINIE, width=2*S)
    # Auto von links, Traktor von oben
    d.rounded_rectangle([W*0.26, H*0.52, W*0.36, H*0.58], radius=4*S, fill=(70, 120, 210))
    d.rounded_rectangle([W*0.285, H*0.53, W*0.335, H*0.57], radius=3*S, fill=(170, 200, 230))
    d.rounded_rectangle([W*0.465, H*0.18, W*0.495, H*0.34], radius=4*S, fill=(52, 150, 70))
    d.rounded_rectangle([W*0.468, H*0.20, W*0.492, H*0.26], radius=3*S, fill=(170, 200, 220))
    # Warndreieck
    cx, cy, r = W*0.78, H*0.25, 44*S
    d.polygon([(cx, cy-r), (cx+r*0.95, cy+r*0.7), (cx-r*0.95, cy+r*0.7)], fill=(250, 250, 245))
    d.polygon([(cx, cy-r*0.7), (cx+r*0.68, cy+r*0.52), (cx-r*0.68, cy+r*0.52)], fill=(230, 60, 50))
    d.polygon([(cx, cy-r*0.4), (cx+r*0.42, cy+r*0.36), (cx-r*0.42, cy+r*0.36)], fill=(250, 250, 245))
    d.rounded_rectangle([cx-3*S, cy-r*0.22, cx+3*S, cy+r*0.12], radius=2*S, fill=(30, 30, 30))
    d.ellipse([cx-3.5*S, cy+r*0.18, cx+3.5*S, cy+r*0.28], fill=(30, 30, 30))
    speichern(img, "hilfe_verkehr")


for f in (ueberblick, wegpunkte, einstellungen, tasten, verkehr):
    f()
print("fertig")
