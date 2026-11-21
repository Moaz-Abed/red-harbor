#!/usr/bin/env python3
"""Red Harbor - the PI's office, Gotham cut. 16 tiles, 16 px each -> assets/tiles/office_tiles.png.

Dark art-deco room: cold blue-grey walls, near-black walnut boards, an oxblood
rug, rain-streaked windows over a skyline, one warm desk lamp and the red neon
door. Everything sits under the office's CanvasModulate dusk, so values here
are one step brighter than they should land on screen.

Run from the repo root:   python3 assets_src/gen_office.py
"""
import os
from PIL import Image

T = (0, 0, 0, 0)
INK = (15, 14, 23)
# walls - cold Gotham stone with faint deco paneling
W1 = (51, 52, 74)
W2 = (40, 41, 60)
W3 = (64, 65, 90)
W4 = (31, 32, 49)
# floor - near-black walnut with a blue cast
P1 = (47, 42, 63)
P2 = (58, 51, 76)
P3 = (40, 36, 54)
PG = (23, 20, 35)
# rug - oxblood with a dark thread
R1 = (97, 27, 51)
R2 = (74, 20, 38)
R3 = (123, 35, 63)
R4 = (164, 49, 77)
# furniture woods
D1 = (79, 58, 42)
D2 = (96, 70, 51)
D3 = (54, 38, 28)
C1 = (59, 52, 59)
C2 = (73, 65, 73)
C3 = (42, 37, 44)
BRASS = (215, 174, 108)
# window
SKY = (24, 29, 55)
SKY2 = (32, 38, 70)
CITY = (14, 15, 31)
CITY2 = (20, 22, 41)
MOON = (238, 251, 255)
LIT = (253, 195, 113)
STREAK = (113, 128, 179)
FR = (63, 59, 87)
FRL = (87, 83, 120)
# neon door / radio / props
NEON = (255, 95, 77)
NEON2 = (255, 177, 138)
DOOR = (36, 32, 52)
DOOR2 = (51, 45, 74)
RAD = (54, 50, 74)
RAD2 = (69, 63, 93)
DIAL = (255, 228, 128)
PAPER = (255, 255, 255)
FOLDER = (255, 238, 161)
MAT = (60, 52, 49)
MAT2 = (76, 67, 61)

W, H, TS = 16, 16, 16


def blank():
    im = Image.new("RGBA", (W * TS, H), T)
    return im, im.load()


def fill(px, ti, c):
    for y in range(H):
        for x in range(TS):
            px[ti * TS + x, y] = c


def rect(px, ti, x0, y0, x1, y1, c):
    for y in range(max(0, y0), min(H, y1 + 1)):
        for x in range(max(0, x0), min(TS, x1 + 1)):
            px[ti * TS + x, y] = c


def px1(px, ti, x, y, c):
    if 0 <= x < TS and 0 <= y < H:
        px[ti * TS + x, y] = c


# deterministic hash so the wood grain never changes between runs
def h(x, y, s=0):
    n = (x * 73856093 + y * 19349663 + s * 83492791) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return (n >> 16) & 0xFF


