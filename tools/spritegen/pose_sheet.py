#!/usr/bin/env python3
"""MEWD — POSE TEMPLATES FOR AN IMAGE MODEL (at the user's request: "a
generic and adaptable sprite sheet with all conceivable contingencies ...
that, when paired with base character images ... and fed to an image
model with an extremely explicit prompt, results in consistent Doom
style character sheets").

    python3 tools/spritegen/pose_sheet.py                 # everything, into tools/spritegen/out/doom
    python3 tools/spritegen/pose_sheet.py --profile mewd  # the game's own four troop sheets, into out/mewd
    python3 tools/spritegen/pose_sheet.py --views 5       # Doom's economy: 5 views, mirror the rest
    python3 tools/spritegen/pose_sheet.py --list          # what the sheets hold

WHAT IT MAKES. A set of PNG sheets, each a grid of cells on a flat
magenta ground. In every cell stands a grey mannequin — a stick figure
with a round head, a dark face patch, its RIGHT arm and leg tinted red
and its LEFT tinted blue, a dark bar for the gun — in one pose, seen from
one angle, with the frame and the angle written in a band above it. The
mannequin is METADATA: it is what the image model is told to replace
with the user's character, cell for cell, pose for pose, angle for
angle. Beside every sheet goes a JSON manifest (which cell is which
frame of which animation at which angle, in fractions of the picture, so
it still applies to whatever size the model returns) and a prompt file
(the master prompt in PROMPT.md with that sheet's own cell-by-cell
contract appended). cut_sheet.py reads the manifest back off the model's
output and makes the game's strip.

HOW THE MANNEQUIN IS DRAWN. A rig of fifteen joints in metres, posed by
angles — lean, twist, each shoulder's pitch and spread, each elbow's
bend, each hip's pitch and spread, each knee's bend — with a root
transform for the whole body (its height off the ground, and its pitch
and roll for lying down). Every cycle (walk, run, crawl) is the same
pose function at four phases. The posed joints are turned about the
vertical by the view's angle, projected orthographically from a camera
ten degrees above level, depth-sorted (the far limbs first, a little
darker) and drawn as capsules. So all eight angles of every pose come
off one definition, and the mirrored pairs really are mirrors.

THE VIEWS, as Doom numbers them and as the game's troop strips lay them
out (render/standees.gd ROTATIONS, tools/prep-troops.mjs): 1 head on,
facing the camera; 2 turned 45 degrees toward the viewer's left; 3 side
on, facing the viewer's left; 4 three quarters from behind, facing away
and to the viewer's left; 5 from behind; 6, 7 and 8 the mirrors of 4, 3
and 2. The game draws five and mirrors three; `--views 8` draws all
eight for a character whose two sides differ.

Needs Pillow and numpy."""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = "/usr/share/fonts/truetype/dejavu"

# ---------------------------------------------------------------------------
# The rig, in metres. A 1.80 m figure.
# ---------------------------------------------------------------------------
L = dict(pelvis=0.98, spine=0.30, neck=0.17, head=0.13, head_r=0.115,
         shoulder=0.20, uarm=0.29, farm=0.27, hip=0.10, thigh=0.44,
         shin=0.43, foot=0.23, heel=0.06)
HEIGHT = 1.80

# body-local axes: +x the figure's LEFT, +y up, +z forward (toward the
# camera in view 1). A figure facing you has its right hand on your left.
DEFAULT = dict(
    root_x=0.0, root_y=L["pelvis"], root_z=0.0,
    root_pitch=0.0, root_roll=0.0, root_yaw=0.0,
    lean=0.0, twist=0.0, roll=0.0, head_pitch=0.0, head_yaw=0.0,
    ra_pitch=0.0, ra_abd=6.0, ra_yaw=0.0, ra_flex=0.0,   # yaw: a forward arm swung inward
    la_pitch=0.0, la_abd=6.0, la_yaw=0.0, la_flex=0.0,
    rl_pitch=0.0, rl_abd=3.0, rl_knee=0.0, rl_ankle=0.0,
    ll_pitch=0.0, ll_abd=3.0, ll_knee=0.0, ll_ankle=0.0,
    weapon="two",      # "two" both hands, "right"/"left" hanging from that hand, "aim" (see aim_axis), None
    aim_axis="forward",  # for weapon "aim": the gun along the body's forward, or "up" (a prone body's length)
    flash=False,       # a muzzle flash on the gun
    blood=0.0,         # 0..1, how much blood to spatter about
    gib=None,          # (seed, t) : the body in pieces, t seconds into it
)


def rx(a):
    c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ry(a):
    c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rz(a):
    c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def V(x, y, z):
    return np.array([x, y, z], dtype=float)


def pose(**kw):
    p = dict(DEFAULT)
    for k in kw:
        if k not in DEFAULT:
            raise KeyError(k)
    p.update(kw)
    return p


def skeleton(p):
    """The posed rig: a dict of joint positions in world metres (before
    the view's turn), plus the list of parts to draw."""
    R_root = ry(p["root_yaw"]) @ rz(p["root_roll"]) @ rx(p["root_pitch"])
    pelvis = V(p["root_x"], p["root_y"], p["root_z"])

    def W(v):
        return pelvis + R_root @ v

    J = {"pelvis": W(V(0, 0, 0))}
    # legs
    for side, sgn in (("r", -1), ("l", 1)):
        hip = V(sgn * L["hip"], -0.06, 0)
        Rl = rz(sgn * p[side + "l_abd"]) @ rx(-p[side + "l_pitch"])
        knee = hip + Rl @ V(0, -L["thigh"], 0)
        Rs = Rl @ rx(p[side + "l_knee"])
        ankle = knee + Rs @ V(0, -L["shin"], 0)
        Rf = Rs @ rx(p[side + "l_ankle"])
        toe = ankle + Rf @ V(0, 0, L["foot"])
        heel = ankle + Rf @ V(0, 0, -L["heel"])
        for n, v in (("hip", hip), ("knee", knee), ("ankle", ankle), ("toe", toe), ("heel", heel)):
            J[side + "_" + n] = W(v)
    # torso and head
    Rt = ry(p["twist"]) @ rz(p["roll"]) @ rx(-p["lean"])
    chest = Rt @ V(0, L["spine"], 0)
    neck = chest + Rt @ V(0, L["neck"], 0)
    Rh = Rt @ ry(p["head_yaw"]) @ rx(-p["head_pitch"])
    head = neck + Rh @ V(0, L["head"], 0)
    face = head + Rh @ V(0, 0, L["head_r"])
    top = head + Rh @ V(0, L["head_r"], 0)
    J.update(chest=W(chest), neck=W(neck), head=W(head), face=W(face), head_top=W(top))
    J["head_up"] = R_root @ Rh @ V(0, 1, 0)
    J["face_dir"] = R_root @ Rh @ V(0, 0, 1)
    # arms
    for side, sgn in (("r", -1), ("l", 1)):
        sh = neck + Rt @ V(sgn * L["shoulder"], -0.03, 0)
        Ra = Rt @ ry(-sgn * p[side + "a_yaw"]) @ rz(sgn * p[side + "a_abd"]) @ rx(-p[side + "a_pitch"])
        elbow = sh + Ra @ V(0, -L["uarm"], 0)
        Rf = Ra @ rx(-p[side + "a_flex"])
        hand = elbow + Rf @ V(0, -L["farm"], 0)
        J[side + "_shoulder"], J[side + "_elbow"], J[side + "_hand"] = W(sh), W(elbow), W(hand)
        J[side + "_farm_dir"] = R_root @ Rf @ V(0, -1, 0)
    # the gun, from the hands
    w = p["weapon"]
    if w == "two":
        grip, fore = J["r_hand"], J["l_hand"]
        axis = fore - grip
        if np.linalg.norm(axis) < 0.12:
            axis = J["r_farm_dir"]
        axis = axis / np.linalg.norm(axis)
        J["stock"] = grip - axis * 0.24
        J["muzzle"] = fore + axis * 0.32
    elif w == "aim":
        axis = R_root @ (V(0, 1, 0) if p["aim_axis"] == "up" else V(0, 0, 1))
        J["stock"] = J["r_hand"] - axis * 0.22
        J["muzzle"] = J["r_hand"] + axis * 0.78
    elif w == "right":
        axis = J["r_farm_dir"]
        J["stock"] = J["r_hand"] - axis * 0.30
        J["muzzle"] = J["r_hand"] + axis * 0.45
    elif w == "left":
        axis = J["l_farm_dir"]
        J["stock"] = J["l_hand"] - axis * 0.30
        J["muzzle"] = J["l_hand"] + axis * 0.45
    # the ground is solid: nothing goes below it (a lying pose's bent
    # knee would otherwise drive the shin into the floor)
    for k, v in J.items():
        if isinstance(v, np.ndarray) and not k.endswith("_dir") and k != "head_up":
            floor = 0.0 if k.endswith(("_toe", "_heel")) else 0.045
            if k == "head":
                floor = L["head_r"]
            if v[1] < floor:
                v[1] = floor
    return J


