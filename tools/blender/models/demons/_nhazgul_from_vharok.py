"""Derives tools/blender/models/demons/nhazgul.py from vharok.py (characters-new round 4):
same humanoid rig + animation set (idle walk attack hit death cheer), re-themed as a plague-hive
demon: sick grey-green hide, corroded verdigris plate, plague-green glows instead of embers, waxy
hive combs grown out of the back and shoulders with glowing larval cells, a bloated belly sac,
pustules, and insect-like greenish wing membranes."""
import os
SRC = 'C:/Projects/demoncore/tools/blender/models/demons/vharok.py'
DST = 'C:/Projects/demoncore/tools/blender/models/demons/nhazgul.py'
s = open(SRC, encoding='utf-8-sig').read()

doc_end = s.index('"""', 3) + 3
s = '''"""Nhazgul, the Plague Hive (characters-new): a bloated, hunched brute of sick grey-green hide,
corroded verdigris plate split by plague-green fissures, waxy hive combs grown out of the back and
shoulders (their cells glow with larvae), a swollen belly sac, pustules, torn insect-veined wings
and a rust-eaten cleaver. Derived from vharok.py by _nhazgul_from_vharok.py: the same rig and
animation set (idle walk attack hit death cheer), re-themed materials plus the hive growths.

Rig: _demon_kit.humanoid (Godot needs "look" + "head") plus jaw, wing_L/R > wing_mid > wingtip,
loin_f0..2 / loin_b0..2, tasset_L/R, chain_L0..2 / chain_R0..2, sword (+ sword_tip marker).
"""''' + s[doc_end:]

# Material block: replace everything from `L = K.lin` to the chain material with a plague palette.
a = s.index('    L = K.lin\n')
b = s.index('    R = K.humanoid(')
mats = '''    L = K.lin
    skin = sbmat.skin("Nhazgul_SkinBloated", L((0.2, 0.22, 0.13)), rough=0.5, scars=0.8, pores=70.0,
                      crease=L((0.06, 0.07, 0.03)), high=L((0.36, 0.38, 0.22)))
    plate = sbmat.worn_steel("Nhazgul_VerdigrisPlate", L((0.16, 0.24, 0.18)), roughness=0.45, rust=0.55,
                             edge_k=3.0, scratch_k=1.6, grime=1.0)
    obsid = sbmat.obsidian_ember("Nhazgul_ObsidianRot", tint=L((0.05, 0.06, 0.04)), strength=0.0)
    trim = sbmat.gold_filigree("Nhazgul_BronzeCorroded", tint=L((0.36, 0.42, 0.24)), scale=1.4)
    horn = sbmat.horn("Nhazgul_HornChitin", L((0.3, 0.3, 0.18)), rough=0.4, tip=L((0.08, 0.09, 0.05)))
    dhorn = sbmat.horn("Nhazgul_HornSpikeChitin", L((0.12, 0.13, 0.07)), rough=0.35, rings=30.0)
    claw = sbmat.horn("Nhazgul_ClawBlack", L((0.07, 0.08, 0.05)), rough=0.35, rings=45.0)
    teeth = sbmat.aged_ivory("Nhazgul_TeethYellow", L((0.62, 0.56, 0.3)), scale=2.0)
    ember = K.mat("Nhazgul_PlagueGlow", (0.25, 0.45, 0.05), 0.5, 0.0, (0.55, 1.0, 0.15), 9.0)
    core = K.mat("Nhazgul_PlagueCore", (0.4, 0.7, 0.1), 0.4, 0.0, (0.7, 1.0, 0.3), 12.0)
    eyes = K.mat("Nhazgul_EyeGlow", (0.7, 0.9, 0.2), 0.4, 0.0, (0.85, 1.0, 0.25), 16.0)
    cloth = sbmat.linen("Nhazgul_ClothRag", L((0.16, 0.17, 0.08)), weave=70.0, rough=0.9, stain=0.8,
                        stain_col=L((0.08, 0.09, 0.03)), grime_col=L((0.02, 0.025, 0.01)))
    cloth2 = sbmat.linen("Nhazgul_ClothBlackened", L((0.07, 0.075, 0.05)), weave=70.0, rough=0.92,
                         stain_col=L((0.1, 0.11, 0.05)), grime_col=L((0.02, 0.02, 0.01)))
    leather = sbmat.leather("Nhazgul_LeatherStrap", L((0.13, 0.11, 0.06)), scale=0.55)
    memb = sbmat.skin("Nhazgul_MembraneWing", L((0.3, 0.33, 0.18)), rough=0.4, veins=1.0, pores=40.0,
                      crease=L((0.08, 0.1, 0.04)))
    blade = sbmat.worn_steel("Nhazgul_BladeRust", L((0.2, 0.17, 0.13)), roughness=0.5, edge_k=2.0,
                             scratch_k=1.4, grime=1.0, rust=0.8)
    chainm = sbmat.worn_steel("Nhazgul_ChainIron", L((0.17, 0.18, 0.15)), roughness=0.5, scale=3.0,
                              rust=0.6, edge_k=2.4)
    hive = sbmat.aged_ivory("Nhazgul_HiveWax", L((0.62, 0.48, 0.18)), scale=3.0)
    larva = K.mat("Nhazgul_LarvaGlow", (0.6, 0.85, 0.2), 0.4, 0.0, (0.75, 1.0, 0.3), 7.0)

'''
s = s[:a] + mats + s[b:]
s = s.replace('K.humanoid("Vharok"', 'K.humanoid("Nhazgul"')

