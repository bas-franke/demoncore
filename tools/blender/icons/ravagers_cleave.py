"""Ravager's Cleave: a notched, blood-rusted executioner's greatsword, held diagonally."""
import sb
import _ikit as k

ACCENT = (0.95, 0.32, 0.12)
VIEW = {"pitch": 6, "yaw": 0, "fill": 0.9}


def build():
    steel = k.metal("I_Steel", (0.32, 0.3, 0.29), 0.32)
    dark = k.metal("I_DarkSteel", (0.08, 0.07, 0.07), 0.45)
    rust = sb.mat("I_Rust", (0.12, 0.035, 0.025), roughness=0.8, metallic=0.2)
    gold = k.metal("I_Gold", (0.55, 0.38, 0.16), 0.35)
    leather = sb.mat("I_Leather", (0.1, 0.05, 0.035), roughness=0.85)
    ember = k.glow("I_Ember", (1.0, 0.3, 0.05), 1.4)
    root = sb.root("Sword")
    root.rotation_euler = (0, 0.75, 0)

    # Broad blade outline (XY, then turned to face the camera) with jagged notches on both edges.
    L, w = 2.4, 0.2
    right = [(w, 0.0), (w, 0.55), (w - 0.11, 0.6), (w, 0.68), (w * 0.98, 1.2), (w - 0.13, 1.26),
             (w * 0.96, 1.33), (w * 0.9, 1.75), (w * 0.82, 1.9), (w * 0.62, 2.12)]
    left = [(-w * 0.55, 2.2), (-w * 0.85, 2.0), (-w * 0.93, 1.6), (-w * 0.93 + 0.12, 1.52),
            (-w * 0.95, 1.45), (-w, 0.95), (-w + 0.1, 0.9), (-w + 0.03, 0.86), (-w, 0.82), (-w, 0.0)]
    outline = right + [(0.05, L)] + left
    sb.extrude_outline("blade", root, outline, 0.05, steel, loc=(0, 0, 0.0), rot=(90, 0, 0), bevel=0.018)
    # Dark fuller and rust bloom.
    sb.box("fuller", root, (0.07, 0.056, 1.5), loc=(0, 0, 0.95), material=dark, bevel=0.01)
    for i, (x, z, s) in enumerate(((0.1, 0.62, 0.09), (-0.13, 0.9, 0.07), (0.08, 1.3, 0.08), (-0.1, 1.5, 0.06))):
        sb.sphere(f"rust{i}", root, s, loc=(x, -0.012, z), scale=(1.3, 0.12, 2.2), material=rust)
    # Hot nicks in the notches.
    for i, (x, z) in enumerate(((w - 0.06, 0.6), (w - 0.09, 1.26), (-w + 0.07, 0.88), (-w * 0.93 + 0.07, 1.52))):
        sb.sphere(f"nick{i}", root, 0.016, loc=(x, -0.02, z), material=ember)

    # Crossguard: heavy bar with drooping, flared ends.
    sb.box("guard", root, (0.78, 0.13, 0.12), loc=(0, 0, -0.02), material=dark, bevel=0.03)
    for s in (-1, 1):
        sb.ptube(f"quillon{s}", root, [(0.36 * s, 0, -0.02), (0.5 * s, 0, -0.06), (0.58 * s, 0, -0.18)],
                 [0.07, 0.05, 0.02], sides=6, material=dark)
    sb.sphere("gem", root, 0.06, loc=(0, -0.07, -0.02), scale=(1, 0.5, 1.2), material=ember)
    sb.box("ricasso", root, (0.3, 0.07, 0.1), loc=(0, 0, 0.08), material=gold, bevel=0.02)
    # Grip and pommel.
    sb.cylinder("grip", root, r1=0.055, r2=0.05, depth=0.6, loc=(0, 0, -0.68), material=leather, segments=10)
    for i in range(6):
        sb.torus(f"wrap{i}", root, 0.058, 0.012, loc=(0, 0, -0.62 + i * 0.1), material=leather,
                 major_segments=16, minor_segments=5)
    sb.sphere("pommel", root, 0.11, loc=(0, 0, -0.78), scale=(1, 0.8, 1.1), material=gold)
    sb.cylinder("pspike", root, r1=0.05, r2=0.0, depth=0.14, loc=(0, 0, -0.88), rot=(180, 0, 0), material=dark,
                segments=6, bevel=0)
    return root