# colours: the mannequin's right side warm, its left cool, so the image
# model can never mistake which side it is looking at
COL = dict(torso=(150, 150, 150), head=(172, 172, 172), face=(48, 48, 48),
           right=(214, 112, 96), left=(98, 140, 220), gun=(34, 34, 34),
           flash=(255, 228, 64), blood=(170, 18, 18), outline=(20, 20, 20),
           ground=(60, 0, 60), arrow=(255, 255, 255))

# (joint a, joint b, thickness in metres, colour key)
PARTS = [
    ("pelvis", "chest", 0.20, "torso"), ("chest", "neck", 0.17, "torso"),
    ("r_shoulder", "l_shoulder", 0.11, "torso"), ("r_hip", "l_hip", 0.13, "torso"),
    ("r_shoulder", "r_elbow", 0.09, "right"), ("r_elbow", "r_hand", 0.08, "right"),
    ("l_shoulder", "l_elbow", 0.09, "left"), ("l_elbow", "l_hand", 0.08, "left"),
    ("r_hip", "r_knee", 0.12, "right"), ("r_knee", "r_ankle", 0.10, "right"), ("r_heel", "r_toe", 0.08, "right"),
    ("l_hip", "l_knee", 0.12, "left"), ("l_knee", "l_ankle", 0.10, "left"), ("l_heel", "l_toe", 0.08, "left"),
]

CAM_PITCH = 10.0  # degrees above level, looking down


def project(v, yaw, scale, origin):
    """World metres -> picture pixels, after the view's turn. Returns
    (x, y, depth); depth grows toward the camera."""
    w = ry(yaw) @ v
    cp, sp = math.cos(math.radians(CAM_PITCH)), math.sin(math.radians(CAM_PITCH))
    sx = origin[0] + w[0] * scale
    sy = origin[1] - (w[1] * cp - w[2] * sp) * scale
    depth = w[2] * cp + w[1] * sp
    return sx, sy, depth


def gib_parts(p, J):
    """The body in pieces: every part thrown by its own seeded velocity
    and fallen under gravity for t seconds, no lower than the ground."""
    seed, t = p["gib"]
    rng = np.random.RandomState(seed)
    out = []
    ease = (1 - math.exp(-2.5 * t)) / 2.5  # the sideways throw, dying away
    for a, b, th, col in PARTS:
        v = rng.uniform(-1, 1, 3) * V(1.7, 0, 1.2) + V(0, rng.uniform(1.5, 4.0), 0)
        spin = rng.uniform(-240, 240)
        pa, pb = J[a], J[b]
        mid = (pa + pb) / 2
        d = mid + V(v[0] * ease, v[1] * t - 4.9 * t * t, v[2] * ease)
        d[0] = max(-0.85, min(0.85, d[0]))
        d[1] = max(0.08, min(1.75, d[1]))
        R = ry(spin * t) @ rz(spin * 0.7 * t)
        out.append((d + R @ (pa - mid), d + R @ (pb - mid), th, col))
    hv = rng.uniform(-1, 1, 3) * V(1.4, 0, 0.8) + V(0, 4.5, 0)
    h = J["head"] + V(hv[0] * ease, hv[1] * t - 4.9 * t * t, hv[2] * ease)
    h[0] = max(-0.85, min(0.85, h[0]))
    h[1] = max(L["head_r"], min(1.75, h[1]))
    return out, h


def draw_mannequin(draw, p, yaw, scale, origin, ss):
    """One figure into `draw`, in pixels already multiplied by ss."""
    J = skeleton(p)
    gib = p["gib"] is not None
    segs = []
    if gib:
        parts, head_pos = gib_parts(p, J)
        for a, b, th, col in parts:
            segs.append((a, b, th, COL[col]))
    else:
        head_pos = J["head"]
        for a, b, th, col in PARTS:
            segs.append((J[a], J[b], th, COL[col]))
        if p["weapon"]:
            segs.append((J["stock"], J["muzzle"], 0.055, COL["gun"]))

    # the ground mark: a flat ring and an arrow the way the body faces
    gx, gz = J["pelvis"][0], J["pelvis"][2]
    ring = [project(V(gx + 0.36 * math.cos(a), 0, gz + 0.36 * math.sin(a)), yaw, scale, origin)
            for a in np.linspace(0, 2 * math.pi, 40)]
    draw.polygon([(x, y) for x, y, _ in ring], outline=COL["ground"], width=max(1, int(2 * ss)))
    fwd = ry(p["root_yaw"]) @ V(0, 0, 1)
    tail = project(V(gx, 0.005, gz), yaw, scale, origin)
    tip = project(V(gx, 0.005, gz) + fwd * 0.55, yaw, scale, origin)
    draw.line([tail[:2], tip[:2]], fill=COL["arrow"], width=max(1, int(3 * ss)))
    for s in (-1, 1):
        side = project(V(gx, 0.005, gz) + fwd * 0.40 + (ry(90) @ fwd) * (0.11 * s), yaw, scale, origin)
        draw.line([tip[:2], side[:2]], fill=COL["arrow"], width=max(1, int(3 * ss)))

    # the body, far parts first
    items = []
    for a, b, th, col in segs:
        pa, pb = project(a, yaw, scale, origin), project(b, yaw, scale, origin)
        items.append(((pa[2] + pb[2]) / 2, "seg", pa, pb, th, col))
    ph = project(head_pos, yaw, scale, origin)
    items.append((ph[2], "head", ph, None, L["head_r"], COL["head"]))
    if not gib and p["weapon"] and p["flash"]:
        pm = project(J["muzzle"], yaw, scale, origin)
        items.append((pm[2] + 0.5, "flash", pm, None, 0.14, COL["flash"]))
    items.sort(key=lambda it: it[0])
    depths = [it[0] for it in items]
    lo, hi = min(depths), max(depths)
    for depth, kind, pa, pb, th, col in items:
        k = 0.78 + 0.22 * ((depth - lo) / (hi - lo) if hi > lo else 1.0)
        c = tuple(int(min(255, v * k)) for v in col)
        w = max(2, int(th * scale))
        if kind == "seg":
            draw.line([pa[:2], pb[:2]], fill=COL["outline"], width=w + int(4 * ss))
            for q in (pa, pb):
                r = (w + int(4 * ss)) / 2
                draw.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=COL["outline"])
            draw.line([pa[:2], pb[:2]], fill=c, width=w)
            for q in (pa, pb):
                r = w / 2
                draw.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=c)
        elif kind == "head":
            r = th * scale
            draw.ellipse([pa[0] - r - 2 * ss, pa[1] - r - 2 * ss, pa[0] + r + 2 * ss, pa[1] + r + 2 * ss], fill=COL["outline"])
            draw.ellipse([pa[0] - r, pa[1] - r, pa[0] + r, pa[1] + r], fill=c)
            if not gib:
                # the face: a dark patch on the side of the head that faces
                # the camera, and nothing when it faces away
                fd = ry(yaw) @ J["face_dir"]
                cp, sp = math.cos(math.radians(CAM_PITCH)), math.sin(math.radians(CAM_PITCH))
                toward = fd[2] * cp + fd[1] * sp
                if toward > -0.05:
                    pf = project(J["face"], yaw, scale, origin)
                    fr = r * 0.62 * max(0.25, min(1.0, 0.35 + toward))
                    draw.ellipse([pf[0] - fr, pf[1] - fr * 0.55, pf[0] + fr, pf[1] + fr * 0.55], fill=COL["face"])
        elif kind == "flash":
            r = th * scale
            pts = []
            for i in range(16):
                rr = r if i % 2 == 0 else r * 0.42
                a = i * math.pi / 8
                pts.append((pa[0] + rr * math.cos(a), pa[1] + rr * math.sin(a)))
            draw.polygon(pts, fill=COL["flash"], outline=(255, 120, 0), width=max(1, int(2 * ss)))

    if p["blood"] > 0:
        rng = np.random.RandomState(int(p["blood"] * 1000) + 7)
        n = int(6 + 30 * p["blood"])
        cx, cz = J["pelvis"][0], J["pelvis"][2]
        for _ in range(n):
            a = rng.uniform(0, 2 * math.pi)
            d = rng.uniform(0.1, 0.5 + 0.8 * p["blood"])
            q = project(V(cx + d * math.cos(a), 0.004, cz + d * math.sin(a)), yaw, scale, origin)
            rr = rng.uniform(0.02, 0.07) * scale * (0.6 + p["blood"])
            draw.ellipse([q[0] - rr, q[1] - rr * 0.35, q[0] + rr, q[1] + rr * 0.35], fill=COL["blood"])
    return J


