#!/usr/bin/env python3
"""Generate the PS1-era textures (128x128, dithered, painted) into assets/tex/.
Run:  python3 assets_src/gen_ps1_textures.py
"""
import math
import os
import random

from PIL import Image

random.seed(11)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "tex")

INK = (20, 18, 28)
WALNUT = (52, 38, 27)
WALNUT_D = (38, 27, 19)
OXBLOOD = (74, 31, 36)
OXBLOOD_D = (56, 22, 27)
BONE = (222, 214, 199)
SODIUM = (232, 179, 102)
NEON = (242, 109, 141)
GLASS = (34, 44, 52)
GLASS_L = (66, 88, 100)

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def canvas(color):
    img = Image.new("RGB", (128, 128), color)
    return img, img.load()


def grain(px, amt=14):
    for y in range(128):
        for x in range(128):
            n = random.randint(-amt, amt)
            r, g, b = px[x, y]
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))


def dither(img):
    # 5-bit quantization with an ordered Bayer offset: the PS1 crunch.
    out = Image.new("RGB", (128, 128))
    po = out.load()
    for y in range(128):
        for x in range(128):
            d = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 6.0
            po[x, y] = tuple(max(0, min(255, int((c + d) / 8.0) * 8)) for c in img.getpixel((x, y)))
    return out


# --- the PI's box atlas -----------------------------------------------------------------
# Godot 4 BoxMesh UVs: every face reads its own cell of a 3x2 atlas, NOT the
# whole texture. Paint the PI's sheets cell by cell so the mug lands on the
# front, the hair on the back, the buttons down the coat's chest.
#   row 0: front | right | back      row 1: left | top | bottom
# On the right cell the image's left edge is his front; on the left cell the
# image's right edge is his front (both read unmirrored from outside).
CELL_RECT = {
    "front": (0, 0, 43, 64),
    "right": (43, 0, 85, 64),
    "back": (85, 0, 128, 64),
    "left": (0, 64, 43, 128),
    "top": (43, 64, 85, 128),
    "bottom": (85, 64, 128, 128),
}


def cell(px, name):
    x0, y0, x1, y1 = CELL_RECT[name]
    w, h = x1 - x0, y1 - y0

    def put(cx, cy, col):
        if 0 <= cx < w and 0 <= cy < h:
            px[x0 + cx, y0 + cy] = col

    return put, w, h


def fill_cell(px, name, col):
    put, w, h = cell(px, name)
    for cy in range(h):
        for cx in range(w):
            put(cx, cy, col)


def planks(img, px, step=18, dark=WALNUT_D, light=WALNUT):
    for y in range(0, 128, step):
        for x in range(128):
            px[x, y] = dark
        for x in range(128):
            if random.random() < 0.30:
                px[x, (y + 1) % 128] = light
    # random vertical seams
    for y in range(0, 128, step):
        for x in range(random.randint(1, 3)):
            sx = random.randint(0, 127)
            for k in range(step - 2):
                px[sx, (y + 1 + k) % 128] = dark


def tex_floor():
    img, px = canvas((44, 33, 23))
    planks(img, px, dark=(28, 21, 14), light=(52, 39, 27))
    grain(px, 10)
    return dither(img)


def tex_wall():
    # warm dark plaster: stained, panelled, tired - the MACHINE PARTY dread
    img, px = canvas((62, 54, 43))
    for x in range(0, 128, 16):           # plaster panel seams
        for y in range(128):
            px[x, y] = (50, 43, 34)
            px[(x + 1) % 128, y] = (44, 38, 30)
    for x in range(128):                  # the soot band up top
        for y in range(0, 10):
            if random.random() < 0.5:
                px[x, y] = (48, 41, 33)
    for x in range(128):                  # the picture rail
        px[x, 4] = (38, 32, 25)
        px[x, 5] = (70, 60, 47)
    for x in range(128):                  # the wainscot and the skirt
        for y in range(96, 112):
            px[x, y] = (40, 34, 27)
        px[x, 95] = (74, 63, 49)
        px[x, 96] = (30, 26, 20)
        px[x, 112] = (28, 24, 19)
        px[x, 113] = (24, 21, 17)
        for y in range(113, 128):         # the baseboard
            px[x, y] = (26, 23, 18)
    grain(px, 8)
    return dither(img)


