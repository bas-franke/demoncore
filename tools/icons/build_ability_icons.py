"""Builds the ability icons: res://assets/icons/abilities/<id>.svg (art-style role).

    python tools/icons/build_ability_icons.py        (from the project root)

Reads data/abilities/abilities.json (+ evolutions.json) and writes one SVG per ability id: a dark
vignette disc (like the painted weapon / passive icons in assets/icons), a soft glow in the
ability's colour, and an emblem picked from the motif library below (by ability id, else by kind,
else by school), filled with a light-to-dark gradient of the ability colour and outlined in ink.
SVGs are plain text; Godot imports them as textures (run `godot --headless --path . --import`).
`Icons.for_ability(id)` loads them. Re-run after adding abilities; hand-edited SVGs are overwritten
only for ids listed in the JSON, so add an id to KEEP to protect a hand-made one.
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "icons", "abilities")
INK = "#140806"
KEEP = set()


# ---------------------------------------------------------------- colour helpers

def hx(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v * 255))) for v in rgb)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ---------------------------------------------------------------- shape helpers (64 x 64 space)

def poly(pts, close=True):
    d = "M%.2f %.2f " % pts[0] + " ".join("L%.2f %.2f" % p for p in pts[1:])
    return d + (" Z" if close else "")


def star(cx, cy, r1, r2, n, rot=-90.0):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180.0 / n)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return poly(pts)


def circle(cx, cy, r):
    return "M%.2f %.2f a%.2f %.2f 0 1 0 %.2f 0 a%.2f %.2f 0 1 0 %.2f 0 Z" % (cx - r, cy, r, r, 2 * r, r, r, -2 * r)


def ring(cx, cy, r, w):
    # Even-odd ring (outer circle + inner circle).
    return circle(cx, cy, r) + " " + circle(cx, cy, r - w)


def rot_pts(pts, cx, cy, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


FLAME = ("M32 6 C36 16 46 20 46 34 C46 45 40 54 32 54 C24 54 18 45 18 35 C18 27 23 24 25 17 "
         "C27 22 29 24 30 25 C30 18 31 12 32 6 Z")
FLAME_CORE = "M32 30 C35 35 39 38 39 44 C39 49 36 52 32 52 C28 52 25 49 25 45 C25 40 30 37 32 30 Z"
DROP = "M32 7 C38 19 47 28 47 39 C47 48 40 55 32 55 C24 55 17 48 17 39 C17 28 26 19 32 7 Z"
HEART = ("M32 52 C20 43 10 35 10 24 C10 16 16 11 22 11 C27 11 30 14 32 18 C34 14 37 11 42 11 "
         "C48 11 54 16 54 24 C54 35 44 43 32 52 Z")
SKULL = ("M32 8 C44 8 52 16 52 28 C52 35 48 39 45 41 L45 49 L39 49 L39 45 L35 45 L35 50 L29 50 "
         "L29 45 L25 45 L25 49 L19 49 L19 41 C16 39 12 35 12 28 C12 16 20 8 32 8 Z")
SKULL_EYES = circle(24.5, 28, 5) + " " + circle(39.5, 28, 5) + " " + poly([(32, 33), (29, 39), (35, 39)])
GHOST = ("M32 7 C43 7 50 15 50 27 L50 55 L45 50 L40 55 L35 50 L32 55 L29 50 L24 55 L19 50 L14 55 "
         "L14 27 C14 15 21 7 32 7 Z")
GHOST_EYES = ("M24 24 C27 24 28 27 27 31 C26 33 23 33 22 31 C21 27 22 24 24 24 Z "
              "M40 24 C42 24 43 27 42 31 C41 33 38 33 37 31 C36 27 37 24 40 24 Z")
CLOUD = ("M15 44 C9 44 7 36 13 33 C11 25 20 20 26 24 C28 16 40 14 43 22 C50 20 57 27 53 34 "
         "C59 37 56 45 49 44 Z")
EYE = "M6 32 C14 20 24 15 32 15 C40 15 50 20 58 32 C50 44 40 49 32 49 C24 49 14 44 6 32 Z"
EYE_PUPIL = "M32 22 C35 26 35 38 32 42 C29 38 29 26 32 22 Z"
CROWN = poly([(10, 48), (8, 20), (20, 32), (32, 12), (44, 32), (56, 20), (54, 48)])
CRESCENT = ("M40 8 C26 10 16 20 16 33 C16 46 27 56 40 56 C33 51 28 43 28 32 C28 21 33 13 40 8 Z")
LIGHTNING = poly([(36, 4), (16, 34), (29, 34), (24, 60), (48, 26), (35, 26), (42, 4)])
MAW = ("M8 22 C16 10 48 10 56 22 L50 30 L45 24 L40 31 L35 24 L32 31 L29 24 L24 31 L19 24 L14 30 Z "
       "M8 42 C16 54 48 54 56 42 L50 35 L45 41 L40 34 L35 41 L32 34 L29 41 L24 34 L19 41 L14 35 Z")
HAND = ("M24 56 L22 34 L16 26 C14 23 18 20 21 23 L25 28 L25 12 C25 9 30 9 30 12 L30 26 L31 9 "
        "C31 6 36 6 36 9 L36 26 L38 11 C38 8 43 8 43 11 L42 28 L44 17 C44 14 49 14 49 17 L46 38 "
        "C45 46 42 52 40 56 Z")
MASK = ("M12 14 C20 10 44 10 52 14 C54 30 48 48 32 56 C16 48 10 30 12 14 Z")
MASK_HOLES = ("M19 26 C22 22 27 23 28 27 C25 30 21 30 19 26 Z M45 26 C42 22 37 23 36 27 "
              "C39 30 43 30 45 26 Z M26 42 C30 45 34 45 38 42 C35 47 29 47 26 42 Z")
GEAR_TEETH = 10


def gear(cx, cy, r1, r2):
    pts = []
    for i in range(GEAR_TEETH * 4):
        a = math.radians(i * 360.0 / (GEAR_TEETH * 4))
        r = r1 if (i % 4) in (0, 1) else r2
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return poly(pts) + " " + circle(cx, cy, 7)


def blade(cx, cy, length, width, deg):
    # Dagger / sword pointing up, then rotated.
    pts = [(cx, cy - length * 0.55), (cx + width, cy + length * 0.15), (cx + width * 0.5, cy + length * 0.2),
           (cx + width * 1.8, cy + length * 0.22), (cx + width * 1.8, cy + length * 0.3), (cx + width * 0.45, cy + length * 0.3),
           (cx + width * 0.45, cy + length * 0.45), (cx - width * 0.45, cy + length * 0.45), (cx - width * 0.45, cy + length * 0.3),
           (cx - width * 1.8, cy + length * 0.3), (cx - width * 1.8, cy + length * 0.22), (cx - width * 0.5, cy + length * 0.2),
           (cx - width, cy + length * 0.15)]
    return poly(rot_pts(pts, cx, cy, deg))


def spear(deg=45.0, bone=False):
    pts = [(32, 4), (37, 16), (34, 18), (34, 58), (30, 58), (30, 18), (27, 16)]
    if bone:
        pts = [(32, 4), (36, 14), (34, 16), (35, 50), (38, 54), (34, 58), (32, 55), (30, 58), (26, 54), (29, 50), (30, 16), (28, 14)]
    return poly(rot_pts(pts, 32, 32, deg))


def chain_links(n=3, deg=-45.0):
    d = []
    for i in range(n):
        y = 14 + i * 14
        pts = [(26, y - 7), (38, y - 7), (42, y), (38, y + 7), (26, y + 7), (22, y)]
        inner = [(28, y - 3), (36, y - 3), (38, y), (36, y + 3), (28, y + 3), (26, y)]
        d.append(poly(rot_pts(pts, 32, 32, deg)) + " " + poly(rot_pts(inner, 32, 32, deg)))
    return " ".join(d)


def burst(n=9, r1=27, r2=12):
    return star(32, 32, r1, r2, n)


def coin(cx=32, cy=32, r=20):
    return circle(cx, cy, r)


def bubbles():
    return " ".join(circle(x, y, r) for x, y, r in [(32, 38, 14), (19, 22, 7), (44, 18, 6), (48, 34, 5), (22, 50, 4)])


def spiral():
    pts = []
    for i in range(70):
        t = i / 69.0
        a = t * math.pi * 4.2
        r = 4 + t * 22
        pts.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    out = [(32 + (x - 32) * 1.0, y) for x, y in pts]
    inner = []
    for i in range(69, -1, -1):
        t = i / 69.0
        a = t * math.pi * 4.2
        r = 4 + t * 22 - 2 - 4 * t
        inner.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    return poly(out + inner)


def lash(barbed=False):
    # S-curve whip as a thick stroke outline (polygon around a sampled curve).
    pts = []
    for i in range(40):
        t = i / 39.0
        x = 10 + t * 44
        y = 46 - t * 30 + math.sin(t * math.pi * 2.0) * 10
        pts.append((x, y))
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        nx, ny = (pts[min(i + 1, 39)][0] - pts[max(i - 1, 0)][0], pts[min(i + 1, 39)][1] - pts[max(i - 1, 0)][1])
        ln = math.hypot(nx, ny) or 1.0
        w = 4.6 * (1.0 - i / 39.0 * 0.7)
        left.append((x - ny / ln * w, y + nx / ln * w))
        right.append((x + ny / ln * w, y - nx / ln * w))
    d = poly(left + right[::-1])
    d += " " + poly([(6, 52), (12, 42), (16, 46), (10, 56)])  # handle
    if barbed:
        for i in range(6, 38, 6):
            x, y = pts[i]
            d += " " + poly([(x - 2, y - 2), (x + 3, y - 8), (x + 3, y)])
    return d


def turret():
    return (poly([(18, 56), (20, 30), (44, 30), (46, 56)]) + " " + poly([(16, 30), (16, 20), (22, 20), (22, 24),
            (28, 24), (28, 20), (36, 20), (36, 24), (42, 24), (42, 20), (48, 20), (48, 30)]) + " "
            + poly([(30, 22), (30, 6), (34, 6), (34, 22)]))


def mine():
    return star(32, 34, 24, 15, 8) + " " + circle(32, 34, 9)


def lantern():
    return (poly([(24, 16), (40, 16), (44, 24), (44, 46), (40, 54), (24, 54), (20, 46), (20, 24)]) + " "
            + poly([(28, 16), (30, 8), (34, 8), (36, 16)]))


def mirror():
    return circle(32, 28, 20) + " " + poly([(29, 47), (35, 47), (36, 60), (28, 60)])


def maul():
    return poly([(12, 12), (40, 12), (40, 30), (12, 30)]) + " " + poly(rot_pts([(29, 30), (35, 30), (35, 60), (29, 60)], 32, 32, 0))


def hook():
    return ("M30 4 L36 4 L36 34 C36 46 28 52 20 48 C14 45 12 38 15 33 L10 30 L22 26 L22 38 L18 36 "
            "C17 40 19 43 22 44 C27 46 30 42 30 34 Z")


def pentagram():
    pts = [(32 + math.cos(math.radians(-90 + i * 144)) * 22, 33 + math.sin(math.radians(-90 + i * 144)) * 22) for i in range(5)]
    return ring(32, 33, 26, 3.2) + " " + poly(pts)


def wail():
    return ("M32 6 C46 6 52 18 52 30 C52 44 44 58 32 58 C20 58 12 44 12 30 C12 18 18 6 32 6 Z")


def horn():
    return "M14 54 C14 34 26 18 50 8 C42 20 38 30 36 40 C34 48 32 52 30 56 Z"


def paw():
    return (circle(32, 40, 12) + " " + circle(17, 26, 6) + " " + circle(26, 16, 6) + " " + circle(38, 16, 6)
            + " " + circle(47, 26, 6))


def imp_head():
    return ("M32 18 C42 18 48 26 48 36 C48 47 41 54 32 54 C23 54 16 47 16 36 C16 26 22 18 32 18 Z "
            "M18 26 L10 6 L26 20 Z M46 26 L54 6 L38 20 Z")


def meteor():
    d = circle(40, 40, 13)
    for i, (sx, sy) in enumerate([(8, 8), (16, 6), (6, 18)]):
        d += " " + poly([(sx, sy), (32 + i, 30 - i), (30 - i, 34 + i)])
    return d


def pillar():
    return poly([(24, 58), (24, 22), (40, 22), (40, 58)]) + " " + FLAME_SMALL


FLAME_SMALL = ("M32 2 C35 8 41 11 41 17 C41 22 37 25 32 25 C27 25 23 22 23 17 C23 12 27 10 28 6 "
               "C29 9 31 10 31 11 C31 7 31 5 32 2 Z")


def chalice():
    return ("M16 10 L48 10 C48 24 42 32 35 34 L35 46 L44 52 L44 56 L20 56 L20 52 L29 46 L29 34 "
            "C22 32 16 24 16 10 Z")


def cleave():
    return ("M8 46 C14 22 34 8 58 10 C40 16 26 28 20 50 Z")


def fissure():
    return poly([(6, 40), (18, 34), (24, 42), (34, 30), (42, 36), (58, 22), (60, 28), (44, 44), (36, 40),
                 (26, 52), (18, 42), (8, 48)])


def quake():
    return ring(32, 36, 26, 3) + " " + ring(32, 36, 17, 3) + " " + fissure()


def locust():
    return ("M32 12 C36 12 38 18 38 26 L38 50 C38 55 34 58 32 58 C30 58 26 55 26 50 L26 26 C26 18 28 12 32 12 Z "
            "M37 26 C48 18 58 22 58 30 C52 32 44 32 37 32 Z M27 26 C16 18 6 22 6 30 C12 32 20 32 27 32 Z")


def flail():
    return star(38, 38, 18, 11, 10) + " " + poly([(6, 8), (12, 6), (30, 30), (26, 32)])  # spiked head + haft


def gem():
    return poly([(32, 8), (52, 26), (32, 56), (12, 26)]) + " " + poly([(12, 26), (52, 26), (32, 30)])


def radiance_stolen():
    return star(32, 32, 27, 15, 12) + " " + "M32 14 L30 30 L38 34 L28 50 L32 34 L24 30 Z"


def sword_down():
    return blade(32, 34, 52, 4.5, 180)


def thralls():
    return " ".join(skull_small(x, y, s) for x, y, s in [(20, 40, 0.55), (44, 40, 0.55), (32, 26, 0.75)])


def skull_small(cx, cy, s):
    return circle(cx, cy - 4 * s, 14 * s) + " " + poly([(cx - 8 * s, cy + 6 * s), (cx + 8 * s, cy + 6 * s), (cx + 6 * s, cy + 14 * s), (cx - 6 * s, cy + 14 * s)])


def nova(n=12):
    return star(32, 32, 28, 15, n) + " " + circle(32, 32, 8)


def mark():
    return ring(32, 32, 24, 3.5) + " " + poly([(30, 4), (34, 4), (34, 60), (30, 60)]) + " " + poly([(4, 30), (60, 30), (60, 34), (4, 34)])


def brute():
    return ("M14 58 L14 36 C14 24 22 18 32 18 C42 18 50 24 50 36 L50 58 Z M18 24 L8 10 L24 18 Z "
            "M46 24 L56 10 L40 18 Z")


def engine():
    return gear(32, 32, 27, 20)


def coins_stack():
    return " ".join(circle(x, y, 11) for x, y in [(22, 40), (42, 40), (32, 24)])


def hubris_face():
    return CROWN + " " + EYE_SMALL


EYE_SMALL = "M18 54 C24 48 40 48 46 54 C40 60 24 60 18 54 Z"


def ball_lightning():
    return circle(32, 32, 20) + " " + poly([(34, 14), (24, 34), (31, 34), (28, 50), (40, 28), (33, 28), (36, 14)])


def heart_burst():
    return star(32, 32, 30, 22, 16) + " " + HEART


def doppel():
    return MASK


# ---------------------------------------------------------------- motif table
# Each entry: list of (path, role[, svg transform]). Roles: "main" (gradient fill + ink outline), "dark" (ink-dark
# detail, drawn on top), "hot" (bright core, drawn on top), "ring" (thin accent in the colour).

def M(*layers):
    return list(layers)


BY_ID = {
    "cinder_spray": M((FLAME, "main"), (FLAME_CORE, "hot")),
    "inferno_nova": M((nova(14), "main"), (circle(32, 32, 8), "hot")),
    "heart_of_gehenna": M((heart_burst(), "main"), (circle(32, 30, 6), "hot")),
    "brimstone_meteor": M((meteor(), "main"), (circle(42, 42, 5), "hot")),
    "pyre_circle": M((ring(32, 32, 27, 6), "main"), (FLAME_SMALL.replace("M32 2", "M32 16"), "hot")),
    "flame_pillar": M((pillar(), "main")),
    "imp_rabble": M((imp_head(), "main"), (circle(26, 36, 3) + " " + circle(38, 36, 3), "hot")),
    "hemorrhage_lance": M((spear(40), "main")),
    "crimson_nova": M((DROP, "main"), (ring(32, 38, 12, 3), "dark")),
    "blood_frenzy": M((HEART, "main"), (LIGHTNING.replace("36 4", "34 14"), "dark")),
    "sanguine_tithe": M((chalice(), "main"), (circle(32, 18, 6), "hot")),
    "bloodboil": M((bubbles(), "main")),
    "raise_thralls": M((thralls(), "main")),
    "legion_of_the_damned": M((brute(), "main"), (circle(26, 34, 3) + " " + circle(38, 34, 3), "hot")),
    "wraith_host": M((GHOST, "main"), (GHOST_EYES, "dark")),
    "bone_spear": M((spear(45, bone=True), "main")),
    "corpse_explosion": M((burst(11, 29, 13), "main"), (SKULL_EYES, "dark")),
    "call_the_pack": M((paw(), "main")),
    "pestilent_cloud": M((CLOUD, "main"), (circle(24, 36, 3) + " " + circle(36, 32, 2.5) + " " + circle(44, 38, 2), "dark")),
    "blight_spit": M((DROP.replace("M32 7", "M32 5"), "main"), (circle(26, 40, 3) + " " + circle(36, 46, 2.5), "dark")),
    "rot_aura": M((ring(32, 32, 28, 5), "main"), (SKULL, "main", "translate(32 32) scale(0.62) translate(-32 -31)")),
    "locust_swarm": M((locust(), "main")),
    "infernal_storm": M((LIGHTNING, "main")),
    "pit_storm": M((CLOUD, "main"), (LIGHTNING.replace("36 4", "36 20"), "hot")),
    "thunder_brand": M((pentagram(), "main"), (LIGHTNING, "hot")),
    "ball_lightning": M((ball_lightning(), "main")),
    "tempest_nova": M((CROWN, "main"), (LIGHTNING.replace("36 4", "34 30"), "hot")),
    "umbral_step": M((CRESCENT, "main"), (poly([(42, 30), (58, 32), (42, 34)]), "main")),
    "shadow_daggers": M((blade(24, 34, 44, 3.5, -20), "main"), (blade(40, 34, 44, 3.5, 20), "main")),
    "death_mark": M((mark(), "main"), (SKULL_EYES, "dark")),
    "shade_clone": M((GHOST, "main", "translate(17 34) scale(0.48) translate(-32 -31)"),
                     (GHOST, "main", "translate(47 34) scale(0.48) translate(-32 -31)"),
                     (GHOST, "main", "translate(32 28) scale(0.66) translate(-32 -31)"),
                     (GHOST_EYES, "dark", "translate(32 28) scale(0.66) translate(-32 -31)")),
    "brimstone_maul": M((maul(), "main")),
    "earthsunder": M((fissure(), "main")),
    "ground_slam": M((quake(), "main")),
    "pit_brute": M((brute(), "main"), (circle(26, 34, 3) + " " + circle(38, 34, 3), "hot")),
    "hellhook": M((hook(), "main")),
    "binding_chains": M((chain_links(3, -45), "main")),
    "chain_whirl": M((flail(), "main")),
    "hex_frailty": M((pentagram(), "main")),
    "withering_gaze": M((EYE, "main"), (EYE_PUPIL, "dark")),
    "malediction": M((nova(8), "main"), (pentagram(), "dark")),
    "soul_siphon": M((FLAME, "main"), (GHOST_EYES, "dark")),
    "reaping_wail": M((wail(), "main"), (MASK_HOLES, "dark")),
    "soul_lanterns": M((lantern(), "main"), (FLAME_CORE.replace("M32 30", "M32 26"), "hot")),
    "harvest_moon": M((CRESCENT, "main"), (circle(42, 20, 3) + " " + circle(46, 32, 2.5) + " " + circle(42, 44, 2), "hot")),
    "wrathful_cleave": M((cleave(), "main")),
    "wrath_incarnate": M((horn(), "main"), (cleave(), "hot")),
    "retribution": M((burst(8, 28, 16), "main"), (blade(32, 32, 30, 3, 0), "dark")),
    "berserker_howl": M((horn(), "main")),
    "seething_aura": M((ring(32, 32, 27, 6), "main"), (FLAME, "main")),
    "coin_barrage": M((coins_stack(), "main")),
    "midas_touch": M((HAND, "main")),
    "avarice": M((gem(), "main")),
    "tithe_coins": M((ring(32, 32, 26, 3), "main"), (coin(32, 32, 12), "main")),
    "stolen_radiance": M((radiance_stolen(), "main")),
    "covetous_gaze": M((EYE, "main"), (EYE_PUPIL, "dark")),
    "jealous_hex": M((pentagram(), "main"), (EYE_PUPIL, "dark")),
    "hubris": M((hubris_face(), "main")),
    "prides_fall": M((sword_down(), "main")),
    "crown_of_contempt": M((CROWN, "main"), (circle(20, 24, 2.5) + " " + circle(32, 16, 3) + " " + circle(44, 24, 2.5), "hot")),
    "devour": M((MAW, "main")),
    "maw_of_hell": M((MAW, "main"), (circle(32, 32, 4), "hot")),
    "bilious_belch": M((CLOUD, "main"), (circle(22, 38, 2.5) + " " + circle(40, 30, 3), "dark")),
    "mirror_image": M((mirror(), "main"), (circle(32, 28, 14), "dark")),
    "hall_of_mirrors": M((mirror(), "main"), (poly([(24, 20), (30, 16), (40, 34), (34, 38)]), "hot")),
    "doppelganger": M((MASK, "main"), (MASK_HOLES, "dark")),
    "brimstone_turret": M((turret(), "main")),
    "infernal_battery": M((turret(), "main"), (LIGHTNING.replace("36 4", "34 30"), "hot")),
    "hellmine_field": M((mine(), "main"), (circle(32, 34, 4), "hot")),
    "infernal_engine": M((engine(), "main")),
    "hellfire_lash": M((lash(), "main")),
    "chain_dance": M((spiral(), "main")),
    "barbed_flurry": M((lash(barbed=True), "main")),
}

BY_KIND = {
    "bolt": M((FLAME, "main")), "nova": M((nova(), "main")), "aura": M((ring(32, 32, 27, 6), "main")),
    "zone": M((CLOUD, "main")), "summon": M((imp_head(), "main")), "hex": M((pentagram(), "main")),
    "chain": M((LIGHTNING, "main")), "orbit": M((ring(32, 32, 26, 3), "main"), (circle(32, 6, 5), "main")),
    "strike": M((meteor(), "main")), "cone": M((cleave(), "main")), "line": M((fissure(), "main")),
    "whip": M((lash(), "main")), "turret": M((turret(), "main")), "mine": M((mine(), "main")),
}


def icon_svg(color_hex, layers):
    c = hx(color_hex)
    light = to_hex(mix(c, (1.0, 0.96, 0.88), 0.55))
    mid = to_hex(c)
    dark = to_hex(mix(c, (0.05, 0.02, 0.02), 0.55))
    hot = to_hex(mix(c, (1.0, 0.95, 0.85), 0.7))
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 64 64">',
           "<defs>",
           '<radialGradient id="bg" cx="32" cy="32" r="32" gradientUnits="userSpaceOnUse">'
           '<stop offset="0" stop-color="#1c0d0a" stop-opacity="0.96"/>'
           '<stop offset="0.72" stop-color="#0c0605" stop-opacity="0.9"/>'
           '<stop offset="1" stop-color="#080404" stop-opacity="0"/></radialGradient>',
           '<radialGradient id="glow" cx="32" cy="32" r="27" gradientUnits="userSpaceOnUse">'
           '<stop offset="0" stop-color="%s" stop-opacity="0.55"/>'
           '<stop offset="1" stop-color="%s" stop-opacity="0"/></radialGradient>' % (mid, mid),
           '<linearGradient id="fill" x1="14" y1="8" x2="48" y2="58" gradientUnits="userSpaceOnUse">'
           '<stop offset="0" stop-color="%s"/><stop offset="0.5" stop-color="%s"/>'
           '<stop offset="1" stop-color="%s"/></linearGradient>' % (light, mid, dark),
           "</defs>",
           '<circle cx="32" cy="32" r="32" fill="url(#bg)"/>',
           '<circle cx="32" cy="32" r="27" fill="url(#glow)"/>']
    for layer in layers:
        d, role = layer[0], layer[1]
        if len(layer) > 2:
            # Optional SVG transform (scale / place a motif): wrap the layer in a group.
            out.append('<g transform="%s">' % layer[2])
        if role == "main":
            out.append('<path d="%s" fill="url(#fill)" fill-rule="evenodd" stroke="%s" stroke-width="1.8" '
                       'stroke-linejoin="round"/>' % (d, INK))
        elif role == "dark":
            out.append('<path d="%s" fill="%s" fill-rule="evenodd" opacity="0.92"/>' % (d, INK))
        elif role == "hot":
            out.append('<path d="%s" fill="%s" fill-rule="evenodd" stroke="%s" stroke-width="0.8"/>' % (d, hot, INK))
        if len(layer) > 2:
            out.append("</g>")
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    with open(os.path.join(ROOT, "data", "abilities", "abilities.json"), encoding="utf-8") as f:
        abilities = json.load(f)["abilities"]
    evo_path = os.path.join(ROOT, "data", "abilities", "evolutions.json")
    if os.path.exists(evo_path):
        with open(evo_path, encoding="utf-8") as f:
            abilities += [e["ability"] for e in json.load(f).get("evolutions", [])]
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for a in abilities:
        aid = a["id"]
        if aid in KEEP:
            continue
        layers = BY_ID.get(aid) or BY_KIND.get(a.get("kind", "")) or M((star(32, 32, 26, 12, 6), "main"))
        if aid not in BY_ID:
            print("no motif for %s (kind %s): using fallback" % (aid, a.get("kind")))
        with open(os.path.join(OUT, aid + ".svg"), "w", encoding="utf-8", newline="\n") as f:
            f.write(icon_svg(a.get("color", "#ff6a20"), layers))
        n += 1
    print("wrote %d icons to %s" % (n, OUT))


if __name__ == "__main__":
    main()