# ---------------------------------------------------------------------------
# The poses. Each animation: frames of (pose, words). A cycle is one
# function of phase.
# ---------------------------------------------------------------------------
def port_arms(**kw):
    """Standing, the rifle held across the chest, muzzle up and to the
    figure's left (the troops' walk)."""
    base = dict(ra_pitch=38, ra_abd=8, ra_flex=72, la_pitch=62, la_abd=-26, la_flex=58)
    base.update(kw)
    return pose(**base)


def aim_arms():
    """The rifle shouldered and pointed straight ahead: the right hand on
    the grip at the chest, the left arm out along the fore-end."""
    return dict(ra_pitch=28, ra_abd=4, ra_yaw=20, ra_flex=110, la_pitch=84, la_abd=0, la_yaw=24, la_flex=0,
                head_pitch=-4, head_yaw=-8, rl_pitch=-8, ll_pitch=14, rl_knee=6, ll_knee=10, lean=4,
                weapon="aim")


def legs_cycle(t, amp=26.0, lift=48.0):
    """Legs at phase t (0..1) of a stride: the left leg forward at t=.25."""
    ph = 2 * math.pi * t
    out = {}
    for side, off in (("l", 0.0), ("r", math.pi)):
        a = ph + off
        out[side + "l_pitch"] = amp * math.sin(a)
        # bent through the swing (the leg behind, coming forward), straight in the stance
        out[side + "l_knee"] = lift * max(0.0, -math.sin(a - math.pi / 4))
    out["root_y"] = L["pelvis"] - 0.025 * abs(math.cos(ph))
    return out


def walk(i):
    t = (i + 1) / 4
    k = legs_cycle(t, amp=30)
    k.update(lean=5, root_y=k["root_y"] - 0.01)
    return port_arms(**k)


def run(i):
    t = (i + 1) / 4
    k = legs_cycle(t, amp=44, lift=95)
    k.update(lean=18, root_y=k["root_y"] + 0.02, ra_pitch=30, ra_abd=10, ra_flex=80,
             la_pitch=40, la_abd=-20, la_flex=85, head_pitch=6)
    return pose(**k)


def crouch(**kw):
    base = dict(root_y=0.62, lean=22, head_pitch=-14, rl_pitch=78, ll_pitch=78, rl_knee=118, ll_knee=118,
                rl_abd=10, ll_abd=10, rl_ankle=-8, ll_ankle=-8,
                ra_pitch=48, ra_abd=10, ra_flex=70, la_pitch=70, la_abd=-24, la_flex=50)
    base.update(kw)
    return pose(**base)


def crouch_walk(i):
    t = i / 4
    ph = 2 * math.pi * t
    k = dict(ll_pitch=78 + 22 * math.sin(ph), rl_pitch=78 - 22 * math.sin(ph),
             ll_knee=118 - 18 * math.sin(ph), rl_knee=118 + 18 * math.sin(ph),
             root_y=0.60 - 0.02 * abs(math.cos(ph)))
    return crouch(**k)


def prone(**kw):
    """Flat on the belly, head toward the camera in view 1, chest and
    head raised on the elbows."""
    base = dict(root_y=0.16, root_pitch=90, lean=-24, head_pitch=-62,
                ra_pitch=128, ra_abd=28, ra_flex=96, la_pitch=128, la_abd=28, la_flex=96,
                rl_pitch=-4, ll_pitch=-4, rl_abd=8, ll_abd=8, rl_ankle=70, ll_ankle=70)
    base.update(kw)
    return pose(**base)


def prone_crawl(i):
    t = i / 4
    ph = 2 * math.pi * t
    s = math.sin(ph)
    return prone(ra_pitch=128 + 30 * s, la_pitch=128 - 30 * s, ra_abd=28 + 10 * s, la_abd=28 - 10 * s,
                 rl_abd=8 + 22 * max(0, -s), ll_abd=8 + 22 * max(0, s),
                 rl_knee=50 * max(0, -s), ll_knee=50 * max(0, s), lean=-20, head_pitch=-58)


def prone_aim(flash=False):
    return prone(ra_pitch=190, ra_abd=8, ra_yaw=-15, ra_flex=95, la_pitch=195, la_abd=4, la_yaw=-20, la_flex=25,
                 lean=-30, head_pitch=-66, weapon="aim", aim_axis="up", flash=flash)


def crawl_knocked(i):
    """Down but not out: dragging along on one elbow, the legs trailing."""
    t = i / 4
    ph = 2 * math.pi * t
    s = math.sin(ph)
    return pose(root_y=0.22, root_pitch=76, root_roll=14, lean=-10, head_pitch=-40, twist=10 * s,
                ra_pitch=132 + 36 * s, ra_abd=34, ra_flex=70, la_pitch=100 - 30 * s, la_abd=22, la_flex=110,
                rl_pitch=6, ll_pitch=-6, rl_abd=4, ll_abd=14, rl_knee=22 + 18 * max(0, s), ll_knee=12,
                rl_ankle=70, ll_ankle=70, weapon=None, blood=0.35)


def swim(i):
    t = i / 4
    ph = 2 * math.pi * t
    s = math.sin(ph)
    return pose(root_y=0.42, root_pitch=84, lean=-14, head_pitch=-50, head_yaw=30 * s,
                ra_pitch=100 + 70 * s, ra_abd=20, ra_flex=20 + 30 * max(0, s),
                la_pitch=100 - 70 * s, la_abd=20, la_flex=20 + 30 * max(0, -s),
                rl_pitch=-10 * s, ll_pitch=10 * s, rl_knee=14, ll_knee=14, rl_ankle=72, ll_ankle=72,
                weapon=None)


def fallen_pose():
    """Lying on the back across the picture, head to the viewer's left."""
    return dict(root_y=0.13, root_pitch=-90, root_yaw=90)


IDLE = [(port_arms(), "standing still, weight even on both feet, the gun held across the chest at port arms (right hand on the grip low by the right hip, left hand on the fore-end high by the left shoulder, the muzzle pointing up and to the figure's left), head level, looking straight ahead")]

WALK_WORDS = [
    "walk, frame 1 of 4: contact — the LEFT (blue) leg is forward with the heel down and the knee straight, the RIGHT (red) leg is behind on its toe; the gun stays across the chest at port arms",
    "walk, frame 2 of 4: passing — the RIGHT (red) leg swings forward under the body with the knee bent and the foot lifted, the LEFT (blue) leg straight under the hips; the body at its highest; gun across the chest",
    "walk, frame 3 of 4: contact — the RIGHT (red) leg is forward with the heel down and the knee straight, the LEFT (blue) leg is behind on its toe; the mirror of frame 1 in the legs only; gun across the chest",
    "walk, frame 4 of 4: passing — the LEFT (blue) leg swings forward under the body with the knee bent and the foot lifted, the RIGHT (red) leg straight under the hips; gun across the chest",
]
RUN_WORDS = [
    "run, frame 1 of 4: a long stride — the LEFT (blue) leg reaching far forward, the RIGHT (red) leg driving far back, the body leaning well forward, the gun carried low in both hands in front of the belly",
    "run, frame 2 of 4: the RIGHT (red) knee driven high and forward, the LEFT (blue) leg straight behind, the body at its highest, leaning forward, gun low in both hands",
    "run, frame 3 of 4: a long stride — the RIGHT (red) leg reaching far forward, the LEFT (blue) leg driving far back, leaning well forward, gun low in both hands",
    "run, frame 4 of 4: the LEFT (blue) knee driven high and forward, the RIGHT (red) leg straight behind, body at its highest, gun low in both hands",
]

ATTACK = [
    (pose(**aim_arms()), "aiming: the rifle shouldered and pointed STRAIGHT AHEAD along the direction the figure faces, the right hand on the grip at the chest, the left arm nearly straight out along the fore-end, the head tucked to the stock, the LEFT (blue) foot a half step forward"),
    (pose(**dict(aim_arms(), lean=1, ra_pitch=24, la_pitch=80, flash=True)), "FIRING: exactly the aiming pose, and a bright yellow-white MUZZLE FLASH at the end of the barrel; the body rocked back a hair by the recoil; this is the only frame with a flash"),
    (pose(lean=-16, head_pitch=22, ra_pitch=-20, ra_abd=52, ra_flex=30, la_pitch=-10, la_abd=60, la_flex=20,
          rl_pitch=10, rl_knee=22, ll_pitch=-6, ll_knee=8, weapon="right"),
     "PAIN: hit — the whole body flinches back from the waist, the head thrown back, both arms flung out and up, the gun still gripped loosely in the right hand pointing down, the knees giving a little"),
]

