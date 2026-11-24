#!/usr/bin/env python3
"""Generate every texture in the cast: 128x128, hand-grimed, dithered.
The palette is murky - soviet green-grey, putty skin, dried-blood maroon -
and every sheet takes the same abuse: stain blobs, drips, scratches, edge
wear, per-pixel noise, then a 5-bit Bayer crunch.
Run:  python3 assets_src/gen_textures.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

random.seed(47)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "tex")
SPRITES = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
FONT_DIR = "/usr/share/fonts/truetype/dejavu"

# the murk
PUTTY = (170, 162, 146)
PUTTY_D = (134, 127, 111)
BONE = (214, 206, 190)
GREY_G = (98, 106, 90)      # soviet green-grey paint
GREY_GD = (62, 68, 56)
CONC = (112, 109, 99)       # warm concrete
CONC_D = (76, 74, 67)
MAROON = (96, 41, 34)       # dried-blood cloth
MAROON_D = (62, 25, 20)
IRON = (58, 58, 62)
IRON_D = (34, 34, 38)
WOOD = (82, 62, 42)
WOOD_D = (52, 39, 27)
BLACK = (24, 22, 20)
AMBER = (208, 146, 60)
PHOS = (126, 170, 94)
CITY = (36, 42, 56)
RUST = (108, 62, 34)
SLIME = (72, 84, 58)
HAIR = (34, 29, 24)         # slicked-back hair, near-black brown
HAIR_D = (22, 19, 16)
HAIR_L = (56, 48, 40)       # the comb sheen

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# Godot 4 BoxMesh UVs: every face reads its own cell of a 3x2 atlas.
#   row 0: front | right | back      row 1: left | top | bottom
CELL_RECT = {
    "front": (0, 0, 43, 64),
    "right": (43, 0, 85, 64),
    "back": (85, 0, 128, 64),
    "left": (0, 64, 43, 128),
    "top": (43, 64, 85, 128),
    "bottom": (85, 64, 128, 128),
}


def canvas(color):
    img = Image.new("RGB", (128, 128), color)
    return img, img.load()


def mix(px, x, y, col, a):
    if not (0 <= x < 128 and 0 <= y < 128):
        return
    r, g, b = px[x, y]
    px[x, y] = (int(r + (col[0] - r) * a), int(g + (col[1] - g) * a),
                int(b + (col[2] - b) * a))


def blob(px, cx, cy, r, col, amt=0.4, wob=0.35):
    # one irregular stain; the edge wobbles so it never reads as a circle
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            d = math.hypot(x - cx, y - cy) / max(r, 0.001)
            if d + random.uniform(-wob, wob) < 1.0:
                mix(px, x % 128, y % 128, col, amt * max(0.0, 1.0 - d * 0.6))


def stains(px, n, cols, rmin=4, rmax=16, amt=0.4):
    for _ in range(n):
        blob(px, random.uniform(0, 128), random.uniform(0, 128),
             random.uniform(rmin, rmax), random.choice(cols),
             amt * random.uniform(0.5, 1.0))


def drip(px, x, y0, ln, col, amt=0.3):
    # a wobble-run down the wall, thinning as it goes
    for i in range(ln):
        x += random.choice((-1, 0, 0, 0, 1))
        if i > ln * 0.7 and random.random() < 0.2:
            break
        mix(px, x % 128, (y0 + i) % 128, col, amt * (1.0 - i / ln))
        mix(px, (x + 1) % 128, (y0 + i) % 128, col, amt * 0.5 * (1.0 - i / ln))


def drips(px, n, col, amt=0.3, ln_min=10, ln_max=50):
    for _ in range(n):
        drip(px, random.randint(0, 127), random.randint(0, 40),
             random.randint(ln_min, ln_max), col, amt * random.uniform(0.5, 1.0))


def scratch(px, x, y, ln, col, amt=0.5, vert=False):
    for i in range(ln):
        mix(px, (x + (0 if vert else i)) % 128, (y + (i if vert else 0)) % 128,
            col, amt * (1.0 - i / ln))


def scratches(px, n, col, amt=0.5, ln_max=14):
    for _ in range(n):
        scratch(px, random.randint(0, 127), random.randint(0, 127),
                random.randint(3, ln_max), col, amt * random.uniform(0.4, 1.0),
                random.random() < 0.3)


def noise(px, amt=14):
    for y in range(128):
        for x in range(128):
            n = random.randint(-amt, amt)
            r, g, b = px[x, y]
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)),
                        max(0, min(255, b + n)))


def edges(px, amt=0.35, band=22):
    # corners and borders wear darker; the grime collects where nobody cleans
    for y in range(128):
        for x in range(128):
            d = min(x, y, 127 - x, 127 - y)
            if d < band:
                t = 1.0 - d / band
                mix(px, x, y, BLACK, amt * t * t)


def ring(px, cx, cy, r, col, amt=0.3):
    # a cup ring or water tide-mark: hollow circle, slightly thick
    steps = int(r * 7)
    for i in range(steps):
        a = i / steps * math.tau
        for rr in (r, r - 1):
            mix(px, int(cx + math.cos(a) * rr) % 128,
                int(cy + math.sin(a) * rr) % 128, col, amt)


def weave(px, col, amt=0.10):
    # cloth threads: faint horizontal lines
    for y in range(0, 128, 2):
        for x in range(128):
            if random.random() < 0.5:
                mix(px, x, y, col, amt)


def scrawl(px, x0, y0, rows, cols, col, amt=0.55, gap=5):
    # typed lines: short dark dashes in rows, reads as print at distance
    for r in range(rows):
        x = x0
        while x < x0 + cols:
            ln = random.randint(3, 7)
            for i in range(ln):
                mix(px, min(127, x + i), y0 + r * gap, col, amt)
            x += ln + random.randint(2, 5)


def dither(img):
    # 5-bit quantization with an ordered Bayer offset: the PS1 crunch
    out = Image.new("RGB", (128, 128))
    po = out.load()
    for y in range(128):
        for x in range(128):
            d = (BAYER[y % 4][x % 4] / 16.0 - 0.5) * 6.0
            po[x, y] = tuple(max(0, min(255, int((c + d) / 8.0) * 8))
                             for c in img.getpixel((x, y)))
    return out


def cell(px, name):
    x0, y0, x1, y1 = CELL_RECT[name]
    w, h = x1 - x0, y1 - y0

    def put(cx, cy, col):
        if 0 <= cx < w and 0 <= cy < h:
            px[x0 + cx, y0 + cy] = col

    return put, w, h


def fill_cells(img, px, base, per_cell):
    # paint every cell: per_cell is {name: fn(put, w, h)}; unlisted cells
    # take the base with plain grime
    for name in CELL_RECT:
        put, w, h = cell(px, name)
        for cy in range(h):
            for cx in range(w):
                put(cx, cy, base)
        if name in per_cell:
            per_cell[name](put, w, h)
    return img


def cell_grime(px, names, skip_edges=False):
    # shared abuse for the listed cells only, so a painted front never
    # spreads onto a plain side
    for name in names:
        x0, y0, x1, y1 = CELL_RECT[name]
        sub = img_crop_grime(x0, y0, x1, y1, px, skip_edges)


def img_crop_grime(x0, y0, x1, y1, px, skip_edges):
    # grime bounded to one cell rect (no wrap, no cross-cell bleed)
    w, h = x1 - x0, y1 - y0
    for _ in range(random.randint(2, 4)):
        cx, cy = random.uniform(x0, x1), random.uniform(y0, y1)
        r = random.uniform(3, w * 0.35)
        col = random.choice([BLACK, IRON_D, RUST])
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                if x0 <= x < x1 and y0 <= y < y1:
                    d = math.hypot(x - cx, y - cy) / r
                    if d + random.uniform(-0.35, 0.35) < 1.0:
                        mix(px, x, y, col, 0.35 * max(0.0, 1.0 - d * 0.6))
    for _ in range(random.randint(2, 6)):
        x, y = random.randint(x0, x1 - 2), random.randint(y0, y1 - 1)
        ln = random.randint(3, 12)
        for i in range(ln):
            if x0 <= x + i < x1 and y0 <= y < y1:
                mix(px, x + i, y, BLACK, 0.4 * (1.0 - i / ln))
    if not skip_edges:
        for y in range(y0, y1):
            for x in range(x0, x1):
                d = min(x - x0, y - y0, x1 - 1 - x, y1 - 1 - y)
                if d < 5:
                    mix(px, x, y, BLACK, 0.28 * (1.0 - d / 5.0))


def save(name, img):
    img.save(os.path.join(OUT, name + ".png"))


# --- the room ---------------------------------------------------------------------------

def tex_floor():
    # worn boards: seams every 16px, per-plank tone drift, cup rings, grime
    img, px = canvas(WOOD)
    for y in range(128):
        plank = y // 16
        base = tuple(max(0, c + random.randint(-6, 6) + (plank % 3) * 4)
                     for c in WOOD)
        for x in range(128):
            px[x, y] = base
        for x in range(128):
            if y % 16 == 0:
                px[x, y] = WOOD_D
            elif y % 16 == 1 and random.random() < 0.4:
                mix(px, x, y, BLACK, 0.3)
    for _ in range(30):        # grain streaks along the boards
        y = random.randint(0, 127)
        scratch(px, random.randint(0, 127), y, random.randint(8, 30),
                WOOD_D if random.random() < 0.6 else BLACK,
                random.uniform(0.2, 0.45))
    for _ in range(3):         # knots
        blob(px, random.uniform(0, 128), random.uniform(0, 128), 3, BLACK, 0.5)
    stains(px, 5, [BLACK, CONC_D], 5, 14, 0.28)
    ring(px, random.randint(10, 118), random.randint(10, 118), 6, BLACK, 0.25)
    noise(px, 12)
    edges(px, 0.30)
    save("floor", dither(img))


def tex_wall():
    # plaster slabs: seam lines, tide stains, long drips, a crack
    img, px = canvas(CONC)
    for y in (0, 64):          # slab seams
        for x in range(128):
            px[x, y] = CONC_D
            if random.random() < 0.4:
                mix(px, x, y + 1, BLACK, 0.4)
    stains(px, 7, [CONC_D, SLIME, BLACK], 6, 20, 0.30)
    drips(px, 8, CONC_D, 0.26, 14, 60)
    # the crack: a jagged dark run
    cx, cy = random.randint(20, 100), 4
    while cy < 120:
        scratch(px, cx, cy, random.randint(3, 7), BLACK, 0.6, vert=True)
        cy += random.randint(4, 9)
        cx += random.randint(-3, 3)
    noise(px, 12)
    edges(px, 0.32)
    save("wall", dither(img))


def tex_wainscot():
    # the painted band: green-grey paint chipping off over older paint
    img, px = canvas(GREY_G)
    for _ in range(24):        # chips where the paint flaked
        x, y = random.randint(0, 127), random.randint(0, 127)
        r = random.uniform(1.5, 4.5)
        blob(px, x, y, r, CONC if random.random() < 0.6 else BLACK, 0.5, 0.4)
    for y in (0, 127):         # trim lines
        for x in range(128):
            px[x, y] = GREY_GD
    drips(px, 5, GREY_GD, 0.25, 8, 34)
    scratches(px, 12, BLACK, 0.4)
    noise(px, 11)
    edges(px, 0.30)
    save("wainscot", dither(img))


def tex_ceiling():
    img, px = canvas(CONC_D)
    for k in range(0, 128, 32):        # panel grid
        for i in range(128):
            px[k, i] = BLACK
            px[i, k] = BLACK
    for _ in range(3):                 # water stains with tide rings
        cx, cy = random.uniform(10, 118), random.uniform(10, 118)
        blob(px, cx, cy, random.uniform(8, 18), BLACK, 0.3)
        ring(px, cx, cy, random.uniform(6, 14), RUST, 0.28)
    noise(px, 10)
    save("ceiling", dither(img))


def tex_door():
    # steel door: brushed streaks, dents, rust blooming at the bottom
    img, px = canvas(CONC)
    for _ in range(40):        # horizontal brush
        y = random.randint(0, 127)
        scratch(px, random.randint(0, 100), y, random.randint(10, 28),
                CONC_D if random.random() < 0.6 else BLACK, 0.3)
    for _ in range(6):         # dents
        blob(px, random.uniform(10, 118), random.uniform(10, 110),
             random.uniform(3, 7), IRON_D, 0.3)
    for _ in range(5):         # rust from the bottom edge
        blob(px, random.uniform(0, 128), random.uniform(96, 126),
             random.uniform(4, 10), RUST, 0.4)
    drips(px, 4, RUST, 0.3, 6, 30)
    for x in range(128):       # worn frame
        px[x, 0] = GREY_GD
        px[x, 127] = GREY_GD
    noise(px, 11)
    edges(px, 0.34)
    save("door", dither(img))


def tex_window():
    # the city at night: building silhouettes and a few lit panes
    img, px = canvas(CITY)
    x = 0
    while x < 128:             # building silhouettes
        w = random.randint(12, 34)
        h = random.randint(30, 78)
        top = 128 - h
        for yy in range(top, 128):
            for xx in range(x, min(128, x + w)):
                px[xx, yy] = (20, 23, 32)
        for _ in range(random.randint(2, 7)):   # lit windows, sparse
            wx = random.randint(x + 2, max(x + 2, min(127, x + w - 4)))
            wy = random.randint(top + 3, 122)
            for yy in range(wy, min(126, wy + 3)):
                for xx in range(wx, min(126, wx + 3)):
                    px[xx, yy] = AMBER
        x += w + random.randint(0, 4)
    stains(px, 3, [BLACK], 8, 18, 0.3)
    noise(px, 8)
    edges(px, 0.4, band=16)
    save("window", dither(img))


def tex_desk():
    # the heavy top: long scratches, cup rings, burn spots, worn edges
    img, px = canvas(WOOD)
    for y in range(0, 128, 4): # grain
        for x in range(128):
            if random.random() < 0.35:
                mix(px, x, y, WOOD, 0.25)
    for _ in range(18):
        scratch(px, random.randint(0, 100), random.randint(0, 127),
                random.randint(10, 40), BLACK, 0.4)
    for _ in range(3):
        ring(px, random.randint(10, 110), random.randint(10, 110),
             random.randint(4, 8), BLACK, 0.4)
    for _ in range(2):
        blob(px, random.uniform(0, 128), random.uniform(0, 128), 5, BLACK, 0.6)
    noise(px, 11)
    edges(px, 0.3)
    save("desk", dither(img))


def tex_cabinet():
    # the file bank: painted metal, drawer fronts with slots and handles
    img, px = canvas(GREY_G)

    def front(put, w, h):
        for k in range(2):     # two drawer panels
            y0 = 6 if k == 0 else h // 2 + 4
            y1 = h // 2 - 4 if k == 0 else h - 6
            for xx in range(4, w - 4):
                put(xx, y0, GREY_GD)
                put(xx, y1, GREY_GD)
            for yy in range(y0, y1):
                put(4, yy, GREY_GD)
                put(w - 5, yy, GREY_GD)
            hy = (y0 + y1) // 2
            for xx in range(w // 2 - 6, w // 2 + 6):   # the handle slot
                put(xx, hy, BLACK)
                put(xx, hy + 1, BLACK)

    def plain(put, w, h):
        for yy in range(h):    # plain metal with a dark edge line
            put(0, yy, GREY_GD)
            put(w - 1, yy, GREY_GD)

    fill_cells(img, px, GREY_G,
               {"front": front, "right": plain, "back": plain,
                "left": plain, "top": plain, "bottom": plain})
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, False)
    x0, y0, x1, y1 = CELL_RECT["front"]
    for _ in range(3):         # rust bloom low on the front
        blob(px, random.randint(x0 + 6, x1 - 6),
             random.randint(y0 + 26, y0 + 56), random.uniform(3, 7), RUST, 0.4)
    noise(px, 10)
    save("cabinet", dither(img))


def tex_typewriter():
    # the machine: black shell, pale key grid on the top cell
    img, px = canvas(BLACK)

    def top(put, w, h):
        for r in range(3):     # three rows of keys
            ky = 18 + r * 14
            for k in range(9):
                kx = 6 + k * 4
                for yy in range(ky, ky + 6):
                    for xx in range(kx, kx + 3):
                        put(xx, yy, PUTTY_D if random.random() < 0.9 else BONE)
        for xx in range(6, w - 6):     # the roller
            put(xx, 6, CONC)
            put(xx, 7, BLACK)

    def sides(put, w, h):
        for yy in range(h):
            put(0, yy, IRON_D)
            put(w - 1, yy, IRON_D)

    plain = {n: sides for n in ("front", "right", "back", "left", "bottom")}
    fill_cells(img, px, BLACK, {"top": top, **plain})
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, False)
    noise(px, 9)
    save("typewriter", dither(img))


def tex_paper():
    img, px = canvas(BONE)
    scrawl(px, 12, 14, 6, 100, IRON, 0.5, gap=8)
    scrawl(px, 12, 70, 3, 80, IRON, 0.45, gap=8)
    ring(px, random.randint(20, 100), random.randint(80, 110), 9, (140, 100, 60), 0.3)
    stains(px, 2, [PUTTY_D], 6, 12, 0.3)
    noise(px, 9)
    edges(px, 0.22, band=10)
    save("paper", dither(img))


def tex_vent():
    img, px = canvas(IRON_D)
    for y in range(6, 122, 10):        # slats
        for x in range(8, 120):
            px[x, y] = IRON
            px[x, y + 1] = BLACK
    stains(px, 4, [BLACK, RUST], 4, 12, 0.35)
    noise(px, 9)
    edges(px, 0.3)
    save("vent", dither(img))


def tex_rug():
    img, px = canvas((58, 30, 28))
    for i in range(0, 128, 8):         # the woven border pattern
        for x in range(128):
            mix(px, x, (i + 4) % 128, BLACK, 0.3)
    for y in range(128):
        for x in range(0, 128, 8):
            mix(px, (x + 4) % 128, y, (70, 38, 34), 0.3)
    stains(px, 6, [BLACK], 5, 16, 0.4)
    noise(px, 12)
    edges(px, 0.32)
    save("rug", dither(img))


def tex_iron():
    img, px = canvas(IRON)
    for _ in range(24):
        y = random.randint(0, 127)
        scratch(px, random.randint(0, 100), y, random.randint(10, 30), IRON_D, 0.35)
    for _ in range(5):
        blob(px, random.uniform(0, 128), random.uniform(0, 128),
             random.uniform(3, 9), RUST, 0.35)
    noise(px, 10)
    edges(px, 0.26)
    save("iron", dither(img))


# --- the PI's sheets ---------------------------------------------------------------------

def tex_pi_shirt():
    # the office shirt: bone-white cloth, a dried-blood tie, black braces
    # over the shoulders; worn, sweat-pale under the arms
    SHIRT_D = (176, 168, 152)
    img, px = canvas(BONE)
    weave(px, BLACK, 0.10)

    def front(put, w, h):
        for i in range(8):          # the collar V
            put(20 - i, i, SHIRT_D)
            put(20 - i, i + 1, SHIRT_D)
            put(22 + i, i, SHIRT_D)
            put(22 + i, i + 1, SHIRT_D)
        for cy in range(5, 13):     # the tie knot
            for cx in range(17, 26):
                if abs(cx - 21) < (cy - 3):
                    put(cx, cy, MAROON)
        for cy in range(13, 42):    # the tie blade, tapering
            half = 3 if cy < 34 else 2
            for cx in range(21 - half, 22 + half):
                put(cx, cy, MAROON)
                if cx == 21 - half or cx == 21 + half - 1:
                    put(cx, cy, MAROON_D)
        for cy in range(0, h):      # the braces, straight over the shoulders
            for cx in range(2, 8):
                put(cx, cy, BLACK)
            for cx in range(w - 8, w - 2):
                put(cx, cy, BLACK)
        for cy in range(2, 7):      # buckle hints on the braces
            for cx in (4, 5, w - 6, w - 5):
                put(cx, cy, IRON_D)

    def back(put, w, h):
        for cy in range(0, h):      # the braces run down the back too
            for cx in range(6, 12):
                put(cx, cy, BLACK)
            for cx in range(w - 12, w - 6):
                put(cx, cy, BLACK)

    fill_cells(img, px, BONE, {"front": front, "back": back})
    stains(px, 5, [PUTTY_D, CONC], 4, 11, 0.22)
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, name != "front")
    noise(px, 9)
    save("pi_shirt", dither(img))


def tex_pi_sleeve():
    # the sleeves: plain shirt cloth, no tie, no braces - the painted front
    # cell of pi_shirt must never leak onto the arm boxes
    img, px = canvas(BONE)
    weave(px, BLACK, 0.10)
    stains(px, 3, [PUTTY_D, CONC], 4, 10, 0.2)
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, False)
    noise(px, 9)
    save("pi_sleeve", dither(img))


def tex_pi_slacks():
    img, px = canvas((46, 44, 42))
    for y in range(0, 128, 6):         # trouser crease lines
        for x in range(128):
            mix(px, x, y, BLACK, 0.25)
    stains(px, 4, [BLACK], 5, 12, 0.3)
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, False)
    noise(px, 9)
    save("pi_slacks", dither(img))


def tex_pi_skin():
    # pale putty: mottled, faintly dirty
    img, px = canvas(PUTTY)
    stains(px, 6, [PUTTY_D], 5, 13, 0.3)
    stains(px, 3, [SLIME], 3, 8, 0.18)
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, False)
    noise(px, 8)
    save("pi_skin", dither(img))


def tex_pi_face():
    # the mug from the reference: slicked-back hairline, a furrowed brow over
    # narrow tired eyes, a chevron mustache drooping past the mouth, three
    # days of stubble up the jaw - worn, sharp, mid-case
    img, px = canvas(PUTTY)
    putf, wf, hf = cell(px, "front")
    for cx in range(wf):       # the hairline: slicked back, a jagged edge
        edge = 7 + (2 if cx % 5 < 2 else 0)
        for cy in range(edge):
            putf(cx, cy, HAIR)
    for cx in (0, 1, wf - 2, wf - 1):   # the temples carry hair lower
        for cy in range(7, 22):
            putf(cx, cy, HAIR)
    for cx in range(14, 29):   # the worry crease on the forehead
        putf(cx, 13 + (cx % 2), PUTTY_D)
    for side in (0, 1):        # the furrowed brows: inner ends pushed down
        for i in range(10):
            bx = (8 + i) if side == 0 else (wf - 9 - i)
            by = 17 + (i // 3)
            for t in range(2):
                putf(bx, by + t, HAIR_D)
    for ex in (12, 30):        # narrow eye pits, one pale glint each
        for cy in range(24, 29):
            for dx in range(-3, 4):
                putf(ex + dx, cy, BLACK if abs(dx) < 3 else PUTTY_D)
        putf(ex - 1, 25, BONE)
        putf(ex + 1, 25, BONE)
        for dx in range(-4, 5):    # the bags under them
            putf(ex + dx, 30, PUTTY_D)
    for cy in range(28, 42):   # the nose shadow, nostrils at the foot
        for dx in range(-1, 2):
            putf(21 + dx, cy, PUTTY_D)
    for cx in (18, 24):
        putf(cx, 41, HAIR_D)
    for cy in range(42, 56):   # the cheeks sink a little, worn
        for cx in (5, 6, 7, 36, 37, 38):
            if random.random() < 0.5:
                putf(cx, cy, PUTTY_D)
    for cx in range(6, 38):    # the mustache: droops past the mouth corners
        drop = abs(cx - 21) // 4
        top = 42
        bot = 47 + drop
        for cy in range(top, bot):
            putf(cx, cy, HAIR if cy < bot - 1 else HAIR_D)
    for cx in range(14, 29):   # a grim line under the mustache
        putf(cx, 52, HAIR_D)
    for cy in range(50, 64):   # the goatee blotches in at the chin
        for cx in range(13, 31):
            if random.random() < 0.6:
                putf(cx, cy, HAIR_D)
    for cy in range(44, 64):   # stubble up the jaw
        for cx in range(2, 42):
            if random.random() < 0.3:
                putf(cx, cy, HAIR_D)
    for name in CELL_RECT:     # hair on top and back; sides split at the eye line
        x0, y0, x1, y1 = CELL_RECT[name]
        if name == "top":
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    px[xx, yy] = HAIR
        elif name in ("back", "left", "right"):
            split = y0 + 26
            for yy in range(y0, split):
                for xx in range(x0, x1):
                    px[xx, yy] = HAIR
            if name == "back":
                for yy in range(y0 + 4, split, 7):   # comb sheen
                    for xx in range(x0 + 6, x1 - 6, 2):
                        px[xx, yy] = HAIR_L
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, name != "front")
    noise(px, 7)
    save("pi_face", dither(img))


def tex_pi_hand():
    # the mitts: pale, knuckle creases, grime in the creases
    img, px = canvas(PUTTY)

    def front(put, w, h):
        for kx in range(6, w - 4, 8):   # finger separations
            for cy in range(h // 3, h - 4):
                put(kx, cy, PUTTY_D)
        for cy in range(h // 2, h - 2): # knuckle dip
            for cx in range(2, w - 2):
                if random.random() < 0.2:
                    put(cx, cy, PUTTY_D)

    for name in CELL_RECT:
        put, w, h = cell(px, name)
        for cy in range(h):
            for cx in range(w):
                put(cx, cy, PUTTY)
        if name == "front":
            front(put, w, h)
    for name in CELL_RECT:
        img_crop_grime(*CELL_RECT[name], px, name != "front")
    noise(px, 8)
    save("pi_hand", dither(img))


def tex_pi_hair():
    # slicked-back hair: dark, oiled, comb lines running through the sheen
    img, px = canvas(HAIR)
    for y in range(0, 128, 6):
        for x in range(128):
            if random.random() < 0.45:
                mix(px, x, y, HAIR_L, 0.5)
    for y in range(3, 128, 6):
        for x in range(128):
            if random.random() < 0.3:
                mix(px, x, y, HAIR_D, 0.4)
    stains(px, 2, [HAIR_D], 4, 9, 0.2)
    noise(px, 6)
    save("pi_hair", dither(img))


def tex_pi_boot():
    # black leather, worn to grey at the toe; no rust - boots stay black
    img, px = canvas(BLACK)
    for name in CELL_RECT:
        put, w, h = cell(px, name)
        for cy in range(h):
            for cx in range(w):
                put(cx, cy, BLACK)
        for _ in range(3):      # worn highlights
            x, y = random.randint(4, w - 6), random.randint(4, h - 6)
            blob(px, x, y, random.uniform(2, 4), (48, 46, 44), 0.5)
        for _ in range(2):
            blob(px, random.randint(4, w - 4), random.randint(4, h - 4),
                 random.uniform(2, 5), (16, 15, 14), 0.5)
    noise(px, 8)
    save("pi_boot", dither(img))


# --- the menu sprites --------------------------------------------------------------------

def grime_text(text, size, color, erode=0.22, offset_shadow=True):
    # mono type with the ink broken up, a misregistered shadow underneath
    f = ImageFont.truetype(os.path.join(FONT_DIR, "DejaVuSansMono-Bold.ttf"), size)
    pad = size // 2
    tmp = Image.new("L", (10, 10))
    td = ImageDraw.Draw(tmp)
    box = td.textbbox((0, 0), text, font=f)
    w, h = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if offset_shadow:
        d.text((pad + 2, pad - box[1] + 2), text, font=f, fill=(10, 10, 10, 200))
    d.text((pad, pad - box[1]), text, font=f, fill=color + (255,))
    px = img.load()
    for y in range(h):          # the ink erodes
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and random.random() < erode:
                px[x, y] = (r, g, b, int(a * random.uniform(0.15, 0.7)))
    return img


def tex_menu_title():
    img = grime_text("RED HARBOR", 52, (226, 220, 206), erode=0.20)
    img.save(os.path.join(SPRITES, "menu_title.png"))


def tex_menu_prompt():
    f = ImageFont.truetype(os.path.join(FONT_DIR, "DejaVuSansMono-Bold.ttf"), 15)
    txt = "PRESS ENTER"
    tmp = Image.new("L", (10, 10))
    td = ImageDraw.Draw(tmp)
    box = td.textbbox((0, 0), txt, font=f)
    w, h = box[2] - box[0] + 24, box[3] - box[1] + 12
    img = Image.new("RGBA", (w, h), (8, 8, 8, 255))
    d = ImageDraw.Draw(img)
    d.text((12, 5 - box[1]), txt, font=f, fill=(226, 220, 206, 255))
    img.save(os.path.join(SPRITES, "menu_prompt.png"))


SHEETS = {
    "floor": tex_floor, "wall": tex_wall, "wainscot": tex_wainscot,
    "ceiling": tex_ceiling, "door": tex_door, "window": tex_window,
    "desk": tex_desk, "cabinet": tex_cabinet, "typewriter": tex_typewriter,
    "paper": tex_paper, "vent": tex_vent, "rug": tex_rug, "iron": tex_iron,
    "pi_shirt": tex_pi_shirt, "pi_sleeve": tex_pi_sleeve, "pi_slacks": tex_pi_slacks,
    "pi_skin": tex_pi_skin, "pi_face": tex_pi_face, "pi_hand": tex_pi_hand,
    "pi_hair": tex_pi_hair, "pi_boot": tex_pi_boot,
    "menu_title": tex_menu_title, "menu_prompt": tex_menu_prompt,
}


def main():
    # pass "name1,name2" to repaint only those sheets; a bare run does all
    import sys
    os.makedirs(OUT, exist_ok=True)
    for name in (sys.argv[1].split(",") if len(sys.argv) > 1 else SHEETS):
        SHEETS[name]()
    print("wrote", len(os.listdir(OUT)), "textures to", OUT)


if __name__ == "__main__":
    main()