# Silhouette: chitin antennae and mandible-horns instead of the great ram horns.
old_horn = """        ctrl = [(x * 1.28, y * 1.18, z * 1.2) for x, y, z in ctrl]
        ram_horn(f"ram_horn_{n}", Hd, ctrl, 0.088, 0.008, horn, n=4, segs=8, rib=0.1, flat=0.2)"""
assert old_horn in s
s = s.replace(old_horn, """        # (Nhazgul) long jointed antennae sweeping up and back, and short hooked mandible-horns.
        ctrl = [(s * 0.06, -0.06, 0.2), (s * 0.12, -0.04, 0.36), (s * 0.2, 0.05, 0.52), (s * 0.3, 0.2, 0.62),
                (s * 0.42, 0.36, 0.64), (s * 0.5, 0.5, 0.6)]
        ram_horn(f"ram_horn_{n}", Hd, ctrl, 0.03, 0.005, horn, n=6, segs=6, rib=0.18, flat=0.0)
        K.horn(f"mandible_{n}", Hd, [(s * 0.08, -0.17, 0.08), (s * 0.13, -0.24, 0.06), (s * 0.08, -0.3, 0.02)],
               0.022, 0.002, horn, segs=6, n=2)""")

# Hive growths, belly sac and pustules: added just before the animation call.
hook = '    animate(R, dict(loin_f=loin_f'
assert hook in s
hive = '''    # ---------------------------------------------------------------- the hive (characters-new)
    # Waxy comb masses grown out of the back and shoulders, each studded with glowing larval cells.
    for k, (loc, rad) in enumerate((((0.0, 0.31, 0.32), 0.3), ((-0.24, 0.27, 0.46), 0.2), ((0.23, 0.28, 0.44), 0.21),
                                    ((0.08, 0.36, 0.12), 0.17), ((-0.13, 0.34, 0.15), 0.15), ((0.0, 0.26, 0.62), 0.16))):
        sb.sphere(f"hive_comb{k}", C, rad, loc=loc, scale=(1.0, 0.8, 1.15), material=hive, segments=10, rings=6)
        for c in range(6):
            a = math.radians(c * 60 + k * 17)
            p = (loc[0] + math.cos(a) * rad * 0.55, loc[1] + rad * 0.72, loc[2] + math.sin(a) * rad * 0.6)
            sb.sphere(f"hive_cell{k}_{c}", C, rad * 0.16, loc=p, scale=(1.0, 0.5, 1.0), material=larva,
                      segments=6, rings=3)
    for s in SIDES:
        n = sname(s)
        sb.sphere(f"hive_shoulder_{n}", C, 0.11, loc=(s * 0.36, 0.08, 0.5), scale=(1.0, 0.9, 0.8), material=hive,
                  segments=8, rings=5)
        for c in range(3):
            sb.sphere(f"hive_shoulder_cell_{n}{c}", C, 0.02, loc=(s * (0.33 + c * 0.03), 0.0, 0.53 + c * 0.02),
                      material=larva, segments=6, rings=3)
    # Swollen belly sac with glowing veins, and pustules on the arms and thighs.
    sb.sphere("belly_sac", SP, 0.2, loc=(0, -0.17, 0.08), scale=(1.15, 0.8, 1.0), material=skin, segments=12, rings=8)
    for v in range(4):
        sb.sphere(f"belly_vein{v}", SP, 0.018, loc=(-0.09 + v * 0.06, -0.33, 0.04 + 0.03 * (v % 2)),
                  scale=(1.0, 0.4, 2.2), material=ember, segments=6, rings=3)
    for s in SIDES:
        n = sname(s)
        for c in range(3):
            sb.sphere(f"pustule_arm_{n}{c}", R.arm[s], 0.028 - c * 0.004, loc=(s * 0.06, -0.04, -0.08 - c * 0.08),
                      material=larva, segments=6, rings=4)
            sb.sphere(f"pustule_leg_{n}{c}", R.thigh[s], 0.026, loc=(s * 0.08, -0.07, -0.12 - c * 0.1),
                      material=larva, segments=6, rings=4)

'''
s = s.replace(hook, hive + hook, 1)
open(DST, 'w', encoding='utf-8').write(s)
print('written', len(s))