def planks(px, ti, s, dim=False):
    """Long floorboards: 4 px boards, rare joints, horizontal grain runs.
    `dim` = the shade variant: same boards, one step darker."""
    fill(px, ti, P1)
    for y in range(H):
        for x in range(TS):
            if y % 4 == 3:
                px1(px, ti, x, y, PG)                    # board gap
            elif h(x // 2, y, s) > 214:                  # grain, in 2 px runs
                px1(px, ti, x, y, P2)
            elif h(x, y, s + 1) < 26:
                px1(px, ti, x, y, P3)
    for b, y in enumerate(range(0, H, 4)):               # one joint per band
        if h(b, 0, s + 2) > 52:
            gx = (b * 11 + s * 3) % 16
            for yy in range(y, y + 3):
                px1(px, ti, gx, yy, PG)
    if dim:
        for y in range(H):
            for x in range(TS):
                r, g, b, a = px[ti * TS + x, y]
                px[ti * TS + x, y] = (int(r * 0.84), int(g * 0.84), int(b * 0.86), a)


def wall_face(px, ti):
    """Top wall: deco paneling, a rail and baseboard at the bottom."""
    fill(px, ti, W1)
    for y in range(H):
        for x in range(TS):
            r = h(x, y, 9)
            if r < 24:
                px1(px, ti, x, y, W2)
            elif r > 236:
                px1(px, ti, x, y, W3)
    for x in range(0, TS, 4):                            # deco fluting
        for y in range(0, 12):
            px1(px, ti, x, y, W2)
            if x > 0:
                px1(px, ti, x - 1, y, W3 if h(x, y, 3) > 120 else W1)
    rect(px, ti, 0, 0, TS - 1, 0, W4)                    # shadow under the ceiling
    rect(px, ti, 0, 12, TS - 1, 12, W3)                  # chair rail
    rect(px, ti, 0, 13, TS - 1, 14, W2)
    rect(px, ti, 0, 15, TS - 1, 15, C3)                  # baseboard


def wall_plain(px, ti):
    fill(px, ti, W2)
    for y in range(H):
        for x in range(TS):
            r = h(x, y, 17)
            if r < 22:
                px1(px, ti, x, y, W4)
            elif r > 232:
                px1(px, ti, x, y, W1)
    for x in range(0, TS, 8):
        for y in range(3, 14):
            px1(px, ti, x, y, W4)


def desk(px, ti, case_file=False):
    fill(px, ti, D1)
    rect(px, ti, 0, 1, TS - 1, 2, D2)                    # lamp sheen across the top
    for y in range(3, H - 2):
        for x in range(TS):
            if h(x // 3, y, 5) > 234:
                px1(px, ti, x, y, D3)                    # sparse wood grain
    rect(px, ti, 0, 13, TS - 1, 13, D3)                  # front edge
    rect(px, ti, 0, 14, TS - 1, 15, INK)
    rect(px, ti, 0, 0, TS - 1, 0, D3)
    if case_file:
        rect(px, ti, 4, 3, 11, 9, FOLDER)                # the manila case file
        rect(px, ti, 4, 3, 11, 3, (222, 190, 130))
        rect(px, ti, 4, 9, 11, 9, (150, 124, 78))
        px1(px, ti, 4, 4, INK); px1(px, ti, 11, 4, INK)
        rect(px, ti, 6, 5, 10, 8, PAPER)                 # a photo slipped out
        px1(px, ti, 6, 5, (160, 155, 142))
        px1(px, ti, 8, 6, (60, 56, 52)); px1(px, ti, 9, 7, (60, 56, 52))


def cabinet(px, ti):
    fill(px, ti, C1)
    for y in range(H):
        for x in range(TS):
            r = h(x, y, 11)
            if r > 232:
                px1(px, ti, x, y, C2)
    rect(px, ti, 0, 0, TS - 1, 0, C3)
    for yy in (5, 11):                                   # drawer seams
        rect(px, ti, 1, yy, TS - 2, yy, C3)
    for yy in (2, 8):                                    # brass pulls
        rect(px, ti, 6, yy, 9, yy, BRASS)
        px1(px, ti, 6, yy, (92, 74, 44))
    rect(px, ti, 0, 15, TS - 1, 15, INK)


def rug(px, ti):
    fill(px, ti, R1)
    for y in range(H):
        for x in range(TS):
            r = h(x, y, 23)
            if r < 30:
                px1(px, ti, x, y, R2)
            elif r > 226:
                px1(px, ti, x, y, R3)
    for y in range(H):                                   # diamond weave
        for x in range(TS):
            if (x + y) % 8 == 0 or (x - y) % 8 == 0:
                px1(px, ti, x, y, R2)
    for y in range(H):                                   # occasional gold thread
        for x in range(TS):
            if (x * y) % 31 == 7:
                px1(px, ti, x, y, R4)


def crate(px, ti):
    fill(px, ti, D3)
    for y in range(H):
        for x in range(TS):
            r = h(x, y, 29)
            if y % 4 == 1:
                px1(px, ti, x, y, D1)
            elif r > 220:
                px1(px, ti, x, y, (56, 42, 30))
    rect(px, ti, 0, 0, TS - 1, 0, INK)
    rect(px, ti, 0, 15, TS - 1, 15, INK)
    rect(px, ti, 0, 0, 0, H - 1, INK)
    rect(px, ti, TS - 1, 0, TS - 1, H - 1, INK)
    rect(px, ti, 0, 7, TS - 1, 8, (20, 15, 11))          # cross brace
    rect(px, ti, 7, 0, 8, H - 1, (20, 15, 11))


def window(px, ti, s):
    fill(px, ti, SKY)
    for y in range(H):
        for x in range(TS):
            if h(x, y, s) > 235:
                px1(px, ti, x, y, SKY2)
    px1(px, ti, 4 + s, 2, MOON); px1(px, ti, 5 + s, 2, MOON)       # the moon
    px1(px, ti, 4 + s, 3, MOON)
    px1(px, ti, 3 + s, 2, (120, 132, 170))
    # skyline: two towers of black with lit windows
    for x in range(0, 6):
        rect(px, ti, x, 6 + (x % 2), x, 15, CITY)
    for x in range(6, 12):
        rect(px, ti, x, 8, x, 15, CITY2)
    for x in range(12, TS):
        rect(px, ti, x, 5 + (x % 3), x, 15, CITY)
    for lx, ly in ((2, 9), (3, 12), (8, 10), (9, 13), (13, 8), (14, 11)):
        px1(px, ti, lx, ly, LIT)
        px1(px, ti, lx, ly + 1, (120, 92, 52))
    rect(px, ti, 0, 14, TS - 1, 15, CITY)                # street ledge
    for x in range(TS):                                  # rain on the glass
        for y in range(H):
            if (x * 3 + y * 7 + s) % 17 == 0:
                px1(px, ti, x, y, STREAK)
            if (x + y * 2) % 23 == 0:
                px1(px, ti, x, y, (44, 52, 82))
    rect(px, ti, 7, 0, 8, H - 1, FR)                     # the window cross
    rect(px, ti, 0, 7, TS - 1, 8, FR)
    rect(px, ti, 0, 0, TS - 1, 0, FRL)
    rect(px, ti, 0, 0, 0, H - 1, FRL)
    rect(px, ti, TS - 1, 0, TS - 1, H - 1, FRL)
    rect(px, ti, 0, 15, TS - 1, 15, INK)                 # sill shadow


def radio(px, ti):
    fill(px, ti, RAD)
    rect(px, ti, 0, 0, TS - 1, 0, INK)
    rect(px, ti, 0, 15, TS - 1, 15, INK)
    rect(px, ti, 2, 2, 7, 6, RAD2)                       # dial glass
    px1(px, ti, 4, 4, DIAL); px1(px, ti, 5, 4, DIAL)     # the warm eye
    px1(px, ti, 3, 4, (110, 84, 48))
    for yy in (9, 11, 13):                               # speaker cloth
        for x in range(9, 15):
            px1(px, ti, x, yy, RAD2 if x % 2 == 0 else RAD)
    rect(px, ti, 9, 3, 14, 6, RAD2)                      # tuning band
    for x in range(10, 14):
        px1(px, ti, x, 2, INK)


def scuff(px, ti):
    planks(px, ti, 2)
    for x, y in ((3, 2), (4, 3), (5, 3), (10, 8), (11, 9), (12, 9), (6, 12), (7, 12)):
        px1(px, ti, x, y, (52, 48, 64))                  # dragged heel marks
        px1(px, ti, x + 1, y - 1, (16, 14, 24))


def papers(px, ti):
    planks(px, ti, 3)
    rect(px, ti, 3, 4, 8, 8, PAPER)                      # two dropped sheets
    rect(px, ti, 3, 4, 3, 8, (170, 165, 152))
    px1(px, ti, 5, 6, (90, 88, 82)); px1(px, ti, 6, 6, (90, 88, 82))
    rect(px, ti, 9, 9, 13, 12, (196, 190, 176))
    px1(px, ti, 11, 10, (90, 88, 82))


def mat(px, ti):
    fill(px, ti, MAT)
    for y in range(H):
        for x in range(TS):
            r = h(x, y, 37)
            if r > 224:
                px1(px, ti, x, y, MAT2)
    for y in range(H):                                   # bristle texture
        for x in range(TS):
            if (x + y) % 5 == 0:
                px1(px, ti, x, y, MAT2)
    rect(px, ti, 0, 0, TS - 1, 0, (24, 21, 20))
    rect(px, ti, 0, 15, TS - 1, 15, INK)


def neon_door(px, ti):
    """One door tile, stamped twice (rows 10-11): the left tube runs the
    full height and the sign band crosses both halves."""
    fill(px, ti, DOOR)
    for y in range(H):
        for x in range(TS):
            if h(x, y, 41) > 240:
                px1(px, ti, x, y, DOOR2)
    rect(px, ti, 4, 2, 11, 5, (26, 22, 36))              # recessed sign box
    rect(px, ti, 5, 3, 10, 4, NEON)                      # the EXIT tube
    rect(px, ti, 5, 3, 10, 3, NEON2)
    px1(px, ti, 4, 3, NEON); px1(px, ti, 11, 3, NEON)
    rect(px, ti, 7, 9, 8, 11, DOOR2)                     # handle plate
    px1(px, ti, 7, 10, BRASS); px1(px, ti, 8, 10, BRASS)
    rect(px, ti, 0, 0, 0, H - 1, NEON)                   # neon frame tube, left
    rect(px, ti, 1, 0, 1, H - 1, (84, 30, 28))
    rect(px, ti, 2, 0, TS - 1, 0, (46, 18, 17))
    rect(px, ti, 2, 15, TS - 1, 15, (46, 18, 17))
    rect(px, ti, TS - 1, 0, TS - 1, H - 1, INK)


def main():
    im, px = blank()
    planks(px, 0, 0)                                     # 0 planks
    planks(px, 1, 0, dim=True)                           # 1 plank shade
    planks(px, 2, 5)                                     # 2 worn floor
    for x, y in ((4, 5), (11, 10), (2, 12), (12, 3), (9, 14)):
        for dx in range(2):                              # old stains, foot-worn
            for dy in range(2):
                px1(px, 2, x + dx, y + dy, (56, 52, 70))
                px1(px, 2, x + dx, y + dy - 1, (14, 12, 22))
    wall_face(px, 3)                                     # 3 wall face
    wall_plain(px, 4)                                    # 4 plain wall
    neon_door(px, 5)                                     # 5 neon door (stamped twice)
    desk(px, 6)                                          # 6 desk
    cabinet(px, 7)                                       # 7 cabinet
    rug(px, 8)                                           # 8 rug
    crate(px, 9)                                         # 9 crate
    window(px, 10, 1)                                    # 10 window
    radio(px, 11)                                        # 11 radio
    scuff(px, 12)                                        # 12 scuff
    papers(px, 13)                                       # 13 papers
    mat(px, 14)                                          # 14 mat
    desk(px, 15, case_file=True)                         # 15 desk with the case file
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "tiles", "office_tiles.png")
    im.save(out)
    print("wrote", os.path.normpath(out))


if __name__ == "__main__":
    main()