def tex_rug():
    # deep dried-blood oxblood, worn to the warp in the walk lanes
    img, px = canvas((58, 25, 29))
    for x in range(128):
        for y in range(128):
            if x < 6 or x > 121 or y < 6 or y > 121:
                px[x, y] = (44, 19, 23)
            elif (x + y) % 2 == 0 and 12 < x < 116:
                px[x, y] = (64, 28, 32)
    for k in range(0, 128, 24):           # the worn diamond grid
        for d in range(-6, 7):
            if 0 <= k + d < 128 and 0 <= 64 + abs(d) < 128:
                px[(k + d) % 128, (64 + abs(d)) % 128] = (44, 19, 23)
    grain(px, 12)
    return dither(img)


def tex_desk():
    img, px = canvas((40, 29, 21))
    planks(img, px, step=32, dark=(28, 20, 14), light=(46, 33, 24))
    for x in range(128):                  # a polished sheen band
        for y in (30, 31, 62, 63):
            px[x, y] = (52, 39, 29)
    grain(px, 8)
    return dither(img)


def tex_cabinet():
    img, px = canvas((34, 36, 44))
    for y in range(0, 128, 32):           # drawer fronts
        for x in range(6, 122):
            px[x, y] = (26, 28, 34)
        for x in range(6, 122):
            px[x, y + 1] = (46, 49, 60)
        for x in (14, 15, 112, 113):      # handles
            px[x, y + 16] = SODIUM
            px[x, y + 17] = (180, 138, 78)
    grain(px, 10)
    return dither(img)


def tex_crate():
    img, px = canvas((46, 34, 23))
    planks(img, px, step=32, dark=(30, 22, 15), light=(54, 41, 28))
    for i in range(126):                  # the brace cross
        px[i, i] = (30, 22, 15)
        px[i, i + 1] = (30, 22, 15)
        px[127 - i, i] = (30, 22, 15)
        px[127 - i, i + 1] = (30, 22, 15)
    grain(px, 12)
    return dither(img)


