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
    # the trench coat: dark dried-blood oxblood, the MACHINE PARTY red, with
    # the lapel overlap on the left edge, pocket flaps low, a button column
    img, px = canvas((74, 33, 33))
    for y in range(128):                  # the twill weave
        for x in range(128):
            if (x + y) % 4 < 2:
                px[x, y] = (66, 29, 29)
            if (x * y) % 7 == 0:
                px[x, y] = (58, 26, 26)
    for y in range(128):                  # the lapel overlap, left edge
        for x in range(0, 14):
            px[x, y] = (52, 23, 23)
        px[14, y] = (42, 18, 18)
    for y in range(84, 96):               # the pocket flaps
        for x in range(24, 52):
            px[x, y] = (52, 23, 23)
        for x in range(76, 104):
            px[x, y] = (52, 23, 23)
    for y in range(30, 100, 14):          # the button column
        for x in range(60, 68):
            for yy in range(y, y + 6):
                px[x, yy] = (36, 16, 16)
    grain(px, 9)
    return dither(img)


def tex_pi_slacks():
    # charcoal wool, warm not blue, with a pressed crease and a knee shine
    img, px = canvas((44, 41, 39))
    for y in range(128):
        for x in range(128):
            if (x + y) % 3 == 0:
                px[x, y] = (39, 36, 34)
    for y in range(128):                  # the crease
        px[63, y] = (52, 49, 46)
        px[64, y] = (52, 49, 46)
    for y in range(58, 86):               # the knee shine
        for x in range(40, 88):
            if random.random() < 0.35:
                px[x, y] = (56, 53, 50)
    grain(px, 7)
    return dither(img)


def tex_pi_face():
    # the PI's mug under the shades: hair heavy over the top and wrapping the
    # side edges, black wrap-around sunglasses banded across the eyes, a flat
    # tired mouth low, jaw stubble. The band wraps so the arms of the glasses
    # read on the profile faces too.
    img, px = canvas((172, 148, 118))
    for y in range(0, 64):                # the hair, the top half
        for x in range(128):
            px[x, y] = (44, 36, 30)
    for x in range(128):                  # the fringe line
        if random.random() < 0.5:
            px[x, 64] = (54, 45, 38)
    for y in range(64, 128):              # the side hair wraps both edges
        for x in range(0, 20):
            px[x, y] = (42, 35, 29)
            px[127 - x, y] = (42, 35, 29)
    for y in range(74, 92):               # the shades, wrapping the head
        for x in range(16, 112):
            px[x, y] = (16, 15, 19)
    for y in range(78, 86):               # a faint lens glare
        for x in range(30, 58):
            if (x + y) % 6 < 2:
                px[x, y] = (44, 48, 56)
        for x in range(70, 98):
            if (x + y) % 6 < 2:
                px[x, y] = (44, 48, 56)
    for x in range(16, 112):              # the frame ridge
        px[x, 74] = (10, 9, 12)
        px[x, 91] = (10, 9, 12)
    for x in range(56, 72):               # the mouth, a flat line
        px[x, 106] = (130, 82, 70)
    for y in range(112, 128):             # the jaw stubble
        for x in range(18, 110):
            if random.random() < 0.45:
                px[x, y] = (146, 122, 96)
    grain(px, 6)
    return dither(img)


def tex_pi_hat():
    # the fedora: tan straw felt like a sun-hat gone noir, the weave coarse,
    # a crown crease, the brim edge shaded and frayed
    img, px = canvas((146, 112, 70))
    for y in range(128):
        for x in range(128):
            if (x + y) % 5 == 0:
                px[x, y] = (134, 102, 62)
            if (x * y) % 11 == 0:
                px[x, y] = (122, 92, 56)
    for x in range(128):                  # the crown crease
        px[x, 20] = (108, 80, 48)
        px[x, 21] = (108, 80, 48)
    for y in range(118, 128):             # the brim edge, frayed
        for x in range(128):
            px[x, y] = (116, 86, 52)
            if random.random() < 0.3:
                px[x, y] = (104, 76, 46)
    grain(px, 6)
    return dither(img)


def tex_pi_glove():
    # the white glove: off-white leather, a seam down the middle, knuckle
    # dents, a cuff band at the bottom
    img, px = canvas((206, 200, 188))
    for y in range(128):
        for x in range(128):
            if (x + y) % 6 == 0:
                px[x, y] = (196, 190, 178)
    for y in range(128):                  # the center seam
        px[63, y] = (162, 156, 146)
        px[64, y] = (162, 156, 146)
    for (kx, ky) in [(38, 34), (64, 26), (90, 34)]:   # the knuckle dents
        for y in range(ky, ky + 8):
            for x in range(kx - 6, kx + 7):
                if math.hypot(x - kx, (y - ky) * 1.6) < 6:
                    px[x, y] = (178, 172, 162)
    for y in range(112, 128):             # the cuff band
        for x in range(128):
            px[x, y] = (186, 180, 170)
    grain(px, 5)
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
    "pi_slacks": tex_pi_slacks,
    "pi_face": tex_pi_face,
    "pi_hat": tex_pi_hat,
    "pi_glove": tex_pi_glove,
    "fan": tex_fan,
}

os.makedirs(OUT, exist_ok=True)
for name, fn in TEXTURES.items():
    img = fn()
    img.save(os.path.join(OUT, f"{name}.png"))
    print(f"tex: {name}.png")
print("PS1 textures done")