DEATH = [
    (pose(lean=-10, head_pitch=14, ra_pitch=-6, ra_abd=40, ra_flex=20, la_pitch=0, la_abd=46, la_flex=10,
          rl_pitch=6, rl_knee=14, ll_pitch=-4, ll_knee=6, weapon="right", blood=0.15),
     "death, frame 1 of 7: the killing hit — standing, rocked back, arms out, the gun slipping from the right hand, a first spatter of blood"),
    (pose(root_y=0.80, lean=-22, head_pitch=24, ra_pitch=-10, ra_abd=36, ra_flex=28, la_pitch=-4, la_abd=40, la_flex=20,
          rl_pitch=48, rl_knee=70, ll_pitch=40, ll_knee=64, weapon=None, blood=0.25),
     "death, frame 2 of 7: the knees buckle — sinking, the back arched, arms loose, the gun gone"),
    (pose(root_y=0.52, lean=-18, head_pitch=30, ra_pitch=-14, ra_abd=28, ra_flex=20, la_pitch=-8, la_abd=30, la_flex=16,
          rl_pitch=14, rl_knee=132, ll_pitch=14, ll_knee=132, rl_ankle=60, ll_ankle=60, weapon=None, blood=0.35),
     "death, frame 3 of 7: on the knees, the shins flat on the ground behind, the torso still upright but leaning back, the head lolling back, arms hanging"),
    (pose(root_y=0.40, root_pitch=-36, root_yaw=24, lean=-8, head_pitch=20, ra_pitch=-30, ra_abd=36, ra_flex=14, la_pitch=-26, la_abd=40, la_flex=10,
          rl_pitch=8, rl_knee=120, ll_pitch=20, ll_knee=100, rl_ankle=60, ll_ankle=60, weapon=None, blood=0.45),
     "death, frame 4 of 7: toppling over BACKWARD from the knees, the whole body tipping away, arms trailing"),
    (pose(root_y=0.22, root_pitch=-72, root_yaw=48, lean=0, head_pitch=10, ra_pitch=-40, ra_abd=50, ra_flex=10, la_pitch=-30, la_abd=44, la_flex=20,
          rl_pitch=10, rl_knee=70, ll_pitch=22, ll_knee=50, weapon=None, blood=0.6),
     "death, frame 5 of 7: nearly down — the body almost flat on its back, twisted a little across the picture, the legs still folded"),
    (pose(**fallen_pose(), lean=4, head_pitch=6, ra_pitch=-50, ra_abd=58, ra_flex=12, la_pitch=-20, la_abd=70, la_flex=24,
          rl_pitch=8, rl_knee=30, ll_pitch=16, ll_knee=12, rl_abd=10, ll_abd=14, weapon=None, blood=0.75),
     "death, frame 6 of 7: DOWN — lying flat on its back ACROSS the picture, the head to the viewer's LEFT and the feet to the viewer's RIGHT, face up, arms sprawled, one knee still a little bent, a pool of blood"),
    (pose(**fallen_pose(), lean=0, head_pitch=-4, head_yaw=30, ra_pitch=-60, ra_abd=66, ra_flex=6, la_pitch=-10, la_abd=78, la_flex=10,
          rl_pitch=4, rl_knee=6, ll_pitch=10, ll_knee=4, rl_abd=14, ll_abd=18, weapon=None, blood=0.85),
     "death, frame 7 of 7: THE CORPSE, the frame that stays — flat on its back across the picture, head to the viewer's LEFT, face turned up and a little toward the camera, legs straight, arms flung wide, the pool of blood spread; this must read as the same body as frame 6, settled"),
]

GIB_WORDS = [
    "violent death, frame 1 of 9: the body still whole but BURSTING — arms thrown up, the torso rocked back, blood erupting from the chest",
    "violent death, frame 2 of 9: the body COMING APART — head, arms, legs and torso separating, flung upward and outward, blood everywhere",
    "violent death, frame 3 of 9: the pieces flying apart at their widest and highest, trailing blood",
    "violent death, frame 4 of 9: the pieces beginning to fall",
    "violent death, frame 5 of 9: the pieces falling, the lower ones hitting the ground",
    "violent death, frame 6 of 9: most pieces on the ground, a few still dropping",
    "violent death, frame 7 of 9: everything landed, a wide spread of parts and blood",
    "violent death, frame 8 of 9: the parts settling, the blood pooling wider",
    "violent death, frame 9 of 9: THE REMAINS, the frame that stays — a low heap of parts in a wide pool of blood, nothing standing, nothing taller than a knee",
]


def gibs():
    out = []
    first = pose(lean=-26, head_pitch=30, ra_pitch=-40, ra_abd=70, ra_flex=40, la_pitch=-40, la_abd=70, la_flex=40,
                 rl_pitch=10, rl_knee=20, ll_pitch=-10, weapon=None, blood=0.6)
    out.append((first, GIB_WORDS[0]))
    for i in range(1, 9):
        t = [0, 0.14, 0.3, 0.46, 0.62, 0.8, 1.0, 1.25, 1.6][i]
        out.append((pose(weapon=None, gib=(11, t), blood=min(1.0, 0.5 + 0.08 * i)), GIB_WORDS[i]))
    return out


JUMP = [
    (port_arms(root_y=0.80, lean=16, head_pitch=-6, rl_pitch=48, ll_pitch=48, rl_knee=76, ll_knee=76, ra_pitch=20, la_pitch=50),
     "jump, frame 1 of 3: the crouch before the leap — knees bent deep, leaning forward, about to push off; gun across the chest"),
    (port_arms(root_y=1.42, lean=6, rl_pitch=56, ll_pitch=70, rl_knee=92, ll_knee=108, ra_pitch=48, la_pitch=70),
     "jump, frame 2 of 3: IN THE AIR at the top of the leap — the whole figure well off the ground, both knees tucked up, feet nowhere near the ground line; gun across the chest"),
    (port_arms(root_y=0.74, lean=22, head_pitch=-10, rl_pitch=52, ll_pitch=52, rl_knee=84, ll_knee=84, rl_abd=14, ll_abd=14, ra_pitch=24, la_pitch=52),
     "jump, frame 3 of 3: the landing — feet wide, knees bent deep to take the fall, leaning forward; gun across the chest"),
]
MELEE = [
    (port_arms(twist=-34, lean=6, ra_pitch=12, ra_abd=20, ra_flex=90, la_pitch=70, la_abd=-10, la_flex=70, rl_pitch=-10, ll_pitch=16),
     "melee, frame 1 of 3: the wind-up — the torso twisted to the figure's right, the rifle drawn back by the right hand, butt first"),
    (port_arms(twist=30, lean=14, ra_pitch=98, ra_abd=-6, ra_flex=20, la_pitch=80, la_abd=-4, la_flex=36, rl_pitch=-14, ll_pitch=24, ll_knee=14),
     "melee, frame 2 of 3: the STRIKE — the torso twisted hard to the figure's left, the rifle's BUTT driven straight forward at head height, both arms extended"),
    (port_arms(twist=6, lean=8, ra_pitch=54, ra_abd=6, ra_flex=66, la_pitch=70, la_abd=-20, la_flex=52, rl_pitch=-6, ll_pitch=12),
     "melee, frame 3 of 3: the recovery — pulling the rifle back to the chest, the twist unwinding"),
]
RELOAD = [
    (port_arms(lean=10, head_pitch=-26, ra_pitch=40, ra_abd=8, ra_flex=80, la_pitch=36, la_abd=-10, la_flex=108),
     "reload, frame 1 of 3: the rifle lowered to the belly, the head bent to look down at it, the left hand pulling the magazine out of the bottom"),
    (port_arms(lean=10, head_pitch=-28, ra_pitch=40, ra_abd=8, ra_flex=80, la_pitch=10, la_abd=-20, la_flex=60),
     "reload, frame 2 of 3: the left hand down and away from the rifle holding the FRESH MAGAZINE, the rifle held by the right hand only, still looking down"),
    (port_arms(lean=8, head_pitch=-20, ra_pitch=40, ra_abd=8, ra_flex=80, la_pitch=50, la_abd=-14, la_flex=100),
     "reload, frame 3 of 3: the left hand slapping the magazine home under the rifle, the head starting to come back up"),
]
THROW = [
    (port_arms(twist=-30, lean=-6, ra_pitch=-50, ra_abd=36, ra_flex=70, la_pitch=50, la_abd=-20, la_flex=70, rl_pitch=-8, ll_pitch=10, weapon="left"),
     "throw, frame 1 of 3: the wind-up — the rifle held in the LEFT hand only, the right arm drawn far back and up behind the head holding the GRENADE, the torso twisted to the right"),
    (port_arms(twist=26, lean=18, ra_pitch=126, ra_abd=10, ra_flex=10, la_pitch=30, la_abd=-10, la_flex=70, rl_pitch=-16, ll_pitch=26, ll_knee=12, weapon="left"),
     "throw, frame 2 of 3: the RELEASE — the right arm snapped straight forward and up at full stretch, the torso twisted to the left and leaning in, the rifle in the left hand"),
    (port_arms(twist=12, lean=20, ra_pitch=70, ra_abd=-6, ra_flex=30, la_pitch=30, la_abd=-10, la_flex=70, rl_pitch=-12, ll_pitch=24, ll_knee=16, weapon="left"),
     "throw, frame 3 of 3: the follow-through — the right arm swinging down across the body, the weight on the front foot, the rifle in the left hand"),
]
USE = [(port_arms(ra_pitch=86, ra_abd=-4, ra_flex=4, la_pitch=10, la_abd=8, la_flex=30, weapon="left", lean=6),
        "use / interact: the RIGHT arm reaching straight out ahead at chest height, the hand open, as if pressing a switch or taking something; the rifle hanging in the LEFT hand pointing down")]