def tex_window():
    img, px = canvas(GLASS)
    skyline = [88, 74, 92, 60, 80, 68, 84, 72]
    for i, h in enumerate(skyline):       # the sleeping city
        x0 = i * 16
        for x in range(x0, x0 + 14):
            for y in range(128 - h, 120):
                px[x, y] = (16, 20, 27)
        for wy in range(128 - h + 4, 116, 8):
            for wx in range(x0 + 3, x0 + 12, 5):
                if random.random() < 0.22:
                    px[wx, wy] = (166, 132, 74)   # a few lit windows
    for y in range(120, 128):
        for x in range(128):
            px[x, y] = (20, 26, 34)
    for i in range(70):                   # rain streaks
        x = random.randint(0, 127)
        y = random.randint(0, 110)
        ln = random.randint(6, 20)
        for k in range(ln):
            px[(x + k // 3) % 128, min(127, y + k)] = GLASS_L
    for x in range(0, 128, 32):           # the frame
        for y in range(128):
            px[x, y] = (16, 14, 22)
            px[(x + 1) % 128, y] = (16, 14, 22)
    return dither(img)


def tex_door():
    img, px = canvas((28, 16, 24))
    for y in range(128):
        for x in range(128):
            if x < 10 or x > 117 or y < 10 or y > 117:
                px[x, y] = (16, 12, 20)   # the frame
    for x in range(16, 112, 2):           # the neon sign band
        px[x, 30] = NEON
        px[x, 31] = (255, 170, 190)
        px[x, 32] = NEON
    for y in range(40, 116):              # frosted panels
        for x in range(20, 108):
            if y % 34 < 30:
                px[x, y] = (36, 22, 30)
    grain(px, 10)
    return dither(img)


def tex_radio():
    img, px = canvas((38, 30, 22))
    for x in range(128):                  # the grille
        for y in range(20, 74):
            if x % 4 < 2:
                px[x, y] = (24, 19, 14)
    for x in range(16, 60):               # the dial
        for y in range(86, 96):
            px[x, y] = (20, 16, 12)
    for x in range(22, 54, 8):
        px[x, 90] = SODIUM
    for x in range(70, 110):              # buttons
        for y in (86, 92):
            px[x, y] = (52, 44, 34)
    grain(px, 10)
    return dither(img)


def tex_paper():
    img, px = canvas(BONE)
    for y in range(12, 128, 10):
        for x in range(10, 118):
            px[x, y] = (150, 142, 130)
    for y in range(128):                  # the coffee ring
        for x in range(128):
            if 90 < ((x - 92) ** 2 + (y - 96) ** 2) ** 0.5 < 96:
                px[x, y] = (196, 168, 132)
    grain(px, 6)
    return dither(img)


def tex_mat():
    img, px = canvas((30, 28, 34))
    for y in range(0, 128, 4):
        for x in range(128):
            if (y // 4) % 2 == 0:
                px[x, y] = (24, 22, 28)
    for x in range(8, 120):
        px[x, 0] = (18, 16, 22)
        px[x, 127] = (18, 16, 22)
    grain(px, 10)
    return dither(img)


def tex_scuff():
    img, px = canvas((26, 24, 30))
    for i in range(60):                   # dragged streaks
        x = random.randint(4, 120)
        y = random.randint(4, 120)
        ln = random.randint(4, 14)
        for k in range(ln):
            px[min(127, x + k), y] = (18, 16, 22)
    return dither(img)


def tex_ceiling():
    img, px = canvas((26, 24, 28))
    for k in range(14):                   # the water stains, ringed
        cx, cy = random.randint(8, 120), random.randint(8, 120)
        r = random.randint(6, 18)
        for y in range(128):
            for x in range(128):
                d = math.hypot(x - cx, y - cy)
                if r - 3 < d < r:
                    px[x, y] = (34, 31, 34)
                elif d <= r - 3 and random.random() < 0.4:
                    px[x, y] = (30, 28, 31)
    for s in range(0, 128, 32):           # the panel seams
        for y in range(128):
            px[s, y] = (18, 17, 20)
            px[y, s] = (18, 17, 20)
    grain(px, 8)
    return dither(img)


def tex_shelf():
    img, px = canvas((26, 20, 15))
    spines = [(232, 179, 102), (222, 214, 199), (116, 52, 58),
              (74, 82, 106), (62, 80, 68), (150, 104, 56)]
    for b in (4, 34, 64, 94, 124):        # the shelf boards
        for x in range(128):
            px[x, b] = (14, 11, 8)
            if b < 124:
                px[x, b + 1] = (48, 37, 26)
    for b in (34, 64, 94, 124):           # the case binders, a few tilted
        x = 3
        while x < 122:
            w = random.randint(5, 9)
            h = random.randint(14, 24)
            c = random.choice(spines)
            tilt = 1 if random.random() < 0.15 else 0
            for yy in range(max(6, b - h), b):
                off = ((b - yy) // 5) * tilt
                for xx in range(min(122, x + off), min(123, x + off + w)):
                    px[xx, yy] = c
            x += w + 1
    grain(px, 10)
    return dither(img)


def tex_corkboard():
    img, px = canvas((106, 80, 54))
    for y in range(128):                  # the cork speckle
        for x in range(128):
            if random.random() < 0.18:
                px[x, y] = (94, 70, 46)
    photos = [(14, 12, 40, 30), (58, 14, 34, 26), (20, 56, 30, 24), (66, 52, 40, 30)]
    for (x0, y0, w, h) in photos:         # the photos and their pins
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                px[x, y] = (30, 32, 40)
        for y in range(y0 + 4, y0 + h - 8, 5):
            for x in range(x0 + 4, x0 + w - 4, 6):
                if random.random() < 0.5:
                    px[x, y] = (88, 86, 90)
        px[x0 + w // 2, y0 - 2] = SODIUM
    for (x0, y0) in [(50, 44), (96, 40), (104, 92), (54, 96)]:
        for y in range(y0, y0 + 12):      # the sticky notes
            for x in range(x0, x0 + 14):
                px[x, y] = (206, 186, 108)
        for k in range(3):
            for x in range(x0 + 3, x0 + 11):
                px[x, y0 + 3 + k * 3] = (120, 104, 60)
    for a, b in [(0, 1), (1, 3), (2, 3)]:  # the red string, only over cork
        (xa, ya, wa, ha), (xb, yb, wb, hb) = photos[a], photos[b]
        ax, ay = xa + wa // 2, ya - 2
        bx, by = xb + wb // 2, yb - 2
        steps = max(abs(bx - ax), abs(by - ay))
        for k in range(steps):
            x = int(ax + (bx - ax) * k / steps)
            y = int(ay + (by - ay) * k / steps)
            if 6 < x < 121 and 6 < y < 121 and px[x, y][0] > 90:
                px[x, y] = (196, 52, 48)
    for y in range(128):                  # the wood frame
        for x in range(128):
            if x < 5 or x > 122 or y < 5 or y > 122:
                px[x, y] = (40, 30, 22)
    grain(px, 8)
    return dither(img)


def tex_clock():
    img, px = canvas((24, 22, 30))        # square corners hide on the wall
    for y in range(128):
        for x in range(128):
            d = math.hypot(x - 64, y - 64)
            if d < 54:
                px[x, y] = (222, 214, 199)
            elif 52 < d < 56:
                px[x, y] = (40, 36, 46)
    for a in range(12):                   # the hour ticks
        ang = a * math.pi / 6
        for r in range(44, 52):
            px[int(64 + r * math.sin(ang)), int(64 - r * math.cos(ang))] = (60, 56, 64)
    ang_h = (11 + 41 / 60.0) / 12.0 * 2 * math.pi    # hands at 23:41
    ang_m = (41 / 60.0) * 2 * math.pi
    for r in range(0, 30):
        px[int(64 + r * math.sin(ang_h)), int(64 - r * math.cos(ang_h))] = (30, 28, 36)
    for r in range(0, 40):
        px[int(64 + r * math.sin(ang_m)), int(64 - r * math.cos(ang_m))] = (30, 28, 36)
    grain(px, 4)
    return dither(img)


def tex_typewriter():
    img, px = canvas((34, 32, 38))
    for y in range(30, 60):               # the roller bar
        for x in range(10, 118):
            px[x, y] = (22, 20, 26)
    for y in range(8, 28):                # the sheet in the roller
        for x in range(24, 104):
            px[x, y] = (216, 208, 192)
    for k in range(4):                    # the typed lines
        for x in range(30, 98, 3):
            px[x, 12 + k * 4] = (120, 116, 108)
    for y in range(64, 100):              # the key grid
        for x in range(14, 114):
            if (x - 14) % 10 < 6 and (y - 64) % 10 < 6:
                px[x, y] = (58, 56, 62)
    grain(px, 8)
    return dither(img)


def tex_phone():
    img, px = canvas((26, 24, 30))
    for y in range(24, 104):              # the body
        for x in range(24, 104):
            px[x, y] = (38, 36, 44)
    for y in range(10, 34):               # the handset across the top
        for x in range(14, 114):
            px[x, y] = (18, 16, 22)
    for y in range(50, 98):               # the dial
        for x in range(40, 88):
            if math.hypot(x - 64, y - 74) < 24:
                px[x, y] = (52, 50, 58)
    for a in range(10):
        ang = a * math.pi / 5
        px[int(64 + 16 * math.sin(ang)), int(74 - 16 * math.cos(ang))] = (90, 86, 92)
    grain(px, 8)
    return dither(img)


def tex_bottles():
    img, px = canvas((30, 26, 20))
    for y in range(100, 128):             # the shelf board
        for x in range(128):
            px[x, y] = (20, 15, 11)
    cols = [(52, 92, 58), (96, 62, 34), (120, 108, 84), (70, 84, 92), (110, 52, 44)]
    x = 4
    while x < 122:                        # the bottle row
        w = random.randint(8, 12)
        h = random.randint(46, 78)
        c = random.choice(cols)
        for yy in range(100 - h, 100):
            pad = w // 3 if yy < 100 - h + 14 else 0
            for xx in range(x + pad, x + w - pad):
                px[xx, yy] = c
        for yy in range(100 - h, min(100, 100 - h + 6)):   # the cap
            for xx in range(x + w // 3, x + w - w // 3):
                px[xx, yy] = (180, 176, 160)
        x += w + 2
    grain(px, 8)
    return dither(img)


def tex_window2():
    img, px = canvas(GLASS)
    skyline = [96, 58, 104, 72, 88, 98, 62, 86]
    for i, h in enumerate(skyline):       # the other side of the street
        x0 = i * 16
        for x in range(x0, x0 + 14):
            for y in range(128 - h, 120):
                px[x, y] = (16, 20, 27)
        for wy in range(128 - h + 4, 116, 8):
            for wx in range(x0 + 3, x0 + 12, 5):
                if random.random() < 0.26:
                    px[wx, wy] = (166, 132, 74)
    for y in range(52, 72):               # one buzzed neon sign
        for x in range(52, 76):
            if y in (52, 71) or x in (52, 75):
                px[x, y] = NEON
            elif y in (53, 70) or x in (53, 74):
                px[x, y] = (255, 170, 190)
    for y in range(120, 128):
        for x in range(128):
            px[x, y] = (20, 26, 34)
    for i in range(70):                   # rain streaks
        x = random.randint(0, 127)
        y = random.randint(0, 110)
        ln = random.randint(6, 20)
        for k in range(ln):
            px[(x + k // 3) % 128, min(127, y + k)] = GLASS_L
    for x in range(0, 128, 32):           # the frame
        for y in range(128):
            px[x, y] = (16, 14, 22)
            px[(x + 1) % 128, y] = (16, 14, 22)
    return dither(img)


def tex_vent():
    img, px = canvas((44, 42, 50))
    for y in range(10, 118, 12):          # the slats
        for x in range(10, 118):
            px[x, y] = (18, 17, 22)
            if y + 1 < 118:
                px[x, y + 1] = (62, 60, 68)
    for (sx, sy) in [(5, 5), (122, 5), (5, 122), (122, 122)]:
        px[sx, sy] = (96, 94, 100)        # the screws
    grain(px, 6)
    return dither(img)


def tex_news():
    img, px = canvas((206, 198, 182))
    for y in range(10, 26):               # the masthead
        for x in range(14, 114):
            px[x, y] = (40, 38, 44)
    for y in range(32, 70):               # the halftone photo
        for x in range(14, 74):
            if random.random() < 0.5:
                px[x, y] = (120, 116, 108)
    for y in range(32, 70):               # the headline column
        for x in range(80, 114):
            if y % 6 < 4:
                px[x, y] = (60, 56, 62)
    for y in range(76, 122):              # the column text
        for x in range(14, 114):
            if (x + y * 2) % 6 < 2 and random.random() < 0.8:
                px[x, y] = (110, 106, 100)
    for x in range(128):                  # the fold
        px[x, 64] = (150, 142, 128)
    grain(px, 6)
    return dither(img)


def tex_pi_coat():
    # the trench coat in the Klubnika key: a murky near-black oxblood slab
    # that sinks into the gloom. No tailoring noise - one bold coat-opening
    # line down the front and a hem shade on every face. The silhouette does
    # the work; the texture stays quiet.
    img, px = canvas((44, 26, 25))
    for y in range(128):                  # a faint twill, barely there
        for x in range(128):
            if (x + y) % 4 < 2:
                px[x, y] = (40, 23, 22)
            if (x * y) % 9 == 0:
                px[x, y] = (36, 21, 20)
    put, w, h = cell(px, "front")
    for cy in range(h):                   # the coat opening, one bold line
        put(13, cy, (26, 15, 14))
        put(14, cy, (26, 15, 14))
    for cy in range(61, h):               # the hem shade
        for cx in range(w):
            put(cx, cy, (32, 18, 17))
    put, w, h = cell(px, "back")
    for cy in range(61, h):
        for cx in range(w):
            put(cx, cy, (32, 18, 17))
    for side in ("right", "left"):
        put, w, h = cell(px, side)
        for cy in range(61, h):
            for cx in range(w):
                put(cx, cy, (32, 18, 17))
    put, w, h = cell(px, "top")
    for cy in range(22, 42):              # the collar shadow on the shoulders
        for cx in range(12, 31):
            put(cx, cy, (34, 20, 19))
    fill_cell(px, "bottom", (28, 16, 15))
    grain(px, 10)
    return dither(img)


def tex_pi_sleeve():
    # the coat's arms: the same murky slab, a cuff seam low so the mitten
    # meets a finished sleeve. Nothing else.
    img, px = canvas((44, 26, 25))
    for y in range(128):
        for x in range(128):
            if (x + y) % 4 < 2:
                px[x, y] = (40, 23, 22)
            if (x * y) % 9 == 0:
                px[x, y] = (36, 21, 20)
    for side in ("front", "back", "right", "left"):
        put, w, h = cell(px, side)
        for cx in range(w):               # the cuff seam + cuff
            put(cx, 54, (26, 15, 14))
            for cy in range(56, 64):
                put(cx, cy, (32, 18, 17))
    put, w, h = cell(px, "top")           # the shoulder catches a little light
    for cy in range(h):
        for cx in range(w):
            if (cx + cy) % 4 < 2:
                put(cx, cy, (46, 27, 26))
    fill_cell(px, "bottom", (28, 16, 15))
    grain(px, 9)
    return dither(img)


def tex_pi_slacks():
    # charcoal wool gone near-black in the murk: flat, with a dark hem at
    # the shoe. No crease, no shine - legs read as one dark mass.
    img, px = canvas((34, 32, 30))
    for y in range(128):
        for x in range(128):
            if (x + y) % 3 == 0:
                px[x, y] = (30, 28, 26)
    for side in ("front", "back", "right", "left"):
        put, w, h = cell(px, side)
        for cy in range(61, 64):          # the hem
            for cx in range(w):
                put(cx, cy, (24, 22, 21))
    fill_cell(px, "bottom", (22, 20, 19))
    grain(px, 8)
    return dither(img)


def tex_pi_face():
    # the PI's mug in the Klubnika key: a pale grey skull, nearly featureless,
    # sunk half into shadow. The bold shades band carries the face; under it
    # only a short flat mouth line. Hair caps the top and wraps the back, the
    # temple arms run the sides. No stubble noise - the grime comes from the
    # dither pass, not from speckle.
    skin = (168, 156, 138)
    hair = (36, 30, 26)
    img, px = canvas(skin)
    put, w, h = cell(px, "front")
    for cy in range(0, 12):               # the hair, heavy over the brow
        for cx in range(w):
            put(cx, cy, hair)
    for cx in range(w):                   # the ragged fringe line
        if random.random() < 0.5:
            put(cx, 12, (44, 37, 32))
    for cy in range(19, 35):              # the wrap-around shades, one bold band
        for cx in range(w):
            put(cx, cy, (12, 12, 14))
    for cx in range(w):                   # the frame ridges
        put(cx, 19, (8, 8, 10))
        put(cx, 34, (8, 8, 10))
    for cy in range(23, 30):              # one lens glare wedge, off center
        for cx in range(7, 19):
            if (cx + cy) % 5 < 2:
                put(cx, cy, (36, 40, 48))
    for cx in range(15, 29):              # the mouth, a short flat line
        put(cx, 47, (120, 96, 82))
        put(cx, 48, (120, 96, 82))
    put(14, 48, (104, 82, 70))            # the corners droop
    put(30, 48, (104, 82, 70))
    # the sides: hair cap, hair wrapping the back edge, the temple arm running
    # front to back. Flat pale skin below - no ear, no stubble.
    for side in ("right", "left"):
        put, w, h = cell(px, side)
        front_left = side == "right"      # which image edge is his front

        def fx(cx, fl=front_left, ww=w):
            return cx if fl else ww - 1 - cx

        for cy in range(0, 15):           # the hair cap
            for cx in range(w):
                put(cx, cy, hair)
        for cy in range(15, 51):          # hair wraps the back edge
            for cx in range(w - 7, w):
                put(fx(cx), cy, (32, 27, 23))
        for cy in range(21, 28):          # the temple arm, front to back
            for cx in range(0, w - 7):
                put(fx(cx), cy, (12, 12, 14))
        for cx in range(0, w - 7):
            put(fx(cx), 21, (8, 8, 10))
    put, w, h = cell(px, "back")
    for cy in range(0, 46):               # the back of the head is hair
        for cx in range(w):
            put(cx, cy, hair)
            if (cx * cy) % 6 == 0:
                put(cx, cy, (42, 35, 30))
    for cx in range(w):                   # a clean hairline at the nape
        put(cx, 46, (44, 37, 32))
    put, w, h = cell(px, "top")
    for cy in range(h):                   # the crown under the fedora
        for cx in range(w):
            put(cx, cy, hair)
            if (cx + cy) % 5 < 1:
                put(cx, cy, (42, 35, 30))
    put, w, h = cell(px, "bottom")
    for cy in range(20, 44):              # the neck patch under the jaw
        for cx in range(15, 28):
            put(cx, cy, (150, 138, 122))
    grain(px, 7)
    return dither(img)


def tex_pi_skin():
    # plain skin for the neck: the same pale grey tone, a shade low so the
    # small box still reads as form under the Gouraud light
    img, px = canvas((168, 156, 138))
    for side in CELL_RECT:
        put, w, h = cell(px, side)
        for cy in range(h - 10, h):
            for cx in range(w):
                put(cx, cy, (150, 138, 122))
    grain(px, 6)
    return dither(img)


def tex_pi_hat():
    # the fedora: grim straw gone murky, coarse weave, a bold crown crease on
    # the long faces, a pinched dent on top, the brim edge frayed and shaded
    # under. It is the identity prop - it reads big and grim, not dapper.
    img, px = canvas((112, 88, 56))
    for y in range(128):
        for x in range(128):
            if (x + y) % 5 == 0:
                px[x, y] = (104, 80, 50)
            if (x * y) % 11 == 0:
                px[x, y] = (96, 74, 46)
    for side in ("front", "back", "right", "left"):
        put, w, h = cell(px, side)
        for cx in range(w):               # the crown crease
            put(cx, 8, (88, 66, 40))
            put(cx, 9, (88, 66, 40))
        for cy in range(58, 64):          # the brim edge, frayed
            for cx in range(w):
                put(cx, cy, (94, 72, 44))
                if random.random() < 0.3:
                    put(cx, cy, (84, 62, 38))
    put, w, h = cell(px, "top")
    for cx in range(w):                   # the front edge shade
        put(cx, 0, (94, 72, 44))
        put(cx, 1, (94, 72, 44))
    for cy in range(4, 29):               # the center dent
        put(w // 2 - 1, cy, (88, 66, 40))
        put(w // 2, cy, (88, 66, 40))
    for t in range(16):                   # the pinch, two folds forward
        put(w // 2 - 8 + t // 2, 4 + t, (88, 66, 40))
        put(w // 2 + 8 - t // 2, 4 + t, (88, 66, 40))
    put, w, h = cell(px, "bottom")
    for cy in range(h):                   # the brim underside
        for cx in range(w):
            put(cx, cy, (84, 62, 38))
            if (cx + cy) % 5 == 0:
                put(cx, cy, (76, 56, 34))
    grain(px, 9)
    return dither(img)


def tex_pi_glove():
    # the mitten: bone leather, grimy. One bold center seam and a cuff band
    # low where it meets the sleeve. The chunky box shape does the rest.
    img, px = canvas((188, 180, 168))
    for y in range(128):
        for x in range(128):
            if (x + y) % 6 == 0:
                px[x, y] = (178, 170, 158)
    for side in ("front", "back"):
        put, w, h = cell(px, side)
        for cy in range(18, 52):          # the center seam
            put(w // 2, cy, (152, 144, 134))
        for cx in range(w):               # the cuff
            put(cx, 52, (152, 144, 134))
            for cy in range(53, 64):
                put(cx, cy, (170, 162, 150))
    for side in ("right", "left"):
        put, w, h = cell(px, side)
        for cy in range(0, 52):
            put(2, cy, (152, 144, 134))
        for cx in range(w):
            put(cx, 52, (152, 144, 134))
            for cy in range(53, 64):
                put(cx, cy, (170, 162, 150))
    fill_cell(px, "top", (180, 172, 160))
    fill_cell(px, "bottom", (162, 154, 144))
    grain(px, 7)
    return dither(img)


def tex_fan():
    # the turbine: a dark housing ring, four swept steel blades, the hub.
    # The whole quad spins; the ring is uniform so only the blades turn.
    img, px = canvas((24, 22, 20))
    for y in range(128):
        for x in range(128):
            dx, dy = x - 64, y - 64
            r = math.hypot(dx, dy)
            if r > 62:
                continue                  # outside stays the dark wall tone
            a = math.atan2(dy, dx)
            if r >= 56:
                px[x, y] = (72, 66, 58)   # the housing ring
            elif r >= 13:
                m = ((a + r * 0.014) / (math.pi * 0.5)) % 1.0
                if m < 0.34:              # the swept blade wedge
                    shade = 108 if m < 0.30 else 88
                    px[x, y] = (shade, shade - 6, shade - 12)
            else:
                px[x, y] = (64, 60, 54)   # the hub
    px[63, 63] = (150, 144, 132)          # the hub bolt
    px[64, 63] = (150, 144, 132)
    px[63, 64] = (150, 144, 132)
    px[64, 64] = (150, 144, 132)
    grain(px, 5)
    return dither(img)




# --- casefile: a manila dossier cover, painted with the PS1 crunch ----------------
def tex_casefile():
    img, px = canvas(WALNUT)
    for y in range(128):
        for x in range(128):
            # worn manila base
            d = BAYER[y % 4][x % 4] / 16.0
            shade = int(165 + d * 20 - abs(x - 64) * 0.3)
            g_shade = int(128 + d * 15 - abs(x - 64) * 0.2)
            b_shade = int(72 + d * 8)
            px[x, y] = (
                max(0, min(255, shade)),
                max(0, min(255, g_shade)),
                max(0, min(255, b_shade)),
            )
    # label block
    for y in range(8, 30):
        for x in range(8, 120):
            shade = 215 if 10 <= y <= 28 else 180
            px[x, y] = (shade, shade - 12, shade - 40)
    # horizontal rules — fields to fill in
    for li in range(5):
        for x in range(10, 118):
            py2 = 36 + li * 14
            px[x, py2] = (110, 85, 52)
    # CLASSIFIED stamp in state red
    for y in range(80, 100):
        for x in range(60, 118):
            px[x, y] = (160, 28, 24) if (y in (80, 99) or x in (60, 117)) else (140, 24, 20)
    # corner fold
    for dy in range(18):
        for dx in range(18 - dy):
            px[127 - dx, dy] = WALNUT_D
    grain(px, 10)
    return dither(img)


# --- case_indicator: a small ring that pulses in the HUD when the case is new ---
def tex_case_indicator():
    img, px = canvas(INK)
    cx, cy = 64, 64
    for y in range(128):
        for x in range(128):
            r = math.hypot(x - cx, y - cy)
            if 50 <= r <= 62:
                a = math.atan2(y - cy, x - cx)
                # arc from -PI to 0 (top to right) = "time remaining" meter
                frac = (a + math.pi) / (math.pi * 2.0)
                if frac < 0.75:
                    px[x, y] = OXBLOOD
                else:
                    px[x, y] = (80, 20, 15)
            elif r < 50:
                px[x, y] = INK
    grain(px, 5)
    return dither(img)


# --- ringing_phone: an overlay icon lit up when the phone is ringing ------------
def tex_phone_ring():
    # the same phone silhouette as tex_phone but bright, with sound-wave arcs
    img, px = canvas(INK)
    # handset shadow
    for y in range(44, 68):
        for x in range(18, 110):
            if (18 <= x <= 40 or 88 <= x <= 110) and 44 <= y <= 68:
                px[x, y] = BONE
            elif 40 <= x <= 88 and 50 <= y <= 62:
                px[x, y] = BONE
    # arc wave: two arcs radiating from the bell
    for step in range(2):
        base_r = 20 + step * 16
        for deg in range(-60, 61, 2):
            a = math.radians(deg)
            for r in range(base_r, base_r + 8):
                xp = int(64 + math.cos(a) * r)
                yp = int(20 + math.sin(a) * r)
                if 0 <= xp < 128 and 0 <= yp < 128:
                    px[xp, yp] = SODIUM
    grain(px, 8)
    return dither(img)

TEXTURES = {
    "floor": tex_floor,
    "wall": tex_wall,
    "rug": tex_rug,
    "desk": tex_desk,
    "cabinet": tex_cabinet,
    "crate": tex_crate,
    "window": tex_window,
    "door": tex_door,
    "radio": tex_radio,
    "paper": tex_paper,
    "mat": tex_mat,
    "scuff": tex_scuff,
    "ceiling": tex_ceiling,
    "shelf": tex_shelf,
    "corkboard": tex_corkboard,
    "clock": tex_clock,
    "typewriter": tex_typewriter,
    "phone": tex_phone,
    "bottles": tex_bottles,
    "window2": tex_window2,
    "vent": tex_vent,
    "news": tex_news,
    "pi_coat": tex_pi_coat,
    "pi_sleeve": tex_pi_sleeve,
    "pi_slacks": tex_pi_slacks,
    "pi_face": tex_pi_face,
    "pi_skin": tex_pi_skin,
    "pi_hat": tex_pi_hat,
    "pi_glove": tex_pi_glove,
    "fan": tex_fan,
    "casefile": tex_casefile,
    "case_indicator": tex_case_indicator,
    "phone_ring": tex_phone_ring,
}

os.makedirs(OUT, exist_ok=True)
for name, fn in TEXTURES.items():
    img = fn()
    img.save(os.path.join(OUT, f"{name}.png"))
    print(f"tex: {name}.png")
print("PS1 textures done")
