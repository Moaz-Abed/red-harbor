#!/usr/bin/env python3
"""Red Harbor - procedural sprite generator (smooth 3-direction animation sheets).

Run from the repo root:   python3 assets_src/gen_sprites.py
Writes: assets/sprites/{player,guard,portrait,exit,intel,task}_sheet.png and the
extended assets/tiles/harbor_tiles.png (+ preview/*.png)

Why a generator: every frame is drawn from one small rig (legs, coat, arms,
head, hat), so walk/sneak/dash/takedown cycles stay consistent and a palette
or proportion change is one edit, not 90 hand-edited frames.

Sheet layout (32x32 cells, ground line at y=30, centre x=16):
  player_sheet.png  256 x 640   rows = anim x view, columns = frames
      rows  0..17 : [idle, walk, sneak, dash, takedown, hurt] x [down, up, side]
      row   18    : dead (side, 6 frames)   row 19 : squeeze (side, 6 frames)
  guard_sheet.png   256 x 480   rows 0..11 : [patrol, chase, idle, alert] x [down, up, side]
      row 12 : search (side, 6)   row 13 : ko (side, 6)   row 14 : search (down, 6)
Views: "side" faces RIGHT; the game flips it for left.
Only the 7 noir-palette colours are used. Red is reserved for the State
(guard hat band / armband / alarm) and for the PI's blood.
"""
import math
import os
from PIL import Image

INK = (20, 18, 28, 255)
SHADOW = (42, 40, 60, 255)
SLATE = (74, 78, 105, 255)
FOG = (122, 112, 128, 255)
BONE = (222, 214, 199, 255)
SODIUM = (224, 164, 88, 255)
RED = (193, 41, 46, 255)
T = (0, 0, 0, 0)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "sprites")
PREVIEW = os.path.join(ROOT, "preview")