FALL = [(pose(root_y=1.10, root_pitch=82, lean=-18, head_pitch=-50, ra_pitch=100, ra_abd=78, ra_flex=20, la_pitch=100, la_abd=78, la_flex=20,
              rl_abd=26, ll_abd=26, rl_knee=36, ll_knee=36, rl_ankle=60, ll_ankle=60, weapon=None),
         "free fall / skydive: belly down IN THE AIR, well above the ground line, arms and legs spread wide like a star, head up looking forward; no gun in hand")]
VICTORY = [
    (pose(ra_pitch=170, ra_abd=24, ra_flex=10, la_pitch=170, la_abd=24, la_flex=10, weapon="right", lean=-6, head_pitch=14),
     "victory, frame 1 of 2: both arms thrust straight up over the head, the rifle held high in the right hand, chest out, head back"),
    (pose(ra_pitch=150, ra_abd=60, ra_flex=20, la_pitch=150, la_abd=60, la_flex=20, weapon="right", lean=-4, head_pitch=10, root_y=1.06, rl_knee=24, ll_knee=24, rl_pitch=16, ll_pitch=16),
     "victory, frame 2 of 2: a little hop off the ground, arms wide and high, the rifle in the right hand"),
]

VIEW_NAMES = {
    1: ("FRONT", "head on: the figure faces the camera straight on; the face is fully visible; its RIGHT (red) side is on the viewer's LEFT and its LEFT (blue) side on the viewer's RIGHT"),
    2: ("FRONT-LEFT 3/4", "turned 45 degrees toward the viewer's LEFT: the figure faces the camera's left; the face is seen three-quarter; its LEFT (blue) shoulder is nearer the camera, its RIGHT (red) side further away"),
    3: ("LEFT PROFILE", "side on, facing the viewer's LEFT: a pure profile; the figure's LEFT (blue) side is toward the camera and its RIGHT (red) limbs are mostly hidden behind; the nose points left"),
    4: ("BACK-LEFT 3/4", "three-quarters from behind, facing AWAY and to the viewer's LEFT: mostly the BACK is seen, with the LEFT (blue) side of the face just visible; no eyes"),
    5: ("BACK", "from directly behind: the figure faces AWAY from the camera; the back of the head and the back are seen; NO FACE AT ALL; its RIGHT (red) side is on the viewer's RIGHT and its LEFT (blue) side on the viewer's LEFT"),
    6: ("BACK-RIGHT 3/4", "three-quarters from behind, facing AWAY and to the viewer's RIGHT: the exact mirror image of view 4; mostly the back, the RIGHT (red) side of the face just visible"),
    7: ("RIGHT PROFILE", "side on, facing the viewer's RIGHT: the exact mirror image of view 3; the figure's RIGHT (red) side is toward the camera; the nose points right"),
    8: ("FRONT-RIGHT 3/4", "turned 45 degrees toward the viewer's RIGHT: the exact mirror image of view 2; the RIGHT (red) shoulder is nearer the camera"),
}
VIEW_YAW = {k: -45.0 * (k - 1) for k in range(1, 9)}
VIEW_SHORT = {1: "FRONT", 2: "F-LEFT 3/4", 3: "LEFT", 4: "B-LEFT 3/4", 5: "BACK", 6: "B-RIGHT 3/4", 7: "RIGHT", 8: "F-RIGHT 3/4"}
VIEW_FACING = {1: "faces the camera", 2: "faces front-left", 3: "faces left", 4: "faces back-left",
               5: "faces away", 6: "faces back-right", 7: "faces right", 8: "faces front-right"}


def anim(key, name, frames, views, cell="tall", air=None, letters=None, words=None):
    out = []
    for i, f in enumerate(frames):
        if isinstance(f, tuple):
            p, w = f
        else:
            p, w = f, words[i]
        out.append({"pose": p, "words": w, "air": bool(air and i in air)})
    return dict(key=key, name=name, frames=out, views=views, cell=cell, letters=letters)


# the animations, each with the Doom frame letters it takes where it has
# them (the troops' table: states.gd _troop)
ANIMS = {
    "IDLE": anim("IDLE", "IDLE (stand)", IDLE, 8),
    "WALK": anim("WALK", "WALK", [walk(i) for i in range(4)], 8, words=WALK_WORDS, letters="ABCD"),
    "ATTACK": anim("ATTACK", "AIM, FIRE, PAIN", ATTACK, 8, letters="EFG"),
    "DEATH": anim("DEATH", "DEATH", DEATH, 1, cell="square", letters="HIJKLMN"),
    "XDEATH": anim("XDEATH", "VIOLENT DEATH (gibs)", gibs(), 1, cell="square", letters="OPQRSTUVW"),
    "RUN": anim("RUN", "RUN", [run(i) for i in range(4)], 8, words=RUN_WORDS),
    "CROUCH": anim("CROUCH", "CROUCH (idle, aim, fire)", [
        (crouch(), "crouching still: squatting low on bent knees, thighs near level, the torso leaning forward, the gun across the chest"),
        (crouch(ra_pitch=24, ra_abd=4, ra_yaw=20, ra_flex=108, la_pitch=70, la_abd=0, la_yaw=24, la_flex=0, head_pitch=-20, head_yaw=-8, weapon="aim"),
         "crouching and AIMING: the rifle shouldered and pointed straight ahead from the squat, the head tucked to the stock"),
        (crouch(ra_pitch=20, ra_abd=4, ra_yaw=20, ra_flex=108, la_pitch=66, la_abd=0, la_yaw=24, la_flex=0, head_pitch=-20, head_yaw=-8, weapon="aim", flash=True),
         "crouching and FIRING: the crouched aim with a MUZZLE FLASH at the end of the barrel"),
    ], 8),
    "CROUCH_WALK": anim("CROUCH_WALK", "CROUCH WALK", [crouch_walk(i) for i in range(4)], 8, words=[
        "crouch walk, frame 1 of 4: creeping low with the LEFT (blue) leg forward, knees deeply bent, torso leaning forward, gun across the chest",
        "crouch walk, frame 2 of 4: the RIGHT (red) leg passing under the body, still low",
        "crouch walk, frame 3 of 4: the RIGHT (red) leg forward, still low",
        "crouch walk, frame 4 of 4: the LEFT (blue) leg passing under the body, still low",
    ]),
    "PRONE": anim("PRONE", "PRONE (lie, aim, fire)", [
        (prone(), "lying prone: FLAT ON THE BELLY on the ground, the chest and head raised on both elbows, the rifle on the ground in front held in both hands, legs straight out behind, toes down"),
        (prone_aim(), "prone and AIMING: flat on the belly, the rifle shouldered and pointed straight ahead along the ground, the head down to the stock"),
        (prone_aim(True), "prone and FIRING: the prone aim with a MUZZLE FLASH at the end of the barrel"),
    ], 8, cell="flat"),
    "PRONE_CRAWL": anim("PRONE_CRAWL", "PRONE CRAWL", [prone_crawl(i) for i in range(4)], 8, cell="flat", words=[
        "prone crawl, frame 1 of 4: flat on the belly, the RIGHT (red) arm reaching forward and the LEFT (blue) knee drawn up to the side; gun in the hands",
        "prone crawl, frame 2 of 4: both arms level, legs straight, pulling along",
        "prone crawl, frame 3 of 4: the LEFT (blue) arm reaching forward and the RIGHT (red) knee drawn up to the side",
        "prone crawl, frame 4 of 4: both arms level, legs straight",
    ]),
    "KNOCKED": anim("KNOCKED", "KNOCKED DOWN, CRAWLING (down but not out)", [crawl_knocked(i) for i in range(4)], 8, cell="flat", words=[
        "knocked down and crawling, frame 1 of 4: on the belly and one hip, wounded, no gun, dragging itself along on the RIGHT (red) forearm with the right arm reaching forward, legs trailing limp behind, blood on the ground",
        "knocked down and crawling, frame 2 of 4: pulling — the right arm drawing back under the chest, the left arm reaching",
        "knocked down and crawling, frame 3 of 4: the LEFT (blue) arm reaching forward, the right drawing back",
        "knocked down and crawling, frame 4 of 4: pulling with the left arm, the right coming forward again",
    ]),
    "JUMP": anim("JUMP", "JUMP", JUMP, 8, air=[1]),
    "MELEE": anim("MELEE", "MELEE (rifle butt)", MELEE, 8),
    "RELOAD": anim("RELOAD", "RELOAD", RELOAD, 8),
    "THROW": anim("THROW", "THROW (grenade)", THROW, 8),
    "USE": anim("USE", "USE / INTERACT", USE, 8),
    "SWIM": anim("SWIM", "SWIM", [swim(i) for i in range(4)], 8, cell="flat", words=[
        "swimming, frame 1 of 4: belly down at the surface, the RIGHT (red) arm stretched forward and the LEFT (blue) arm pulling back along the side, the head turned to breathe, no gun",
        "swimming, frame 2 of 4: both arms mid-stroke, head down",
        "swimming, frame 3 of 4: the LEFT (blue) arm stretched forward and the RIGHT (red) pulling back, head turned the other way",
        "swimming, frame 4 of 4: both arms mid-stroke, head down",
    ]),
    "FALL": anim("FALL", "FREE FALL / SKYDIVE", FALL, 8, cell="square", air=[0]),
    "VICTORY": anim("VICTORY", "VICTORY (emote)", VICTORY, 1, air=[1]),
}

