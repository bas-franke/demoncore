"""Derives tools/blender/models/demons/iscariel.py from lilaeth.py (characters-new round 5): the same
rig and animation set (idle walk attack hit death cheer), re-themed as Iscariel, the Turncoat - a
fallen angel who went over to Hell: ash-grey skin whose holy-gold veins are turning to hellfire,
blackened armour with burnt-gold filigree, a charcoal robe over a molten-gold lining, a blackened
halo broken into more pieces, and mismatched wings - the right still pale ash-white, the left
burned down to a smaller, charred, ember-edged ruin.

Run with plain python (not Blender):  python tools/blender/models/demons/_iscariel_from_lilaeth.py
then build:  blender -b --factory-startup --python tools/blender/build.py -- demons/iscariel
(The leading underscore keeps build.py's "all" from treating this file as a model.)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "lilaeth.py")
DST = os.path.join(HERE, "iscariel.py")


def main():
    s = open(SRC, encoding="utf-8-sig").read()
    doc_end = s.index('"""', 3) + 3
    s = ('"""Iscariel, the Turncoat (characters-new): a fallen angel who went over to Hell. Ash-grey skin\n'
         'whose holy-gold veins are turning to hellfire, blackened armour with burnt-gold filigree, a\n'
         'charcoal robe over a molten-gold lining, a blackened halo broken into many pieces, and\n'
         'mismatched wings: the right still pale ash-white, the left burned to a smaller charred ruin.\n'
         'Generated from lilaeth.py by _iscariel_from_lilaeth.py: same rig and animation set.\n"""'
         + s[doc_end:])

    a = s.index("    L = K.lin\n")
    b = s.index("    FM = (feath, ember)\n")
    mats = '''    L = K.lin
    skin = sbmat.skin("Iscariel_Skin", L((0.42, 0.4, 0.42)), rough=0.5, pores=130.0,
                      crease=L((0.22, 0.2, 0.22)), high=L((0.55, 0.52, 0.53)), veins=0.6,
                      vein_col=L((0.85, 0.5, 0.12)), scars=0.4)
    armor = sbmat.worn_steel("Iscariel_ArmorSteel", L((0.06, 0.055, 0.06)), roughness=0.32, edge_k=3.0,
                             scratch_k=2.0, grime=0.9)
    gilt = sbmat.gold_filigree("Iscariel_GoldBurnt", tint=L((0.5, 0.3, 0.12)), scale=1.6)
    robe = sbmat.linen("Iscariel_RobeCloth", L((0.05, 0.048, 0.05)), weave=90.0, rough=0.86, stain=0.5,
                       stain_col=L((0.14, 0.09, 0.05)), grime_col=L((0.02, 0.015, 0.012)))
    lining = sbmat.silk("Iscariel_SilkCloth", L((0.75, 0.42, 0.08)), rough=0.4)
    hair = sbmat.hair("Iscariel_HairSilk", L((0.1, 0.09, 0.1)), rough=0.45)
    feath = sbmat.feathers("Iscariel_WingFeather", L((0.9, 0.88, 0.84)), sheen=(0.3, 0.28, 0.2), barbs=60.0)
    ember = K.mat("Iscariel_FeatherEmber", (0.3, 0.15, 0.04), 0.6, 0.0, (1.0, 0.55, 0.12), 3.2)
    feath_burnt = sbmat.feathers("Iscariel_WingFeatherBurnt", L((0.035, 0.03, 0.03)), barbs=40.0)
    ember_burnt = K.mat("Iscariel_FeatherEmberHot", (0.4, 0.06, 0.02), 0.6, 0.0, (1.0, 0.25, 0.05), 5.0)
    thorn = sbmat.horn("Iscariel_ThornBranch", L((0.1, 0.08, 0.06)), rough=0.6, rings=35.0)
    claw = sbmat.horn("Iscariel_Claw", L((0.06, 0.05, 0.05)), rough=0.3, rings=45.0)
    fire = K.mat("Iscariel_HellfireGlow", (0.45, 0.22, 0.04), 0.5, 0.0, (1.0, 0.5, 0.1), 8.0)
    halo_m = K.mat("Iscariel_HaloGlow", (0.3, 0.12, 0.04), 0.4, 0.5, (1.0, 0.35, 0.08), 4.5)
    char = K.mat("Iscariel_HaloCharGold", (0.05, 0.04, 0.035), 0.5, 0.8)
    eyes = K.mat("Iscariel_EyeGlow", (0.7, 0.5, 0.1), 0.5, 0.0, (1.0, 0.75, 0.2), 14.0)
    gem = K.mat("Iscariel_EmberGem", (0.6, 0.3, 0.03), 0.15, 0.0, (1.0, 0.6, 0.1), 4.0)
    lips = K.mat("Iscariel_LipSkin", (0.18, 0.12, 0.12), 0.45)
'''
    s = s[:a] + mats + s[b:]
    s = s.replace('K.humanoid("Lilaeth"', 'K.humanoid("Iscariel"')

    # The halo: blackened (materials above) and broken into more pieces.
    old = "    gaps = (0, 3)    # two big breaks\n"
    assert old in s
    s = s.replace(old, "    gaps = (0, 2, 3, 5)    # (Iscariel) broken in four places\n")

    # Mismatched wings: the left one burned (charred materials, smaller).
    old = "        r = random.Random(100 + s)\n        w0 = sb.empty(f\"wing_{n}\", C, loc=(s * 0.07, 0.15, 0.25))\n"
    assert old in s
    s = s.replace(old, old + (
        "        # (Iscariel) the left wing burned down to a charred, ember-edged ruin; the right stays ash-white.\n"
        "        FM = (feath_burnt, ember_burnt) if s < 0 else (feath, ember)\n"
        "        if s < 0:\n"
        "            w0.scale = (0.74, 0.74, 0.74)\n"))
    open(DST, "w", encoding="utf-8").write(s)
    print("written", DST)


if __name__ == "__main__":
    main()