class Cv:
    def __init__(self, w=32, h=32):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w, h), T)
        self.px = self.im.load()

    def p(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def r(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.p(x, y, c)

    def line(self, x0, y0, x1, y1, c, th=1):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.r(x0, y0, x0 + th - 1, y0 + th - 1, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def outline(self):
        src = self.im.copy().load()
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3] == 0:
                    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                        if 0 <= nx < self.w and 0 <= ny < self.h and src[nx, ny][3] > 0:
                            self.px[x, y] = INK
                            break


# ----------------------------------------------------------------------------
# Character rig
# ----------------------------------------------------------------------------

def _hat(c, view, cx, hy, guard, lean=0):
    """Fedora (PI) or peaked cap (guard). hy = face top row."""
    band = RED if guard else SLATE
    if guard:
        c.r(cx - 4 + lean, hy - 4, cx + 3 + lean, hy - 2, INK)        # flat cap crown
        c.r(cx - 4 + lean, hy - 2, cx + 3 + lean, hy - 2, band)
        if view == "side":
            c.r(cx - 4 + lean, hy - 1, cx + 6 + lean, hy - 1, INK)    # visor forward
        else:
            c.r(cx - 5 + lean, hy - 1, cx + 4 + lean, hy - 1, INK)
    else:
        c.r(cx - 3 + lean, hy - 5, cx + 2 + lean, hy - 5, INK)        # pinched crown top
        c.r(cx - 4 + lean, hy - 4, cx + 3 + lean, hy - 2, INK)
        c.r(cx - 4 + lean, hy - 2, cx + 3 + lean, hy - 2, band)
        if view == "side":
            c.r(cx - 5 + lean, hy - 1, cx + 6 + lean, hy - 1, INK)
        else:
            c.r(cx - 6 + lean, hy - 1, cx + 5 + lean, hy - 1, INK)


def draw_front(c, P, guard=False):
    cx = 16 + P.get("sway", 0)
    dy, cr = P.get("dy", 0), P.get("crouch", 0)
    flare = P.get("flare", 0)
    spread = P.get("spread", 0)
    # legs (dark, shorter when lifted)
    for s, lift in ((-1, P.get("legL", 0)), (1, P.get("legR", 0))):
        x = 16 + s * 3 - 1 + spread * s
        top, bot = 23 + cr, 30 - lift
        c.r(x, top, x + 2, bot, INK)
        c.r(x, bot, x + 2, bot, SHADOW)
    half = 6 + (1 if guard else 0)
    top = 13 + dy + cr
    hem = 24 + cr
    # arms behind coat edge
    sw = {-1: P.get("armL", 0), 1: P.get("armR", 0)}
    raise_arm = P.get("arms_out", 0)
    for s in (-1, 1):
        ax = cx + s * (half + 1) + (0 if s > 0 else -1) + s * raise_arm
        ay0 = top + 1 - (raise_arm and 2)
        ay1 = top + 8 + sw[s] - (raise_arm * 3)
        c.r(ax, ay0, ax + 1, ay1, SHADOW)
        c.r(ax, ay0, ax, ay1, SLATE)
        c.r(ax, ay1 + 1, ax + 1, ay1 + 1, BONE)
        if guard and s == -1:
            c.r(ax, top + 4, ax + 1, top + 4, RED)      # armband
    # coat (trapezoid)
    for y in range(top, hem + 1):
        t = (y - top) / max(1, hem - top)
        h = int(round(half + t * (1.6 + flare)))
        c.r(cx - h, y, cx + h - 1, y, SHADOW)
        c.p(cx - h, y, SLATE)
    c.r(cx - half - 1, top, cx + half, top, SLATE)       # shoulder line
    if not guard:
        c.r(cx - 1, top, cx, top + 2, BONE)              # shirt
        c.r(cx - 1, top + 1, cx, top + 4, SODIUM)        # tie
        c.p(cx - 2, top + 1, SLATE); c.p(cx + 1, top + 1, SLATE)
    else:
        c.r(cx - 1, top, cx, top + 2, BONE)
        c.r(cx - 1, top + 1, cx, top + 1, FOG)
    c.r(cx - half, top + 7, cx + half - 1, top + 7, INK)  # belt
    c.p(cx, top + 7, SODIUM if not guard else FOG)
    if guard:
        c.p(cx + 4, top + 8, INK); c.p(cx + 4, top + 9, INK)  # baton
    # head
    hy = 9 + dy + cr
    c.r(cx - 3, hy, cx + 2, hy + 4, BONE)
    c.r(cx - 3, hy, cx + 2, hy, FOG)                     # brim shadow
    eyes = P.get("eyes", "open")
    if eyes == "open":
        c.p(cx - 2, hy + 2, INK); c.p(cx + 1, hy + 2, INK)
    elif eyes == "shut":
        c.r(cx - 2, hy + 2, cx - 1, hy + 2, INK); c.r(cx, hy + 2, cx + 1, hy + 2, INK)
    c.r(cx - 1, hy + 4, cx, hy + 4, FOG)                 # mouth
    if P.get("hurt"):
        c.p(cx, hy + 4, RED)
    if P.get("cig"):
        c.p(cx + 3, hy + 3, BONE); c.p(cx + 4, hy + 3, SODIUM)
        sm = P.get("smoke", 0)
        if sm:
            c.p(cx + 4 + (sm % 2), hy + 3 - sm, FOG)
    _hat(c, "front", cx, hy, guard)
    if P.get("torch"):
        c.r(cx + half + 1, top + 9, cx + half + 2, top + 10, FOG)
        c.p(cx + half + 1, top + 11, BONE)               # lens toward the camera
    if P.get("bang"):
        _bang(c, cx + 8, hy - 6)


def draw_back(c, P, guard=False):
    cx = 16 + P.get("sway", 0)
    dy, cr = P.get("dy", 0), P.get("crouch", 0)
    flare = P.get("flare", 0)
    spread = P.get("spread", 0)
    for s, lift in ((-1, P.get("legL", 0)), (1, P.get("legR", 0))):
        x = 16 + s * 3 - 1 + spread * s
        top, bot = 23 + cr, 30 - lift
        c.r(x, top, x + 2, bot, INK)
        c.r(x, bot, x + 2, bot, SHADOW)
    half = 6 + (1 if guard else 0)
    top = 13 + dy + cr
    hem = 24 + cr
    sw = {-1: P.get("armL", 0), 1: P.get("armR", 0)}
    raise_arm = P.get("arms_out", 0)
    for s in (-1, 1):
        ax = cx + s * (half + 1) + (0 if s > 0 else -1) + s * raise_arm
        ay0 = top + 1 - (raise_arm and 2)
        ay1 = top + 8 + sw[s] - (raise_arm * 3)
        c.r(ax, ay0, ax + 1, ay1, SHADOW)
        c.r(ax + 1, ay0, ax + 1, ay1, SLATE)
        c.r(ax, ay1 + 1, ax + 1, ay1 + 1, BONE)
        if guard and s == -1:
            c.r(ax, top + 4, ax + 1, top + 4, RED)
    for y in range(top, hem + 1):
        t = (y - top) / max(1, hem - top)
        h = int(round(half + t * (1.6 + flare)))
        c.r(cx - h, y, cx + h - 1, y, SHADOW)
        c.p(cx + h - 1, y, SLATE)
    c.r(cx - half - 1, top, cx + half, top, SLATE)
    c.r(cx - half + 1, top + 1, cx + half - 2, top + 1, SLATE)   # collar
    c.r(cx, top + 2, cx, hem, INK)                       # back seam
    c.r(cx - half, top + 7, cx + half - 1, top + 7, INK)
    c.r(cx - 1, top + 7, cx + 1, top + 7, SLATE)         # belt strap
    hy = 9 + dy + cr
    c.r(cx - 3, hy, cx + 2, hy + 4, INK)                 # back of head: hair
    c.r(cx - 2, hy + 3, cx + 1, hy + 4, BONE)            # neck
    c.p(cx - 4, hy + 2, BONE); c.p(cx + 3, hy + 2, BONE) # ears
    _hat(c, "back", cx, hy, guard)
    if guard:
        c.r(cx - 3, hy + 1, cx + 2, hy + 1, SHADOW)
    if P.get("bang"):
        _bang(c, cx + 8, hy - 6)


def draw_side(c, P, guard=False):
    """Faces RIGHT."""
    lean = P.get("lean", 0)
    cx = 16
    dy, cr = P.get("dy", 0), P.get("crouch", 0)
    tail = P.get("tail", 1)
    top = 13 + dy + cr
    hem = 24 + cr
    # back leg (dark) then back arm
    sB, lB = P.get("legB", 0), P.get("liftB", 0)
    sF, lF = P.get("legF", 0), P.get("liftF", 0)
    c.r(cx - 2 + sB, 23 + cr, cx + sB, 30 - lB, INK)
    c.r(cx - 2 + sB, 30 - lB, cx + 1 + sB, 30 - lB, SHADOW)
    # back arm
    bax, bay = P.get("armB", (-1, 8))
    c.line(cx + lean - 1, top + 2, cx + lean + bax, top + bay, SHADOW, 2)
    c.r(cx + lean + bax, top + bay + 1, cx + lean + bax + 1, top + bay + 2, BONE)
    # coat tail (behind) + body
    for y in range(top + 3, hem + 1):
        t = (y - top - 3) / max(1, hem - top - 3)
        back = 4 + int(round(t * (1 + tail)))
        c.r(cx - back + lean * (1 - t), y, cx + 3 + lean * (1 - t), y, SHADOW)
    c.r(cx - 4 + lean, top, cx + 3 + lean, top + 3, SHADOW)
    c.r(cx - 4 + lean, top, cx + 3 + lean, top, SLATE)              # shoulder
    c.r(cx - 4 + lean, top + 1, cx - 4 + lean, hem - 2, SLATE)      # rim light, back
    c.r(cx - 5 + lean, top + 7, cx + 3 + lean, top + 7, INK)        # belt
    c.p(cx + 3 + lean, top + 7, SODIUM if not guard else FOG)
    if not guard:
        c.r(cx + 2 + lean, top, cx + 3 + lean, top + 2, BONE)       # shirt/lapel edge
        c.r(cx + 3 + lean, top + 1, cx + 3 + lean, top + 3, SODIUM) # tie
    else:
        c.r(cx + 2 + lean, top, cx + 3 + lean, top + 2, BONE)
        c.p(cx - 3 + lean, top + 9, INK); c.p(cx - 3 + lean, top + 10, INK)  # baton
    # front leg
    c.r(cx - 1 + sF, 23 + cr, cx + 1 + sF, 30 - lF, SHADOW)
    c.r(cx - 1 + sF, 30 - lF, cx + 2 + sF, 30 - lF, INK)            # shoe + toe
    c.r(cx + sF, 23 + cr, cx + sF, 28 - lF, SLATE)
    # front arm
    ax, ay = P.get("armF", (1, 8))
    sx, sy = cx + lean, top + 2
    c.line(sx, sy, sx + ax, top + ay, SHADOW, 2)
    c.line(sx, sy, sx + ax, top + ay, SLATE, 1)
    if guard:
        mx, my = (sx + sx + ax) // 2, (sy + top + ay) // 2
        c.r(mx, my, mx + 1, my, RED)                                # armband
    c.r(sx + ax, top + ay + 1, sx + ax + 1, top + ay + 2, BONE)     # hand
    if P.get("torch"):
        c.r(sx + ax + 1, top + ay + 1, sx + ax + 3, top + ay + 2, FOG)
        c.p(sx + ax + 4, top + ay + 1, BONE)
        c.p(sx + ax + 4, top + ay + 2, SODIUM)
    # head
    hl = P.get("headlean", lean)
    hy = 9 + dy + cr
    c.r(cx - 2 + hl, hy, cx + 3 + hl, hy + 4, BONE)
    c.r(cx - 2 + hl, hy, cx + 3 + hl, hy, FOG)
    c.r(cx - 3 + hl, hy, cx - 2 + hl, hy + 2, INK)                  # hair at back
    c.p(cx + 4 + hl, hy + 2, BONE)                                  # nose
    eyes = P.get("eyes", "open")
    if eyes == "open":
        c.p(cx + 2 + hl, hy + 2, INK)
    elif eyes == "shut":
        c.r(cx + 1 + hl, hy + 2, cx + 2 + hl, hy + 2, INK)
    c.r(cx + 1 + hl, hy + 4, cx + 3 + hl, hy + 4, FOG)
    if P.get("hurt"):
        c.p(cx + 3 + hl, hy + 4, RED)
    if P.get("cig"):
        c.r(cx + 4 + hl, hy + 3, cx + 5 + hl, hy + 3, BONE)
        c.p(cx + 6 + hl, hy + 3, SODIUM)
        sm = P.get("smoke", 0)
        if sm:
            c.p(cx + 6 + hl + (sm % 2), hy + 3 - sm, FOG)
            if sm > 2:
                c.p(cx + 7 + hl - (sm % 2), hy + 3 - sm - 1, FOG)
    _hat(c, "side", cx, hy, guard, hl)
    if P.get("bang"):
        _bang(c, cx + 8, hy - 6)


def _bang(c, x, y):
    c.r(x, y, x, y + 3, RED)
    c.p(x, y + 5, RED)


def new_char(view, P, guard=False):
    c = Cv()
    {"down": draw_front, "up": draw_back, "side": draw_side}[view](c, P, guard)
    c.outline()
    return c.im


# ----------------------------------------------------------------------------
# Pose generators
# ----------------------------------------------------------------------------

def walk_pose(view, k, n, guard=False, crouch=0, amp=1.0, speed_lean=0):
    ph = 2 * math.pi * k / n
    s, co = math.sin(ph), math.cos(ph)
    bob = -1 if abs(co) > 0.7 else 0
    if crouch:
        bob = -1 if abs(co) > 0.85 else 0
    if view == "side":
        a = 5 * amp
        sF = round(a * s)
        P = dict(dy=bob, crouch=crouch, legF=sF, legB=-sF, tail=1 + (1 if abs(s) > 0.6 else 0),
                 liftF=round(2 * max(0, co) * amp), liftB=round(2 * max(0, -co) * amp), lean=speed_lean,
                 armF=(round(-3 * s * amp) + 1, 8 - (1 if crouch else 0)),
                 armB=(round(3 * s * amp) - 1, 8 - (1 if crouch else 0)))
        if guard:
            P["armF"] = (4, 5)                  # flashlight held out front
            P["torch"] = True
            P["armB"] = (round(3 * s * amp) - 1, 8)
        else:
            P["cig"] = True
    else:
        P = dict(dy=bob, crouch=crouch, legL=round(2 * max(0, s) * amp), legR=round(2 * max(0, -s) * amp),
                 armL=round(2 * s * amp), armR=round(-2 * s * amp), sway=round(0.7 * s * amp))
        if view == "down":
            if guard:
                P["torch"] = True
                P["armR"] = 1
            else:
                P["cig"] = True
    return P


def idle_pose(view, k, n, guard=False):
    dy = (0, 0, 1, 1)[k % 4] if n == 4 else 0
    sm = k + 1
    if view == "side":
        P = dict(dy=dy, headlean=0, armF=(1, 8 + dy), armB=(-1, 8 + dy), tail=1)
        if guard:
            P.update(armF=(4, 5), torch=True)
        else:
            P.update(cig=True, smoke=sm)
    else:
        P = dict(dy=dy, armL=dy, armR=dy)
        if view == "down":
            if guard:
                P["torch"] = True
            else:
                P.update(cig=True, smoke=sm)
    return P


def dash_pose(view, k):
    # 0 launch crouch, 1-2 stretched, 3 recover
    if view == "side":
        table = [
            dict(lean=1, crouch=2, legF=3, legB=-3, liftB=1, armF=(-3, 6), armB=(-4, 5), tail=2),
            dict(lean=4, crouch=1, legF=5, legB=-5, liftB=2, liftF=1, armF=(-5, 4), armB=(-6, 5), tail=4, headlean=4),
            dict(lean=4, crouch=1, legF=-1, legB=-6, liftB=3, liftF=2, armF=(-6, 4), armB=(-5, 3), tail=4, headlean=4),
            dict(lean=2, crouch=0, legF=2, legB=-2, armF=(-2, 7), armB=(-3, 6), tail=2),
        ]
        P = dict(table[k])
        P["cig"] = True
        return P
    table = [
        dict(crouch=3, spread=1, armL=-1, armR=-1),
        dict(crouch=1, spread=3, flare=2, arms_out=1, legL=1, legR=0),
        dict(crouch=1, spread=3, flare=2, arms_out=1, legL=0, legR=1),
        dict(crouch=0, spread=1, armL=0, armR=0),
    ]
    P = dict(table[k])
    if view == "down":
        P["cig"] = True
    return P


def takedown_pose(view, k, guard=False):
    # 0 reach, 1 grab + lunge, 2 hold (strike), 3 release
    if view == "side":
        table = [
            dict(lean=1, armF=(5, 3), armB=(3, 4), legF=2, legB=-2),
            dict(lean=3, crouch=1, armF=(7, 3), armB=(6, 4), legF=4, legB=-4, liftB=1, tail=3),
            dict(lean=3, crouch=1, armF=(8, 2), armB=(7, 3), legF=4, legB=-3, tail=3),
            dict(lean=1, armF=(3, 6), armB=(1, 6), legF=2, legB=-1),
        ]
        return dict(table[k], cig=True)
    out = [1, 2, 2, 1][k]
    P = dict(arms_out=out, crouch=[0, 1, 1, 0][k], armL=-1, armR=-1, spread=[0, 1, 1, 0][k])
    if view == "down":
        P["cig"] = True
    return P


def hurt_pose(view, k):
    if view == "side":
        t = [dict(lean=-2, headlean=-3, crouch=0, armF=(-3, 3), armB=(-4, 2), legF=-1, legB=1, eyes="shut", hurt=True, tail=3),
             dict(lean=-1, headlean=-2, crouch=1, armF=(-2, 5), armB=(-3, 4), legF=0, legB=0, eyes="shut", hurt=True, tail=2)]
        return t[k]
    return [dict(dy=1, crouch=0, arms_out=1, eyes="shut", hurt=True, sway=-1, spread=1),
            dict(dy=1, crouch=1, arms_out=0, eyes="shut", hurt=True, spread=1)][k]


def sneak_pose(view, k, n=6):
    return walk_pose(view, k, n, crouch=4, amp=0.6, speed_lean=1)


# ----------------------------------------------------------------------------
# Falling / lying
# ----------------------------------------------------------------------------

def lying(guard=False, blood=0, hat_off=True, shift=0, variant=0):
    c = Cv()
    # shadowed pose, head to the RIGHT, ground line y=30
    # shoes + legs
    c.r(4, 26, 12, 29, INK)
    c.r(3, 26, 4, 29, SHADOW)
    c.r(11, 25, 12, 29, SHADOW)
    # coat body
    c.r(11, 22, 23, 29, SHADOW)
    c.r(11, 22, 23, 22, SLATE)
    c.r(11, 27, 23, 27, INK)                    # belt line (vertical in the real world)
    c.r(13, 23, 14, 24, SLATE)
    # arm
    c.r(15, 25, 22, 26, SHADOW)
    c.r(23, 25, 24, 26, BONE)
    # head
    c.r(24, 22, 28, 28, BONE)
    c.r(24, 22, 28, 22, FOG)
    c.p(27, 24, INK)
    c.r(27, 27, 28, 27, FOG)
    c.r(23, 22, 24, 24, INK)                    # hair
    if not guard:
        c.p(29, 25, BONE)
    if hat_off:
        # hat rolled next to the head
        band = RED if guard else SLATE
        c.r(26, 29, 31, 29, INK)
        c.r(27 if not guard else 26, 28, 30, 28, INK)
        c.r(27, 28, 29, 28, band)
    if blood:
        c.r(20 - blood, 29, 23 + blood, 30, RED)
        c.r(23, 28 - (blood > 1), 24, 29, RED) if blood > 0 else None
    img = c
    img.outline()
    return img.im


def fall_frame(base_im, angle, dx, dy_, pivot=(16, 30)):
    big = Image.new("RGBA", (64, 64), T)
    big.paste(base_im, (16 + dx, 16 + dy_))
    rot = big.rotate(-angle, resample=Image.NEAREST, center=(pivot[0] + 16 + dx, pivot[1] + 16 + dy_))
    return rot.crop((16, 16, 48, 48))


# ----------------------------------------------------------------------------
# Sheet builders
# ----------------------------------------------------------------------------
COLS = 8
VIEWS = ["down", "up", "side"]


def put(sheet, im, col, row):
    sheet.alpha_composite(im, (col * 32, row * 32))


def build_player():
    rows = 20
    sheet = Image.new("RGBA", (COLS * 32, rows * 32), T)
    anims = [("idle", 4), ("walk", 8), ("sneak", 6), ("dash", 4), ("takedown", 4), ("hurt", 2)]
    for ai, (name, n) in enumerate(anims):
        for vi, view in enumerate(VIEWS):
            for k in range(n):
                if name == "idle":
                    P = idle_pose(view, k, n)
                elif name == "walk":
                    P = walk_pose(view, k, n)
                elif name == "sneak":
                    P = sneak_pose(view, k, n)
                elif name == "dash":
                    P = dash_pose(view, k)
                elif name == "takedown":
                    P = takedown_pose(view, k)
                else:
                    P = hurt_pose(view, k)
                put(sheet, new_char(view, P), k, ai * 3 + vi)
    # dead: stagger, buckle, fall, fall, lie, lie+pool
    base = new_char("side", dict(lean=-2, headlean=-3, eyes="shut", hurt=True, armF=(-3, 3), armB=(-4, 2), tail=3))
    buck = new_char("side", dict(lean=-1, headlean=-2, crouch=5, eyes="shut", hurt=True, armF=(-2, 4), armB=(-3, 3), liftF=1, tail=2))
    frames = [
        base,
        buck,
        fall_frame(buck, 40, -4, 0),
        fall_frame(buck, 75, -8, 0),
        lying(False, blood=1),
        lying(False, blood=3),
    ]
    for k, f in enumerate(frames):
        put(sheet, f, k, 18)
    for k in range(6):                                  # row 19: squeeze (tight spots)
        put(sheet, crawl_frame(k), k, 19)
    return sheet


def build_guard():
    rows = 15
    sheet = Image.new("RGBA", (COLS * 32, rows * 32), T)
    for vi, view in enumerate(VIEWS):
        for k in range(8):                                   # patrol walk
            put(sheet, new_char(view, walk_pose(view, k, 8, guard=True, amp=0.85), True), k, 0 * 3 + vi)
        for k in range(8):                                   # chase run
            P = walk_pose(view, k, 8, guard=True, amp=1.5)
            if view == "side":
                P["lean"] = 2
                P["armF"] = (3, 5)
                P["tail"] = 3
            put(sheet, new_char(view, P, True), k, 1 * 3 + vi)
        for k in range(4):                                   # idle / waiting
            put(sheet, new_char(view, idle_pose(view, k, 4, guard=True), True), k, 2 * 3 + vi)
        for k in range(4):                                   # alert startle
            if view == "side":
                P = [dict(armF=(4, 5), torch=True, lean=0, tail=1),
                     dict(armF=(5, 0), torch=True, lean=-1, dy=-1, tail=2, bang=True),
                     dict(armF=(6, -1), torch=True, lean=-1, dy=-1, tail=2, bang=True),
                     dict(armF=(6, 0), torch=True, lean=0, tail=1, bang=True)][k]
            else:
                P = [dict(torch=view == "down"),
                     dict(dy=-1, arms_out=1, bang=True, torch=view == "down"),
                     dict(dy=-1, arms_out=1, bang=True, torch=view == "down"),
                     dict(arms_out=0, bang=True, torch=view == "down")][k]
            put(sheet, new_char(view, P, True), k, 3 * 3 + vi)
    # search: head sweeps left/right while torch moves (side row, front row)
    for k in range(6):
        s = math.sin(2 * math.pi * k / 6)
        put(sheet, new_char("side", dict(headlean=round(1.5 * s), lean=0, armF=(4, 5 - round(s)), torch=True,
                                          dy=1 if k % 3 == 1 else 0, tail=1), True), k, 12)
        put(sheet, new_char("down", dict(sway=round(s), dy=1 if k % 3 == 1 else 0, torch=True, armR=round(-s)), True), k, 14)
    # KO: startled -> stagger -> fall -> lying (no blood)
    stag = new_char("side", dict(lean=-2, headlean=-3, eyes="shut", armF=(-3, 3), armB=(-4, 2), tail=3), True)
    buck = new_char("side", dict(lean=-1, headlean=-2, crouch=5, eyes="shut", armF=(-2, 4), armB=(-3, 3), tail=2), True)
    ko = [stag, buck, fall_frame(buck, 40, -4, 0), fall_frame(buck, 75, -8, 0),
          lying(True, blood=0), lying(True, blood=0)]
    for k, f in enumerate(ko):
        put(sheet, f, k, 13)
    return sheet


# --- portrait: derive blink + smoke drift from the hand-drawn mugshots --------
def build_portrait():
    src = Image.open(os.path.join(OUT, "portrait_sheet.png")).convert("RGBA")
    if src.width > 192:                       # already regenerated: use the first row
        src = src.crop((0, 0, 192, 32))
    sheet = Image.new("RGBA", (192, 32 * 4), T)
    smoke = [(24, 10), (25, 13), (24, 16)]
    for st in range(6):
        base = src.crop((st * 32, 0, st * 32 + 32, 32))
        clean = base.copy()
        cp = clean.load()
        for (x, y) in smoke:
            cp[x, y] = T
        def with_smoke(dyy, dxx):
            im = clean.copy()
            ip = im.load()
            for (x, y) in smoke:
                nx, ny = x + dxx, y + dyy
                if 0 <= ny < 32 and 0 <= nx < 32:
                    ip[nx, ny] = BONE
            return im
        f0 = with_smoke(0, 0)
        f1 = with_smoke(-1, 0)
        f3 = with_smoke(-2, 1)
        f2 = with_smoke(0, 0)
        if st <= 3:                           # blink: close the two eye boxes
            bp = f2.load()
            for y in (10, 11, 12):
                for x in (12, 13, 17, 18):
                    if bp[x, y][:3] == INK[:3]:
                        bp[x, y] = BONE if y != 11 else INK
        for k, f in enumerate((f0, f1, f2, f3)):
            sheet.alpha_composite(f, (st * 32, k * 32))
    return sheet


# --- exit door (32x32): 6-frame hum with a scanline + lamp flicker ----------
def build_exit():
    sheet = Image.new("RGBA", (6 * 32, 32), T)
    for k in range(6):
        c = Cv()
        lamp = [SODIUM, SODIUM, BONE, SODIUM, FOG, SODIUM][k]
        c.r(13, 1, 18, 1, INK)
        c.r(14, 0, 17, 0, lamp)
        c.r(5, 3, 26, 30, INK)                          # frame
        c.r(7, 5, 24, 28, SODIUM)                       # door
        c.r(7, 5, 24, 6, (236, 184, 112, 255) if k in (2,) else SODIUM)
        c.r(7, 27, 24, 28, (176, 120, 60, 255) if False else SODIUM)
        # sweeping scanline (bone) + soft trail
        y = 6 + (k * 4) % 20
        c.r(7, y, 24, y, BONE)
        c.r(7, y + 1, 24, y + 1, (240, 200, 140, 255))
        # door handle + hinge pixels
        c.r(21, 17, 22, 18, INK)
        c.p(9, 8, INK); c.p(9, 24, INK)
        c.r(8, 29, 23, 29, BONE if k % 2 == 0 else FOG)  # threshold light
        # light spill on the floor
        for i in range(0, 4):
            c.r(6 - i, 31, 25 + i, 31, FOG if k % 3 else SLATE) if False else None
        sheet.alpha_composite(c.im, (k * 32, 0))
    return sheet


# --- intel folder (16x16): bob + glint + paper flutter ---------------------
def build_intel():
    sheet = Image.new("RGBA", (6 * 16, 16), T)
    bob = [0, 0, -1, -1, 0, 0]
    paper = [0, 1, 2, 3, 2, 1]
    glint = [None, (4, 8), (3, 7), None, (12, 9), (13, 10)]
    for k in range(6):
        c = Cv(16, 16)
        b = bob[k]
        c.r(2, 7 + b, 12, 13 + b, SODIUM)               # folder body
        c.r(2, 6 + b, 8, 7 + b, SODIUM)                 # tab
        c.r(3, 9 + b, 4, 9 + b, BONE)                   # label dash
        c.r(11, 7 + b, 12, 8 + b, BONE)                 # paper edge
        if paper[k]:
            c.r(11, 5 + b - paper[k] // 2, 11, 7 + b, BONE)
        c.r(2, 13 + b, 12, 13 + b, (176, 120, 60, 255))
        if glint[k]:
            gx, gy = glint[k]
            c.p(gx, gy + b, BONE)
            c.p(gx - 1, gy + b, BONE); c.p(gx + 1, gy + b, BONE)
            c.p(gx, gy + b - 1, BONE); c.p(gx, gy + b + 1, BONE)
        c.outline()
        sheet.alpha_composite(c.im, (k * 16, 0))
    return sheet


def tile_crawl():
    """Crawlspace floor: a tight spot only the PI can squeeze through."""
    c = Cv(16, 16)
    c.r(0, 0, 15, 15, INK)
    c.r(0, 3, 15, 3, SLATE)               # low lintel above and below the slot
    c.r(0, 12, 15, 12, SLATE)
    c.r(0, 4, 15, 4, SHADOW)
    c.r(0, 11, 15, 11, SHADOW)
    for x in (2, 8):                      # chevrons pointing along the slot
        c.line(x, 6, x + 2, 8, FOG)
        c.line(x + 2, 8, x, 10, FOG)
    return c.im


def crawl_frame(k):
    """The PI squeezing through a 1-tile slot: belly-down side-view crawl,
    facing RIGHT, 12 px tall so it fits the 16 px slot. 6 frames."""
    c = Cv()
    ph = 2 * math.pi * k / 6
    s, co = math.sin(ph), math.cos(ph)
    ground = 21
    undulate = 1 if s > 0.3 else 0
    reach = round(2 * s)                  # front arm pulls forward, back arm trails
    kick = 1 if co > 0.3 else 0
    # trailing legs (alternate kicks)
    c.r(4, ground - 2 - kick, 11, ground - kick, INK)
    c.r(5, ground - 4 + kick, 10, ground - 3 + kick, SHADOW)
    c.r(3, ground - 1 - kick, 5, ground - kick, INK)
    # coat body, flat along the floor
    c.r(10, ground - 6 - undulate, 22, ground - 1, SHADOW)
    c.r(10, ground - 6 - undulate, 22, ground - 6 - undulate, SLATE)
    c.r(10, ground - 4, 22, ground - 4, INK)                # belt
    c.p(16, ground - 4, SODIUM)
    # back arm along the body, front arm reaching ahead
    c.r(14, ground - 1, 19 + max(-reach, 0), ground, SHADOW)
    c.r(21, ground - 3, 26 + reach, ground - 2, SHADOW)
    c.r(27 + reach, ground - 3, 28 + reach, ground - 2, BONE)
    # head, chin down, hat tipped over the eyes
    c.r(22, ground - 11 - undulate, 27, ground - 5 - undulate, BONE)
    c.r(22, ground - 11 - undulate, 27, ground - 11 - undulate, FOG)
    c.p(26, ground - 8 - undulate, INK)
    c.r(24, ground - 6 - undulate, 26, ground - 6 - undulate, FOG)
    c.p(28, ground - 7 - undulate, BONE)                    # cigarette
    c.p(29, ground - 7 - undulate, SODIUM)
    c.r(21, ground - 14 - undulate, 27, ground - 12 - undulate, INK)    # hat crown
    c.r(20, ground - 12 - undulate, 29, ground - 12 - undulate, INK)    # brim
    c.r(21, ground - 12 - undulate, 27, ground - 12 - undulate, SLATE)  # band
    c.outline()
    return c.im


# --- building tiles: 4 furniture/floor tiles appended to harbor_tiles.png -----
# atlas columns 0..5 are the P3 street set (hand-made, kept as is);
# 6 DESK, 7 CABINET, 8 RUG (walkable), 9 CRATE, 10 CRAWL (walkable, squeeze only).
# The street builder only reads 0..5.
def tile_desk():
    c = Cv(16, 16)
    c.r(0, 0, 15, 15, INK)
    c.r(1, 1, 14, 13, SHADOW)
    c.r(1, 1, 14, 1, SLATE)
    c.r(3, 4, 8, 8, BONE)                       # papers
    c.r(4, 5, 7, 5, FOG); c.r(4, 7, 7, 7, FOG)
    c.r(11, 3, 12, 4, SODIUM)                   # desk lamp
    c.p(11, 5, INK)
    c.r(3, 10, 9, 11, SLATE)                    # keyboard
    for x in (4, 6, 8):
        c.p(x, 10, FOG)
    c.r(11, 9, 12, 10, FOG)                     # mug
    return c.im


def tile_cabinet():
    c = Cv(16, 16)
    c.r(0, 0, 15, 15, INK)
    c.r(1, 1, 14, 14, SLATE)
    c.r(1, 1, 14, 1, FOG)
    for y in (5, 9, 13):
        c.r(1, y, 14, y, INK)
    for y in (3, 7, 11):
        c.r(6, y, 9, y, FOG)                    # drawer handles
        c.p(3, y, SHADOW); c.p(12, y, SHADOW)
    return c.im


def tile_rug():
    c = Cv(16, 16)
    c.r(0, 0, 15, 15, INK)
    c.r(1, 1, 14, 14, SHADOW)
    c.r(2, 2, 13, 13, INK)
    c.r(3, 3, 12, 12, SHADOW)
    for i in range(4):                          # woven diamond
        c.p(7 - i, 4 + i, SLATE); c.p(8 + i, 4 + i, SLATE)
        c.p(7 - i, 11 - i, SLATE); c.p(8 + i, 11 - i, SLATE)
    c.p(7, 7, FOG); c.p(8, 8, FOG)
    return c.im


def tile_crate():
    c = Cv(16, 16)
    c.r(0, 0, 15, 15, INK)
    c.r(1, 1, 14, 14, SLATE)
    c.r(1, 1, 14, 2, FOG)
    c.line(2, 3, 13, 13, INK)
    c.line(13, 3, 2, 13, INK)
    c.r(1, 7, 14, 8, SHADOW)
    c.p(2, 2, BONE); c.p(13, 2, BONE)           # stencilled corners
    return c.im


def build_tiles():
    path = os.path.join(ROOT, "assets", "tiles", "harbor_tiles.png")
    base = Image.open(path).convert("RGBA").crop((0, 0, 96, 16))   # keep the 6 hand-made tiles
    sheet = Image.new("RGBA", (176, 16), T)
    sheet.alpha_composite(base, (0, 0))
    for i, im in enumerate((tile_desk(), tile_cabinet(), tile_rug(), tile_crate(), tile_crawl())):
        sheet.alpha_composite(im, (96 + i * 16, 0))
    return sheet


# --- task props (16x16, 6 frames/row): rows = bug phone, ledger, evidence case ----
# "documents" reuse the sodium folder in intel_sheet.png.
def _task_frame(kind, k):
    bob = [0, 0, -1, -1, 0, 0][k]
    c = Cv(16, 16)
    if kind == "bug":
        ring = k in (2, 3, 4)
        h = -1 if ring else 0
        c.r(3, 9 + bob, 12, 13 + bob, SLATE)            # desk-phone body
        c.r(3, 13 + bob, 12, 13 + bob, SHADOW)
        c.r(6, 10 + bob, 9, 12 + bob, BONE)             # rotary dial
        c.r(7, 11 + bob, 8, 11 + bob, INK)
        c.p(4, 10 + bob, FOG); c.p(11, 10 + bob, FOG)   # hook buttons
        c.r(2, 5 + bob + h, 13, 6 + bob + h, FOG)       # handset resting above the cradle
        c.r(2, 7 + bob + h, 3, 7 + bob + h, INK); c.r(12, 7 + bob + h, 13, 7 + bob + h, INK)
        if ring:
            c.p(1, 3 + bob, BONE); c.p(14, 3 + bob, BONE)
            c.p(0, 5 + bob, BONE); c.p(15, 5 + bob, BONE)
    elif kind == "ledger":
        c.r(1, 6 + bob, 14, 13 + bob, SHADOW)           # cover
        c.r(2, 6 + bob, 7, 12 + bob, BONE)
        c.r(8, 6 + bob, 13, 12 + bob, BONE)
        c.r(7, 6 + bob, 8, 12 + bob, INK)               # spine
        for y in (8, 10):
            c.r(3, y + bob, 6, y + bob, FOG); c.r(9, y + bob, 12, y + bob, FOG)
        if k in (1, 2, 3, 4):                           # camera glint sweeping the page
            gx = 3 + (k - 1) * 3
            c.p(gx, 7 + bob, SODIUM); c.p(gx + 1, 7 + bob, SODIUM)
    else:
        c.r(2, 7 + bob, 13, 13 + bob, SLATE)            # attache case
        c.r(2, 7 + bob, 13, 7 + bob, FOG)
        c.r(6, 5 + bob, 9, 6 + bob, INK)                # handle
        c.r(7, 9 + bob, 8, 10 + bob, RED)               # the State's wax seal
        c.p(3, 12 + bob, SHADOW); c.p(12, 12 + bob, SHADOW)
        if k in (2, 3):
            c.p(7, 9 + bob, BONE)
    c.outline()
    return c.im


def build_tasks():
    sheet = Image.new("RGBA", (6 * 16, 3 * 16), T)
    for r, kind in enumerate(("bug", "ledger", "evidence")):
        for k in range(6):
            sheet.alpha_composite(_task_frame(kind, k), (k * 16, r * 16))
    return sheet


# --- previews ---------------------------------------------------------------
def preview(sheet, path, scale=3, cell=32, bg=(46, 44, 60, 255)):
    bgim = Image.new("RGBA", sheet.size, bg)
    bgim.alpha_composite(sheet)
    bgim = bgim.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    bgim.save(path)


def main():
    os.makedirs(PREVIEW, exist_ok=True)
    player = build_player()
    guard = build_guard()
    portrait = build_portrait()
    ex = build_exit()
    intel = build_intel()
    tiles = build_tiles()
    tasks = build_tasks()
    tiles.save(os.path.join(ROOT, "assets", "tiles", "harbor_tiles.png"))
    preview(tiles, os.path.join(PREVIEW, "preview_harbor_tiles.png"), 4)
    for name, im in (("player", player), ("guard", guard), ("portrait", portrait), ("exit", ex), ("intel", intel)):
        im.save(os.path.join(OUT, f"{name}_sheet.png"))
        preview(im, os.path.join(PREVIEW, f"preview_{name}_sheet.png"), 3 if name in ("player", "guard") else 4)
    tasks.save(os.path.join(OUT, "task_sheet.png"))
    preview(tasks, os.path.join(PREVIEW, "preview_task_sheet.png"), 4)
    print("sheets written:", {k: v.size for k, v in dict(player=player, guard=guard, portrait=portrait, exit=ex, intel=intel).items()})


if __name__ == "__main__":
    main()