# the sheets: which animations go together on one picture. The game's
# own profile is the troop strip exactly (states.gd TROOPS: ABCDEFG
# turned, five views; HIJKLMNOPQRSTUVW flat, one view). The doom profile
# is the same with all the extras after it.
PROFILES = {
    "mewd": [
        ("walk", ["WALK"]),
        ("attack", ["ATTACK"]),
        ("death", ["DEATH"]),
        ("gibs", ["XDEATH"]),
    ],
    "doom": [
        ("walk", ["WALK"]),
        ("attack", ["IDLE", "ATTACK"]),
        ("death", ["DEATH"]),
        ("gibs", ["XDEATH"]),
        ("run", ["RUN"]),
        ("crouch", ["CROUCH"]),
        ("crouch-walk", ["CROUCH_WALK"]),
        ("prone", ["PRONE"]),
        ("prone-crawl", ["PRONE_CRAWL"]),
        ("knocked", ["KNOCKED"]),
        ("jump", ["JUMP"]),
        ("melee", ["MELEE"]),
        ("reload", ["RELOAD"]),
        ("throw", ["THROW"]),
        ("use-fall", ["USE", "FALL"]),
        ("swim", ["SWIM"]),
        ("victory", ["VICTORY"]),
    ],
}

BG = (255, 0, 255)
FRAME = (28, 28, 28)
BAND = (52, 52, 52)
INK = (255, 255, 255)
GRID = (0, 0, 0)
RATIOS = {"1:1": 1.0, "4:3": 4 / 3, "3:4": 3 / 4, "3:2": 1.5, "2:3": 2 / 3, "16:9": 16 / 9, "9:16": 9 / 16,
          "4:5": 0.8, "5:4": 1.25, "21:9": 21 / 9}


def font(size, bold=False):
    name = "DejaVuSansMono-Bold.ttf" if bold else "DejaVuSansMono.ttf"
    try:
        return ImageFont.truetype(os.path.join(FONT_DIR, name), size)
    except OSError:
        return ImageFont.load_default()


def compass_icon(draw, cx, cy, r, yaw, ss):
    """A top-down compass: the camera as a dot at the bottom, an arrow
    the way the figure faces."""
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK, width=max(1, int(1.5 * ss)))
    cr = r * 0.22
    draw.ellipse([cx - cr, cy + r - cr, cx + cr, cy + r + cr], fill=INK)
    a = math.radians(yaw)
    dx, dy = -math.sin(a), math.cos(a)  # view 1 points at the camera, i.e. down the icon
    tip = (cx + dx * r * 0.85, cy + dy * r * 0.85)
    draw.line([(cx, cy), tip], fill=(255, 220, 80), width=max(1, int(2.5 * ss)))
    for s in (-1, 1):
        px, py = -dy * s, dx * s
        draw.line([tip, (cx + dx * r * 0.5 + px * r * 0.3, cy + dy * r * 0.5 + py * r * 0.3)], fill=(255, 220, 80), width=max(1, int(2.5 * ss)))


def wrap_text(d, text, xy, width, f, fill, y_max):
    """Text broken to a width; returns the y below it."""
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    if cur:
        lines.append(cur)
    x, y = xy
    lh = f.size * 1.25
    for ln in lines:
        if y + lh > y_max:
            break
        d.text((x, y), ln, font=f, fill=fill)
        y += lh
    return y


class Sheet:
    def __init__(self, name, anims, views, cell_px=512, ss=2):
        self.name = name
        self.anims = anims
        self.views = views
        self.ss = ss
        kinds = {a["cell"] for a in anims}
        if kinds == {"flat"}:
            self.cell_w, self.cell_h = cell_px, int(cell_px * 0.62)
        elif kinds == {"tall"}:
            self.cell_w, self.cell_h = cell_px // 2, cell_px
        else:
            self.cell_w, self.cell_h = cell_px, cell_px
        self.flat = kinds == {"flat"}
        self.nominal = cell_px
        self.band = int(cell_px * 0.11)
        self.head_h = int(cell_px * 0.13)
        self.colh_h = int(cell_px * 0.10)
        self.rowh_w = int(cell_px * 0.42)
        self.rows = []  # (anim, frame index)
        for a in anims:
            for i in range(len(a["frames"])):
                self.rows.append((a, i))
        self.rot_rows = [r for r in self.rows if r[0]["views"] > 1]
        self.flat_rows = [r for r in self.rows if r[0]["views"] == 1]
        if self.rot_rows and self.flat_rows:
            raise ValueError("one sheet holds turned frames or flat frames, not both")
        if self.rot_rows:
            self.cols = views
            self.layout = [[(a, i, v) for v in range(1, views + 1)] for a, i in self.rot_rows]
        else:
            self.cols = min(len(self.flat_rows), 4)
            self.layout = []
            for k in range(0, len(self.flat_rows), self.cols):
                self.layout.append([(a, i, 0) for a, i in self.flat_rows[k:k + self.cols]])
        self.nrows = len(self.layout)
        self.grid_w = self.cols * self.cell_w
        self.grid_h = self.nrows * self.cell_h
        nat_w = self.rowh_w + self.grid_w + 2 * 24
        nat_h = self.head_h + self.colh_h + self.grid_h + 2 * 24
        # pad out to the nearest aspect ratio an image model can return
        best = min(RATIOS.items(), key=lambda kv: abs(math.log(kv[1] / (nat_w / nat_h))))
        self.ratio = best[0]
        r = best[1]
        if nat_w / nat_h < r:
            self.W, self.H = int(round(nat_h * r)), nat_h
        else:
            self.W, self.H = nat_w, int(round(nat_w / r))
        self.ox = (self.W - (self.rowh_w + self.grid_w)) // 2 + self.rowh_w
        self.oy = (self.H - (self.head_h + self.colh_h + self.grid_h)) // 2 + self.head_h + self.colh_h

    def cell_box(self, r, c):
        x0 = self.ox + c * self.cell_w
        y0 = self.oy + r * self.cell_h
        return (x0, y0, x0 + self.cell_w, y0 + self.cell_h)

    def figure_box(self, r, c):
        x0, y0, x1, y1 = self.cell_box(r, c)
        return (x0, y0 + self.band, x1, y1)

    def render(self, title):
        ss = self.ss
        W, H = self.W * ss, self.H * ss
        im = Image.new("RGB", (W, H), FRAME)
        d = ImageDraw.Draw(im)
        f_title = font(int(self.head_h * 0.42 * ss), True)
        f_sub = font(int(self.head_h * 0.26 * ss))
        f_col = font(int(self.colh_h * 0.27 * ss), True)
        f_col2 = font(int(self.colh_h * 0.22 * ss))
        f_cell = font(int(self.band * 0.44 * ss), True)
        f_cell2 = font(int(self.band * 0.23 * ss))
        f_row = font(int(self.cell_h * 0.055 * ss), True)
        f_row2 = font(int(self.cell_h * 0.040 * ss))
        # the header
        hx, hy = (self.ox - self.rowh_w) * ss, (self.oy - self.head_h - self.colh_h) * ss
        d.text((hx + 12 * ss, hy + 8 * ss), title, font=f_title, fill=INK)
        d.text((hx + 12 * ss, hy + self.head_h * 0.56 * ss),
               "POSE TEMPLATE  ·  grey mannequin = POSE + ANGLE metadata, replace it with the character  ·  "
               "red limbs = its RIGHT side, blue limbs = its LEFT  ·  ground is flat #FF00FF  ·  %d columns x %d rows"
               % (self.cols, self.nrows), font=f_sub, fill=(200, 200, 200))
        # column headers
        for c in range(self.cols):
            x0, _, x1, _ = self.cell_box(0, c)
            y = (self.oy - self.colh_h) * ss
            d.rectangle([x0 * ss, y, x1 * ss, self.oy * ss], fill=BAND, outline=GRID, width=2 * ss)
            if self.rot_rows:
                v = c + 1
                d.text((x0 * ss + 10 * ss, y + 6 * ss), "VIEW %d %s" % (v, VIEW_SHORT[v]), font=f_col, fill=INK)
                d.text((x0 * ss + 10 * ss, y + self.colh_h * 0.5 * ss), VIEW_FACING[v], font=f_col2, fill=(220, 220, 220))
                compass_icon(d, x1 * ss - self.colh_h * 0.5 * ss, y + self.colh_h * 0.5 * ss, self.colh_h * 0.36 * ss, VIEW_YAW[v], ss)
            else:
                d.text((x0 * ss + 10 * ss, y + 6 * ss), "COLUMN %d" % (c + 1), font=f_col, fill=INK)
                d.text((x0 * ss + 10 * ss, y + self.colh_h * 0.5 * ss), "front view only (no turning)", font=f_col2, fill=(220, 220, 220))
        # cells
        cells = []
        for r, row in enumerate(self.layout):
            # the row header
            a, i = row[0][0], row[0][1]
            x0, y0, _, y1 = self.cell_box(r, 0)
            rx0 = (x0 - self.rowh_w) * ss
            d.rectangle([rx0, y0 * ss, x0 * ss, y1 * ss], fill=BAND, outline=GRID, width=2 * ss)
            letter = a["letters"][i] if a["letters"] else "-"
            d.text((rx0 + 10 * ss, y0 * ss + 10 * ss), "ROW %d" % (r + 1), font=f_row, fill=INK)
            d.text((rx0 + 10 * ss, y0 * ss + 10 * ss + self.cell_h * 0.07 * ss), a["name"], font=f_row2, fill=INK)
            d.text((rx0 + 10 * ss, y0 * ss + 10 * ss + self.cell_h * 0.125 * ss),
                   "frame %d/%d" % (i + 1, len(a["frames"])) + (" · %s" % letter if letter != "-" else ""), font=f_row2, fill=INK)
            wrap_text(d, a["frames"][i]["words"], (rx0 + 10 * ss, y0 * ss + 10 * ss + self.cell_h * 0.19 * ss),
                       (self.rowh_w - 20) * ss, font(int(self.cell_h * 0.030 * ss)), (205, 205, 205), (y1 - 8) * ss)
            for c, (a, i, v) in enumerate(row):
                box = self.cell_box(r, c)
                fbox = self.figure_box(r, c)
                X0, Y0, X1, Y1 = [q * ss for q in box]
                d.rectangle([X0, Y0, X1, Y1], fill=BG)
                # the label band
                d.rectangle([X0, Y0, X1, Y0 + self.band * ss], fill=BAND)
                letter = a["letters"][i] if a["letters"] else None
                tag = ("%s%d" % (letter, v) if letter else "%s-%d/%d" % (a["key"], i + 1, v)) if v else (letter or "%s-%d" % (a["key"], i + 1))
                d.text((X0 + 8 * ss, Y0 + 5 * ss), tag, font=f_cell, fill=INK)
                sub = "%s %d/%d" % (a["key"], i + 1, len(a["frames"]))
                if v:
                    sub += " · " + VIEW_SHORT[v]
                    compass_icon(d, X1 - self.band * 0.5 * ss, Y0 + self.band * 0.5 * ss, self.band * 0.36 * ss, VIEW_YAW[v], ss)
                d.text((X0 + 8 * ss, Y0 + self.band * 0.56 * ss), sub, font=f_cell2, fill=(220, 220, 220))
                # the figure: feet on a ground line 92% down the figure box
                fx0, fy0, fx1, fy1 = fbox
                scale = (self.nominal - self.band) * 0.86 / (HEIGHT + 0.14) * ss
                ground_y = fy0 + (fy1 - fy0) * (0.80 if self.flat else 0.92)
                origin = ((fx0 + fx1) / 2 * ss, ground_y * ss)
                yaw = VIEW_YAW[v] if v else 0.0
                draw_mannequin(d, a["frames"][i]["pose"], yaw, scale, origin, ss)
                cells.append(dict(
                    anim=a["key"], frame=i + 1, frames=len(a["frames"]), letter=letter, view=v,
                    row=r + 1, col=c + 1, tag=tag, air=a["frames"][i]["air"],
                    words=a["frames"][i]["words"], view_words=VIEW_NAMES[v][1] if v else "front view only",
                    cell=[q / self.W if k % 2 == 0 else q / self.H for k, q in enumerate(box)],
                    figure=[q / self.W if k % 2 == 0 else q / self.H for k, q in enumerate(fbox)],
                    ground=ground_y / self.H, px_per_m=scale / ss))
        # the grid lines over everything
        for r in range(self.nrows + 1):
            y = (self.oy + r * self.cell_h) * ss
            d.line([((self.ox - self.rowh_w) * ss, y), ((self.ox + self.grid_w) * ss, y)], fill=GRID, width=3 * ss)
        for c in range(self.cols + 1):
            x = (self.ox + c * self.cell_w) * ss
            d.line([(x, (self.oy - self.colh_h) * ss), (x, (self.oy + self.grid_h) * ss)], fill=GRID, width=3 * ss)
        im = im.resize((self.W, self.H), Image.LANCZOS)
        return im, cells



def save_png(im, path):
    """A palette PNG (a third the size of the RGB one; the flat colours
    survive it, the magenta stays exactly #FF00FF)."""
    q = im.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q.save(path, optimize=True)


def key_sheet(out_dir, ss=2):
    """KEY.png: what the mannequin's marks mean, and the eight views from
    above, to go in with every request."""
    W, H = 2048, 1152
    im = Image.new("RGB", (W * ss, H * ss), FRAME)
    d = ImageDraw.Draw(im)
    d.text((40 * ss, 28 * ss), "KEY TO THE POSE TEMPLATES", font=font(54 * ss, True), fill=INK)
    d.text((40 * ss, 100 * ss), "read this with every sheet: what the mannequin's marks mean, and where the camera is for each view",
           font=font(28 * ss), fill=(210, 210, 210))
    # the legend figure
    lx, ly = 40 * ss, 170 * ss
    d.rectangle([lx, ly, lx + 560 * ss, ly + 900 * ss], fill=BG)
    scale = 900 * 0.80 / (HEIGHT + 0.14) * ss
    draw_mannequin(d, pose(**dict(aim_arms(), flash=True)), -30.0, scale, (lx + 280 * ss, ly + 900 * 0.92 * ss), ss)
    f = font(25 * ss)
    notes = [
        "GREY MANNEQUIN = the pose, the camera angle, the scale and the placement of the figure in its cell. It is NOT the character.",
        "RED arm and leg = the character's RIGHT side.",
        "BLUE arm and leg = the character's LEFT side.",
        "DARK PATCH on the head = the FACE. No patch = the head is seen from behind.",
        "DARK BAR in the hands = the gun (the character's own weapon).",
        "YELLOW STAR = a muzzle flash, only in FIRE frames.",
        "RED SPOTS = blood, only in death and wounded frames.",
        "WHITE ARROW on the ground = the way the figure faces.",
        "PURPLE RING on the ground = where the feet stand; it marks the ground line. REMOVE the ring and the arrow in the output.",
        "COMPASS in the corner of a cell: the dot at the bottom is the camera; the yellow arrow is the way the figure faces.",
        "LABEL BAND above each figure: frame letter + view number. Leave it exactly as it is.",
    ]
    y = ly
    for n in notes:
        y = wrap_text(d, n, (lx + 600 * ss, y), 620 * ss, f, INK, H * ss) + 10 * ss
    # the eight views from above
    cx, cy, R = 1690 * ss, 600 * ss, 250 * ss
    d.text((cx - 300 * ss, cy - 400 * ss), "THE EIGHT VIEWS, SEEN FROM ABOVE", font=font(32 * ss, True), fill=INK)
    wrap_text(d, "the camera is at the bottom, looking up the page at the figure in the middle", (cx - 300 * ss, cy - 355 * ss), 600 * ss, font(22 * ss), (210, 210, 210), H * ss)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=INK, width=3 * ss)
    d.ellipse([cx - 22 * ss, cy - 22 * ss, cx + 22 * ss, cy + 22 * ss], fill=(170, 170, 170), outline=INK, width=2 * ss)
    d.polygon([(cx - 40 * ss, cy + R + 100 * ss), (cx + 40 * ss, cy + R + 100 * ss), (cx + 20 * ss, cy + R + 50 * ss), (cx - 20 * ss, cy + R + 50 * ss)], fill=INK)
    d.text((cx + 60 * ss, cy + R + 55 * ss), "CAMERA", font=font(26 * ss, True), fill=INK)
    fb = font(30 * ss, True)
    for v in range(1, 9):
        a = math.radians(VIEW_YAW[v])
        dx, dy = -math.sin(a), math.cos(a)
        tip = (cx + dx * R * 0.78, cy + dy * R * 0.78)
        d.line([(cx, cy), tip], fill=(255, 220, 80), width=5 * ss)
        for s in (-1, 1):
            d.line([tip, (cx + dx * R * 0.62 + (-dy * s) * R * 0.08, cy + dy * R * 0.62 + (dx * s) * R * 0.08)], fill=(255, 220, 80), width=5 * ss)
        tx, ty = cx + dx * R * 1.12, cy + dy * R * 1.12
        lab = "%d %s" % (v, VIEW_SHORT[v])
        tw = d.textlength(lab, font=fb)
        d.text((tx - tw / 2, ty - 18 * ss), lab, font=fb, fill=INK)
    wrap_text(d, "view 1 faces the camera. 2, 3, 4 turn toward the viewer's LEFT. 5 faces away. 6, 7, 8 are the mirror images of 4, 3, 2 (Doom draws five and flips three).",
              (cx - 300 * ss, cy + R + 130 * ss), 600 * ss, font(22 * ss), (210, 210, 210), H * ss)
    im = im.resize((W, H), Image.LANCZOS)
    save_png(im, os.path.join(out_dir, "KEY.png"))


def sheet_prompt(master, sheet, cells, title, fname):
    """The master prompt with this sheet's own contract appended."""
    lines = []
    lines.append("=" * 78)
    lines.append("THIS SHEET: %s  (file %s)" % (title, fname))
    lines.append("=" * 78)
    lines.append("")
    lines.append("THE GRID: %d columns across and %d rows down of equal cells, inside a dark frame, "
                 "with a label band above every figure, a header band above every column and a text "
                 "panel to the left of every row. The picture is %d x %d (aspect %s). Return an image "
                 "of the same size and the same aspect, with the same %d x %d grid in the same place."
                 % (sheet.cols, sheet.nrows, sheet.W, sheet.H, sheet.ratio, sheet.cols, sheet.nrows))
    lines.append("")
    if sheet.rot_rows:
        lines.append("THE COLUMNS ARE CAMERA ANGLES. Every cell in a column is seen from the same angle. "
                     "Every cell in a row is the same instant of the same pose, turned.")
        for c in range(sheet.cols):
            v = c + 1
            lines.append("  COLUMN %d = VIEW %d, %s: %s." % (v, v, VIEW_NAMES[v][0], VIEW_NAMES[v][1]))
        lines.append("")
        lines.append("Say it again so it cannot be missed: in column 1 the character looks at you; in column %d it "
                     "has its back to you; between them it turns toward the viewer's left, one eighth of a "
                     "turn per column. The same character, the same pose, the same instant — only the camera moves."
                     % (5 if sheet.cols >= 5 else sheet.cols))
    else:
        lines.append("THESE ARE FLAT FRAMES: one view only, from the front, in reading order (left to right, "
                     "then the next row). They are the frames of a death as it happens; the last one is the "
                     "frame that stays on the ground for ever.")
    lines.append("")
    lines.append("THE ROWS ARE FRAMES (the cells, one by one):")
    for cell in cells:
        if cell["view"] in (0, 1):
            lines.append("  ROW %d, %s%s — %s." % (
                cell["row"], cell["anim"], (" (letter %s)" % cell["letter"]) if cell["letter"] else "",
                cell["words"]))
    lines.append("")
    lines.append("THE LABELS. Each cell's band reads its tag, which is its frame letter and its view number "
                 "(like 'A1'), or the animation's name and frame. The tags on this sheet, in reading order, are:")
    lines.append("  " + ", ".join(c["tag"] for c in cells))
    lines.append("")
    air = [c["tag"] for c in cells if c["air"]]
    if air:
        lines.append("IN THE AIR: the mannequin in %s is off the ground on purpose (a jump, a fall). Draw the "
                     "character at the same height above the ground line, not standing on it." % ", ".join(air))
        lines.append("")
    if sheet.cell_w >= sheet.cell_h:
        lines.append("THE CELLS ARE WIDE on this sheet because the figure lies down or stretches out. "
                     "Keep the figure at the mannequin's size: a lying body is as long as the standing one is tall, "
                     "and it lies flat along the ground line, not floating.")
        lines.append("")
    lines.append("FINAL CHECK FOR THIS SHEET: %d cells, %d figures, every one the same character, every "
                 "label band untouched, flat #FF00FF behind every figure, no ring and no arrow left on the "
                 "ground, no figure crossing a line." % (len(cells), len(cells)))
    return master.replace("{{SHEET}}", "\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--profile", choices=sorted(PROFILES), default="doom",
                    help="mewd: the game's own troop sheets; doom: those and every extra (default)")
    ap.add_argument("--views", type=int, choices=(5, 8), default=None,
                    help="views per turned frame: 5 (mirror the rest, the mewd default) or 8 (the doom default)")
    ap.add_argument("--cell", type=int, default=512, help="cell height in pixels (default 512)")
    ap.add_argument("--out", help="output directory (default tools/spritegen/out/<profile>)")
    ap.add_argument("--only", help="only the sheets whose names contain this")
    ap.add_argument("--list", action="store_true", help="list the sheets and stop")
    args = ap.parse_args()
    views = args.views or (5 if args.profile == "mewd" else 8)
    args.out = args.out or os.path.join(HERE, "out", args.profile)
    os.makedirs(args.out, exist_ok=True)
    master_path = os.path.join(HERE, "PROMPT.md")
    master = open(master_path).read() if os.path.exists(master_path) else "{{SHEET}}"
    manifest = dict(profile=args.profile, views=views, background=list(BG), cell_px=args.cell,
                    camera_pitch_deg=CAM_PITCH, figure_height_m=HEIGHT, sheets=[])
    n = 0
    for k, (name, keys) in enumerate(PROFILES[args.profile]):
        if args.only and args.only not in name:
            continue
        anims = [ANIMS[q] for q in keys]
        sheet = Sheet(name, anims, views, args.cell)
        title = "SHEET %02d  %s  ·  %s" % (k + 1, name.upper(), " + ".join(a["name"] for a in anims))
        if args.list:
            print("%02d %-12s %dx%d cells %4dx%4d (%s)  %s" % (k + 1, name, sheet.cols, sheet.nrows, sheet.W, sheet.H, sheet.ratio,
                                                            ", ".join(a["key"] for a in anims)))
            continue
        fname = "sheet%02d-%s.png" % (k + 1, name)
        im, cells = sheet.render(title)
        save_png(im, os.path.join(args.out, fname))
        entry = dict(sheet=k + 1, name=name, file=fname, width=sheet.W, height=sheet.H, aspect=sheet.ratio,
                     cols=sheet.cols, rows=sheet.nrows, cell_w=sheet.cell_w, cell_h=sheet.cell_h,
                     band=sheet.band, anims=[a["key"] for a in anims], cells=cells)
        manifest["sheets"].append(entry)
        with open(os.path.join(args.out, fname[:-4] + ".json"), "w") as f:
            json.dump(dict(manifest, sheets=[entry]), f, indent=1)
        with open(os.path.join(args.out, fname[:-4] + ".prompt.txt"), "w") as f:
            f.write(sheet_prompt(master, sheet, cells, title, fname))
        n += len(cells)
        print("%-28s %2dx%d cells  %4dx%4d (%s)  %s" % (fname, sheet.cols, sheet.nrows, sheet.W, sheet.H, sheet.ratio,
                                                      ", ".join(a["key"] for a in anims)))
    if args.list:
        return
    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    key_sheet(args.out)
    print("%d cells on %d sheets, KEY.png and manifest.json in %s" % (n, len(manifest["sheets"]), args.out))


if __name__ == "__main__":
    main()
